import Foundation

/// A deterministic decoded-cost budget and one shared asynchronous load per key.
/// All mutable state is protected by `lock`; loaders and continuations run outside it.
final class BudgetedResourceCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    struct Statistics: Sendable {
        let entryCount: Int
        let retainedCost: Int
        let inFlightCount: Int
        let loadCount: Int
        let hitCount: Int
        let coalescedCount: Int
        let evictionCount: Int
        let completedLoadCount: Int
    }

    private struct Entry {
        let value: Value
        let cost: Int
        var access: UInt64
    }

    // Waiter fields are accessed only under the owning cache's lock.
    private final class Waiter: @unchecked Sendable {
        let id = UUID()
        var cancelled = false
        var flightID: UUID?
        var continuation: CheckedContinuation<Value?, Never>?
    }

    private final class Flight {
        let id = UUID()
        var retainsResult = true
        var waiters: [UUID: Waiter] = [:]
        var task: Task<Void, Never>?
    }

    let costLimit: Int
    let countLimit: Int
    private let cost: @Sendable (Value) -> Int
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var flights: [Key: Flight] = [:]
    private var retainedCost = 0
    private var access: UInt64 = 0
    private var mutationEpoch: UInt64 = 0
    private var loadCount = 0
    private var hitCount = 0
    private var coalescedCount = 0
    private var evictionCount = 0
    private var completedLoadCount = 0

    init(costLimit: Int, countLimit: Int, cost: @escaping @Sendable (Value) -> Int) {
        self.costLimit = max(0, costLimit)
        self.countLimit = max(0, countLimit)
        self.cost = cost
    }

    var statistics: Statistics {
        lock.withLock {
            Statistics(entryCount: entries.count, retainedCost: retainedCost,
                       inFlightCount: flights.count, loadCount: loadCount, hitCount: hitCount,
                       coalescedCount: coalescedCount, evictionCount: evictionCount,
                       completedLoadCount: completedLoadCount)
        }
    }

    func cachedValue(for key: Key) -> Value? {
        lock.withLock { lookup(key) }
    }

    /// Legacy synchronous callers remain synchronous. An invalidation during their
    /// read prevents cache refill; asynchronous UI requests use `value` to coalesce.
    func synchronousValue(for key: Key, loader: () -> Value?) -> Value? {
        let start: (Value?, UInt64) = lock.withLock {
            if let value = lookup(key) { return (value, mutationEpoch) }
            loadCount += 1
            return (nil, mutationEpoch)
        }
        if let value = start.0 { return value }
        guard let value = loader() else { return nil }
        let bytes = cost(value)
        return lock.withLock {
            guard mutationEpoch == start.1 else { return value }
            insert(value, cost: bytes, for: key)
            return value
        }
    }

    func value(for key: Key, loader: @escaping @Sendable () async throws -> Value?) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let waiter = Waiter()
        let value = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                register(waiter, continuation: continuation, key: key, loader: loader)
            }
        } onCancel: {
            self.cancel(waiter, key: key)
        }
        return Task.isCancelled ? nil : value
    }

    /// Invalidates every size/variant of a resource in one critical section.
    func invalidate(where matches: (Key) -> Bool) {
        var cancelled: [Flight] = []
        let continuations: [CheckedContinuation<Value?, Never>] = lock.withLock {
            mutationEpoch &+= 1
            for key in entries.keys.filter(matches) {
                if let removed = entries.removeValue(forKey: key) { retainedCost -= removed.cost }
            }
            cancelled = flights.keys.filter(matches).compactMap { flights.removeValue(forKey: $0) }
            return detachWaiters(from: cancelled)
        }
        cancelled.forEach { $0.task?.cancel() }
        continuations.forEach { $0.resume(returning: nil) }
    }

    func clear() {
        invalidate { _ in true }
    }

    /// Memory pressure evicts retained pixels without interrupting visible readers.
    /// Already-running loads still deliver their result, but cannot refill the cache.
    func purgeRetainedValues() {
        lock.withLock {
            mutationEpoch &+= 1
            entries.removeAll()
            retainedCost = 0
            flights.values.forEach { $0.retainsResult = false }
        }
    }

    private func register(
        _ waiter: Waiter,
        continuation: CheckedContinuation<Value?, Never>,
        key: Key,
        loader: @escaping @Sendable () async throws -> Value?
    ) {
        var immediate: Value?
        let shouldResume: Bool = lock.withLock {
            guard !waiter.cancelled else { return true }
            if let cached = lookup(key) {
                immediate = cached
                return true
            }
            waiter.continuation = continuation
            if let flight = flights[key] {
                waiter.flightID = flight.id
                flight.waiters[waiter.id] = waiter
                coalescedCount += 1
            } else {
                let flight = Flight()
                waiter.flightID = flight.id
                flight.waiters[waiter.id] = waiter
                flights[key] = flight
                loadCount += 1
                let id = flight.id
                flight.task = Task.detached(priority: .utility) { [self] in
                    let value: Value?
                    do {
                        try Task.checkCancellation()
                        value = try await loader()
                    } catch {
                        value = nil
                    }
                    finish(key: key, id: id, value: Task.isCancelled ? nil : value)
                }
            }
            return false
        }
        if shouldResume { continuation.resume(returning: immediate) }
    }

    private func cancel(_ waiter: Waiter, key: Key) {
        var worker: Task<Void, Never>?
        let continuation: CheckedContinuation<Value?, Never>? = lock.withLock {
            waiter.cancelled = true
            let continuation = waiter.continuation
            waiter.continuation = nil
            if let flight = flights[key], flight.id == waiter.flightID {
                flight.waiters.removeValue(forKey: waiter.id)
                if flight.waiters.isEmpty {
                    flights.removeValue(forKey: key)
                    worker = flight.task
                }
            }
            return continuation
        }
        worker?.cancel()
        continuation?.resume(returning: nil)
    }

    private func finish(key: Key, id: UUID, value: Value?) {
        let bytes = value.map(cost) ?? 0
        let continuations: [CheckedContinuation<Value?, Never>] = lock.withLock {
            completedLoadCount += 1
            guard let flight = flights[key], flight.id == id else { return [] }
            flights.removeValue(forKey: key)
            if let value, flight.retainsResult { insert(value, cost: bytes, for: key) }
            return detachWaiters(from: [flight])
        }
        continuations.forEach { $0.resume(returning: value) }
    }

    private func detachWaiters(from flights: [Flight]) -> [CheckedContinuation<Value?, Never>] {
        flights.flatMap { flight in
            let continuations = flight.waiters.values.compactMap { waiter in
                let continuation = waiter.continuation
                waiter.continuation = nil
                return continuation
            }
            flight.waiters.removeAll()
            return continuations
        }
    }

    // The following helpers are only called while holding `lock`.
    private func lookup(_ key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        access &+= 1
        entry.access = access
        entries[key] = entry
        hitCount += 1
        return entry.value
    }

    private func insert(_ value: Value, cost: Int, for key: Key) {
        if let previous = entries.removeValue(forKey: key) { retainedCost -= previous.cost }
        let bytes = max(1, cost)
        guard countLimit > 0, bytes <= costLimit else { return }
        while entries.count >= countLimit || retainedCost > costLimit - bytes {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key,
                  let removed = entries.removeValue(forKey: oldest) else { break }
            retainedCost -= removed.cost
            evictionCount += 1
        }
        access &+= 1
        entries[key] = Entry(value: value, cost: bytes, access: access)
        retainedCost += bytes
    }
}
