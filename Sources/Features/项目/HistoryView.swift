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
                    String(localized: "还没有计算历史"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(String(localized: "完成一次计算后，最近结果会显示在这里。"))
                )
            }
            ForEach(store.historyRecords) { r in
                Button { selectedRecord = r } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.tool).font(.body.weight(.medium))
                            Spacer(); Text(r.date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(String(format: String(localized: "输入: %@"), r.input))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "结果: %@"), r.result))
                            .font(.callout)
                    }
                }
            }
            .onDelete { idx in
                let ids = Set(idx.compactMap { store.historyRecords.indices.contains($0) ? store.historyRecords[$0].id : nil })
                deleteHistoryRecords(ids: ids)
            }
        }
        .navigationTitle(String(localized: "历史计算"))
        .toolbar {
            if !store.historyRecords.isEmpty {
                Button { showClearConfirm = true } label: { Text(String(localized: "清空")) }
            }
        }
        .confirmationDialog(String(localized: "清空所有历史？"), isPresented: $showClearConfirm) {
            Button(String(localized: "清空"), role: .destructive) { clearHistoryRecords() }
            Button(String(localized: "取消"), role: .cancel) {}
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                Form {
                    Section(String(localized: "计算详情")) {
                        LabeledContent(String(localized: "工具"), value: record.tool)
                        LabeledContent(String(localized: "时间"), value: record.date)
                    }
                    Section(String(localized: "输入")) { Text(record.input).font(.callout) }
                    Section(String(localized: "结果")) { Text(record.result).font(.title3.monospaced()) }
                    Section {
                        Button { ClipboardService.copy(record.result) } label: {
                            Label(String(localized: "复制结果"), systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .navigationTitle(String(localized: "历史详情")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "关闭")) { selectedRecord = nil }
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
                summary: String(format: String(localized: "删除计算历史 %lld 条"), Int64(count)),
                source: "CalculationHistoryView"
            )
        )
        queueHistoryDeletion(deletion, clearAll: false)
    }

    private func clearHistoryRecords() {
        let count = store.historyRecords.count
        let deletion = store.clearCalculationHistory(
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "清空计算历史 %lld 条"), Int64(count)),
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
                ? String(format: String(localized: "已清空 %lld 条计算历史"), Int64(deletion.deletedCount))
                : String(format: String(localized: "已删除 %lld 条计算历史"), Int64(deletion.deletedCount)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.historyRecords = deletion.restoredItems(
                    current: store.historyRecords,
                    id: \.id
                )
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }
}
