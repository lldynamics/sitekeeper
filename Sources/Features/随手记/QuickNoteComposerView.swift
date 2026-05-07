import SwiftUI

struct QuickNoteComposerView: View {
    let projects: [Project]
    @Binding var content: String
    @Binding var projectId: UUID?
    @Binding var attachments: [QuickNoteAttachment]
    var mode: QuickNoteComposerMode = .full
    let onPublish: () -> Void
    let onPreview: (QuickNoteAttachment) -> Void
    var onAttachmentAdded: (QuickNoteAttachment) -> Void = { _ in }
    var onAttachmentRemoved: (QuickNoteAttachment) -> Void = { _ in }
    var onDraftCleared: ([QuickNoteAttachment]) -> Void = { _ in }
    @FocusState private var isContentFocused: Bool

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPublish: Bool {
        !trimmedContent.isEmpty || !attachments.isEmpty
    }

    @ViewBuilder
    var body: some View {
        if mode == .compact {
            VStack(alignment: .leading, spacing: 10) {
                Label("快速随手记", systemImage: "square.and.pencil")
                    .font(.headline)
                composerContent
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
        } else {
            Section {
                composerContent
            }
        }
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: mode == .compact ? 8 : 12) {
                TextField(mode.placeholder, text: $content, axis: .vertical)
                    .focused($isContentFocused)
                    .lineLimit(mode == .compact ? 3...6 : 5...12)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .frame(minHeight: mode == .compact ? 78 : 128, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
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
                    mode: mode == .compact ? .compact : .full
                ) { attachment in
                    attachments.append(attachment)
                    onAttachmentAdded(attachment)
                }

                HStack(spacing: 10) {
                    Picker("工程", selection: $projectId) {
                        Text("不关联工程").tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if canPublish {
                        Button("清空") { clearDraft(deleteFiles: true) }
                            .buttonStyle(.bordered)
                            .controlSize(mode == .compact ? .small : .regular)
                    }

                    Button(mode.publishTitle) {
                        onPublish()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(mode == .compact ? .small : .regular)
                    .disabled(!canPublish)
                }
            }
            .padding(.vertical, mode == .compact ? 2 : 4)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isContentFocused = false }
                }
            }
    }

    private func removeAttachment(_ attachment: QuickNoteAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        QuickNoteAttachmentStorage.delete(fileName: attachment.fileName)
        onAttachmentRemoved(attachment)
    }

    private func clearDraft(deleteFiles: Bool) {
        let removed = attachments
        if deleteFiles {
            QuickNoteAttachmentStorage.delete(attachments: attachments)
        }
        content = ""
        attachments = []
        onDraftCleared(removed)
    }

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return projects.first(where: { $0.id == id })?.name ?? ""
    }
}

enum QuickNoteComposerMode {
    case full
    case compact

    var placeholder: String {
        switch self {
        case .full:
            return "像发动态一样，记录现场情况、客户交代或临时想法"
        case .compact:
            return "随手记几句，或直接加媒体/附件"
        }
    }

    var publishTitle: String {
        switch self {
        case .full: return "发布"
        case .compact: return "记下"
        }
    }
}
