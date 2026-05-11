import SwiftUI

private enum DataManagementTab: String, CaseIterable {
    case export = "导出"
    case backup = "备份"
    case restore = "导入恢复"

    var displayName: String { rawValue }
}

struct DataManagementView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedTab: DataManagementTab
    @State private var showClearHistoryConfirm = false

    init(initialTab: String? = nil) {
        if let initialTab, let tab = DataManagementTab(rawValue: initialTab) {
            _selectedTab = State(initialValue: tab)
        } else {
            _selectedTab = State(initialValue: .export)
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.normal) {
            Picker("数据管理", selection: $selectedTab) {
                ForEach(DataManagementTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if !store.historyRecords.isEmpty {
                HStack(spacing: AppSpacing.tight) {
                    Label("计算历史 \(store.historyRecords.count) 条", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空计算历史", role: .destructive) {
                        showClearHistoryConfirm = true
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal)
            }

            Group {
                switch selectedTab {
                case .export:
                    ExportView(showsNavigationTitle: false)
                case .backup:
                    BackupView(showsNavigationTitle: false)
                case .restore:
                    BackupView(autoOpenImporter: true, showsNavigationTitle: false)
                }
            }
            .id(selectedTab)
        }
        .navigationTitle("数据管理")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("清空所有计算历史？", isPresented: $showClearHistoryConfirm) {
            Button("清空", role: .destructive) { store.clearCalculationHistory() }
            Button("取消", role: .cancel) {}
        }
    }
}
