import SwiftUI
import PhotosUI

struct ConstructionMethodTutorialEditorSections: View {
    let didRestoreDraft: Bool
    @Binding var tutorialBody: String
    @Binding var selectedTutorialMediaItems: [PhotosPickerItem]
    let isImportingTutorialMedia: Bool
    let tutorialMediaImportMessage: String
    let tutorialAttachments: [QuickNoteAttachment]
    let onInsertBlock: (String) -> Void
    let onOpenCamera: () -> Void
    let onPreviewAttachment: (QuickNoteAttachment) -> Void
    let onRemoveAttachment: (QuickNoteAttachment) -> Void

    private var renderedTutorialPreview: AttributedString {
        let normalized = tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if let markdown = try? AttributedString(markdown: normalized) {
            return markdown
        }
        return AttributedString(normalized)
    }

    var body: some View {
        Group {
            Section("教程排版") {
                if didRestoreDraft {
                    Label("已恢复上次未保存草稿", systemImage: "arrow.clockwise")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ConstructionMethodTutorialBlockCatalog.quickTools) { block in
                            Button(block.title) { onInsertBlock(block.snippet) }
                                .buttonStyle(.bordered)
                        }
                        Menu {
                            ForEach(ConstructionMethodTutorialBlockCatalog.structureTemplates) { block in
                                Button(block.title) {
                                    onInsertBlock(block.snippet)
                                }
                            }
                        } label: {
                            Label("插入模块", systemImage: "plus.rectangle.on.folder")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("完整教程正文") {
                ZStack(alignment: .topLeading) {
                    if tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("建议写明：适用场景、施工准备、关键工序、质量控制、常见问题、验收标准。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $tutorialBody)
                        .font(.body)
                        .frame(minHeight: 220)
                }
            }
            Section("教程预览") {
                if tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入内容后会在这里显示预览。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(renderedTutorialPreview)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            Section("教程图片/视频") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $selectedTutorialMediaItems, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                            Label("相册图/视频", systemImage: "photo.stack.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        Button(action: onOpenCamera) {
                            Label("拍照", systemImage: "camera")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if isImportingTutorialMedia {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(tutorialMediaImportMessage.isEmpty ? "正在导入教程媒体..." : tutorialMediaImportMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if tutorialAttachments.isEmpty {
                    Text("还没有教程媒体。可补充关键节点图片和短视频。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    QuickNoteAttachmentStrip(
                        attachments: tutorialAttachments,
                        onPreview: onPreviewAttachment,
                        onRemove: onRemoveAttachment
                    )
                }
            }
        }
    }
}
