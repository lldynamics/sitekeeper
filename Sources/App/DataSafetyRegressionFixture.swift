#if DEBUG
import Foundation

@MainActor
enum DataSafetyRegressionFixture {
    static func prepareIfRequested(store: DataStore) async {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITEST_STORAGE_RECOVERY_FIXTURE"] == "1" else { return }
        await store.awaitInitialLoad()
        guard store.loadState == .ready else { return }
        do {
            try store.createProject(Project(name: "读取恢复保留项目", location: "合成测试数据"))
            try await store.flushSaveOrThrow()
            let original = try Data(contentsOf: store.storeURL)
            try Data("{synthetic read failure".utf8).write(to: store.storeURL)
            store.loadAsync()
            await store.awaitInitialLoad()
            // Make the original available again while retaining the real failed-load
            // state. Only the user's retry action should enable editing again.
            try original.write(to: store.storeURL)
        } catch { assertionFailure("Storage recovery fixture: \(error)") }
    }
}
#endif
