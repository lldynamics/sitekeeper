import SwiftUI

struct QuickNoteTimelineView: View {
    let notes: [QuickNote]
    let projects: [Project]
    let onCreate: () -> Void
    let onEdit: (QuickNote) -> Void
    let onConvert: (QuickNote) -> Void
    let onDelete: ([QuickNote]) -> Void
    let onPreview: (QuickNoteAttachment) -> Void

    // MARK: - 按日期分组

    private struct DayGroup: Identifiable {
        let id: String
        let title: String
        let notes: [QuickNote]
    }

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let grouped = Dictionary(grouping: notes) { note -> String in
            guard let date = Formatters.parseDateOrDateTime(note.createdAt) else {
                return ""
            }
            return Formatters.date.string(from: date)
        }

        return grouped.compactMap { dateStr, items -> DayGroup? in
            guard !dateStr.isEmpty else { return nil }

            let title: String
            if dateStr == Formatters.date.string(from: today) {
                title = "今天"
            } else if dateStr == Formatters.date.string(from: yesterday) {
                title = "昨天"
            } else {
                title = dateStr
            }

            return DayGroup(id: dateStr, title: title, notes: items.sorted { $0.createdAt > $1.createdAt })
        }.sorted { lhs, rhs in
            lhs.id > rhs.id
        }
    }

    var body: some View {
        if notes.isEmpty {
            Section {
                VStack(spacing: 10) {
                    ContentUnavailableView("暂无记录", systemImage: "square.and.pencil", description: Text("写一句、拍一张、录一段，都可以先放这里，之后可转为日志、待办或项目资料。"))
                    Button(action: onCreate) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.pencil")
                                .symbolRenderingMode(.monochrome)
                            Text("立即发布一条")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appWarning)
                }
            }
        } else {
            ForEach(dayGroups) { group in
                Section(group.title) {
                    ForEach(group.notes) { note in
                        QuickNoteTimelineRow(
                            note: note,
                            projectName: projectName(note.projectId),
                            onConvert: { onConvert(note) },
                            onPreview: onPreview
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(note) }
                    }
                    .onDelete { offsets in
                        let selected = offsets.compactMap { group.notes.indices.contains($0) ? group.notes[$0] : nil }
                        onDelete(selected)
                    }
                }
            }
        }
    }

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return projects.first(where: { $0.id == id })?.name ?? ""
    }
}

// MARK: - 单条随手记行

private struct QuickNoteTimelineRow: View {
    let note: QuickNote
    let projectName: String
    let onConvert: () -> Void
    let onPreview: (QuickNoteAttachment) -> Void

    private var hasProject: Bool { !projectName.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            // 左边框颜色条
            RoundedRectangle(cornerRadius: 2)
                .fill(hasProject ? Color.appPrimaryAction : Color.appMutedSurface)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(QuickNoteText.displayContent(for: note))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(5)

                if !note.attachments.isEmpty {
                    QuickNoteAttachmentStrip(
                        attachments: note.attachments,
                        showsRemoveButton: false,
                        onPreview: onPreview,
                        onRemove: { _ in }
                    )
                }

                HStack(spacing: 8) {
                    Text(note.createdAt)
                        .font(.caption2)
                    if hasProject {
                        Text(projectName)
                            .font(.caption2)
                            .foregroundStyle(.appPrimaryAction)
                    }
                    if !note.attachments.isEmpty {
                        Text(QuickNoteText.attachmentSummary(note.attachments))
                            .font(.caption2)
                    }
                    Spacer(minLength: 8)
                    Button(action: onConvert) {
                        Label("转为", systemImage: "arrow.triangle.branch")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("转换记录")
                    .accessibilityHint("双击转换为日志、待办或项目资料")
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("双击编辑这条随手记")
    }

    private var accessibilityLabelText: String {
        var parts: [String] = [QuickNoteText.displayContent(for: note)]
        if !projectName.isEmpty { parts.append("工程 \(projectName)") }
        parts.append("时间 \(note.createdAt)")
        if !note.attachments.isEmpty {
            parts.append(QuickNoteText.attachmentSummary(note.attachments))
        }
        return parts.joined(separator: "，")
    }
}
