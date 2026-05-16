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
                    "还没有计算历史",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("完成一次计算后，最近结果会显示在这里。")
                )
            }
            ForEach(store.historyRecords) { r in
                Button { selectedRecord = r } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.tool).font(.body.weight(.medium))
                            Spacer(); Text(r.date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("输入: \(r.input)").font(.caption).foregroundStyle(.secondary)
                        Text("结果: \(r.result)").font(.callout)
                    }
                }
            }
            .onDelete { idx in
                let ids = Set(idx.compactMap { store.historyRecords.indices.contains($0) ? store.historyRecords[$0].id : nil })
                deleteHistoryRecords(ids: ids)
            }
        }
        .navigationTitle("历史计算")
        .toolbar {
            if !store.historyRecords.isEmpty {
                Button { showClearConfirm = true } label: { Text("清空") }
            }
        }
        .confirmationDialog("清空所有历史？", isPresented: $showClearConfirm) {
            Button("清空", role: .destructive) { clearHistoryRecords() }
            Button("取消", role: .cancel) {}
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                Form {
                    Section("计算详情") {
                        LabeledContent("工具", value: record.tool)
                        LabeledContent("时间", value: record.date)
                    }
                    Section("输入") { Text(record.input).font(.callout) }
                    Section("结果") { Text(record.result).font(.title3.monospaced()) }
                    Section {
                        Button { ClipboardService.copy(record.result) } label: {
                            Label("复制结果", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                        }
                    }
                }
                .navigationTitle("历史详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { selectedRecord = nil } } }
            }
            .presentationDetents([.medium])
        }
    }

    private func deleteHistoryRecords(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let snapshot = store.historyRecords
        let targets = snapshot.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        store.historyRecords.removeAll { ids.contains($0.id) }
        queueHistoryDeletion(snapshot: snapshot, ids: ids, count: targets.count, clearAll: false)
    }

    private func clearHistoryRecords() {
        let snapshot = store.historyRecords
        guard !snapshot.isEmpty else { return }
        let ids = Set(snapshot.map(\.id))
        store.historyRecords.removeAll()
        selectedRecord = nil
        queueHistoryDeletion(snapshot: snapshot, ids: ids, count: snapshot.count, clearAll: true)
    }

    private func queueHistoryDeletion(snapshot: [HistoryRecord], ids: Set<UUID>, count: Int, clearAll: Bool) {
        undoableDeletion.queue(
            notice: $operationNotice,
            message: clearAll
                ? String(format: String(localized: "已清空 %lld 条计算历史"), Int64(count))
                : String(format: String(localized: "已删除 %lld 条计算历史"), Int64(count)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.historyRecords = UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.historyRecords,
                    deletedIDs: ids
                )
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: clearAll
                    ? String(format: String(localized: "清空计算历史 %lld 条"), Int64(count))
                    : String(format: String(localized: "删除计算历史 %lld 条"), Int64(count)),
                source: "CalculationHistoryView"
            )
        )
    }
}
