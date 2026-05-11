import SwiftUI

struct RootView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: Tab = .dashboard
    @AppStorage(UserPreferenceKeys.darkMode) private var legacyDarkMode = false
    @AppStorage(UserPreferenceKeys.appearanceMode) private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage(UserPreferenceKeys.didCompleteOnboarding) private var didCompleteOnboarding = false
    @AppStorage(UserPreferenceKeys.completedOnboardingVersion) private var completedOnboardingVersion = 0
    @AppStorage(UserPreferenceKeys.languageCode) private var languageCode = AppLanguage.chinese.rawValue
    @State private var showOnboarding = false
    @State private var showOnboardingBackupImport = false
    @State private var projectComposerOpenToken = 0
    @State private var padDetailResetToken = 0
    @State private var padShellResetToken = 0
    @State private var padColumnVisibility: NavigationSplitViewVisibility = .all

    private let currentOnboardingVersion = 1

    private var allowsSampleDataImport: Bool {
        AppFeatureFlags.allowsSampleDataImport
    }

    private var skipOnboardingForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-skip-onboarding")
            || ProcessInfo.processInfo.environment["UITEST_SKIP_ONBOARDING"] == "1"
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
        Locale(identifier: languageCode)
    }

    private var usesPadSplitShell: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            mainContentShell
            .allowsHitTesting(!showOnboarding)

            if showOnboarding {
                FirstLaunchOnboardingView(
                    allowsSampleDataImport: allowsSampleDataImport,
                    onCreateProject: {
                        finishOnboarding()
                        selectedTab = .records
                        projectComposerOpenToken += 1
                    },
                    onImportBackup: {
                        finishOnboarding()
                        Task { @MainActor in
                            showOnboardingBackupImport = true
                        }
                    },
                    onLoadSample: {
                        store.importSampleData(replacingExisting: true)
                        finishOnboarding()
                    }
                )
                .background(Color(.systemBackground))
                .ignoresSafeArea()
            }
        }
        .tint(.orange)
        .preferredColorScheme(preferredAppearance)
        .environment(\.locale, preferredLocale)
        .alert("数据读写异常", isPresented: persistenceErrorBinding) {
            Button("知道了", role: .cancel) {
                store.persistenceErrorMessage = nil
            }
        } message: {
            Text(store.persistenceErrorMessage ?? "")
        }
        .sheet(isPresented: $showOnboardingBackupImport) {
            NavigationStack {
                BackupView(autoOpenImporter: true)
            }
        }
        .onAppear {
            migrateLegacyAppearanceIfNeeded()
            migrateOnboardingVersionIfNeeded()
            refreshOnboardingState()
        }
        .onChange(of: store.hasAnyBusinessData) { _, _ in
            refreshOnboardingState()
        }
    }

    @ViewBuilder
    private var mainContentShell: some View {
        if usesPadSplitShell {
            padSplitShell
        } else {
            phoneTabShell
        }
    }

    private var phoneTabShell: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(Tab.dashboard.title, systemImage: Tab.dashboard.systemImage) }
                .tag(Tab.dashboard)

            NavigationStack {
                ProjectListView(autoOpenComposerToken: projectComposerOpenToken)
            }
            .tabItem { Label(Tab.records.title, systemImage: Tab.records.systemImage) }
            .tag(Tab.records)

            ChecklistTabView()
                .tabItem { Label(Tab.checklist.title, systemImage: Tab.checklist.systemImage) }
                .tag(Tab.checklist)

            QuickNoteView()
                .tabItem { Label(Tab.quickNote.title, systemImage: Tab.quickNote.systemImage) }
                .tag(Tab.quickNote)

            ProfileTabView()
                .tabItem { Label(Tab.profile.title, systemImage: Tab.profile.systemImage) }
                .tag(Tab.profile)
        }
    }

    private var padSplitShell: some View {
        NavigationSplitView(columnVisibility: $padColumnVisibility) {
            List {
                ForEach(Tab.allCases) { tab in
                    Button {
                        switchPadModule(to: tab)
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.body.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .orange : .primary)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedTab == tab ? Color.orange.opacity(0.12) : Color.clear)
                }
            }
            .navigationTitle(AppBrand.displayName)
            .listStyle(.sidebar)
        } detail: {
            selectedModuleContent
                .id("pad-detail-\(selectedTab.id)-\(padDetailResetToken)")
        }
        .navigationSplitViewStyle(.balanced)
        .id("pad-shell-\(padShellResetToken)")
    }

    @ViewBuilder
    private var selectedModuleContent: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .records:
            NavigationStack {
                ProjectListView(
                    autoOpenComposerToken: projectComposerOpenToken,
                    prefersSplitNavigation: false
                )
            }
        case .checklist:
            NavigationStack {
                ChecklistTabView(embedsNavigationStack: false)
            }
        case .quickNote:
            NavigationStack {
                QuickNoteView(embedsNavigationStack: false)
            }
        case .profile:
            NavigationStack {
                ProfileTabView(embedsNavigationStack: false)
            }
        }
    }

    private func switchPadModule(to tab: Tab) {
        guard selectedTab != tab else { return }
        selectedTab = tab
        padColumnVisibility = .all
        padDetailResetToken &+= 1
        padShellResetToken &+= 1
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

    private func refreshOnboardingState() {
        let needsFirstSetup = !didCompleteOnboarding && !store.hasAnyBusinessData
        let needsVersionGuide = didCompleteOnboarding && completedOnboardingVersion < currentOnboardingVersion
        showOnboarding = !skipOnboardingForUITests && (needsFirstSetup || needsVersionGuide)
    }

    private func finishOnboarding() {
        didCompleteOnboarding = true
        completedOnboardingVersion = currentOnboardingVersion
        showOnboarding = false
    }

    private func migrateOnboardingVersionIfNeeded() {
        guard didCompleteOnboarding, completedOnboardingVersion == 0 else { return }
        completedOnboardingVersion = currentOnboardingVersion
    }

    private func migrateLegacyAppearanceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: UserPreferenceKeys.appearanceMode) == nil else { return }
        appearanceMode = legacyDarkMode ? AppAppearanceMode.dark.rawValue : AppAppearanceMode.system.rawValue
    }
}

enum Tab: Hashable, CaseIterable, Identifiable {
    case dashboard
    case records
    case checklist
    case quickNote
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard:
            return "工作台"
        case .records:
            return "项目"
        case .checklist:
            return "工具箱"
        case .quickNote:
            return "随手记"
        case .profile:
            return "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "house.fill"
        case .records:
            return "building.2.fill"
        case .checklist:
            return "books.vertical.fill"
        case .quickNote:
            return "square.and.pencil"
        case .profile:
            return "person.circle"
        }
    }
}

private struct FirstLaunchOnboardingView: View {
    let allowsSampleDataImport: Bool
    let onCreateProject: () -> Void
    let onImportBackup: () -> Void
    let onLoadSample: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 0)
                Text("欢迎使用 \(AppBrand.displayName)")
                    .font(.largeTitle.bold())
                Text("首次打开建议先选择一个开始方式。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("数据默认保存在本机，可随时手动导出完整 ZIP 备份。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    Button(action: onCreateProject) {
                        actionRow(title: "新建项目", subtitle: "从空白开始创建你的第一个工程", icon: "building.2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Button(action: onImportBackup) {
                        actionRow(title: "导入备份", subtitle: "从 ZIP 恢复已有项目数据", icon: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.bordered)
                    if allowsSampleDataImport {
                        Button(action: onLoadSample) {
                            actionRow(title: "查看示例", subtitle: "导入演示数据体验完整功能", icon: "sparkles")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .buttonBorderShape(.roundedRectangle)
                Spacer()
            }
            .padding(20)
            .navigationTitle("首次设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func actionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
            }
            Spacer()
        }
    }
}
