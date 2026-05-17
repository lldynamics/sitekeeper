import SwiftUI
import PhotosUI

struct ProfileTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.userName) private var userName = ""
    @AppStorage(UserPreferenceKeys.userAvatarData) private var userAvatarData = Data()
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    @AppStorage(UserPreferenceKeys.autoSave) private var autoSaveEnabled = true
    @AppStorage(UserPreferenceKeys.darkMode) private var legacyDarkMode = false
    @AppStorage(UserPreferenceKeys.appearanceMode) private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage(UserPreferenceKeys.appTheme) private var appTheme = AppTheme.jiangnanSpring.rawValue
    @AppStorage(UserPreferenceKeys.languageCode) private var languageCode = AppLanguage.chinese.rawValue
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudBackupLastSuccessAt = 0.0
    @State private var languageSwitchFeedback = ""
    @State private var localStorageUsageText = String(localized: "正在统计...")
    @State private var localStorageFileCount = 0
    @State private var isRefreshingStorageUsage = false
    @State private var lastStorageSampleAt: Date?
    @State private var hasLoadedStorageUsage = false
    @State private var showUserNameEditor = false
    @State private var showSampleImportConfirm = false
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
        return value.isEmpty ? String(localized: "未设置用户名") : value
    }

    private var avatarUIImage: UIImage? {
        guard !userAvatarData.isEmpty else { return nil }
        return UIImage(data: userAvatarData)
    }

    private var hasCustomAvatar: Bool {
        !userAvatarData.isEmpty
    }

    private var backupStatusText: String {
        guard cloudBackupLastSuccessAt > 0 else { return String(localized: "尚未记录云备份成功") }
        let date = Date(timeIntervalSince1970: cloudBackupLastSuccessAt)
        return String(format: String(localized: "最近云备份：%@"), Formatters.dateTime.string(from: date))
    }

    private var storageCaptionText: String {
        var parts = [String(format: String(localized: "%@ 个文件"), "\(localStorageFileCount)")]
        if let lastStorageSampleAt {
            parts.append(String(format: String(localized: "更新于 %@"), Formatters.dateTime.string(from: lastStorageSampleAt)))
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
                HStack(spacing: 14) {
                    avatarPicker
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            userNameDraft = userName
                            showUserNameEditor = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(displayUserName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "编辑用户名"))
                        Text("\(AppBrand.displayName) · v\(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section(String(localized: "快捷设置")) {
                Toggle(String(localized: "公制单位"), isOn: $useMetric)
                Toggle(String(localized: "自动保存记录"), isOn: $autoSaveEnabled)

                Picker(String(localized: "配色"), selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker(String(localized: "主题"), selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker(String(localized: "语言"), selection: $languageCode) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                        Text(LocalizedStringKey(lang.displayName)).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if !languageSwitchFeedback.isEmpty {
                    Text(languageSwitchFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "数据安全")) {
                backupStatusCard
                NavigationLink { DataManagementView(initialRoute: .backup) } label: {
                    HStack(spacing: AppSpacing.tight) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(Color.appPrimaryAction)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "数据管理"))
                            Text(String(localized: "导出、备份、导入恢复、体检与清理"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("profile-data-management-link")
#if DEBUG
                if AppFeatureFlags.allowsSampleDataImport {
                    Button(role: .destructive) {
                        showSampleImportConfirm = true
                    } label: {
                        HStack(spacing: AppSpacing.tight) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.appWarning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "导入示例数据"))
                                Text(String(localized: "覆盖当前本地数据，用演示项目体验完整流程"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "导入示例数据"))
                    .accessibilityHint(String(localized: "会先确认，确认后覆盖当前本地数据"))
                }
#endif
            }

            Section(String(localized: "系统")) {
                NavigationLink { SettingsView() } label: {
                    Label(String(localized: "更多设置"), systemImage: "gear")
                }
                .accessibilityIdentifier("profile-settings-link")
            }

            Section(String(localized: "关于")) {
                HStack {
                    Label(String(localized: "当前版本"), systemImage: "info.circle")
                    Spacer()
                    Text("v\(appVersion)")
                        .foregroundStyle(.secondary)
                }
                NavigationLink { PrivacyPolicyView() } label: {
                    Label(String(localized: "隐私政策"), systemImage: "hand.raised.fill")
                }
                NavigationLink { OpenSourceLicensesView() } label: {
                    Label(String(localized: "开源许可"), systemImage: "curlybraces.square")
                }
                NavigationLink { FeedbackView() } label: {
                    Label(String(localized: "意见反馈"), systemImage: "envelope.fill")
                }
            }
        }
        .navigationTitle(String(localized: "我的"))
        .task {
            guard !hasLoadedStorageUsage else { return }
            hasLoadedStorageUsage = true
            migrateLegacyAppearanceIfNeeded()
            await refreshLocalStorageUsage()
        }
        .onChange(of: languageCode) { _, newCode in
            if let lang = AppLanguage(rawValue: newCode) {
                AppLanguage.apply(lang)
                languageSwitchFeedback = String(localized: "settings_language_switch_feedback")
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
            userNameEditorSheet
        }
#if DEBUG
        .alert(String(localized: "导入示例数据？"), isPresented: $showSampleImportConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "覆盖并导入"), role: .destructive) {
                store.importSampleData(replacingExisting: true)
                AppHaptics.success()
            }
        } message: {
            if store.hasAnyBusinessData {
                Text(String(localized: "将清空当前本地数据并写入示例项目、日志、报价、材料和仓库记录。此操作不可撤销。"))
            } else {
                Text(String(localized: "将写入示例项目、日志、报价、材料和仓库记录，便于演示功能。"))
            }
        }
#endif
    }

    private var backupStatusCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "备份与存储"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(backupStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "本机占用：%@"), localStorageUsageText))
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Text(storageCaptionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isRefreshingStorageUsage {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task {
                            await refreshLocalStorageUsage()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appStrokeSecondary, lineWidth: 1)
        )
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatarUIImage {
                        Image(uiImage: avatarUIImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .foregroundStyle(Color.appPrimaryAction)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.appStrokeSecondary, lineWidth: 1)
                )

                Image(systemName: "camera.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.appPrimaryAction, in: Circle())
                    .offset(x: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "修改头像"))
        .contextMenu {
            if hasCustomAvatar {
                Button(role: .destructive) {
                    userAvatarData = Data()
                } label: {
                    Label(String(localized: "恢复默认头像"), systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private var userNameEditorSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "用户名")) {
                    TextField(String(localized: "请输入用户名"), text: $userNameDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text(String(localized: "留空将显示“未设置用户名”。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "编辑用户名"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        showUserNameEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        userName = userNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        showUserNameEditor = false
                    }
                }
            }
        }
    }

    @MainActor
    private func updateAvatar(from item: PhotosPickerItem) async {
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

    private func migrateLegacyAppearanceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: UserPreferenceKeys.appearanceMode) == nil else { return }
        appearanceMode = legacyDarkMode ? AppAppearanceMode.dark.rawValue : AppAppearanceMode.system.rawValue
    }

    private func refreshLocalStorageUsage() async {
        guard !isRefreshingStorageUsage else { return }
        isRefreshingStorageUsage = true
        defer { isRefreshingStorageUsage = false }

        let snapshot = await Task.detached(priority: .utility) {
            Self.calculateLocalStorageUsage()
        }.value

        guard let snapshot else {
            localStorageUsageText = String(localized: "读取失败")
            localStorageFileCount = 0
            lastStorageSampleAt = nil
            return
        }

        localStorageUsageText = Self.formattedFileSize(snapshot.totalBytes)
        localStorageFileCount = snapshot.fileCount
        lastStorageSampleAt = Date()
    }

    nonisolated private static func formattedFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    nonisolated private static func calculateLocalStorageUsage() -> (totalBytes: Int64, fileCount: Int)? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: documentsDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var totalBytes: Int64 = 0
        var fileCount = 0
        while let object = autoreleasepool(invoking: { enumerator.nextObject() }) {
            guard let fileURL = object as? URL else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            totalBytes += Int64(size)
            fileCount += 1
        }
        return (totalBytes, fileCount)
    }
}

private struct OpenSourceLicensesView: View {
    private let gplURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    var body: some View {
        List {
            Section(String(localized: "内置开源组件")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LibreDWG")
                        .font(.headline)
                    Text(String(localized: "用于在本机读取 DWG 图纸几何并交给 CAD 查看器渲染。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(String(localized: "许可证"), value: String(localized: "GNU GPLv3 或更新版本"))
                LabeledContent(String(localized: "源码"), value: String(localized: "随发布提供对应源码包"))
            }

            Section(String(localized: "用户权利")) {
                Text(String(localized: "本发布包含 GPL 覆盖的软件。你可以按照 GPL 复制、分发和修改该组件及其对应源码；该组件按许可证原样提供，不提供担保。"))
                    .font(.callout)
            }

            Section(String(localized: "源码获取")) {
                Text(String(format: String(localized: "对应源码包会随发布提供；也可以通过 %@ 请求获取。"), AppContact.supportEmail))
                    .font(.callout)
                Link(String(localized: "查看 GNU GPLv3 完整文本"), destination: gplURL)
            }
        }
        .navigationTitle(String(localized: "开源许可"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
