import SwiftUI

enum ProjectOverviewFilter: String {
    case active
    case overdue
    case todo
    case missingReceipt
    case financialDue
    case missingTodayLog
    case priceSpike

    var displayName: String {
        switch self {
        case .active:
            return String(localized: "进行中")
        case .overdue:
            return String(localized: "延期")
        case .todo:
            return String(localized: "待办")
        case .missingReceipt:
            return String(localized: "缺票")
        case .financialDue:
            return String(localized: "应收付")
        case .missingTodayLog:
            return String(localized: "未写日志")
        case .priceSpike:
            return String(localized: "价格异动")
        }
    }
}

enum ProjectSortOption: String, CaseIterable {
    case recentUpdate
    case expectedEnd
    case unpaidAmount

    var displayName: String {
        switch self {
        case .recentUpdate:
            return String(localized: "最近更新")
        case .expectedEnd:
            return String(localized: "预计完工")
        case .unpaidAmount:
            return String(localized: "未收款")
        }
    }
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
        if badges.contains(where: { $0.color == .appRisk }) { return .appRisk }
        if badges.contains(where: { $0.color == .appPrimaryAction }) { return .appPrimaryAction }
        return isSelected ? .appPrimaryAction : .clear
    }

    private var detailParts: [String] {
        var parts: [String] = []
        if unpaidAmount > 0 {
            parts.append(String(format: String(localized: "未收 %@"), ReportBuilder.money(unpaidAmount)))
        }
        if !project.expectedEndDate.isEmpty {
            parts.append(String(format: String(localized: "完工 %@"), project.expectedEndDate))
        }
        if !project.managerName.isEmpty {
            parts.append(String(format: String(localized: "负责人 %@"), project.managerName))
        }
        if parts.isEmpty, !project.location.isEmpty {
            parts.append(project.location)
        }
        return parts
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

                if !detailParts.isEmpty {
                    HStack(spacing: AppSpacing.tight) {
                        ForEach(Array(detailParts.enumerated()), id: \.offset) { index, part in
                            if index > 0 {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(part)
                                .foregroundStyle(index == 0 && unpaidAmount > 0 ? Color.appPrimaryAction : .secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .lineLimit(1)
                }

                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(badges.prefix(2)), id: \.title) { badge in
                            ProjectRiskBadgeView(badge: badge)
                        }
                        if badges.count > 2 {
                            Text("+\(badges.count - 2)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(projectAccessibilityLabel)
    }

    private var projectAccessibilityLabel: String {
        var parts = [project.name, project.status.displayName]
        if !project.location.isEmpty { parts.append(project.location) }
        if !project.customerName.isEmpty { parts.append(project.customerName) }
        if unpaidAmount > 0 {
            parts.append(String(format: String(localized: "未收 %@"), ReportBuilder.money(unpaidAmount)))
        }
        if !badges.isEmpty {
            parts.append(String(format: String(localized: "风险 %@"), badges.prefix(3).map(\.title).joined(separator: "，")))
        }
        return parts.joined(separator: "，")
    }
}

struct ProjectStatusBadge: View {
    let status: ProjectStatus

    private var color: Color {
        switch status {
        case .active: return .appPrimaryAction
        case .paused: return .appPrimaryAction
        case .completed: return .appSuccess
        case .settled: return .appDoc
        case .archived: return .appMuted
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
                .background(isSelected ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
