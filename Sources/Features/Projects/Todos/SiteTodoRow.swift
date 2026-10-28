import SwiftUI

struct SiteTodoRow: View {
    let todo: SiteTodo
    let isOverdue: Bool
    let projectName: String
    let methodTitles: [String]
    var onToggle: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let onToggle {
                    Button(action: onToggle) {
                        Image(systemName: todo.isDone ? "checkmark.circle.fill" : isOverdue ? "exclamationmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(todo.isDone ? Color.appSuccess : isOverdue ? .appRisk : Color.appWarning)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(todo.isDone ? AppLocalization.string("标记未完成") : AppLocalization.string("标记完成"))
                } else {
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : isOverdue ? "exclamationmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(todo.isDone ? Color.appSuccess : isOverdue ? .appRisk : Color.appWarning)
                }
                Text(todo.title.isEmpty ? AppLocalization.string("未命名事项") : todo.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .strikethrough(todo.isDone)
                Spacer()
                if isOverdue && !todo.isDone {
                    Text(AppLocalization.string("已逾期"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.appRisk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.appRisk.opacity(0.12))
                        )
                }
                priorityBadge(todo.priority)
            }
            HStack(spacing: 8) {
                Text(Formatters.displayRelativeOrShortDate(todo.dueDate))
                Text(todo.issueType.displayName)
                if !todo.owner.isEmpty { Text(todo.owner) }
                if !projectName.isEmpty { Text(projectName).foregroundStyle(Color.appDoc) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !todo.note.isEmpty {
                Text(todo.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !drawingIssueTags.isEmpty {
                FlowTagLine(tags: drawingIssueTags)
            }
            if !todo.drawingIssueCloseEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(String(format: AppLocalization.string("关闭证据: %@"), todo.drawingIssueCloseEvidence))
                    .font(.caption2)
                    .foregroundStyle(Color.appSuccess)
                    .lineLimit(2)
            }
            if !methodTitles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(Color.appWarning)
                    Text(methodTitles.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if todo.rectificationBeforePhotoFileName != nil || todo.rectificationAfterPhotoFileName != nil {
                HStack(spacing: 8) {
                    thumbnail(title: AppLocalization.string("前"), fileName: todo.rectificationBeforePhotoFileName)
                    thumbnail(title: AppLocalization.string("后"), fileName: todo.rectificationAfterPhotoFileName)
                }
            }
            if let completedAt = todo.completedAt, todo.isDone {
                Text(String(format: AppLocalization.string("完成时间: %@"), Formatters.displayDateText(completedAt)))
                    .font(.caption2)
                    .foregroundStyle(Color.appSuccess)
            }
        }
        .padding(.vertical, 4)
    }

    private var drawingIssueTags: [String] {
        [
            todo.drawingIssueLocation.isEmpty ? "" : String(format: AppLocalization.string("位置: %@"), todo.drawingIssueLocation),
            todo.drawingIssueLayerOrPage.isEmpty ? "" : String(format: AppLocalization.string("图层/页码: %@"), todo.drawingIssueLayerOrPage),
            todo.drawingIssueMeasurement.isEmpty ? "" : String(format: AppLocalization.string("测量: %@"), todo.drawingIssueMeasurement)
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func priorityBadge(_ priority: TodoPriority) -> some View {
        let color: Color
        switch priority {
        case .high:
            color = .appRisk
        case .medium:
            color = .appWarning
        case .low:
            color = .appMuted
        }
        return Text(priority.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    @ViewBuilder
    private func thumbnail(title: String, fileName: String?) -> some View {
        if fileName != nil {
            ZStack(alignment: .topLeading) {
                AsyncPhotoThumbnailImageView(fileName: fileName) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 48)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .frame(width: 64, height: 48)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }
                Text(title)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(4)
            }
        }
    }
}

enum TodoFilter: CaseIterable {
    case open
    case overdue
    case done
    case all

    var displayName: String {
        switch self {
        case .open:
            return AppLocalization.string("未完成")
        case .overdue:
            return AppLocalization.string("延期")
        case .done:
            return AppLocalization.string("已完成")
        case .all:
            return AppLocalization.string("全部")
        }
    }

    func matches(_ todo: SiteTodo, dayContext: ProjectDayContext) -> Bool {
        switch self {
        case .open: return !todo.isDone
        case .overdue: return !todo.isDone && dayContext.isOverdue(date: todo.dueDate)
        case .done: return todo.isDone
        case .all: return true
        }
    }
}
