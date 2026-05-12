import SwiftUI

private enum HealthCleanupSection: String, CaseIterable {
    case health = "健康检查"
    case storage = "存储清理"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .health:
            return "stethoscope"
        case .storage:
            return "internaldrive"
        }
    }

    var summary: String {
        switch self {
        case .health:
            return "扫描缺失文件、无效关联与孤立文件，并支持一键修复。"
        case .storage:
            return "查看照片/视频/CAD/备份/历史计算占用，支持按项目清理附件文件。"
        }
    }

    static func from(route: String?) -> Self {
        guard let route else { return .health }
        switch route {
        case "存储清理", "存储", "空间清理":
            return .storage
        default:
            return .health
        }
    }
}

private enum DataManagementTab: String, CaseIterable {
    case export = "导出"
    case backup = "备份"
    case restore = "导入恢复"
    case healthAndCleanup = "体检与清理"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .export:
            return "square.and.arrow.up"
        case .backup:
            return "externaldrive"
        case .restore:
            return "arrow.clockwise.icloud"
        case .healthAndCleanup:
            return "cross.case.fill"
        }
    }

    var summary: String {
        switch self {
        case .export:
            return "按项目或日期筛选后导出 CSV / Excel / PDF / ZIP。"
        case .backup:
            return "创建本地或 iCloud 备份，并查看备份体积与恢复建议。"
        case .restore:
            return "导入备份并预览差异，可选择合并或覆盖当前数据。"
        case .healthAndCleanup:
            return "统一查看健康检查和存储占用，集中完成体检、修复与清理。"
        }
    }

    static func from(route: String?) -> Self {
        guard let route else { return .export }
        switch route {
        case "导出", "导出数据":
            return .export
        case "备份", "数据备份":
            return .backup
        case "导入恢复", "恢复", "导入":
            return .restore
        case "健康检查", "数据健康":
            return .healthAndCleanup
        case "存储清理", "存储", "空间清理":
            return .healthAndCleanup
        default:
            return DataManagementTab(rawValue: route) ?? .export
        }
    }
}

struct DataManagementView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedTab: DataManagementTab
    @State private var healthCleanupSection: HealthCleanupSection
    @State private var showClearHistoryConfirm = false

    init(initialTab: String? = nil) {
        _selectedTab = State(initialValue: DataManagementTab.from(route: initialTab))
        _healthCleanupSection = State(initialValue: HealthCleanupSection.from(route: initialTab))
    }

    private var historyTrimCount: Int {
        let perToolLimit = store.historyRetentionPerToolLimit
        let totalLimit = store.historyRetentionTotalLimit
        var kept = 0
        var perToolCounts: [String: Int] = [:]
        for record in store.historyRecords {
            guard kept < totalLimit else { break }
            let count = perToolCounts[record.tool, default: 0]
            guard count < perToolLimit else { continue }
            perToolCounts[record.tool] = count + 1
            kept += 1
        }
        return max(store.historyRecords.count - kept, 0)
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

            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: selectedTab.icon)
                    .foregroundStyle(.appWarning)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
                Text(selectedTab.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            if !store.historyRecords.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.tight * 0.6) {
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
                    HStack(spacing: AppSpacing.tight) {
                        Text("保留策略：每工具最近 \(store.historyRetentionPerToolLimit) 条，总计最多 \(store.historyRetentionTotalLimit) 条")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if historyTrimCount > 0 {
                            Button("按策略清理 \(historyTrimCount) 条") {
                                store.enforceCalculationHistoryRetention()
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.appWarning)
                        }
                    }
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
                case .healthAndCleanup:
                    healthAndCleanupContent
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

    private var healthAndCleanupContent: some View {
        VStack(spacing: AppSpacing.normal) {
            Picker("体检与清理", selection: $healthCleanupSection) {
                ForEach(HealthCleanupSection.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: healthCleanupSection.icon)
                    .foregroundStyle(.appWarning)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
                Text(healthCleanupSection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            Group {
                switch healthCleanupSection {
                case .health:
                    DataHealthView(showsNavigationTitle: false)
                case .storage:
                    StorageCleanupCenterView(showsNavigationTitle: false)
                }
            }
            .id(healthCleanupSection)
        }
    }
}
