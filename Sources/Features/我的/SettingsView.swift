import SwiftUI

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.showTemplates) private var showTemplates = AppFeatureFlags.showTemplates
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) private var backupHealthReminderDays = 7
    @AppStorage(UserPreferenceKeys.cadPreviewEngine) private var cadPreviewEngineRaw = CADPreviewEngine.libreDWG.rawValue
    @State private var showSampleImportConfirm = false
    @State private var showClearLocalDataConfirm = false
    @State private var showClearLocalDataSheet = false
    @State private var isClearingLocalData = false
    @State private var clearLocalDataPhase = ""

    private var allowsSampleDataImport: Bool {
        AppFeatureFlags.allowsSampleDataImport
    }

    private var selectedCADEngine: CADPreviewEngine {
        get {
            StringEnumFallback.value(cadPreviewEngineRaw, default: .libreDWG)
        }
        nonmutating set {
            cadPreviewEngineRaw = newValue.rawValue
        }
    }

    private var isLibreDWGAvailable: Bool {
        CADPreviewCapability.isLibreDWGRendererAvailable()
    }

    var body: some View {
        Form {
            Section("显示") {
                Text("公制单位、自动保存、主题、配色和语言已放到“我的”首页快捷设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("CAD 预览") {
                Picker("图纸预览引擎", selection: $cadPreviewEngineRaw) {
                    ForEach(CADPreviewEngine.allCases, id: \.rawValue) { engine in
                        Text(engine.title).tag(engine.rawValue)
                    }
                }
                .pickerStyle(.menu)
                if isLibreDWGAvailable {
                    Text("LibreDWGBridge 已接入，可在应用内尝试直接预览 DWG/DXF。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("当前构建未接入 LibreDWGBridge。选择 LibreDWG 时会显示接入提示；系统引擎仍建议使用同名 PDF 预览。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedCADEngine == .libreDWG {
                        Button("切回系统 CAD 预览") {
                            selectedCADEngine = .systemQuickLook
                        }
                    }
                }
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
            let normalized = StringEnumFallback.value(cadPreviewEngineRaw, default: CADPreviewEngine.libreDWG)
            if normalized.rawValue != cadPreviewEngineRaw {
                cadPreviewEngineRaw = normalized.rawValue
            }
        }
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
