import SwiftUI

struct DashboardProjectRow: Identifiable {
    var id: UUID { project.id }
    let project: Project
    let subtitle: String
    let color: Color
    let score: Int
    let activityDate: Date
}

struct DashboardProjectSignal {
    let subtitle: String
    let color: Color
    let score: Int
}

enum DashboardSubtitleBuilder {
    static func joined(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    static func moneySummary(_ leading: String, amount: String) -> String {
        joined([leading, amount])
    }

    static func datedAmount(_ date: String, amount: String, projectName: String? = nil) -> String {
        joined([date, amount, projectName ?? ""])
    }

    static func versionState(_ versionLabel: String, state: String) -> String {
        joined([versionLabel, state])
    }

    static func progress(_ completion: Double) -> String {
        String(format: AppLocalization.string("%lld%%"), Int64(completion.rounded(.towardZero)))
    }

    static func todoStatus(isDone: Bool) -> String {
        isDone ? AppLocalization.string("已完成") : AppLocalization.string("未完成")
    }

    static func labor(workers: String, hours: String) -> String {
        joined(["\(workers)人", "\(hours)h"])
    }

    static func document(category: String, pageCount: Int) -> String {
        joined([category, String(format: AppLocalization.string("%lld页"), Int64(pageCount))])
    }

    static func projectSignal(label: String, count: Int) -> String {
        String(format: AppLocalization.string("%@ %lld"), label, Int64(count))
    }

    static func overdue(_ count: Int) -> String {
        projectSignal(label: AppLocalization.string("延期"), count: count)
    }

    static func today(_ count: Int) -> String {
        projectSignal(label: AppLocalization.string("今日"), count: count)
    }

    static func missingReceipt(_ count: Int) -> String {
        projectSignal(label: AppLocalization.string("缺票"), count: count)
    }

    static func priceSpike(_ count: Int) -> String {
        projectSignal(label: AppLocalization.string("价格异动"), count: count)
    }

    static func openTodo(_ count: Int) -> String {
        projectSignal(label: AppLocalization.string("待办"), count: count)
    }
}

struct DashboardProjectPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [DashboardProjectRow]
    let selectedProjectId: UUID?
    let onSelect: (UUID?) -> Void
    @State private var searchText = ""

    private var filteredRows: [DashboardProjectRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.project.name.localizedStandardContains(query)
            || $0.project.location.localizedStandardContains(query)
            || $0.subtitle.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(AppLocalization.string("今日关注工程")) {
                    ForEach(filteredRows) { row in
                        Button {
                            onSelect(row.project.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedProjectId == row.project.id ? "checkmark.circle.fill" : "building.2")
                                    .foregroundStyle(selectedProjectId == row.project.id ? row.color : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.project.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text(row.subtitle)
                                            .foregroundStyle(row.color)
                                        if !row.project.location.isEmpty {
                                            Text(row.project.location)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: AppLocalization.string("搜索工程"))
            .navigationTitle(AppLocalization.string("选择当前工程"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("关闭")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DashboardProjectChip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var accessibleMinimumHeight: CGFloat = 76
    let title: String
    let subtitle: String
    let isSelected: Bool
    let color: Color

    private var minChipWidth: CGFloat {
        isSelected ? 136 : 116
    }

    private var maxChipWidth: CGFloat {
        isSelected ? 260 : 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight * 0.625) {
            HStack(alignment: .center, spacing: AppSpacing.tight * 0.625) {
                Circle()
                    .fill(isSelected ? .white : color)
                    .frame(width: AppSpacing.tight * 0.75, height: AppSpacing.tight * 0.75)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSelected ? .white.opacity(0.88) : color)
                .appListSecondaryTextLayout()
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: minChipWidth, maxWidth: maxChipWidth, alignment: .leading)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? accessibleMinimumHeight : 66, alignment: .leading)
        .padding(.horizontal, AppSpacing.normal - 2)
        .padding(.vertical, AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.tight + 2, style: .continuous)
                .fill(isSelected ? color : Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.tight + 2, style: .continuous)
                .stroke(isSelected ? color : Color(uiColor: .separator).opacity(0.10), lineWidth: isSelected ? 1 : 0.5)
        )
    }
}

struct TimelineActivity {
    let id: String
    let projectId: UUID?
    let type: TimelineActivityType
    let title: String
    let date: BusinessDateValue
    let subtitle: String
}

enum TimelineActivityType {
    case log
    case todo
    case financial
    case progress
    case material
    case drawing
    case quote
    case labor
    case document
    case warehouse
    case note

    var projectDetailMode: ProjectDetailMode {
        switch self {
        case .log, .todo, .progress, .note:
            return .records
        case .drawing, .document:
            return .assets
        case .financial, .material, .quote, .labor, .warehouse:
            return .finance
        }
    }
}

struct TimelineActivityRow: View {
    let activity: TimelineActivity
    let projectName: String?
    var showsChevron = false

    private var icon: String {
        switch activity.type {
        case .log: return "book.pages"
        case .todo: return "checkmark.circle"
        case .financial: return "yensign.circle"
        case .progress: return "checklist.checked"
        case .material: return "shippingbox"
        case .drawing: return "doc.richtext"
        case .quote: return "doc.text"
        case .labor: return "person.2"
        case .document: return "doc.viewfinder"
        case .warehouse: return "shippingbox.and.arrow.backward"
        case .note: return "square.and.pencil"
        }
    }

    private var tint: Color {
        switch activity.type {
        case .log: return .appDoc
        case .todo: return .appWarning
        case .financial: return .appSuccess
        case .progress: return .appWarning
        case .material: return .appInventory
        case .drawing: return .appDoc
        case .quote: return .appFinance
        case .labor: return .appFinance
        case .document: return .appDoc
        case .warehouse: return .appInventory
        case .note: return .appFinance
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.tight + 2) {
            Image(systemName: icon)
                .font(.callout.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.35) {
                Text(activity.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .appListPrimaryTextLayout()
                HStack(spacing: AppSpacing.tight * 0.75) {
                    if let name = projectName {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .appListSecondaryTextLayout(lines: 1)
                    }
                    Text(activity.subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                        .appListSecondaryTextLayout(lines: 1)
                }
            }
            Spacer()
            Text(Formatters.displayRelativeOrShortDate(activity.date))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, AppSpacing.normal - 2)
        .padding(.vertical, AppSpacing.tight + 1)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
        )
    }
}

struct PanelSummaryLabel: View {
    let warehouse: Int
    let overdue: Int
    let todos: Int
    let logs: Int

    var body: some View {
        Group {
            if warehouse == 0, overdue == 0, todos == 0, logs == 0 {
                Text(AppLocalization.string("暂无数据"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: AppSpacing.tight * 0.75) {
                    if warehouse > 0 { tag(String(format: AppLocalization.string("📦 %lld"), Int64(warehouse)), color: .appInventory) }
                    if overdue > 0 { tag(String(format: AppLocalization.string("⚠️ %lld"), Int64(overdue)), color: .appRisk) }
                    if todos > 0 { tag(String(format: AppLocalization.string("✅ %lld"), Int64(todos)), color: .appWarning) }
                    if logs > 0 { tag(String(format: AppLocalization.string("📝 %lld"), Int64(logs)), color: .appDoc) }
                }
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, AppSpacing.tight * 0.75)
            .padding(.vertical, AppSpacing.tight * 0.25)
            .background(RoundedRectangle(cornerRadius: AppSpacing.tight * 0.5).fill(color.opacity(0.1)))
            .foregroundStyle(color)
    }
}

struct DashboardToastView: View {
    let message: String

    var body: some View {
        AppPanel(
            tone: .materialThin,
            cornerRadius: 999,
            padding: 0,
            shadow: .card,
            stroke: Color(uiColor: .separator).opacity(0.45)
        ) {
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, AppSpacing.tight)
        }
    }
}
