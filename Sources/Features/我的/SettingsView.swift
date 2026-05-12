import SwiftUI

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.hasSeenBackupGuide) private var hasSeenBackupGuide = false
    @AppStorage(UserPreferenceKeys.hasSeenProjectFileRootGuide) private var hasSeenProjectFileRootGuide = false
    @AppStorage(UserPreferenceKeys.hasSeenProjectFileCategoryGuide) private var hasSeenProjectFileCategoryGuide = false
    @AppStorage(UserPreferenceKeys.hasCompletedBackupExportTask) private var hasCompletedBackupExportTask = false
    @AppStorage(UserPreferenceKeys.showTemplates) private var showTemplates = AppFeatureFlags.showTemplates
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) private var backupHealthReminderDays = 7
    @AppStorage(UserPreferenceKeys.materialLibraryPromptAfterAdd) private var materialLibraryPromptAfterAdd = true
    @AppStorage(UserPreferenceKeys.appTheme) private var appTheme = AppTheme.dropboxBlue.rawValue
    @State private var showSampleImportConfirm = false
    @State private var showClearLocalDataConfirm = false
    @State private var showClearLocalDataSheet = false
    @State private var isClearingLocalData = false
    @State private var clearLocalDataPhase = ""
    @State private var guideResetFeedback = ""

    private var allowsSampleDataImport: Bool {
        AppFeatureFlags.allowsSampleDataImport
    }

    var body: some View {
        Form {
            Section("显示与主题") {
                Picker("配色", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Text("公制单位、自动保存、主题和语言已放到“我的”首页快捷设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if allowsSampleDataImport {
                Section("示例数据") {
                    Text("默认不预置示例项目和记录。如需演示，可手动导入示例数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("导入示例数据（覆盖当前本地数据）", role: .destructive) {
                        showSampleImportConfirm = true
                    }
                }
            }
            Section("数据管理") {
                Stepper(value: $backupHealthReminderDays, in: 1 ... 30) {
                    LabeledContent("备份健康提醒阈值", value: "\(backupHealthReminderDays) 天")
                }
                Text("超过该天数未成功备份时，工作台会显示“备份超期”提醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("材料添加后提示前往材料单", isOn: $materialLibraryPromptAfterAdd)
                Text("关闭后，材料库添加成功将只显示顶部提示，不再弹窗询问是否跳转。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("清空本机全部数据（不可恢复）", role: .destructive) {
                    showClearLocalDataConfirm = true
                }
                .disabled(isClearingLocalData)
                Text("将删除本机所有项目、附件与导入文件，不会影响你已导出的备份 ZIP。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isClearingLocalData {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(clearLocalDataPhase.isEmpty ? "正在清空本机数据，请稍候..." : "\(clearLocalDataPhase)...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("实验功能") {
                Toggle("显示模板管理入口", isOn: $showTemplates)
                Text("默认关闭。开启后会在工具箱显示“模板管理”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("使用提示") {
                Button {
                    resetGuideState()
                } label: {
                    Label("重新显示使用提示", systemImage: "arrow.counterclockwise")
                }
                Text("会重新显示备份页和项目文件页的新手提示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !guideResetFeedback.isEmpty {
                    Text(guideResetFeedback)
                        .font(.caption)
                        .foregroundStyle(.appSuccess)
                }
            }
            Section("关于") {
                HStack { Text("版本"); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .alert("导入示例数据？", isPresented: $showSampleImportConfirm) {
            Button("取消", role: .cancel) {}
            Button("覆盖并导入", role: .destructive) {
                store.importSampleData(replacingExisting: true)
            }
        } message: {
            if store.hasAnyBusinessData {
                Text("将清空当前本地数据并写入示例项目、日志、报价和材料。此操作不可撤销。")
            } else {
                Text("将写入示例项目、日志、报价和材料，便于演示功能。")
            }
        }
        .alert("即将清空本机数据", isPresented: $showClearLocalDataConfirm) {
            Button("取消", role: .cancel) {}
            Button("继续", role: .destructive) {
                showClearLocalDataSheet = true
            }
        } message: {
            Text("此操作会删除本机全部项目数据与附件文件，且无法恢复。建议先在「数据管理」里导出 ZIP。")
        }
        .sheet(isPresented: $showClearLocalDataSheet) {
            ClearLocalDataConfirmationSheet {
                Task {
                    await MainActor.run {
                        showClearLocalDataSheet = false
                        isClearingLocalData = true
                        clearLocalDataPhase = "正在准备"
                    }
                    await store.clearAllBusinessDataAsync(deleteStoredFiles: true) { phase in
                        clearLocalDataPhase = phase
                    }
                    await MainActor.run {
                        isClearingLocalData = false
                        clearLocalDataPhase = ""
                    }
                }
            } onCancel: {
                showClearLocalDataSheet = false
            }
        }
        .onAppear {
            backupHealthReminderDays = min(max(backupHealthReminderDays, 1), 30)
        }
    }

    private func resetGuideState() {
        hasSeenBackupGuide = false
        hasSeenProjectFileRootGuide = false
        hasSeenProjectFileCategoryGuide = false
        hasCompletedBackupExportTask = false
        guideResetFeedback = "已重置。下次进入相关页面会再次显示使用提示。"
    }
}

private struct FavoriteCalcEditor: View {
    @AppStorage(UserPreferenceKeys.favoriteCalculators) private var data = ""
    private let all = CalculatorDestination.allCases

    private var favSet: Set<String> {
        Set(data.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    var body: some View {
        List {
            ForEach(all, id: \.title) { def in
                HStack {
                    ToolRow(icon: def.icon, title: def.title, desc: def.desc, color: .appWarning)
                    Spacer()
                    let isFav = favSet.contains(def.title)
                    Button {
                        var set = favSet
                        if isFav { set.remove(def.title) } else { set.insert(def.title) }
                        data = set.sorted().joined(separator: ",")
                    } label: {
                        Image(systemName: isFav ? "star.fill" : "star")
                            .foregroundStyle(isFav ? .appWarning : .appMuted)
                    }
                }
            }
        }
        .navigationTitle("收藏计算器").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ClearLocalDataConfirmationSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private static let requiredPhrase = "确认删除数据"

    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var isInputValid: Bool {
        input == Self.requiredPhrase
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.appRisk)
                    .padding(.top, 24)

                Text("即将清空本机全部数据")
                    .font(.title2.weight(.semibold))

                Text("此操作不可恢复。\n所有项目、日志、报价、材料与附件文件将被永久删除。\n建议先在「数据管理」中导出一份 ZIP。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("请输入「\(Self.requiredPhrase)」以确认：")
                        .font(.callout.weight(.medium))
                    TextField(Self.requiredPhrase, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button("取消", role: .cancel) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("确认清空", role: .destructive) {
                        onConfirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isInputValid)
                }
                .padding(.top, 8)

                Spacer()
            }
            .interactiveDismissDisabled()
            .onAppear { isFocused = true }
        }
    }
}
