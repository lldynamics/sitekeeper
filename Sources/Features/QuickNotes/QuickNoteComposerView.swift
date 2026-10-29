import SwiftUI

struct QuickNoteComposerView: View {
    let projects: [Project]
    @Binding var content: String
    @Binding var projectId: UUID?
    @Binding var attachments: [QuickNoteAttachment]
    var mode: QuickNoteComposerMode = .full
    var isPublishing = false
    var usesWorkspaceBackground = false
    let onPublish: () -> Void
    let onPreview: (QuickNoteAttachment) -> Void
    var onAttachmentAdded: (QuickNoteAttachment) -> Void = { _ in }
    var onAttachmentRemoved: (QuickNoteAttachment) -> Void = { _ in }
    var onDiscardDraftRequest: () -> Void = {}
    var onAttachmentActivityChange: (Bool) -> Void = { _ in }
    @FocusState private var isContentFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var horizontalActionsMinimumWidth: CGFloat = 330
    @State private var composerWidth: CGFloat = 0
    @State private var hasAttachmentActivity = false

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPublish: Bool {
        !trimmedContent.isEmpty || !attachments.isEmpty
    }

    @ViewBuilder
    var body: some View {
        if mode == .compact {
            compactComposerContent
        } else {
            Section {
                fullComposerContent
            }
        }
    }

    private var compactComposerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("quick_note_composer_capture_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !attachments.isEmpty {
                QuickNoteAttachmentStrip(
                    attachments: attachments,
                    onPreview: onPreview,
                    onRemove: removeAttachment(_:)
                )
            }

            TextField(mode.placeholder, text: $content, axis: .vertical)
                .focused($isContentFocused)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 76, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(usesWorkspaceBackground ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.appStrokeSeparator, lineWidth: 0.5)
                )
                .accessibilityLabel(AppLocalization.string("quick_note_composer_input_accessibility_label"))
                .accessibilityIdentifier("quick-note-content-input")

            compactActionsLayout {
                compactActionTools
                    .frame(maxWidth: .infinity, alignment: .leading)
                publishButton
                    .frame(maxWidth: usesVerticalActions ? .infinity : nil, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            usesWorkspaceBackground ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(.bar),
            ignoresSafeAreaEdges: usesWorkspaceBackground ? [] : .all
        )
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { composerWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in composerWidth = width }
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
        .appKeyboardToolbar {
            HStack {
                Spacer()
                Button(AppLocalization.string("quick_note_composer_done_button")) { isContentFocused = false }
                    .accessibilityIdentifier("keyboard-done")
            }
        }
    }

    private var compactActionTools: some View {
        QuickNoteAttachmentPickerBar(
            projectName: projectName(projectId),
            mode: .compact,
            onDiscardDraftRequest: canPublish && !hasAttachmentActivity ? onDiscardDraftRequest : nil,
            onActivityChange: attachmentActivityChanged
        ) { attachment in
            attachments.append(attachment)
            onAttachmentAdded(attachment)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var compactActionsLayout: AnyLayout {
        if usesVerticalActions {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        } else {
            AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        }
    }

    private var usesVerticalActions: Bool {
        dynamicTypeSize.isAccessibilitySize || composerWidth - 24 < horizontalActionsMinimumWidth
    }

    private var publishButton: some View {
        Button(action: onPublish) {
            HStack(spacing: 6) {
                if isPublishing {
                    ProgressView().controlSize(.small)
                }
                Text(AppLocalization.string(isPublishing ? "quick_note_composer_saving" : "quick_note_composer_save_button"))
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 92, minHeight: 44)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.appPrimaryAction)
        .disabled(!canPublish || isPublishing || hasAttachmentActivity)
        .accessibilityLabel(AppLocalization.string(isPublishing ? "quick_note_composer_saving" : "quick_note_composer_send_accessibility_label"))
        .accessibilityIdentifier("quick-note-publish")
    }

    private var fullComposerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(mode.placeholder, text: $content, axis: .vertical)
                .focused($isContentFocused)
                .accessibilityIdentifier("quick-note-content-input")
                .lineLimit(5...12)
                .textFieldStyle(.plain)
                .padding(10)
                .frame(minHeight: 128, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appStrokeSeparator, lineWidth: 0.5)
                )

            if !attachments.isEmpty {
                QuickNoteAttachmentStrip(
                    attachments: attachments,
                    onPreview: onPreview,
                    onRemove: removeAttachment(_:)
                )
            }

            QuickNoteAttachmentPickerBar(
                projectName: projectName(projectId),
                mode: .full,
                onActivityChange: attachmentActivityChanged
            ) { attachment in
                attachments.append(attachment)
                onAttachmentAdded(attachment)
            }

            HStack(spacing: 10) {
                Picker(AppLocalization.string("quick_note_composer_project_picker_title"), selection: $projectId) {
                    Text(AppLocalization.string("quick_note_composer_no_project_option")).tag(nil as UUID?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
                .labelsHidden()
                .disabled(hasAttachmentActivity)
                .frame(maxWidth: .infinity, alignment: .leading)

                if canPublish && !hasAttachmentActivity {
                    Button(AppLocalization.string("quick_note_composer_discard_draft_button"), role: .destructive) {
                        onDiscardDraftRequest()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
            .padding(.vertical, 4)
            .appKeyboardToolbar {
                HStack {
                    Spacer()
                    Button(AppLocalization.string("quick_note_composer_done_button")) { isContentFocused = false }
                    .accessibilityIdentifier("keyboard-done")
                }
            }
    }

    private func removeAttachment(_ attachment: QuickNoteAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
            [attachment.fileName],
            summary: "quickNoteComposer.removeAttachment"
        )?.perform()
        onAttachmentRemoved(attachment)
    }

    private func attachmentActivityChanged(_ isActive: Bool) {
        hasAttachmentActivity = isActive
        onAttachmentActivityChange(isActive)
    }

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return projects.first(where: { $0.id == id })?.name ?? ""
    }
}

struct QuickNoteProjectSelectionCard: View {
    let projects: [Project]
    @Binding var projectId: UUID?
    var title = AppLocalization.string("quick_note_current_project_title")

    private var selectedProjectName: String {
        guard let projectId else { return AppLocalization.string("quick_note_composer_no_project_option") }
        return projects.first(where: { $0.id == projectId })?.name
            ?? AppLocalization.string("quick_note_composer_no_project_option")
    }

    var body: some View {
        Menu {
            Picker(AppLocalization.string("quick_note_composer_link_project_picker_title"), selection: $projectId) {
                Text(AppLocalization.string("quick_note_composer_no_project_option")).tag(nil as UUID?)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    projectIdentity
                    Spacer(minLength: 8)
                    switchLabel
                }
                VStack(alignment: .leading, spacing: 10) {
                    projectIdentity
                    switchLabel
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.appStrokeSeparator, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string("quick_note_composer_link_project_picker_title"))
        .accessibilityValue(selectedProjectName)
        .accessibilityIdentifier("quick-note-project-selector")
    }

    private var projectIdentity: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: projectId == nil ? "building.2" : "building.2.fill")
                .font(.title2)
                .foregroundStyle(Color.appPrimaryAction)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedProjectName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var switchLabel: some View {
        Label(AppLocalization.string("quick_note_switch_project_button"), systemImage: "chevron.down")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.appPrimaryAction)
            .fixedSize()
            .frame(minHeight: 44)
    }
}

enum QuickNoteComposerMode {
    case full
    case compact

    var placeholder: String {
        switch self {
        case .full:
            return AppLocalization.string("quick_note_composer_full_placeholder")
        case .compact:
            return AppLocalization.string("quick_note_composer_compact_placeholder")
        }
    }
}
