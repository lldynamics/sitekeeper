import SwiftUI

@main
struct SitekeeperApp: App {
    @State private var store: DataStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLanguage.restoreFromStorage()
        if UITestLaunchConfig.shouldResetLocalState {
            UITestLaunchConfig.resetLocalState()
        }
        _store = State(initialValue: DataStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await CloudAutoBackupScheduler.shared.triggerIfNeeded(store: store)
                }
            case .background, .inactive:
                Task {
                    await store.flushSave()
                }
            default:
                break
            }
        }
    }
}

private enum UITestLaunchConfig {
    private static let resetArguments = ["-uitest-reset-state"]

    static var shouldResetLocalState: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["UITEST_RESET_STATE"] == "1" {
            return true
        }
        return resetArguments.contains { processInfo.arguments.contains($0) }
    }

    static func resetLocalState() {
        let defaults = UserDefaults.standard
        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }

        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localStoreFiles = ["sitekeeper.json", "construction_toolbox.json"]
            for fileName in localStoreFiles {
                let fileURL = documentsDirectory.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }

        PhotoStorage.delete(fileNames: PhotoStorage.allStoredFileNames())
        DrawingStorage.delete(fileNames: DrawingStorage.allStoredFileNames())
        ProjectDocumentStorage.delete(fileNames: ProjectDocumentStorage.allStoredFileNames())
        QuickNoteAttachmentStorage.delete(fileNames: QuickNoteAttachmentStorage.allStoredFileNames())
        StorageIssueLog.clear()
        defaults.synchronize()
    }
}
