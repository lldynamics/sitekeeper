import SwiftUI

struct ProjectContextRow: View {
    let project: Project
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(project.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
            }
            HStack(spacing: 8) {
                if !project.location.isEmpty {
                    Label(project.location, systemImage: "mappin.and.ellipse")
                }
                if !project.managerName.isEmpty {
                    Label(project.managerName, systemImage: "person.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
                Section(String(localized: "今日关注工程")) {
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
            .searchable(text: $searchText, prompt: String(localized: "搜索工程"))
            .navigationTitle(String(localized: "选择当前工程"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DashboardProjectChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let color: Color

    private var minChipWidth: CGFloat {
        isSelected ? 124 : 104
    }

    private var maxChipWidth: CGFloat {
        isSelected ? 240 : 152
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight * 0.625) {
            HStack(spacing: AppSpacing.tight * 0.625) {
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
                .lineLimit(1)
        }
        .frame(minWidth: minChipWidth, maxWidth: maxChipWidth, alignment: .leading)
        .frame(minHeight: 52, alignment: .topLeading)
        .padding(.horizontal, AppSpacing.normal - 2)
        .padding(.vertical, AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.tight + 1)
                .fill(isSelected ? color : color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.tight + 1)
                .stroke(isSelected ? color : color.opacity(0.28), lineWidth: 1)
        )
    }
}

struct TimelineActivity {
    let id: String
    let projectId: UUID?
    let type: TimelineActivityType
    let title: String
    let date: String
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
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.25) {
                Text(activity.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: AppSpacing.tight * 0.75) {
                    if let name = projectName {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(activity.subtitle)
                        .font(.caption2)
                        .foregroundStyle(tint)
                }
            }
            Spacer()
            Text(activity.date)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, AppSpacing.normal - 2)
        .padding(.vertical, AppSpacing.tight * 0.75)
        .background(RoundedRectangle(cornerRadius: AppSpacing.tight).fill(Color(uiColor: .tertiarySystemGroupedBackground)))
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
                Text(String(localized: "暂无数据"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: AppSpacing.tight * 0.75) {
                    if warehouse > 0 { tag(String(localized: "📦 \(warehouse)"), color: .appInventory) }
                    if overdue > 0   { tag(String(localized: "⚠️ \(overdue)"), color: .appRisk) }
                    if todos > 0     { tag(String(localized: "✅ \(todos)"), color: .appWarning) }
                    if logs > 0      { tag(String(localized: "📝 \(logs)"), color: .appDoc) }
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
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, AppSpacing.normal)
            .padding(.vertical, AppSpacing.tight)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
