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
    var onDiscardDraftRequest: () -> Void = {}
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
            compactComposerContent
        } else {
            Section {
                fullComposerContent
            }
        }
    }

    private var compactComposerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                QuickNoteAttachmentStrip(
                    attachments: attachments,
                    onPreview: onPreview,
                    onRemove: removeAttachment(_:)
                )
                .padding(.horizontal, 12)
            }

            compactActionTools

            HStack(alignment: .bottom, spacing: 8) {
                TextField(mode.placeholder, text: $content, axis: .vertical)
                    .focused($isContentFocused)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minHeight: 40, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.appStrokeSeparator, lineWidth: 0.5)
                    )
                    .accessibilityLabel("随手记消息输入框")

                Button {
                    onPublish()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canPublish ? Color.appPrimaryAction : Color(uiColor: .tertiaryLabel))
                        .frame(width: 36, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!canPublish)
                .accessibilityLabel("发送随手记")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { isContentFocused = false }
            }
        }
    }

    private var compactActionTools: some View {
        let selectedProjectName = projectName(projectId)

        return HStack(alignment: .top, spacing: 8) {
            Menu {
                Picker("关联工程", selection: $projectId) {
                    Text("不关联工程").tag(nil as UUID?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            } label: {
                Label(selectedProjectName.isEmpty ? "不关联工程" : selectedProjectName, systemImage: projectId == nil ? "building.2" : "building.2.fill")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(projectId == nil ? .secondary : .appPrimaryAction)
            .accessibilityLabel(projectId == nil ? "选择关联工程" : "已关联工程 \(selectedProjectName)")

            QuickNoteAttachmentPickerBar(
                projectName: selectedProjectName,
                mode: .compact
            ) { attachment in
                attachments.append(attachment)
                onAttachmentAdded(attachment)
            }
            .fixedSize(horizontal: true, vertical: false)

            if canPublish {
                Button {
                    onDiscardDraftRequest()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("清空草稿")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var fullComposerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(mode.placeholder, text: $content, axis: .vertical)
                .focused($isContentFocused)
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
                mode: .full
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
                    Button("放弃草稿", role: .destructive) {
                        onDiscardDraftRequest()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
            .padding(.vertical, 4)
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
            return "记录现场情况、客户交代或临时想法"
        case .compact:
            return "发消息记录现场情况"
        }
    }
}
