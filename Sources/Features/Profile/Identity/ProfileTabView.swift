import SwiftUI
import PhotosUI

struct ProfileTabView: View {
    @Environment(\.scenePhase) private var scenePhase
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
        if embedsNavigationStack {
            NavigationStack {
                profileSurface
            }
        } else {
            profileSurface
        }
    }

    private var profileSurface: some View {
        List {
            Section {
                ProfileIdentityView(
                    displayUserName: displayUserName,
                    appVersion: appVersion,
                    avatarImage: avatarUIImage,
                    hasCustomAvatar: hasCustomAvatar,
                    selectedAvatarItem: $selectedAvatarItem,
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
