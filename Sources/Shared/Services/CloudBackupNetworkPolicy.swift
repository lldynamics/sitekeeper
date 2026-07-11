import Foundation
import Network

enum CloudBackupNetworkPolicy {
    static func evaluate(requiresWiFi: Bool) async -> CloudBackupExecutionGateDecision {
        guard requiresWiFi else { return .allow }
        let isWiFi = await CloudNetworkPolicyChecker.isUsingWiFi()
        guard isWiFi == true else {
            return .skip(statusMessage: "自动备份已跳过：当前不是 Wi‑Fi 网络。")
        }
        return .allow
    }
}

enum CloudNetworkPolicyChecker {
    static func isUsingWiFi(timeout: TimeInterval = 1.2) async -> Bool? {
        guard let path = await CloudNetworkPathMonitor.shared.currentPath(timeout: timeout) else { return nil }
        guard path.status == .satisfied else { return false }
        return path.usesInterfaceType(.wifi)
    }
}

private final class CloudNetworkPathMonitor: @unchecked Sendable {
    static let shared = CloudNetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.chengjinfang.sitekeeper.cloudbackup.network")
    private let lock = NSLock()
    private var latestPath: NWPath?
    private var waiters: [UUID: CloudNetworkPathWaiter] = [:]

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(path)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    func currentPath(timeout: TimeInterval) async -> NWPath? {
        let id = UUID()
        let waiter = CloudNetworkPathWaiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                switch registerWaiter(id: id, waiter: waiter, continuation: continuation) {
                case .resolved(let path):
                    continuation.resume(returning: path)
                    return
                case .waiting:
                    break
                }

                queue.asyncAfter(deadline: .now() + timeout) {
                    self.resumeWaiter(id: id, path: nil)
                }
            }
        } onCancel: {
            removeWaiter(id: id)
            waiter.resume(returning: nil)
        }
    }

    private func handle(_ path: NWPath) {
        let pending: [CloudNetworkPathWaiter]
        lock.lock()
        latestPath = path
        pending = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()

        for waiter in pending {
            waiter.resume(returning: path)
        }
    }

    private enum WaiterRegistration {
        case resolved(NWPath?)
        case waiting
    }

    private func registerWaiter(
        id: UUID,
        waiter: CloudNetworkPathWaiter,
        continuation: CheckedContinuation<NWPath?, Never>
    ) -> WaiterRegistration {
        lock.lock()
        defer { lock.unlock() }

        if let latestPath {
            return .resolved(latestPath)
        }
        guard waiter.install(continuation) else {
            return .resolved(nil)
        }
        waiters[id] = waiter
        return .waiting
    }

    private func resumeWaiter(id: UUID, path: NWPath?) {
        let waiter: CloudNetworkPathWaiter?
        lock.lock()
        waiter = waiters.removeValue(forKey: id)
        lock.unlock()

        waiter?.resume(returning: path)
    }

    private func removeWaiter(id: UUID) {
        lock.lock()
        waiters.removeValue(forKey: id)
        lock.unlock()
    }
}

private final class CloudNetworkPathWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NWPath?, Never>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<NWPath?, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isResolved else { return false }
        self.continuation = continuation
        return true
    }

    func resume(returning path: NWPath?) {
        let continuation: CheckedContinuation<NWPath?, Never>?
        lock.lock()
        if isResolved {
            lock.unlock()
            return
        }
        isResolved = true
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: path)
    }
}
