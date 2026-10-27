import SwiftUI

struct CalculationHistoryView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedRecord: HistoryRecord?
    @State private var showClearConfirm = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    var body: some View {
        List {
            if store.historyRecords.isEmpty {
                ContentUnavailableView(
                    AppLocalization.string("还没有计算历史"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(AppLocalization.string("计算完成后，点击“保存到历史记录”即可在这里查看。"))
                )
            }
            ForEach(store.historyRecords) { r in
                Button { selectedRecord = r } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.tool).font(.body.weight(.medium))
                            Spacer()
                            Text(Formatters.displayDateText(r.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(String(format: AppLocalization.string("输入: %@"), r.input))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let projectName = projectName(for: r.projectId) {
                            Label(String(format: AppLocalization.string("项目: %@"), projectName), systemImage: "building.2")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(String(format: AppLocalization.string("结果: %@"), r.result))
                            .font(.callout)
                    }
                }
            }
            .onDelete { idx in
                let ids = Set(idx.compactMap { store.historyRecords.indices.contains($0) ? store.historyRecords[$0].id : nil })
                deleteHistoryRecords(ids: ids)
            }
        }
        .navigationTitle(AppLocalization.string("历史计算"))
        .toolbar {
            if !store.historyRecords.isEmpty {
                Button { showClearConfirm = true } label: { Text(AppLocalization.string("清空")) }
            }
        }
        .confirmationDialog(AppLocalization.string("清空所有历史？"), isPresented: $showClearConfirm) {
            Button(AppLocalization.string("清空"), role: .destructive) { clearHistoryRecords() }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                Form {
                    Section(AppLocalization.string("计算详情")) {
                        LabeledContent(AppLocalization.string("工具"), value: record.tool)
                        LabeledContent(AppLocalization.string("时间"), value: Formatters.displayDateText(record.date))
                        if let projectName = projectName(for: record.projectId) {
                            LabeledContent(AppLocalization.string("项目"), value: projectName)
                        }
                    }
                    Section(AppLocalization.string("输入")) { Text(record.input).font(.callout) }
                    Section(AppLocalization.string("结果")) { Text(record.result).font(.title3.monospaced()) }
                    Section {
                        Button { ClipboardService.copy(record.result) } label: {
                            Label(AppLocalization.string("复制结果"), systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .navigationTitle(AppLocalization.string("历史详情")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocalization.string("关闭")) { selectedRecord = nil }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func deleteHistoryRecords(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let count = store.historyRecords.filter { ids.contains($0.id) }.count
        let deletion = store.removeCalculationHistory(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("删除计算历史 %lld 条"), Int64(count)),
                source: "CalculationHistoryView"
            )
        )
        queueHistoryDeletion(deletion, clearAll: false)
    }

    private func clearHistoryRecords() {
        let count = store.historyRecords.count
        let deletion = store.clearCalculationHistory(
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("清空计算历史 %lld 条"), Int64(count)),
                source: "CalculationHistoryView"
            )
        )
        selectedRecord = nil
        queueHistoryDeletion(deletion, clearAll: true)
    }

    private func queueHistoryDeletion(_ deletion: DataStoreRemovalResult<HistoryRecord>, clearAll: Bool) {
        guard !deletion.isEmpty else { return }
        undoableDeletion.queue(
            notice: $operationNotice,
            message: clearAll
                ? String(format: AppLocalization.string("已清空 %lld 条计算历史"), Int64(deletion.deletedCount))
                : String(format: AppLocalization.string("已删除 %lld 条计算历史"), Int64(deletion.deletedCount)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreHistoryRecords(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func projectName(for projectId: UUID?) -> String? {
        guard let projectId else { return nil }
        return store.projects.first { $0.id == projectId }?.name ?? AppLocalization.string("未知项目")
    }
}
