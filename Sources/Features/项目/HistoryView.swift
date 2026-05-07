import SwiftUI

struct HistoryView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedRecord: HistoryRecord?
    @State private var showClearConfirm = false

    var body: some View {
        List {
            if store.historyRecords.isEmpty {
                Text("暂无历史记录").foregroundStyle(.secondary)
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
                let ids = idx.map { store.historyRecords[$0].id }
                store.historyRecords.removeAll { ids.contains($0.id) }
                store.scheduleSave()
            }
        }
        .navigationTitle("历史计算")
        .toolbar {
            if !store.historyRecords.isEmpty {
                Button { showClearConfirm = true } label: { Text("清空") }
            }
        }
        .confirmationDialog("清空所有历史？", isPresented: $showClearConfirm) {
            Button("清空", role: .destructive) { store.historyRecords.removeAll(); store.scheduleSave() }
            Button("取消", role: .cancel) {}
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
}
