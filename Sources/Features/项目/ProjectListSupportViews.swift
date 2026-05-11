import SwiftUI

enum ProjectOverviewFilter: String {
    case active
    case overdue
    case todo
    case missingReceipt
    case financialDue
    case missingTodayLog
}

enum ProjectSortOption: String, CaseIterable {
    case recentUpdate = "最近更新"
    case expectedEnd = "预计完工"
    case unpaidAmount = "未收款"

    var displayName: String { rawValue }
}

struct ProjectRiskBadge {
    let title: String
    let systemImage: String
    let color: Color
}

struct ProjectRowContent: View {
    let project: Project
    let isSelected: Bool
    let unpaidAmount: Double
    let badges: [ProjectRiskBadge]

    private var riskColor: Color {
        if badges.contains(where: { $0.color == .red }) { return .red }
        if badges.contains(where: { $0.color == .orange }) { return .orange }
        if badges.contains(where: { $0.color == .pink }) { return .pink }
        return isSelected ? .orange : .clear
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            RoundedRectangle(cornerRadius: 2)
                .fill(riskColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.625) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                    Text(project.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.tight)
                    ProjectStatusBadge(status: project.status)
                }

                HStack(spacing: AppSpacing.tight) {
                    if !project.location.isEmpty {
                        Image(systemName: "mappin").font(.caption2)
                        Text(project.location)
                    }
                    if !project.customerName.isEmpty {
                        Text("·")
                        Text(project.customerName)
                    }
                    if !project.expectedEndDate.isEmpty {
                        Text("·")
                        Text("完工 \(project.expectedEndDate)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: AppSpacing.tight) {
                    if !project.contractAmount.isEmpty {
                        Text("合同 \(ReportBuilder.money(project.contractAmountValue.doubleValue))")
                            .font(.caption2.weight(.medium))
                    }
                    if unpaidAmount > 0 {
                        Text("未收 \(ReportBuilder.money(unpaidAmount))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)

                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(badges.prefix(3)), id: \.title) { badge in
                            ProjectRiskBadgeView(badge: badge)
                        }
                        if badges.count > 3 {
                            Text("+\(badges.count - 3)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ProjectStatusBadge: View {
    let status: ProjectStatus

    private var color: Color {
        switch status {
        case .active: return .orange
        case .paused: return .yellow
        case .completed: return .green
        case .settled: return .blue
        case .archived: return .gray
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, AppSpacing.tight)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }
}

struct ProjectRiskBadgeView: View {
    let badge: ProjectRiskBadge

    var body: some View {
        Label(badge.title, systemImage: badge.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badge.color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(badge.color.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, 6)
                .background(isSelected ? Color.orange : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
