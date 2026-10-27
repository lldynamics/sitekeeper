import SwiftUI

struct QuickNoteTimelineView: View {
    let notes: [QuickNote]
    let projects: [Project]
    var confirmedSavedNoteId: UUID? = nil
    var usesWorkspaceCards = false
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
                title = AppLocalization.string("quick_note_timeline_today")
            } else if dateStr == Formatters.date.string(from: yesterday) {
                title = AppLocalization.string("quick_note_timeline_yesterday")
            } else if dateStr.hasPrefix("invalid-") {
                title = AppLocalization.string("quick_note_timeline_unknown_date")
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
                    AppLocalization.string("quick_note_timeline_empty_title"),
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text(AppLocalization.string("quick_note_timeline_empty_message"))
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
                            isSaveConfirmed: note.id == confirmedSavedNoteId,
                            usesWorkspaceCard: usesWorkspaceCards,
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
    let isSaveConfirmed: Bool
    let usesWorkspaceCard: Bool
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
            return note.createdAt.storageText
        }
        return Self.timeFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: usesWorkspaceCard ? 0 : 36)
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
                Label(AppLocalization.string("quick_note_timeline_convert_label"), systemImage: "arrow.triangle.branch")
            }
            .tint(.appWarning)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(AppLocalization.string("quick_note_timeline_delete_label"), systemImage: "trash")
            }
            Button {
                onEdit()
            } label: {
                Label(AppLocalization.string("quick_note_timeline_edit_label"), systemImage: "pencil")
            }
            .tint(.appPrimaryAction)
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label(AppLocalization.string("quick_note_timeline_edit_label"), systemImage: "pencil")
            }
            Button {
                onConvert()
            } label: {
                Label(AppLocalization.string("quick_note_timeline_convert_record_label"), systemImage: "arrow.triangle.branch")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(AppLocalization.string("quick_note_timeline_delete_label"), systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(AppLocalization.string("quick_note_timeline_row_accessibility_hint"))
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
        .frame(maxWidth: usesWorkspaceCard ? .infinity : 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appStrokeSeparator, lineWidth: 0.5)
        )
    }

    private var metaLine: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(timeText)
                if isSaveConfirmed {
                    Label(AppLocalization.string("quick_note_saved_status"), systemImage: "checkmark")
                        .foregroundStyle(Color.appPrimaryAction)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    projectAndAttachmentDetails
                    Spacer(minLength: 8)
                    organizeButton
                }
                VStack(alignment: .trailing, spacing: 4) {
                    projectAndAttachmentDetails
                        .frame(maxWidth: .infinity, alignment: .leading)
                    organizeButton
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 560, alignment: .trailing)
    }

    private var projectAndAttachmentDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                hasProject ? projectName : AppLocalization.string("quick_note_composer_no_project_option"),
                systemImage: "building.2"
            )
            .fixedSize(horizontal: false, vertical: true)
            if !note.attachments.isEmpty {
                Text(QuickNoteText.attachmentSummary(note.attachments))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var organizeButton: some View {
        Button(action: onConvert) {
            Label(AppLocalization.string("quick_note_organize_button"), systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appPrimaryAction)
        .accessibilityLabel(AppLocalization.string("quick_note_organize_button"))
        .accessibilityHint(AppLocalization.string("quick_note_timeline_convert_accessibility_hint"))
        .accessibilityIdentifier("quick-note-organize")
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
                    format: AppLocalization.string("quick_note_timeline_accessibility_project_format"),
                    projectName
                )
            )
        }
        parts.append(
            String(
                format: AppLocalization.string("quick_note_timeline_accessibility_time_format"),
                timeText
            )
        )
        if !note.attachments.isEmpty {
            parts.append(QuickNoteText.attachmentSummary(note.attachments))
        }
        return parts.joined(separator: AppLocalization.string("quick_note_timeline_accessibility_separator"))
    }
}
