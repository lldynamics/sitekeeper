import SwiftUI

private struct DashboardFlatSurfacesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dashboardFlatSurfaces: Bool {
        get { self[DashboardFlatSurfacesKey.self] }
        set { self[DashboardFlatSurfacesKey.self] = newValue }
    }
}

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
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let color: Color
    let hasRisk: Bool
    let destination: DashboardDestination
    var quickActions: [DashboardRiskQuickAction] = []

    var body: some View {
        NavigationLink {
            LazyDashboardDestinationView(destination: destination)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.tight * 0.75) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .fixedSize()
                    Spacer(minLength: 0)
                    Text(value)
                        .font(.caption.weight(.bold))
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: AppSpacing.tight * 0.375) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(value)
                        .font(.caption.weight(.bold))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(hasRisk ? (colorScheme == .dark ? color : Color.white) : color)
            .padding(.horizontal, AppSpacing.normal - 2)
            .padding(.vertical, AppSpacing.tight - 1)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.normal - 2, style: .continuous)
                    .fill(hasRisk ? (colorScheme == .dark ? color.opacity(0.22) : color) : color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.normal - 2, style: .continuous)
                    .stroke(hasRisk ? (colorScheme == .dark ? color.opacity(0.45) : Color.clear) : color.opacity(0.28), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !quickActions.isEmpty {
                ForEach(quickActions) { action in
                    Button(role: action.role) {
                        action.action()
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
        }
        .accessibilityLabel("\(title)：\(value)")
        .accessibilityHint(String(format: AppLocalization.string("打开%@详情"), title))
        .accessibilityActions {
            ForEach(quickActions) { action in
                Button(action.title) {
                    action.action()
                }
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
        .padding(AppSpacing.tight + 2)
        .background {
            AppSurface(
                tone: .tertiary,
                cornerRadius: 10,
                stroke: Color(uiColor: .separator).opacity(0.10)
            ) {
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
            .accessibilityHint(String(format: AppLocalization.string("打开%@详情"), title))
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
                .accessibilityHint(String(format: AppLocalization.string("打开%@"), title))
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
    @Environment(\.dashboardFlatSurfaces) private var flatSurfaces

    func body(content: Content) -> some View {
        AppPanel(
            tone: .grouped,
            cornerRadius: 16,
            padding: AppSpacing.normal,
            shadow: flatSurfaces ? .none : .card,
            stroke: AppSurfaceDefaults.stroke
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
        .padding(.horizontal, AppSpacing.normal - 2)
        .padding(.vertical, AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

struct TodoPreviewRow: View {
    let todo: SiteTodo
    let projectName: String?
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: AppSpacing.tight + 2) {
            if let onToggle, todo.review == nil {
                Button(action: onToggle) {
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : (todo.isOverdue ? "exclamationmark.circle.fill" : "circle"))
                        .font(.body)
                        .foregroundStyle(todo.isDone ? Color.appSuccess : (todo.isOverdue ? Color.appRisk : Color.appPrimaryAction))
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(todo.isDone ? AppLocalization.string("标记未完成") : AppLocalization.string("标记完成"))
            } else {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : (todo.isOverdue ? "exclamationmark.circle.fill" : "circle"))
                    .font(.body)
                    .foregroundStyle(todo.isDone ? Color.appSuccess : (todo.isOverdue ? Color.appRisk : Color.appPrimaryAction))
                    .frame(minWidth: 32, minHeight: 32)
            }

            NavigationLink {
                SiteTodoView(initialProjectId: todo.projectId, focusedTodoId: todo.id)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.tight * 0.375) {
                        Text(todo.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(todo.isDone ? .secondary : .primary)
                            .strikethrough(todo.isDone)
                            .appListPrimaryTextLayout()
                        ViewThatFits(in: .horizontal) {
                            todoMetadataRow
                            todoMetadataColumn
                        }
                        if let review = todo.review {
                            Text(review.status.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(review.status == .closed ? Color.appSuccess : Color.appWarning)
                        }
                        if let completedAt = todo.completedAt, todo.isDone {
                            Text(String(format: AppLocalization.string("完成 %@"), Formatters.displayDateText(completedAt)))
                                .font(.caption2)
                                .foregroundStyle(Color.appSuccess)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.normal - 2)
        .padding(.vertical, AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var todoMetadataContent: some View {
        Text(Formatters.displayRelativeOrShortDate(todo.dueDate))
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
        .padding(.horizontal, AppSpacing.normal - 2)
        .padding(.vertical, AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

struct EmptyDashboardRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.6))
            )
            .accessibilityLabel(text)
    }
}
