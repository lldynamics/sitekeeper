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

    var body: some View {
        Group {
            Section(AppLocalization.string("教程排版")) {
                if didRestoreDraft {
                    Label(AppLocalization.string("已恢复上次未保存草稿"), systemImage: "arrow.clockwise")
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
                            Label(AppLocalization.string("插入模块"), systemImage: "plus.rectangle.on.folder")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.appProminent())
                    }
                }
            }
            ConstructionMethodTutorialRichTextEditor(text: $tutorialBody)
            Section(AppLocalization.string("教程图片/视频")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $selectedTutorialMediaItems, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                            Label(AppLocalization.string("相册图/视频"), systemImage: "photo.stack.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        Button(action: onOpenCamera) {
                            Label(AppLocalization.string("拍照"), systemImage: "camera")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if isImportingTutorialMedia {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(tutorialMediaImportMessage.isEmpty ? AppLocalization.string("正在导入教程媒体...") : tutorialMediaImportMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if tutorialAttachments.isEmpty {
                    Text(AppLocalization.string("还没有教程媒体。可补充关键节点图片和短视频。"))
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
