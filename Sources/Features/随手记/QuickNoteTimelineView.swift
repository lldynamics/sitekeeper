import SwiftUI

struct QuickNoteTimelineView: View {
    let notes: [QuickNote]
    let projects: [Project]
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
                return "invalid-\(note.id.uuidString)"
            }
            return Formatters.date.string(from: date)
        }

        return grouped.map { dateStr, items -> DayGroup in
            let title: String
            if dateStr == Formatters.date.string(from: today) {
                title = String(localized: "quick_note_timeline_today")
            } else if dateStr == Formatters.date.string(from: yesterday) {
                title = String(localized: "quick_note_timeline_yesterday")
            } else if dateStr.hasPrefix("invalid-") {
                title = String(localized: "quick_note_timeline_unknown_date")
            } else {
                title = dateStr
            }

            return DayGroup(id: dateStr, title: title, notes: items.sorted { Formatters.isLater($0.createdAt, than: $1.createdAt) })
        }.sorted { lhs, rhs in
            lhs.id > rhs.id
        }
    }

    var body: some View {
        if notes.isEmpty {
            Section {
                ContentUnavailableView(
                    String(localized: "quick_note_timeline_empty_title"),
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text(String(localized: "quick_note_timeline_empty_message"))
                )
                    .padding(.vertical, 48)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(dayGroups) { group in
                Section {
                    ForEach(group.notes) { note in
                        QuickNoteTimelineRow(
                            note: note,
                            projectName: projectName(note.projectId),
                            onEdit: { onEdit(note) },
                            onConvert: { onConvert(note) },
                            onDelete: { onDelete([note]) },
                            onPreview: onPreview
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    HStack {
                        Spacer()
                        Text(group.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                        Spacer()
                    }
                    .textCase(nil)
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
    let onEdit: () -> Void
    let onConvert: () -> Void
    let onDelete: () -> Void
    let onPreview: (QuickNoteAttachment) -> Void
    @State private var expandedAudioAttachmentId: UUID? = nil

    private var hasProject: Bool { !projectName.isEmpty }
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var timeText: String {
        guard let date = Formatters.parseDateOrDateTime(note.createdAt) else {
            return note.createdAt
        }
        return Self.timeFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 36)
                messageBubble
            }
            metaLine
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onConvert()
            } label: {
                Label(String(localized: "quick_note_timeline_convert_label"), systemImage: "arrow.triangle.branch")
            }
            .tint(.appWarning)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "quick_note_timeline_delete_label"), systemImage: "trash")
            }
            Button {
                onEdit()
            } label: {
                Label(String(localized: "quick_note_timeline_edit_label"), systemImage: "pencil")
            }
            .tint(.appPrimaryAction)
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label(String(localized: "quick_note_timeline_edit_label"), systemImage: "pencil")
            }
            Button {
                onConvert()
            } label: {
                Label(String(localized: "quick_note_timeline_convert_record_label"), systemImage: "arrow.triangle.branch")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "quick_note_timeline_delete_label"), systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(String(localized: "quick_note_timeline_row_accessibility_hint"))
    }

    private var messageBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(QuickNoteText.displayContent(for: note))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !note.attachments.isEmpty {
                QuickNoteAttachmentStrip(
                    attachments: note.attachments,
                    showsRemoveButton: false,
                    onPreview: handleAttachmentTap(_:),
                    onRemove: { _ in }
                )
            }

            if let expandedAudioAttachment {
                QuickNoteInlineAudioAttachmentPlayer(attachment: expandedAudioAttachment) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedAudioAttachmentId = nil
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hasProject ? Color.appPrimarySurfaceSubtle : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(hasProject ? Color.appPrimaryAction.opacity(0.16) : Color.appStrokeSeparator, lineWidth: 0.5)
        )
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            if hasProject {
                Label(projectName, systemImage: "building.2")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            if !note.attachments.isEmpty {
                Text(QuickNoteText.attachmentSummary(note.attachments))
                    .lineLimit(1)
            }
            Text(timeText)
            Button {
                onConvert()
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "quick_note_timeline_convert_record_label"))
            .accessibilityHint(String(localized: "quick_note_timeline_convert_accessibility_hint"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 560, alignment: .trailing)
    }

    private var expandedAudioAttachment: QuickNoteAttachment? {
        guard let expandedAudioAttachmentId else { return nil }
        return note.attachments.first {
            $0.id == expandedAudioAttachmentId && $0.attachmentKind == .audio
        }
    }

    private func handleAttachmentTap(_ attachment: QuickNoteAttachment) {
        guard attachment.attachmentKind == .audio else {
            onPreview(attachment)
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            expandedAudioAttachmentId = expandedAudioAttachmentId == attachment.id ? nil : attachment.id
        }
    }

    private var accessibilityLabelText: String {
        var parts: [String] = [QuickNoteText.displayContent(for: note)]
        if !projectName.isEmpty {
            parts.append(
                String(
                    format: String(localized: "quick_note_timeline_accessibility_project_format"),
                    projectName
                )
            )
        }
        parts.append(
            String(
                format: String(localized: "quick_note_timeline_accessibility_time_format"),
                timeText
            )
        )
        if !note.attachments.isEmpty {
            parts.append(QuickNoteText.attachmentSummary(note.attachments))
        }
        return parts.joined(separator: String(localized: "quick_note_timeline_accessibility_separator"))
    }
}
