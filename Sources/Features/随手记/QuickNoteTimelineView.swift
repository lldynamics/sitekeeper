import SwiftUI

struct QuickNoteTimelineView: View {
    let notes: [QuickNote]
    let projects: [Project]
    let onCreate: () -> Void
    let onEdit: (QuickNote) -> Void
    let onConvert: (QuickNote) -> Void
    let onDelete: ([QuickNote]) -> Void
    let onPreview: (QuickNoteAttachment) -> Void

    var body: some View {
        Section("时间线") {
            if notes.isEmpty {
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
                    .tint(.orange)
                }
            } else {
                ForEach(notes) { note in
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
                    let selected = offsets.compactMap { notes.indices.contains($0) ? notes[$0] : nil }
                    onDelete(selected)
                }
            }
        }
    }

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return projects.first(where: { $0.id == id })?.name ?? ""
    }
}

private struct QuickNoteTimelineRow: View {
    let note: QuickNote
    let projectName: String
    let onConvert: () -> Void
    let onPreview: (QuickNoteAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                if !projectName.isEmpty {
                    Text(projectName).foregroundStyle(.blue)
                }
                if !note.attachments.isEmpty {
                    Text(QuickNoteText.attachmentSummary(note.attachments))
                }
                Spacer(minLength: 8)
                Button(action: onConvert) {
                    Label("转为", systemImage: "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel("转换记录")
                .accessibilityHint("双击转换为日志、待办或项目资料")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
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
