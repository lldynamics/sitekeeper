import SwiftUI

struct DashboardRiskQuickAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void
}

struct DashboardRiskPin: Identifiable {
    let id: String
    let title: String
    let value: String
    let color: Color
    let hasRisk: Bool
    let priority: Int
    let destination: DashboardDestination
    var quickActions: [DashboardRiskQuickAction] = []
}

struct DashboardRiskPill: View {
    let title: String
    let value: String
    let color: Color
    let hasRisk: Bool
    let destination: DashboardDestination
    var quickActions: [DashboardRiskQuickAction] = []

    var body: some View {
        HStack(spacing: AppSpacing.tight * 0.5) {
            NavigationLink {
                LazyDashboardDestinationView(destination: destination)
            } label: {
                HStack(spacing: AppSpacing.tight * 0.75) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hasRisk ? Color.white : color)
                    Text(value)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(hasRisk ? Color.white : color)
                }
                .padding(.horizontal, AppSpacing.normal - 2)
                .padding(.vertical, AppSpacing.tight - 1)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.normal - 2, style: .continuous)
                        .fill(hasRisk ? color : color.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.normal - 2, style: .continuous)
                        .stroke(hasRisk ? Color.clear : color.opacity(0.28), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title)：\(value)")
            .accessibilityHint(String(format: String(localized: "打开%@详情"), title))

            if !quickActions.isEmpty {
                Menu {
                    ForEach(quickActions) { action in
                        Button(role: action.role) {
                            action.action()
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background {
                            AppSurface(tone: .grouped, cornerRadius: AppSpacing.tight * 0.75) {
                                Color.clear
                        }
                    }
                }
                .accessibilityLabel(String(format: String(localized: "%@更多操作"), title))
            }
        }
    }
}

struct DashboardInventoryPill: View {
    let title: String
    let value: String
    let color: Color
    var destination: DashboardDestination? = nil

    var body: some View {
        let content = VStack(alignment: .leading, spacing: AppSpacing.tight * 0.375) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.tight + 1)
        .background {
            AppSurface(tone: .grouped, cornerRadius: AppSpacing.tight) {
                Color.clear
            }
        }

        if let destination {
            NavigationLink {
                LazyDashboardDestinationView(destination: destination)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(String(format: String(localized: "打开%@详情"), title))
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }
}

struct DashboardPanel<Content: View>: View {
    let title: String
    let systemImage: String
    var destination: DashboardDestination? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight + 2) {
            if let destination {
                NavigationLink {
                    LazyDashboardDestinationView(destination: destination)
                } label: {
                    HStack(spacing: AppSpacing.tight * 0.75) {
                        Label(title, systemImage: systemImage)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(format: String(localized: "打开%@"), title))
            } else {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DashboardPanelSurfaceModifier())
    }
}

private struct DashboardPanelSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        AppPanel(
            tone: .materialThin,
            cornerRadius: AppSpacing.tight,
            padding: AppSpacing.normal + 2
        ) {
            content
        }
    }
}

struct LogPreviewRow: View {
    let log: DailyLog
    let projectName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight * 0.5) {
            HStack {
                Text(log.weather)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.appSuccess)
                if !log.workers.isEmpty {
                    Text(log.workers)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let projectName {
                    Text(projectName)
                        .font(.caption2)
                        .foregroundStyle(Color.appDoc)
                        .appListSecondaryTextLayout(lines: 1)
                }
            }
            Text(log.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .appListSecondaryTextLayout()
        }
        .accessibilityElement(children: .combine)
    }
}

struct TodoPreviewRow: View {
    let todo: SiteTodo
    let projectName: String?

    var body: some View {
        HStack(spacing: AppSpacing.tight + 2) {
            Image(systemName: todo.isOverdue ? "exclamationmark.circle.fill" : "circle")
                .foregroundStyle(todo.isOverdue ? Color.appRisk : Color.appPrimaryAction)
            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.375) {
                Text(todo.title)
                    .font(.callout.weight(.medium))
                    .appListPrimaryTextLayout()
                ViewThatFits(in: .horizontal) {
                    todoMetadataRow
                    todoMetadataColumn
                }
                if let completedAt = todo.completedAt, todo.isDone {
                    Text(String(format: String(localized: "完成 %@"), completedAt))
                        .font(.caption2)
                        .foregroundStyle(Color.appSuccess)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var todoMetadataContent: some View {
        Text(todo.dueDate)
        Text(todo.priority.displayName)
        Text(todo.issueType.displayName)
        if !todo.owner.isEmpty { Text(todo.owner) }
        if let projectName { Text(projectName).foregroundStyle(Color.appDoc) }
    }

    private var todoMetadataRow: some View {
        HStack(spacing: AppSpacing.tight) {
            todoMetadataContent
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var todoMetadataColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            todoMetadataContent
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct IssueRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyDashboardRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
            .accessibilityLabel(text)
    }
}
