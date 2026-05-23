import SwiftUI
import UIKit

struct ConstructionMethodTutorialBlock: View {
    let tutorialBody: String
    let attachments: [QuickNoteAttachment]
    var onPreviewAttachment: ((QuickNoteAttachment) -> Void)? = nil

    private var normalizedBody: String {
        tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var renderedBody: AttributedString {
        if let markdown = try? AttributedString(markdown: normalizedBody) {
            return markdown
        }
        return AttributedString(normalizedBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "完整教程"), systemImage: "doc.text")
                .font(.headline)
            if normalizedBody.isEmpty {
                Text(String(localized: "未填写完整教程。可在编辑页补充从准备到验收的全流程说明。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(renderedBody)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if !attachments.isEmpty {
                ConstructionMethodAttachmentCarousel(
                    attachments: attachments,
                    onPreview: { attachment in
                        onPreviewAttachment?(attachment)
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ConstructionMethodAttachmentCarousel: View {
    let attachments: [QuickNoteAttachment]
    let onPreview: (QuickNoteAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachments) { attachment in
                    Button {
                        onPreview(attachment)
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                            if let image = previewImage(for: attachment) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: attachment.attachmentKind.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            if attachment.attachmentKind == .video {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.45))
                                    .padding(8)
                            }
                        }
                        .frame(width: 220, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func previewImage(for attachment: QuickNoteAttachment) -> UIImage? {
        switch attachment.attachmentKind {
        case .photo, .drawing:
            guard let data = QuickNoteAttachmentStorage.data(for: attachment.fileName) else { return nil }
            return UIImage(data: data)
        case .video:
            return QuickNoteAttachmentStorage.videoThumbnail(for: attachment.fileName)
        case .audio, .file:
            return nil
        }
    }
}

struct ConstructionMethodDetailBlock: View {
    private struct NumberedLine: Identifiable {
        let id: String
        let number: Int
        let text: String
    }

    let title: String
    let systemImage: String
    let lines: [String]
    var isCheckable = false
    var showOnlyPendingItems = false

    @State private var checkedIndexes: Set<Int> = []
    @State private var showCompletedItems = false

    private var sanitizedLines: [String] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var completedCount: Int {
        checkedIndexes.intersection(Set(sanitizedLines.indices)).count
    }

    private var pendingIndexes: [Int] {
        sanitizedLines.indices.filter { !checkedIndexes.contains($0) }
    }

    private var completedIndexes: [Int] {
        sanitizedLines.indices.filter { checkedIndexes.contains($0) }
    }

    private var numberedLines: [NumberedLine] {
        var occurrenceByLine: [String: Int] = [:]
        return sanitizedLines.enumerated().map { index, line in
            let nextOccurrence = occurrenceByLine[line, default: 0] + 1
            occurrenceByLine[line] = nextOccurrence
            return NumberedLine(
                id: "\(line)#\(nextOccurrence)",
                number: index + 1,
                text: line
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if isCheckable, !sanitizedLines.isEmpty {
                    Text("\(completedCount)/\(sanitizedLines.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button(String(localized: "重置")) { checkedIndexes.removeAll() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                }
            }
            if sanitizedLines.isEmpty {
                Text(String(localized: "未填写"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if isCheckable {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pendingIndexes, id: \.self) { index in
                            checkableLineRow(index: index, line: sanitizedLines[index], isChecked: false)
                        }
                        if showOnlyPendingItems {
                            if !completedIndexes.isEmpty {
                                Text(String(format: String(localized: "已隐藏 %lld 项已完成内容"), Int64(completedIndexes.count)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if !completedIndexes.isEmpty {
                                DisclosureGroup(String(format: String(localized: "已完成 %lld 项"), Int64(completedIndexes.count)), isExpanded: $showCompletedItems) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(completedIndexes, id: \.self) { index in
                                            checkableLineRow(index: index, line: sanitizedLines[index], isChecked: true)
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                                .font(.caption)
                                .tint(.secondary)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(numberedLines) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(line.number).")
                                    .foregroundStyle(.secondary)
                                Text(line.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
        .onChange(of: sanitizedLines) { _, _ in
            checkedIndexes.removeAll()
            showCompletedItems = false
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggleChecked(_ index: Int) {
        if checkedIndexes.contains(index) {
            checkedIndexes.remove(index)
        } else {
            checkedIndexes.insert(index)
        }
    }

    @ViewBuilder
    private func checkableLineRow(index: Int, line: String, isChecked: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                toggleChecked(index)
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            Text(line)
                .frame(maxWidth: .infinity, alignment: .leading)
                .strikethrough(isChecked, color: .secondary)
                .foregroundStyle(isChecked ? .secondary : .primary)
        }
        .font(.callout)
    }
}

struct ConstructionMethodAttachmentMiniStrip: View {
    let attachments: [QuickNoteAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments.prefix(3)) { attachment in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                        if let image = previewImage(for: attachment) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: attachment.attachmentKind.systemImage)
                                .foregroundStyle(.secondary)
                        }
                        if attachment.attachmentKind == .video {
                            Image(systemName: "play.circle.fill")
                                .font(.caption)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if attachments.count > 3 {
                    Text("+\(attachments.count - 3)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.top, 2)
        }
    }

    private func previewImage(for attachment: QuickNoteAttachment) -> UIImage? {
        switch attachment.attachmentKind {
        case .photo, .drawing:
            guard let data = QuickNoteAttachmentStorage.data(for: attachment.fileName) else { return nil }
            return UIImage(data: data)
        case .video:
            return QuickNoteAttachmentStorage.videoThumbnail(for: attachment.fileName)
        case .audio, .file:
            return nil
        }
    }
}
