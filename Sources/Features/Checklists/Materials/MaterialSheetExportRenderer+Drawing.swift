import Foundation
import UIKit

extension MaterialSheetExportRenderer {
    static func drawDocumentHeader(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
        var y = origin.y
        y = drawText(
            template.title,
            at: CGPoint(x: origin.x, y: y),
            w: width,
            f: .boldSystemFont(ofSize: 21),
            a: .center,
            color: titleColor
        ) + 2
        accentColor.setStroke()
        let path = UIBezierPath()
        path.lineWidth = 1.2
        path.move(to: CGPoint(x: origin.x, y: y))
        path.addLine(to: CGPoint(x: origin.x + width, y: y))
        path.stroke()
        y += 10
        return y
    }

    static func drawSummarySection(
        _ rows: [(label: String, value: String)],
        at origin: CGPoint,
        width: CGFloat
    ) -> CGFloat {
        var y = drawSectionTitle(text("materialSheet.export.projectSummary"), at: origin, width: width)
        let cellWidth = width / 2
        let rowHeight: CGFloat = 24
        for pairIndex in stride(from: 0, to: rows.count, by: 2) {
            for offset in 0..<2 {
                let index = pairIndex + offset
                guard rows.indices.contains(index) else { continue }
                let rect = CGRect(
                    x: origin.x + CGFloat(offset) * cellWidth,
                    y: y,
                    width: cellWidth,
                    height: rowHeight
                )
                drawSummaryCell(label: rows[index].label, value: rows[index].value, in: rect)
            }
            y += rowHeight
        }
        return y + 10
    }

    static func drawTotalsSection(
        template: ExportTemplate,
        options: MaterialSheetExportOptions,
        at origin: CGPoint,
        width: CGFloat
    ) -> CGFloat {
        var y = origin.y
        if options.showPrice, template.totalEstimate.isPositive {
            y = drawText(
                "\(text("materialSheet.export.estimateTotal")): \(amountDisplay(template.totalEstimate, currencyDisplayMode: template.currencyDisplayMode))",
                at: CGPoint(x: origin.x, y: y),
                w: width,
                f: .systemFont(ofSize: 10),
                color: bodyColor
            )
        }
        if options.showLabor, template.totalLabor.isPositive {
            y = drawText(
                "\(text("materialSheet.export.laborTotal")): \(amountDisplay(template.totalLabor, currencyDisplayMode: template.currencyDisplayMode))",
                at: CGPoint(x: origin.x, y: y),
                w: width,
                f: .systemFont(ofSize: 10),
                color: bodyColor
            )
        }
        if template.grandTotal.isPositive {
            y = drawText(
                "\(text("materialSheet.export.grandTotal")): \(amountDisplay(template.grandTotal, currencyDisplayMode: template.currencyDisplayMode))",
                at: CGPoint(x: origin.x, y: y),
                w: width,
                f: .boldSystemFont(ofSize: 12),
                color: titleColor
            )
        }
        return y
    }

    static func drawSignatureSection(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
        var y = drawSectionTitle(text("materialSheet.export.signatureArea"), at: origin, width: width)
        let labels = [
            text("materialSheet.export.preparedBy"),
            text("materialSheet.export.receivedBy"),
            text("materialSheet.export.signatureDate")
        ]
        let values = [template.preparer.isEmpty ? "" : template.preparer, "", ""]
        let cellWidth = width / CGFloat(labels.count)
        let rowHeight: CGFloat = 42
        for index in labels.indices {
            let rect = CGRect(x: origin.x + CGFloat(index) * cellWidth, y: y, width: cellWidth, height: rowHeight)
            drawSignatureCell(label: labels[index], value: values[index], in: rect)
        }
        y += rowHeight + 10
        return drawText(
            format("materialSheet.export.generatedBy", AppBrand.displayName),
            at: CGPoint(x: origin.x, y: y),
            w: width,
            f: .systemFont(ofSize: 8),
            a: .center,
            color: mutedColor
        )
    }

    static func drawImageDocumentHeader(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
        var y = origin.y
        y = drawImageText(
            template.title,
            at: CGPoint(x: origin.x, y: y),
            w: width,
            f: .boldSystemFont(ofSize: 24),
            a: .center,
            color: titleColor
        ) + 2
        accentColor.setStroke()
        let path = UIBezierPath()
        path.lineWidth = 1.4
        path.move(to: CGPoint(x: origin.x, y: y))
        path.addLine(to: CGPoint(x: origin.x + width, y: y))
        path.stroke()
        return y + 10
    }

    static func drawImageSummarySection(
        _ rows: [(label: String, value: String)],
        at origin: CGPoint,
        width: CGFloat
    ) -> CGFloat {
        var y = drawImageSectionTitle(text("materialSheet.export.projectSummary"), at: origin, width: width)
        let cellWidth = width / 2
        let rowHeight: CGFloat = 25
        for pairIndex in stride(from: 0, to: rows.count, by: 2) {
            for offset in 0..<2 {
                let index = pairIndex + offset
                guard rows.indices.contains(index) else { continue }
                let rect = CGRect(
                    x: origin.x + CGFloat(offset) * cellWidth,
                    y: y,
                    width: cellWidth,
                    height: rowHeight
                )
                drawSummaryCell(label: rows[index].label, value: rows[index].value, in: rect, fontSize: 11)
            }
            y += rowHeight
        }
        return y + 10
    }

    static func drawImageTotalsSection(
        template: ExportTemplate,
        options: MaterialSheetExportOptions,
        at origin: CGPoint,
        width: CGFloat
    ) -> CGFloat {
        var y = origin.y
        if options.showPrice, template.totalEstimate.isPositive {
            y = drawImageText(
                "\(text("materialSheet.export.estimateTotal")): \(amountDisplay(template.totalEstimate, currencyDisplayMode: template.currencyDisplayMode))",
                at: CGPoint(x: origin.x, y: y),
                w: width,
                f: .systemFont(ofSize: 12),
                color: bodyColor
            )
        }
        if options.showLabor, template.totalLabor.isPositive {
            y = drawImageText(
                "\(text("materialSheet.export.laborTotal")): \(amountDisplay(template.totalLabor, currencyDisplayMode: template.currencyDisplayMode))",
                at: CGPoint(x: origin.x, y: y),
                w: width,
                f: .systemFont(ofSize: 12),
                color: bodyColor
            )
        }
        if template.grandTotal.isPositive {
            y = drawImageText(
                "\(text("materialSheet.export.grandTotal")): \(amountDisplay(template.grandTotal, currencyDisplayMode: template.currencyDisplayMode))",
                at: CGPoint(x: origin.x, y: y),
                w: width,
                f: .boldSystemFont(ofSize: 15),
                color: titleColor
            )
        }
        return y
    }

    static func drawImageSignatureSection(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
        var y = drawImageSectionTitle(text("materialSheet.export.signatureArea"), at: origin, width: width)
        let labels = [
            text("materialSheet.export.preparedBy"),
            text("materialSheet.export.receivedBy"),
            text("materialSheet.export.signatureDate")
        ]
        let values = [template.preparer.isEmpty ? "" : template.preparer, "", ""]
        let cellWidth = width / CGFloat(labels.count)
        let rowHeight: CGFloat = 46
        for index in labels.indices {
            let rect = CGRect(x: origin.x + CGFloat(index) * cellWidth, y: y, width: cellWidth, height: rowHeight)
            drawSignatureCell(label: labels[index], value: values[index], in: rect, fontSize: 11)
        }
        y += rowHeight + 8
        return drawImageText(
            format("materialSheet.export.generatedBy", AppBrand.displayName),
            at: CGPoint(x: origin.x, y: y),
            w: width,
            f: .systemFont(ofSize: 10),
            a: .center,
            color: mutedColor
        )
    }

    static func drawSectionTitle(_ title: String, at origin: CGPoint, width: CGFloat) -> CGFloat {
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: 22)
        sectionFillColor.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
        _ = drawText(
            title,
            at: CGPoint(x: rect.minX + 8, y: rect.minY + 4),
            w: rect.width - 16,
            f: .boldSystemFont(ofSize: 10),
            color: titleColor
        )
        return rect.maxY + 6
    }

    static func drawImageSectionTitle(_ title: String, at origin: CGPoint, width: CGFloat) -> CGFloat {
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: 24)
        sectionFillColor.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
        _ = drawImageText(
            title,
            at: CGPoint(x: rect.minX + 9, y: rect.minY + 4),
            w: rect.width - 18,
            f: .boldSystemFont(ofSize: 12),
            color: titleColor
        )
        return rect.maxY + 6
    }

    static func drawSummaryCell(label: String, value: String, in rect: CGRect, fontSize: CGFloat = 9) {
        tableBorderColor.setStroke()
        UIBezierPath(rect: rect).stroke()
        let labelWidth = min(CGFloat(74), rect.width * 0.36)
        drawCellText(label, in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: labelWidth, height: rect.height - 8), font: .boldSystemFont(ofSize: fontSize), color: mutedColor)
        drawCellText(value, in: CGRect(x: rect.minX + labelWidth + 8, y: rect.minY + 5, width: rect.width - labelWidth - 12, height: rect.height - 8), font: .systemFont(ofSize: fontSize), color: bodyColor)
    }

    static func drawSignatureCell(label: String, value: String, in rect: CGRect, fontSize: CGFloat = 9) {
        tableBorderColor.setStroke()
        UIBezierPath(rect: rect).stroke()
        drawCellText(label, in: CGRect(x: rect.minX + 6, y: rect.minY + 6, width: rect.width - 12, height: 14), font: .systemFont(ofSize: fontSize), color: mutedColor)
        let baselineY = rect.maxY - 13
        tableBorderColor.setStroke()
        let path = UIBezierPath()
        path.lineWidth = 0.8
        path.move(to: CGPoint(x: rect.minX + 8, y: baselineY))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: baselineY))
        path.stroke()
        if !value.isEmpty {
            drawCellText(value, in: CGRect(x: rect.minX + 8, y: rect.minY + 22, width: rect.width - 16, height: 14), font: .systemFont(ofSize: fontSize), color: bodyColor)
        }
    }

    static func drawImageText(
        _ text: String,
        at origin: CGPoint,
        w: CGFloat,
        f: UIFont,
        a: NSTextAlignment = .left,
        color: UIColor = bodyColor
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = a
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: f,
            .paragraphStyle: paragraph,
            .foregroundColor: color
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let rect = attributedString.boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = ceil(rect.height)
        attributedString.draw(in: CGRect(x: origin.x, y: origin.y, width: w, height: height))
        return origin.y + max(18, height + 4)
    }

    static func drawImageHeader(_ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        for column in columns {
            let rect = CGRect(x: currentX, y: y, width: column.width, height: h)
            tableHeaderFillColor.setFill()
            UIBezierPath(rect: rect).fill()
            tableBorderColor.setStroke()
            UIBezierPath(rect: rect).stroke()
            drawCellText(column.title, in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: rect.height - 8), font: .boldSystemFont(ofSize: 11), color: titleColor)
            currentX += column.width
        }
        return y + h
    }

    static func drawImageRow(_ values: [String], _ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        for (index, column) in columns.enumerated() {
            let rect = CGRect(x: currentX, y: y, width: column.width, height: h)
            tableBorderColor.setStroke()
            UIBezierPath(rect: rect).stroke()
            let value = values.indices.contains(index) ? values[index] : ""
            drawCellText(value, in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: rect.height - 8), font: .systemFont(ofSize: 11), color: bodyColor)
            currentX += column.width
        }
        return y + h
    }

    static func drawText(
        _ text: String,
        at origin: CGPoint,
        w: CGFloat,
        f: UIFont,
        a: NSTextAlignment = .left,
        color: UIColor = bodyColor
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = a
        paragraph.lineBreakMode = .byWordWrapping
        let attributes = NSAttributedString(
            string: text,
            attributes: [.font: f, .paragraphStyle: paragraph, .foregroundColor: color]
        )
        let rect = attributes.boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = ceil(rect.height)
        attributes.draw(in: CGRect(x: origin.x, y: origin.y, width: w, height: height))
        return origin.y + max(16, height + 3)
    }

    static func drawHeader(_ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        for column in columns {
            let rect = CGRect(x: currentX, y: y, width: column.width, height: h)
            tableHeaderFillColor.setFill()
            UIBezierPath(rect: rect).fill()
            tableBorderColor.setStroke()
            UIBezierPath(rect: rect).stroke()
            drawCellText(column.title, in: CGRect(x: rect.minX + 3, y: rect.minY + 5, width: rect.width - 6, height: rect.height - 6), font: .boldSystemFont(ofSize: 9), color: titleColor)
            currentX += column.width
        }
        return y + h
    }

    static func drawRow(_ values: [String], _ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        for (index, column) in columns.enumerated() {
            let rect = CGRect(x: currentX, y: y, width: column.width, height: h)
            tableBorderColor.setStroke()
            UIBezierPath(rect: rect).stroke()
            let value = values.indices.contains(index) ? values[index] : ""
            drawCellText(value, in: CGRect(x: rect.minX + 3, y: rect.minY + 5, width: rect.width - 6, height: rect.height - 6), font: .systemFont(ofSize: 9), color: bodyColor)
            currentX += column.width
        }
        return y + h
    }

    static func drawCellText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: color
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    static func amountRaw(_ value: MoneyValue) -> String {
        ReportBuilder.amountRaw(value)
    }

    static func parsedAmountRaw(_ text: String) -> String {
        guard let decimal = DataValueParser.decimalValueIfPresent(from: text) else {
            return ""
        }
        return ReportBuilder.amountRaw(MoneyValue(decimal))
    }

    static func amountDisplay(
        _ value: MoneyValue,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> String {
        ReportBuilder.amountDisplay(value, currencyDisplayMode: currencyDisplayMode)
    }

    static func amountDisplay(
        rawText: String,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        guard let decimal = DataValueParser.decimalValueIfPresent(from: trimmed) else {
            return trimmed
        }
        return ReportBuilder.amountDisplay(
            MoneyValue(decimal),
            currencyDisplayMode: currencyDisplayMode
        )
    }

    static func displayText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    static func currentCurrencyDisplayMode() -> ExportCurrencyDisplayMode {
        let rawValue = UserPreferencesStore.shared.string(
            UserPreferenceKeys.exportCurrencyDisplayMode,
            default: ExportCurrencyDisplayMode.defaultMode.rawValue
        )
        return StringEnumFallback.value(rawValue, default: ExportCurrencyDisplayMode.defaultMode)
    }

    static func text(_ key: String) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: key))
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    static var accentColor: UIColor {
        AppTheme.current.palette.inventoryUIColor
    }

    static var titleColor: UIColor {
        UIColor(red: 0.12, green: 0.16, blue: 0.14, alpha: 1)
    }

    static var bodyColor: UIColor {
        UIColor(red: 0.20, green: 0.24, blue: 0.22, alpha: 1)
    }

    static var mutedColor: UIColor {
        UIColor(red: 0.48, green: 0.52, blue: 0.49, alpha: 1)
    }

    static var tableBorderColor: UIColor {
        UIColor(red: 0.78, green: 0.82, blue: 0.79, alpha: 1)
    }

    static var tableHeaderFillColor: UIColor {
        accentColor.withAlphaComponent(0.12)
    }

    static var sectionFillColor: UIColor {
        accentColor.withAlphaComponent(0.08)
    }
}
