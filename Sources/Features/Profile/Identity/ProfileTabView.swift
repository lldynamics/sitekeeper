import SwiftUI
import PhotosUI

struct ProfileTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.expandedPhoneWorkspaceWidth) private var rootWorkspaceWidth
    @State private var containerWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var expandedPhoneMinimumWidth: CGFloat = 820
    @AppStorage(UserPreferenceKeys.userName) private var userName = ""
    @AppStorage(UserPreferenceKeys.userAvatarData) private var userAvatarData = Data()
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    @AppStorage(UserPreferenceKeys.appearanceMode) private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage(UserPreferenceKeys.appTheme) private var appTheme = AppTheme.jiangnanSpring.rawValue
    @AppStorage(UserPreferenceKeys.languageCode) private var languageCode = AppLanguage.chinese.rawValue
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudBackupLastSuccessAt = 0.0
    @State private var didSwitchLanguage = false
    @State private var localStorageUsageText = AppLocalization.string("正在统计...")
    @State private var localStorageFileCount = 0
    @State private var isRefreshingStorageUsage = false
    @State private var lastStorageSampleAt: Date?
    @State private var hasLoadedStorageUsage = false
    @State private var showUserNameEditor = false
    @State private var userNameDraft = ""
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var showAvatarPicker = false
    let embedsNavigationStack: Bool

    init(embedsNavigationStack: Bool = true) {
        self.embedsNavigationStack = embedsNavigationStack
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var displayUserName: String {
        let value = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? AppLocalization.string("未设置用户名") : value
    }

    private var avatarUIImage: UIImage? {
        guard !userAvatarData.isEmpty else { return nil }
        return UIImage(data: userAvatarData)
    }

    private var hasCustomAvatar: Bool {
        !userAvatarData.isEmpty
    }

    private var backupStatusText: String {
        let backupDates = [localBackupLastSuccessAt, cloudBackupLastSuccessAt]
            .filter { $0 > 0 }
            .map(Date.init(timeIntervalSince1970:))
        guard let latestDate = backupDates.max() else {
            return AppLocalization.string("尚未记录成功备份")
        }
        return String(format: AppLocalization.string("最近备份：%@"), Formatters.dateTime.string(from: latestDate))
    }

    private var storageCaptionText: String {
        var parts = [String(format: AppLocalization.string("%@ 个文件"), "\(localStorageFileCount)")]
        if let lastStorageSampleAt {
            parts.append(String(format: AppLocalization.string("更新于 %@"), Formatters.dateTime.string(from: lastStorageSampleAt)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if embedsNavigationStack {
                NavigationStack {
                    profileSurface
                }
            } else {
                profileSurface
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { containerWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in containerWidth = width }
            }
        }
    }

    private var compactProfileList: some View {
        List {
            Section {
                ProfileIdentityView(
                    displayUserName: displayUserName,
                    appVersion: appVersion,
                    avatarImage: avatarUIImage,
                    hasCustomAvatar: hasCustomAvatar,
                    onChooseAvatar: { showAvatarPicker = true },
                    onEditUserName: {
                        userNameDraft = userName
                        showUserNameEditor = true
                    },
                    onResetAvatar: { userAvatarData = Data() }
                )
                .padding(.vertical, 8)
            }

            Section(AppLocalization.string("快捷设置")) {
                Toggle(AppLocalization.string("公制单位"), isOn: $useMetric)

                Picker(AppLocalization.string("配色"), selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("profile-theme-picker")

                Picker(AppLocalization.string("主题"), selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker(AppLocalization.string("语言"), selection: $languageCode) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                        Text(LocalizedStringKey(lang.displayName)).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("profile-language-picker")

                // Resolve feedback on each render so it follows later language changes.
                if didSwitchLanguage {
                    Text(AppLocalization.string("settings_language_switch_feedback"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(AppLocalization.string("数据安全")) {
                ProfileStorageStatusCard(
                    backupStatusText: backupStatusText,
                    localStorageUsageText: localStorageUsageText,
                    storageCaptionText: storageCaptionText,
                    isRefreshing: isRefreshingStorageUsage,
                    onRefresh: { Task { await refreshLocalStorageUsage() } }
                )
                NavigationLink { DataManagementView(initialRoute: .backup) } label: {
                    HStack(spacing: AppSpacing.tight) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(Color.appPrimaryAction)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppLocalization.string("数据管理"))
                            Text(AppLocalization.string("先看风险，再备份、恢复、清理"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("profile-data-management-link")
            }

            Section(AppLocalization.string("系统")) {
                NavigationLink { SettingsView() } label: {
                    Label(AppLocalization.string("更多设置"), systemImage: "gear")
                }
                .accessibilityIdentifier("profile-settings-link")
            }

            Section(AppLocalization.string("关于")) {
                HStack {
                    Label(AppLocalization.string("当前版本"), systemImage: "info.circle")
                    Spacer()
                    Text("v\(appVersion)")
                        .foregroundStyle(.secondary)
                }
                NavigationLink { PrivacyPolicyView() } label: {
                    Label(AppLocalization.string("隐私政策"), systemImage: "hand.raised.fill")
                }
                NavigationLink { FeedbackView() } label: {
                    Label(AppLocalization.string("意见反馈"), systemImage: "envelope.fill")
                }
            }
        }
    }

    private var profileSurface: some View {
        Group {
            if usesExpandedProfile {
                expandedProfileLayout
            } else {
                compactProfileList
            }
        }
        .navigationTitle(AppLocalization.string("我的"))
        .task {
            guard !hasLoadedStorageUsage else { return }
            hasLoadedStorageUsage = true
            await refreshLocalStorageUsage()
        }
        .onChange(of: languageCode) { _, newCode in
            if let lang = AppLanguage(rawValue: newCode) {
                AppLanguage.apply(lang)
                didSwitchLanguage = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshLocalStorageUsage()
            }
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await updateAvatar(from: newItem)
                selectedAvatarItem = nil
            }
        }
        .photosPicker(isPresented: $showAvatarPicker, selection: $selectedAvatarItem, matching: .images)
        .sheet(isPresented: $showUserNameEditor) {
            ProfileUserNameEditorSheet(
                userNameDraft: $userNameDraft,
                onCancel: { showUserNameEditor = false },
                onSave: {
                    userName = userNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    showUserNameEditor = false
                }
            )
        }
    }

    private var availableWorkspaceWidth: CGFloat {
        rootWorkspaceWidth > 0 ? rootWorkspaceWidth : containerWidth
    }

    private var usesExpandedProfile: Bool {
        ExpandedPhoneWorkspaceLayout.isAvailable(width: availableWorkspaceWidth,
                                                 minimumWidth: expandedPhoneMinimumWidth)
    }

    private var profileSidebarWidth: CGFloat {
        ExpandedPhoneWorkspaceLayout.sidebarWidth(containerWidth: availableWorkspaceWidth,
                                                 minimumWorkspaceWidth: expandedPhoneMinimumWidth)
    }

    private var expandedProfileLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: AppSpacing.relaxed) {
                    profileWorkspaceCard {
                        ProfileIdentityView(
                            displayUserName: displayUserName,
                            appVersion: appVersion,
                            avatarImage: avatarUIImage,
                            hasCustomAvatar: hasCustomAvatar,
                            onChooseAvatar: { showAvatarPicker = true },
                            onEditUserName: {
                                userNameDraft = userName
                                showUserNameEditor = true
                            },
                            onResetAvatar: { userAvatarData = Data() }
                        )
                    }
                    profileWorkspaceCard(title: AppLocalization.string("数据安全")) {
                        ProfileStorageStatusCard(
                            backupStatusText: backupStatusText,
                            localStorageUsageText: localStorageUsageText,
                            storageCaptionText: storageCaptionText,
                            isRefreshing: isRefreshingStorageUsage,
                            onRefresh: { Task { await refreshLocalStorageUsage() } }
                        )
                        NavigationLink { DataManagementView(initialRoute: .backup) } label: {
                            Label(AppLocalization.string("数据管理"), systemImage: "externaldrive")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appPrimaryAction)
                        .accessibilityIdentifier("profile-data-management-link")
                    }
                }
                .padding(AppSpacing.relaxed)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .modifier(ExpandedPhoneSidebarScrollModifier(
                isExpanded: true,
                paneBackground: Color(.systemGroupedBackground)
            ))
            .frame(width: profileSidebarWidth)
            .clipped()
            .accessibilityIdentifier("profile-expanded-identity-safety-pane")

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: AppSpacing.relaxed) {
                    profileWorkspaceCard(title: AppLocalization.string("快捷设置")) {
                        Toggle(AppLocalization.string("公制单位"), isOn: $useMetric)
                            .frame(minHeight: 44)
                        Divider()
                        HStack(spacing: AppSpacing.normal) {
                            Text(AppLocalization.string("配色"))
                            Spacer(minLength: AppSpacing.normal)
                            Picker(AppLocalization.string("配色"), selection: $appTheme) {
                                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                                    Text(theme.displayName).tag(theme.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityIdentifier("profile-theme-picker")
                        }
                        .frame(minHeight: 44)
                        Divider()
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            Text(AppLocalization.string("主题"))
                            Picker(AppLocalization.string("主题"), selection: $appearanceMode) {
                                ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                                    Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            Text(AppLocalization.string("语言"))
                            Picker(AppLocalization.string("语言"), selection: $languageCode) {
                                ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                                    Text(LocalizedStringKey(lang.displayName)).tag(lang.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityIdentifier("profile-language-picker")
                        }
                        if didSwitchLanguage {
                            Text(AppLocalization.string("settings_language_switch_feedback"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    profileWorkspaceCard(title: AppLocalization.string("更多设置")) {
                        NavigationLink { SettingsView() } label: {
                            Label(AppLocalization.string("更多设置"), systemImage: "gear")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("profile-settings-link")
                    }
                    profileWorkspaceCard(title: AppLocalization.string("关于")) {
                        HStack {
                            Label(AppLocalization.string("当前版本"), systemImage: "info.circle")
                            Spacer(minLength: AppSpacing.tight)
                            Text("v\(appVersion)")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        NavigationLink { PrivacyPolicyView() } label: {
                            Label(AppLocalization.string("隐私政策"), systemImage: "hand.raised.fill")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        Divider()
                        NavigationLink { FeedbackView() } label: {
                            Label(AppLocalization.string("意见反馈"), systemImage: "envelope.fill")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                }
                .padding(AppSpacing.relaxed)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("profile-expanded-settings-pane")
        }
        .overlay(alignment: .leading) {
            ExpandedPhoneColumnDivider()
                .frame(width: 1)
                .offset(x: profileSidebarWidth - 0.5)
        }
        .background(Color(.systemGroupedBackground), ignoresSafeAreaEdges: .all)
        .modifier(ExpandedPhoneScrollEdgeModifier(isExpanded: true))
    }

    private func profileWorkspaceCard<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(AppSpacing.relaxed)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appStrokeSecondary, lineWidth: 0.5)
        }
    }
}

private extension ProfileTabView {
    @MainActor
    func updateAvatar(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        let thumbnail = await Task.detached(priority: .userInitiated) {
            image.preparingThumbnail(of: CGSize(width: 320, height: 320)) ?? image
        }.value

        if let compressed = thumbnail.jpegData(compressionQuality: 0.82) {
            userAvatarData = compressed
        }
    }

    func refreshLocalStorageUsage() async {
        guard !isRefreshingStorageUsage else { return }
        isRefreshingStorageUsage = true
        defer { isRefreshingStorageUsage = false }

        let snapshot: (totalBytes: Int64, fileCount: Int)?
        do {
            snapshot = try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: "profile.storage_usage_scan",
                    source: "ProfileTabView.refreshLocalStorageUsage",
                    category: .fileStorage
                )
            ) {
                ProfileStorageUsage.calculateLocalStorageUsage()
            }
        } catch {
            snapshot = nil
        }

        guard let snapshot else {
            localStorageUsageText = AppLocalization.string("读取失败")
            localStorageFileCount = 0
            lastStorageSampleAt = nil
            return
        }

        localStorageUsageText = ProfileStorageUsage.formattedFileSize(snapshot.totalBytes)
        localStorageFileCount = snapshot.fileCount
        lastStorageSampleAt = Date()
    }
}
