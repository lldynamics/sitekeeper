import Foundation

enum QuickNoteText {
    static func displayContent(for note: QuickNote) -> String {
        if !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return note.content
        }
        if !note.attachments.isEmpty {
            return attachmentSummary(note.attachments)
        }
        return note.title.isEmpty ? "未命名记录" : note.title
    }

    static func attachmentSummary(_ attachments: [QuickNoteAttachment]) -> String {
        let mediaCount = attachments.filter { [.photo, .video].contains($0.attachmentKind) }.count
        var parts: [String] = []
        if mediaCount > 0 {
            parts.append("媒体 \(mediaCount)")
        }
        let grouped = Dictionary(grouping: attachments, by: { $0.attachmentKind })
        for kind in [QuickNoteAttachmentKind.audio, .drawing, .file] {
            guard let count = grouped[kind]?.count, count > 0 else { continue }
            parts.append("\(kind.title) \(count)")
        }
        return parts.joined(separator: " · ")
    }

    static func title(from content: String, attachments: [QuickNoteAttachment]) -> String {
        let compact = content.replacingOccurrences(of: "\n", with: " ")
        if !compact.isEmpty { return String(compact.prefix(24)) }
        let summary = attachmentSummary(attachments)
        return summary.isEmpty ? "随手记" : summary
    }
}
