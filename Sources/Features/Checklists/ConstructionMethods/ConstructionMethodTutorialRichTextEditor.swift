import SwiftUI

struct ConstructionMethodTutorialRichTextEditor: View {
    @Binding var text: String

    var editorTitle = AppLocalization.string("完整教程正文")
    var previewTitle = AppLocalization.string("教程预览")
    var placeholder = AppLocalization.string("建议写明：适用场景、施工准备、关键工序、质量控制、常见问题、验收标准。")
    var emptyPreviewText = AppLocalization.string("输入内容后会在这里显示预览。")
    var minEditorHeight: CGFloat = 220

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var renderedPreview: AttributedString {
        if let markdown = try? AttributedString(markdown: normalizedText) {
            return markdown
        }
        return AttributedString(normalizedText)
    }

    var body: some View {
        Group {
            Section(editorTitle) {
                ZStack(alignment: .topLeading) {
                    if normalizedText.isEmpty {
                        Text(placeholder)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: minEditorHeight)
                }
            }

            Section(previewTitle) {
                if normalizedText.isEmpty {
                    Text(emptyPreviewText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(renderedPreview)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
