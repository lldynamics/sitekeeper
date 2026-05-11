import SwiftUI

struct ProfileTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(UserPreferenceKeys.userName) private var userName = ""
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    @AppStorage(UserPreferenceKeys.autoSave) private var autoSaveEnabled = true
    @AppStorage(UserPreferenceKeys.darkMode) private var legacyDarkMode = false
    @AppStorage(UserPreferenceKeys.appearanceMode) private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage(UserPreferenceKeys.languageCode) private var languageCode = AppLanguage.chinese.rawValue
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudBackupLastSuccessAt = 0.0
    @State private var languageSwitchFeedback = ""
    @State private var localStorageUsageText = "正在统计..."
    @State private var localStorageFileCount = 0
    @State private var isRefreshingStorageUsage = false
    @State private var lastStorageSampleAt: Date?
    @State private var hasLoadedStorageUsage = false
    let embedsNavigationStack: Bool

    init(embedsNavigationStack: Bool = true) {
        self.embedsNavigationStack = embedsNavigationStack
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var displayUserName: String {
        let value = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未设置用户名" : value
    }

    private var backupStatusText: String {
        guard cloudBackupLastSuccessAt > 0 else { return "尚未记录云备份成功" }
        let date = Date(timeIntervalSince1970: cloudBackupLastSuccessAt)
        return "最近云备份：\(Formatters.dateTime.string(from: date))"
    }

    private var storageCaptionText: String {
        var parts = ["\(localStorageFileCount) 个文件"]
        if let lastStorageSampleAt {
            parts.append("更新于 \(Formatters.dateTime.string(from: lastStorageSampleAt))")
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
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayUserName)
                            .font(.title3.weight(.semibold))
                        Text("\(AppBrand.displayName) · v\(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("快捷设置") {
                Toggle("公制单位", isOn: $useMetric)
                Toggle("自动保存记录", isOn: $autoSaveEnabled)

                Picker("主题", selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("语言", selection: $languageCode) {
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

            Section("数据安全") {
                backupStatusCard
                NavigationLink { DataManagementView(initialTab: "导出") } label: {
                    Label("数据管理", systemImage: "externaldrive")
                }
                NavigationLink { DataHealthView() } label: {
                    Label("数据健康检查", systemImage: "stethoscope")
                }
            }

            Section("系统") {
                NavigationLink { SettingsView() } label: {
                    Label("更多设置", systemImage: "gear")
                }
            }

            Section("关于") {
                HStack {
                    Label("当前版本", systemImage: "info.circle")
                    Spacer()
                    Text("v\(appVersion)")
                        .foregroundStyle(.secondary)
                }
                NavigationLink { PrivacyPolicyView() } label: {
                    Label("隐私政策", systemImage: "hand.raised.fill")
                }
                NavigationLink { FeedbackView() } label: {
                    Label("意见反馈", systemImage: "envelope.fill")
                }
            }
        }
        .navigationTitle("我的")
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
    }

    private var backupStatusCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("备份与存储")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(backupStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("本机占用：\(localStorageUsageText)")
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
            localStorageUsageText = "读取失败"
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
