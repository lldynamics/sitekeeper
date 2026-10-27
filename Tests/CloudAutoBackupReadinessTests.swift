import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct CloudAutoBackupReadinessTests {
    @Test func activationWaitsForSlowLoadAndSeesLoadedRecords() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let gate = BackupReadinessGate()
        store.setLoadState(.loading)
        store.initialLoadTask = Task { await gate.wait()
        store.setLoadState(.ready) }
        let observations = BackupReadinessObservations()
        let scheduler = CloudAutoBackupScheduler { store in
            let count = await store.projects.count
            await observations.record(count)
        }
        let trigger = Task { await scheduler.triggerIfNeeded(store: store) }
        await gate.waitUntilEntered()
        #expect(await observations.values.isEmpty)
        await gate.release()
        await trigger.value
        #expect(await observations.values == [fixture.snapshot.projects.count])
    }

    @Test func cancelledActivationDoesNotBlockNextActivationDuringLoad() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let gate = BackupReadinessGate()
        store.setLoadState(.loading)
        store.initialLoadTask = Task { await gate.wait()
        store.setLoadState(.ready) }
        let observations = BackupReadinessObservations()
        let scheduler = CloudAutoBackupScheduler { _ in await observations.record(1) }
        let cancelled = Task { await scheduler.triggerIfNeeded(store: store) }
        await gate.waitUntilEntered()
        cancelled.cancel()
        let next = Task { await scheduler.triggerIfNeeded(store: store) }
        await gate.release()
        await cancelled.value
        await next.value
        #expect(await observations.values == [1])
    }

    @Test func failedOrRestoringStoreNeverReachesCloudOperationAndRetryCanRun() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let observations = BackupReadinessObservations()
        let scheduler = CloudAutoBackupScheduler { _ in await observations.record(1) }
        store.setLoadState(.failed)
        await scheduler.triggerIfNeeded(store: store)
        store.setLoadState(.ready)
        store.isApplyingBackup = true
        await scheduler.triggerIfNeeded(store: store)
        #expect(await observations.values.isEmpty)
        store.isApplyingBackup = false
        await scheduler.triggerIfNeeded(store: store)
        #expect(await observations.values == [1])
    }

    @Test func concurrentActivationsDoNotStartDuplicateBackup() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let gate = BackupReadinessGate()
        let observations = BackupReadinessObservations()
        let scheduler = CloudAutoBackupScheduler { _ in
            await observations.record(1)
            await gate.wait()
        }
        let first = Task { await scheduler.triggerIfNeeded(store: store) }
        await gate.waitUntilEntered()
        await scheduler.triggerIfNeeded(store: store)
        #expect(await observations.values == [1])
        await gate.release()
        await first.value
    }
}

private actor BackupReadinessObservations {
    var values: [Int] = []
    func record(_ value: Int) { values.append(value) }
}

private actor BackupReadinessGate {
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }

    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
