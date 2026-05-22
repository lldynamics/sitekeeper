import Foundation
import UIKit

extension ReportBuilder {
    static func drawPhotoWallPages(
        title: String,
        items: [ReportPhotoItem],
        context: UIGraphicsPDFRendererContext,
        page: CGRect,
        margin: CGFloat,
        thumbnailsByFileName: [String: UIImage] = [:]
    ) {
        let colCount = 2
        let rowCount = 3
        let cardGap: CGFloat = 12
        let cardWidth = (page.width - margin * 2 - cardGap) / CGFloat(colCount)
        let cardHeight: CGFloat = 220
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.projectName < rhs.projectName }
            return lhs.date > rhs.date
        }

        var index = 0
        while index < max(sortedItems.count, 1) {
            context.beginPage()
            let maxWidth = page.width - margin * 2
            _ = drawPDFText(title, at: CGPoint(x: margin, y: 32), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 18), alignment: .center)
            _ = drawPDFText(locFormat("生成时间: %@", Formatters.now()), at: CGPoint(x: margin, y: 58), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 10), alignment: .center)
            if sortedItems.isEmpty {
                _ = drawPDFText(loc("暂无照片"), at: CGPoint(x: margin, y: 120), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13), alignment: .center)
                break
            }

            for row in 0..<rowCount {
                for col in 0..<colCount {
                    guard index < sortedItems.count else { continue }
                    let item = sortedItems[index]
                    let x = margin + CGFloat(col) * (cardWidth + cardGap)
                    let y = 90 + CGFloat(row) * (cardHeight + 14)
                    let cardRect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
                    UIBezierPath(roundedRect: cardRect, cornerRadius: 8).stroke()
                    let imageRect = CGRect(x: x + 8, y: y + 8, width: cardWidth - 16, height: 146)
                    if let image = thumbnailsByFileName[item.fileName] ?? PhotoStorage.thumbnail(for: item.fileName) {
                        image.draw(in: imageRect)
                    } else {
                        UIColor.secondarySystemFill.setFill()
                        UIBezierPath(rect: imageRect).fill()
                    }
                    let titleText = "\(item.date) · \(item.projectName)"
                    _ = drawPDFText(titleText, at: CGPoint(x: x + 8, y: y + 160), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    _ = drawPDFText(locFormat("标签: %@", item.tag), at: CGPoint(x: x + 8, y: y + 176), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    _ = drawPDFText(item.note.isEmpty ? loc("备注: -") : locFormat("备注: %@", item.note), at: CGPoint(x: x + 8, y: y + 192), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    index += 1
                }
            }
        }
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func drawPDFText(
        _ text: String,
        at origin: CGPoint,
        maxWidth: CGFloat,
        font: UIFont,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
        let rect = attr.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let height = ceil(rect.height)
        attr.draw(with: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return origin.y + max(18, height + 4)
    }

    static func drawPDFTableHeader(
        columns: [(title: String, width: CGFloat)],
        startX: CGFloat,
        y: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        var x = startX
        for column in columns {
            let rect = CGRect(x: x, y: y, width: column.width, height: height)
            UIBezierPath(rect: rect).stroke()
            let attr = NSAttributedString(
                string: column.title,
                attributes: [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.black]
            )
            let textRect = CGRect(x: rect.minX + 4, y: rect.minY + 6, width: rect.width - 8, height: rect.height - 8)
            attr.draw(in: textRect)
            x += column.width
        }
        return y + height
    }

    static func drawPDFTableRow(
        values: [String],
        columns: [(title: String, width: CGFloat)],
        startX: CGFloat,
        y: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        var x = startX
        for (index, column) in columns.enumerated() {
            let rect = CGRect(x: x, y: y, width: column.width, height: height)
            UIBezierPath(rect: rect).stroke()
            let value = values.indices.contains(index) ? values[index] : ""
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attr = NSAttributedString(
                string: value,
                attributes: [.font: UIFont.systemFont(ofSize: 10), .paragraphStyle: paragraph, .foregroundColor: UIColor.black]
            )
            attr.draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 6, width: rect.width - 8, height: rect.height - 8))
            x += column.width
        }
        return y + height
    }

    static func pdfData(lines: [String]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 36
            let margin: CGFloat = 36
            let maxWidth = page.width - margin * 2
            for line in lines {
                if y > page.height - 54 {
                    context.beginPage()
                    y = 36
                }
                let isHeading = isReportLineHeading(line)
                let font = line.isEmpty
                    ? UIFont.systemFont(ofSize: 6)
                    : UIFont.systemFont(ofSize: isHeading ? 15 : 11, weight: isHeading ? .semibold : .regular)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attr = NSAttributedString(string: line, attributes: [.font: font, .paragraphStyle: paragraph])
                let rect = attr.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                attr.draw(with: CGRect(x: margin, y: y, width: maxWidth, height: ceil(rect.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += max(16, ceil(rect.height) + 6)
            }
        }
    }

    private static func isReportLineHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-"), !trimmed.hasPrefix("   -") else { return false }
        if trimmed.count > 36 { return false }
        if trimmed.contains(":") { return false }
        if trimmed.rangeOfCharacter(from: .decimalDigits) == nil { return true }
        return trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") || trimmed.hasPrefix("3.") || trimmed.hasPrefix("4.") || trimmed.hasPrefix("5.")
    }
}
