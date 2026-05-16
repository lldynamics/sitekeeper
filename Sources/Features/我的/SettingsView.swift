import SwiftUI

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.showTemplates) private var showTemplates = AppFeatureFlags.showTemplates
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) private var backupHealthReminderDays = 7
    @State private var showSampleImportConfirm = false
    @State private var showClearLocalDataBackupGate = false
    @State private var showClearLocalDataSheet = false
    @State private var isClearingLocalData = false
    @State private var clearLocalDataFlowStartedAt = 0.0
    @State private var clearLocalDataPhase = ""

    private var allowsSampleDataImport: Bool {
        AppFeatureFlags.allowsSampleDataImport
    }

    private var clearLocalDataSnapshot: String {
        [
            "projects=\(store.projects.count)",
            "logs=\(store.dailyLogs.count)",
            "todos=\(store.siteTodos.count)",
            "quotes=\(store.quoteItems.count)",
            "materials=\(store.materialItems.count)",
            "drawings=\(store.projectDrawings.count)",
            "documents=\(store.projectDocuments.count)",
            "notes=\(store.quickNotes.count)"
        ].joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section(String(localized: "显示")) {
                Text(String(localized: "公制单位、自动保存、主题、配色和语言已放到“我的”首页快捷设置。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
#if DEBUG
            if allowsSampleDataImport {
                Section(String(localized: "示例数据")) {
                    Text(String(localized: "默认不预置示例项目和记录。如需演示，可手动导入示例数据。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "导入示例数据（覆盖当前本地数据）"), role: .destructive) {
                        showSampleImportConfirm = true
                    }
                }
            }
#endif
            Section(String(localized: "数据管理")) {
                Stepper(value: $backupHealthReminderDays, in: 1 ... 30) {
                    LabeledContent(
                        String(localized: "备份健康提醒阈值"),
                        value: String(format: String(localized: "%lld 天"), Int64(backupHealthReminderDays))
                    )
                }
                Text(String(localized: "超过该天数未成功备份时，工作台会显示“备份超期”提醒。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "清空本机全部数据（需先备份）"), role: .destructive) {
                    clearLocalDataFlowStartedAt = Date().timeIntervalSince1970
                    showClearLocalDataBackupGate = true
                }
                .disabled(isClearingLocalData)
                Text(String(localized: "将删除本机所有项目、附件与导入文件，不会影响你已导出的备份 ZIP。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isClearingLocalData {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            clearLocalDataPhase.isEmpty
                                ? String(localized: "正在清空本机数据，请稍候...")
                                : String(format: String(localized: "%@..."), clearLocalDataPhase)
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(String(localized: "实验功能")) {
                Toggle(String(localized: "显示模板管理入口"), isOn: $showTemplates)
                Text(String(localized: "默认关闭。开启后会在工具箱显示“模板管理”。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(String(localized: "关于")) {
                HStack {
                    Text(String(localized: "版本"))
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "设置")).navigationBarTitleDisplayMode(.inline)
#if DEBUG
        .alert(String(localized: "导入示例数据？"), isPresented: $showSampleImportConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "覆盖并导入"), role: .destructive) {
                store.importSampleData(replacingExisting: true)
            }
        } message: {
            if store.hasAnyBusinessData {
                Text(String(localized: "将清空当前本地数据并写入示例项目、日志、报价和材料。此操作不可撤销。"))
            } else {
                Text(String(localized: "将写入示例项目、日志、报价和材料，便于演示功能。"))
            }
        }
#endif
        .sheet(isPresented: $showClearLocalDataBackupGate) {
            ClearLocalDataBackupGateSheet(flowStartedAt: clearLocalDataFlowStartedAt) {
                showClearLocalDataBackupGate = false
                showClearLocalDataSheet = true
            }
        }
        .sheet(isPresented: $showClearLocalDataSheet) {
            ClearLocalDataConfirmationSheet {
                Task {
                    let snapshot = clearLocalDataSnapshot
                    await MainActor.run {
                        showClearLocalDataSheet = false
                        isClearingLocalData = true
                        clearLocalDataPhase = String(localized: "正在准备")
                        OperationAuditLog.record(
                            action: .delete,
                            outcome: .started,
                            summary: String(localized: "清空本机全部数据"),
                            detail: snapshot,
                            source: "SettingsView"
                        )
                    }
                    await store.clearAllBusinessDataAsync(deleteStoredFiles: true) { phase in
                        clearLocalDataPhase = phase
                    }
                    await MainActor.run {
                        isClearingLocalData = false
                        clearLocalDataPhase = ""
                        OperationAuditLog.record(
                            action: .delete,
                            outcome: .succeeded,
                            summary: String(localized: "清空本机全部数据"),
                            detail: snapshot,
                            source: "SettingsView"
                        )
                    }
                }
            } onCancel: {
                showClearLocalDataSheet = false
                OperationAuditLog.record(
                    action: .delete,
                    outcome: .cancelled,
                    summary: String(localized: "清空本机全部数据"),
                    source: "SettingsView"
                )
            }
        }
        .onAppear {
            backupHealthReminderDays = min(max(backupHealthReminderDays, 1), 30)
        }
    }

}

private struct ClearLocalDataBackupGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0

    let flowStartedAt: Double
    let onContinue: () -> Void

    private var hasBackupCreatedInThisFlow: Bool {
        localBackupLastSuccessAt > flowStartedAt
    }

    private var backupStatusText: String {
        guard localBackupLastSuccessAt > 0 else {
            return String(localized: "尚未生成本机备份")
        }
        let date = Date(timeIntervalSince1970: localBackupLastSuccessAt)
        return String(format: String(localized: "最近本机备份：%@"), Formatters.dateTime.string(from: date))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label(String(localized: "先备份再清空"), systemImage: "externaldrive.badge.checkmark")
                    .font(.title3.weight(.semibold))

                Text(String(localized: "清空本机数据前，必须先生成一份新的本机备份 ZIP。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    DataManagementView(initialRoute: .backup)
                } label: {
                    Label(String(localized: "去备份并导出 ZIP"), systemImage: "externaldrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text(String(localized: "导出完成后回到这里继续。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(backupStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasBackupCreatedInThisFlow {
                    Label(String(localized: "已检测到本次流程内的新备份"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appSuccess)
                } else {
                    Label(String(localized: "请先完成本机备份后再继续清空。"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appRisk)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button(String(localized: "取消"), role: .cancel) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button(String(localized: "继续清空"), role: .destructive) {
                        onContinue()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!hasBackupCreatedInThisFlow)
                }
            }
            .padding(20)
            .navigationTitle(String(localized: "清空本机数据"))
            .navigationBarTitleDisplayMode(.inline)
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
        .navigationTitle(String(localized: "收藏计算器")).navigationBarTitleDisplayMode(.inline)
    }
}

private struct ClearLocalDataConfirmationSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var requiredPhrase: String {
        String(localized: "确认删除数据")
    }

    private var isInputValid: Bool {
        input == requiredPhrase
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.appRisk)
                    .padding(.top, 24)

                Text(String(localized: "即将清空本机全部数据"))
                    .font(.title2.weight(.semibold))

                Text(String(localized: "此操作不可恢复。\n所有项目、日志、报价、材料与附件文件将被永久删除。"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: String(localized: "请输入「%@」以确认："), requiredPhrase))
                        .font(.callout.weight(.medium))
                    TextField(requiredPhrase, text: $input)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button(String(localized: "取消"), role: .cancel) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(String(localized: "确认清空"), role: .destructive) {
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
