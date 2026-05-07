import SwiftUI

struct DashboardRiskPill: View {
    let title: String
    let value: String
    let color: Color
    let destination: AnyView

    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(value)")
        .accessibilityHint("打开\(title)详情")
    }
}

struct DashboardInventoryPill: View {
    let title: String
    let value: String
    let color: Color
    var destination: AnyView? = nil

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemGroupedBackground)))

        if let destination {
            NavigationLink {
                destination
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("打开\(title)详情")
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }
}

struct DashboardPanel<Content: View>: View {
    let title: String
    let systemImage: String
    var destination: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let destination {
                NavigationLink { destination } label: {
                    HStack(spacing: 6) {
                        Label(title, systemImage: systemImage)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开\(title)")
            } else {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
    }
}

struct LogPreviewRow: View {
    let log: DailyLog
    let projectName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.weather)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                if !log.workers.isEmpty {
                    Text(log.workers)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let projectName {
                    Text(projectName)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
            Text(log.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TodoPreviewRow: View {
    let todo: SiteTodo
    let projectName: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: todo.isOverdue ? "exclamationmark.circle.fill" : "circle")
                .foregroundStyle(todo.isOverdue ? .red : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(todo.dueDate)
                    Text(todo.priority)
                    Text(todo.issueType)
                    if !todo.owner.isEmpty { Text(todo.owner) }
                    if let projectName { Text(projectName).foregroundStyle(.blue) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let completedAt = todo.completedAt, todo.isDone {
                    Text("完成 \(completedAt)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
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
