import SwiftUI
import UIKit

@main
struct SitekeeperApp: App {
    @State private var store: DataStore
    @State private var scenePhaseTask: Task<Void, Never>?
    @State private var dayBoundaryRefreshTask: Task<Void, Never>?
    @State private var dueReminderRefreshTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLanguage.restoreFromStorage()
        UserPreferencesStore.shared.removeRetiredKeys()
#if DEBUG
        if UITestLaunchConfig.disablesAnimations {
            UIView.setAnimationsEnabled(false)
        }
        if UITestLaunchConfig.shouldResetLocalState {
            UITestLaunchConfig.resetLocalState()
        }
#endif
        _store = State(initialValue: DataStore())
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG && targetEnvironment(simulator)
        if Phase2ThumbnailValidationView.isRequested {
            Phase2ThumbnailValidationView()
        } else {
            normalRootContent
        }
#else
        normalRootContent
#endif
    }

    @ViewBuilder
    private var normalRootContent: some View {
        let rootView = RootView()
            .environment(store)
            .environment(store.projectStore)
            .environment(store.financeStore)
            .environment(store.materialLibraryStore)
            .environment(store.materialLibraryPreferencesStore)
 #if DEBUG
            .task {
                await ReviewRegressionFixture.prepareIfRequested(store: store)
                await DataSafetyRegressionFixture.prepareIfRequested(store: store)
            }
 #endif

 #if DEBUG
        if let size = UITestLaunchConfig.dynamicTypeSizeOverride {
            rootView.dynamicTypeSize(size)
        } else {
            rootView
        }
 #else
        rootView
 #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
#if DEBUG
                .transaction { transaction in
                    if UITestLaunchConfig.disablesAnimations {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
#endif
                .task { refreshDayAndScheduleBoundaryIfActive() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    refreshDayAndScheduleBoundaryIfActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    refreshDayAndScheduleBoundaryIfActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    refreshDayAndScheduleBoundaryIfActive()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            dayBoundaryRefreshTask?.cancel()
            if newPhase == .active {
                refreshDayAndScheduleBoundaryIfActive()
            }
            scenePhaseTask?.cancel()
            scenePhaseTask = Task {
                switch newPhase {
                case .active:
#if DEBUG
                    guard !UITestLaunchConfig.isUITestSession else { return }
#endif
                    await CloudAutoBackupScheduler.shared.triggerIfNeeded(store: store)
                    await DueReminderNotificationScheduler.shared.refreshIfEnabled(
                        snapshot: DueReminderSnapshot(store: store)
                    )
                case .background, .inactive:
                    await BackgroundTaskAssertion.application.run(named: "sitekeeper.final-save") {
                        await store.flushSave()
                    }
                default:
                    break
                }
            }
        }
        .onChange(of: store.projectStore.dayContext) { _, _ in
            store.publishWidgetData()
        }
        .onChange(of: store.projectStore.dueReminderVersion) { _, _ in
            dueReminderRefreshTask?.cancel()
            dueReminderRefreshTask = Task { @MainActor in
                guard await DebouncedTask.wait(for: .milliseconds(500)) else { return }
                await DueReminderNotificationScheduler.shared.refreshIfEnabled(
                    snapshot: DueReminderSnapshot(store: store)
                )
            }
        }
    }

    @MainActor
    private func refreshDayAndScheduleBoundaryIfActive() {
        guard scenePhase == .active else { return }
        dayBoundaryRefreshTask?.cancel()
        store.projectStore.refreshDateSensitiveStateIfNeeded()
        let delay = store.projectStore.secondsUntilNextDay
        dayBoundaryRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            refreshDayAndScheduleBoundaryIfActive()
        }
    }
}

#if DEBUG
private enum UITestLaunchConfig {
    /// Opt in for deterministic functional UI tests on simulator runtimes whose
    /// animation-idle notification can remain pending after text entry.
    static let disablesAnimations = ProcessInfo.processInfo.environment["UITEST_DISABLE_ANIMATIONS"] == "1"

    private static let resetArguments = ["-uitest-reset-state"]
    private static let dynamicTypeSizeArgument = "-uitest-dynamic-type-size"
    private static let knownUITestArguments = [
        "-uitest-skip-onboarding",
        "-uitest-reset-state",
        "-uitest-backup-preview",
        "-uitest-allow-clear-without-backup",
        "-uitest-dynamic-type-size"
    ]

    static var isUITestSession: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment.keys.contains(where: { $0.hasPrefix("UITEST_") }) {
            return true
        }
        return knownUITestArguments.contains { processInfo.arguments.contains($0) }
    }

    static var shouldResetLocalState: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["UITEST_RESET_STATE"] == "1" {
            return true
        }
        return resetArguments.contains { processInfo.arguments.contains($0) }
    }

    static var dynamicTypeSizeOverride: DynamicTypeSize? {
        let processInfo = ProcessInfo.processInfo
        if let raw = processInfo.environment["UITEST_DYNAMIC_TYPE_SIZE"] {
            return DynamicTypeSize.uiTestValue(raw)
        }

        if let index = processInfo.arguments.firstIndex(of: dynamicTypeSizeArgument),
           processInfo.arguments.indices.contains(index + 1) {
            return DynamicTypeSize.uiTestValue(processInfo.arguments[index + 1])
        }

        return nil
    }

    static func resetLocalState() {
        let preferenceStore = UserPreferencesStore.shared
        if let bundleID = Bundle.main.bundleIdentifier {
            preferenceStore.removePersistentDomain(forName: bundleID)
        }

        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            removeLocalStoreFiles(in: documentsDirectory)
            removeStorageDirectories(in: documentsDirectory)
        }

        if let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let quarantineURL = applicationSupportDirectory.appendingPathComponent("FileQuarantine", isDirectory: true)
            do {
                _ = try FileOps.removeIfExists(
                    at: quarantineURL,
                    context: .init(
                        event: "ui_test.reset_local_state.remove_quarantine_directory",
                        category: .fileStorage,
                        source: "SitekeeperApp.resetLocalState"
                    )
                )
            } catch {
                StorageIssueLog.recordEvent(
                    "ui_test.reset_local_state_remove_quarantine_directory_failed",
                    category: .fileStorage,
                    details: ["source": "SitekeeperApp.resetLocalState"],
                    error: error
                )
            }
        }

        StorageIssueLog.clear()
        preferenceStore.synchronize()
    }

    private static func removeLocalStoreFiles(in documentsDirectory: URL) {
        let localStoreFiles = ["sitekeeper.json", "sitekeeper_date_provenance.json"]
        for fileName in localStoreFiles {
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            do {
                _ = try FileOps.removeIfExists(
                    at: fileURL,
                    context: .init(
                        event: "ui_test.reset_local_state.remove_store_file",
                        category: .dataStore,
                        source: "SitekeeperApp.resetLocalState"
                    )
                )
            } catch {
                StorageIssueLog.recordEvent(
                    "ui_test.reset_local_state_remove_file_failed",
                    category: .dataStore,
                    details: [
                        "source": "SitekeeperApp.resetLocalState",
                        "file_name": fileURL.lastPathComponent
                    ],
                    error: error
                )
            }
        }
    }

    private static func removeStorageDirectories(in documentsDirectory: URL) {
        // UI tests 需要可重复、可预期的冷启动；这里直接清空目录，避免大批量隔离迁移导致启动超时。
        let storageDirectories = [
            "Photos",
            "PhotoThumbnails",
            "Drawings",
            "ProjectDocuments",
            "QuickNoteAttachments",
            "BusinessDrafts",
            ".sqlite-candidates"
        ]
        for directoryName in storageDirectories {
            let directoryURL = documentsDirectory.appendingPathComponent(directoryName, isDirectory: true)
            do {
                _ = try FileOps.removeIfExists(
                    at: directoryURL,
                    context: .init(
                        event: "ui_test.reset_local_state.remove_storage_directory",
                        category: .fileStorage,
                        source: "SitekeeperApp.resetLocalState"
                    )
                )
            } catch {
                StorageIssueLog.recordEvent(
                    "ui_test.reset_local_state_remove_storage_directory_failed",
                    category: .fileStorage,
                    details: [
                        "source": "SitekeeperApp.resetLocalState",
                        "directory": directoryName
                    ],
                    error: error
                )
            }
        }
    }
}
#endif

private extension DynamicTypeSize {
    static func uiTestValue(_ rawValue: String) -> DynamicTypeSize? {
        let key = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch key {
        case "xsmall", "x-small", ".xsmall", "uictcontentsizecategoryxs":
            return .xSmall
        case "small", ".small", "uictcontentsizecategorys":
            return .small
        case "medium", ".medium", "uictcontentsizecategorym":
            return .medium
        case "large", ".large", "uictcontentsizecategoryl":
            return .large
        case "xlarge", "x-large", ".xlarge", "uictcontentsizecategoryxl":
            return .xLarge
        case "xxlarge", "xx-large", ".xxlarge", "uictcontentsizecategoryxxl":
            return .xxLarge
        case "xxxlarge", "xxx-large", ".xxxlarge", "uictcontentsizecategoryxxxl":
            return .xxxLarge
        case "accessibility1", "a1", ".accessibility1", "uictcontentsizecategoryaccessibilitym":
            return .accessibility1
        case "accessibility2", "a2", ".accessibility2", "uictcontentsizecategoryaccessibilityl":
            return .accessibility2
        case "accessibility3", "a3", ".accessibility3", "uictcontentsizecategoryaccessibilityxl":
            return .accessibility3
        case "accessibility4", "a4", ".accessibility4", "uictcontentsizecategoryaccessibilityxxl":
            return .accessibility4
        case "accessibility5", "a5", ".accessibility5", "axxxl", "uictcontentsizecategoryaccessibilityxxxl":
            return .accessibility5
        default:
            return nil
        }
    }
}
