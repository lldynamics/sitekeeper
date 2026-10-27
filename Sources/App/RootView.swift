import SwiftUI

struct RootView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedTab: Tab = .dashboard
    @AppStorage(UserPreferenceKeys.appTheme) private var appTheme = AppTheme.jiangnanSpring.rawValue
    @AppStorage(UserPreferenceKeys.appearanceMode) private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage(UserPreferenceKeys.didCompleteOnboarding) private var didCompleteOnboarding = false
    @AppStorage(UserPreferenceKeys.completedOnboardingVersion) private var completedOnboardingVersion = 0
    @AppStorage(UserPreferenceKeys.languageCode) private var languageCode = AppLanguage.chinese.rawValue
    @State private var showOnboarding = false
    @State private var showOnboardingBackupImport = false
    @State private var showRecoveryBackupImport = false
    @State private var pendingDeepLinkURL: URL?
    @State private var widgetDeepLinkDestination: WidgetDeepLinkDestination?
    @State private var projectComposerOpenToken = 0
    @State private var consumedProjectComposerOpenToken = 0

    private let currentOnboardingVersion = 1

    private var skipOnboardingForUITests: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-skip-onboarding")
            || ProcessInfo.processInfo.environment["UITEST_SKIP_ONBOARDING"] == "1"
#else
        false
#endif
    }

    private var preferredAppearance: ColorScheme? {
        switch StringEnumFallback.value(appearanceMode, default: AppAppearanceMode.system) {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var preferredLocale: Locale {
        StringEnumFallback.value(languageCode, default: AppLanguage.chinese).preferredLocale
    }

    // A resize must not replace the entire navigation tree and dismiss editors.
    // NavigationSplitView handles compact collapse without replacing its content.
    @State private var usesPadSplitShell = UIDevice.current.userInterfaceIdiom == .pad

    private var pendingProjectComposerOpenToken: Int {
        projectComposerOpenToken == consumedProjectComposerOpenToken ? 0 : projectComposerOpenToken
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            mainContentShell
            .disabled(!store.canEditBusinessData)
            .allowsHitTesting(!showOnboarding && store.canEditBusinessData)
            .accessibilityHidden(!store.canEditBusinessData)

            if !store.canEditBusinessData {
                StoreAvailabilityOverlay(
                    failed: store.loadState == .failed,
                    onRetry: { store.loadAsync() },
                    onRestore: { showRecoveryBackupImport = true }
                )
            }

            if showOnboarding {
                FirstLaunchOnboardingView(
                    onCreateProject: {
                        selectedTab = .records
                        projectComposerOpenToken += 1
                    },
                    onImportBackup: {
                        Task { @MainActor in
                            showOnboardingBackupImport = true
                        }
                    },
                    onSkip: finishOnboarding
                )
                .background(Color(.systemBackground))
                .ignoresSafeArea()
            }
        }
        .tint(StringEnumFallback.value(appTheme, default: AppTheme.jiangnanSpring).palette.primary)
        .preferredColorScheme(preferredAppearance)
        .environment(\.locale, preferredLocale)
        .alert(AppLocalization.string("数据读写异常"), isPresented: persistenceErrorBinding) {
            Button(AppLocalization.string("知道了"), role: .cancel) {
                store.persistenceErrorMessage = nil
            }
        } message: {
            Text(store.persistenceErrorMessage ?? "")
        }
        .sheet(isPresented: $showOnboardingBackupImport, onDismiss: {
            if store.hasAnyBusinessData {
                finishOnboarding()
            }
        }) {
            NavigationStack {
                DataManagementView(initialRoute: .restore)
            }
        }
        .sheet(isPresented: $showRecoveryBackupImport) {
            NavigationStack {
                DataManagementView(initialRoute: .restore)
            }
        }
        .sheet(item: $widgetDeepLinkDestination) { destination in
            NavigationStack {
                widgetDeepLinkView(for: destination)
                    .disabled(!store.canEditBusinessData)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppLocalization.string("关闭")) {
                                widgetDeepLinkDestination = nil
                            }
                        }
                    }
            }
        }
        .onAppear {
            migrateOnboardingVersionIfNeeded()
            refreshOnboardingState()
        }
        .onChange(of: store.hasAnyBusinessData) { _, hasBusinessData in
            if hasBusinessData, showOnboarding {
                finishOnboarding()
            }
            refreshOnboardingState()
        }
        .onChange(of: store.canEditBusinessData) { _, canEdit in
            refreshOnboardingState()
            if canEdit, let url = pendingDeepLinkURL {
                pendingDeepLinkURL = nil
                handleIncomingURL(url)
            }
        }
        .onOpenURL(perform: handleIncomingURL)
    }

    @ViewBuilder
    private var mainContentShell: some View {
        if usesPadSplitShell {
            RootPadNavigationShell(
                selectedTab: $selectedTab,
                projectComposerOpenToken: pendingProjectComposerOpenToken,
                onComposerConsumed: consumeProjectComposerRequest
            )
        } else {
            RootPhoneTabShell(
                selectedTab: $selectedTab,
                projectComposerOpenToken: pendingProjectComposerOpenToken,
                onComposerConsumed: consumeProjectComposerRequest
            )
        }
    }

    private func consumeProjectComposerRequest(_ token: Int) {
        guard token == projectComposerOpenToken else { return }
        // Keep the one-time request above all adaptive navigation shells.
        consumedProjectComposerOpenToken = token
    }

    private var persistenceErrorBinding: Binding<Bool> {
        Binding(
            get: { store.persistenceErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.persistenceErrorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func widgetDeepLinkView(for destination: WidgetDeepLinkDestination) -> some View {
        switch destination {
        case .todos:
            SiteTodoView()
                .navigationTitle(AppLocalization.string("现场待办"))
                .navigationBarTitleDisplayMode(.inline)
        case .lowStock:
            MaterialCenterView(initialTab: .warehouse)
        case .missingReceipt:
            ProjectListView(initialOverviewFilter: .missingReceipt)
        case .backupOverdue:
            DataManagementView(initialRoute: .backup)
        case .priceSpike:
            MaterialPriceSpikeDetailView()
        case .project(let projectId):
            if store.projects.contains(where: { $0.id == projectId }) {
                ProjectDetailView(projectId: projectId)
            } else {
                ContentUnavailableView(
                    AppLocalization.string("项目不存在"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(AppLocalization.string("该项目可能已被删除或尚未同步到本机。"))
                )
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let destination = WidgetDeepLinkDestination(url: url) else { return }
        guard store.canEditBusinessData else {
            pendingDeepLinkURL = url
            return
        }
        switch destination {
        case .todos:
            selectedTab = .dashboard
        case .lowStock:
            selectedTab = .checklist
        case .missingReceipt:
            selectedTab = .records
        case .backupOverdue:
            selectedTab = .profile
        case .priceSpike:
            selectedTab = .dashboard
        case .project:
            selectedTab = .records
        }
        widgetDeepLinkDestination = destination
    }
}

private extension RootView {
    func refreshOnboardingState() {
        guard store.canEditBusinessData else { showOnboarding = false
        return }
        let needsFirstSetup = !didCompleteOnboarding && !store.hasAnyBusinessData
        let needsVersionGuide = didCompleteOnboarding && completedOnboardingVersion < currentOnboardingVersion
        showOnboarding = !skipOnboardingForUITests && (needsFirstSetup || needsVersionGuide)
    }

    func finishOnboarding() {
        didCompleteOnboarding = true
        completedOnboardingVersion = currentOnboardingVersion
        showOnboarding = false
    }

    func migrateOnboardingVersionIfNeeded() {
        guard didCompleteOnboarding, completedOnboardingVersion == 0 else { return }
        completedOnboardingVersion = currentOnboardingVersion
    }
}
