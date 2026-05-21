import Foundation
import UIKit

enum MaterialSheetExportRenderer {
    private struct ExportTemplate {
        var title: String
        var projectName: String
        var preparer: String
        var exportDate: String
        var itemCount: Int
        var totalEstimate: MoneyValue
        var totalLabor: MoneyValue
        var currencyDisplayMode: ExportCurrencyDisplayMode

        var projectDisplayName: String {
            projectName.isEmpty ? text("materialSheet.export.notFilled") : projectName
        }

        var preparerDisplayName: String {
            preparer.isEmpty ? text("materialSheet.export.notFilled") : preparer
        }

        var grandTotal: MoneyValue {
            totalEstimate + totalLabor
        }

        var summaryRows: [(label: String, value: String)] {
            [
                (text("materialSheet.export.projectName"), projectDisplayName),
                (text("materialSheet.export.exportDate"), exportDate),
                (text("materialSheet.export.preparedBy"), preparerDisplayName),
                (
                    text("materialSheet.export.itemCount"),
                    format("materialSheet.export.itemCount.value", Int64(itemCount))
                )
            ]
        }
    }

    private struct ExportColumn {
        var title: String
        var width: CGFloat
    }

    static func timestampToken() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter.string(from: Date())
    }

    static func generatePDF(
        sheetItems: [MaterialSheetItem],
        options: MaterialSheetExportOptions,
        exportProjectName: String,
        exportPreparer: String
    ) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let margin: CGFloat = 30
        let maxWidth = page.width - margin * 2
        let columns = activeColumns(options: options, pageWidth: page.width)
        let rowHeight: CGFloat = 22
        let template = makeTemplate(
            sheetItems: sheetItems,
            exportProjectName: exportProjectName,
            exportPreparer: exportPreparer
        )

        return renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.cgContext.fill(page)

            var y: CGFloat = 30
            y = drawDocumentHeader(template: template, at: CGPoint(x: margin, y: y), width: maxWidth)
            y = drawSummarySection(template.summaryRows, at: CGPoint(x: margin, y: y), width: maxWidth)
            y = drawSectionTitle(text("materialSheet.export.detailTable"), at: CGPoint(x: margin, y: y), width: maxWidth)
            y = drawHeader(columns, x: margin, y: y, h: rowHeight)

            if sheetItems.isEmpty {
                y = drawRow(emptyRowValues(columns: columns), columns, x: margin, y: y, h: rowHeight)
            } else {
                for (index, item) in sheetItems.enumerated() {
                    if y > page.height - 150 {
                        context.beginPage()
                        UIColor.white.setFill()
                        context.cgContext.fill(page)
                        y = 44
                        y = drawHeader(columns, x: margin, y: y, h: rowHeight)
                    }
                    var rowValues = itemRowValues(
                        item,
                        options: options,
                        currencyDisplayMode: template.currencyDisplayMode
                    )
                    rowValues[0] = "\(index + 1)"
                    y = drawRow(rowValues, columns, x: margin, y: y, h: rowHeight)
                }
            }

            y = drawTotalsSection(template: template, options: options, at: CGPoint(x: margin, y: y + 10), width: maxWidth)
            _ = drawSignatureSection(template: template, at: CGPoint(x: margin, y: y + 12), width: maxWidth)
        }
    }

    static func generateCSV(
        sheetItems: [MaterialSheetItem],
        options: MaterialSheetExportOptions
    ) -> String {
        let currencyDisplayMode = currentCurrencyDisplayMode()
        var lines = [csvHeader(options: options)]
        for (index, item) in sheetItems.enumerated() {
            lines.append(csvItemRow(item, index: index, options: options, currencyDisplayMode: currencyDisplayMode))
        }
        return lines.joined(separator: "\n")
    }

    static func generateImage(
        sheetItems: [MaterialSheetItem],
        options: MaterialSheetExportOptions,
        exportProjectName: String,
        exportPreparer: String
    ) -> Data? {
        let columns = activeColumns(options: options, pageWidth: 700)
        let rowHeight: CGFloat = 24
        let totalWidth = max(CGFloat(700), columns.reduce(CGFloat(20)) { $0 + $1.width } + 20)
        let headerHeight: CGFloat = 178
        let footerHeight: CGFloat = 158
        let itemRowCount = max(sheetItems.count, 1)
        let totalHeight = headerHeight + CGFloat(itemRowCount) * rowHeight + footerHeight
        let template = makeTemplate(
            sheetItems: sheetItems,
            exportProjectName: exportProjectName,
            exportPreparer: exportPreparer
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: max(totalHeight, 220)))
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: max(totalHeight, 220)))

            var y: CGFloat = 14
            y = drawImageDocumentHeader(template: template, at: CGPoint(x: 14, y: y), width: totalWidth - 28)
            y = drawImageSummarySection(template.summaryRows, at: CGPoint(x: 14, y: y), width: totalWidth - 28)
            y = drawImageSectionTitle(text("materialSheet.export.detailTable"), at: CGPoint(x: 14, y: y), width: totalWidth - 28)
            y = drawImageHeader(columns, x: 14, y: y, h: rowHeight)

            if sheetItems.isEmpty {
                y = drawImageRow(emptyRowValues(columns: columns), columns, x: 14, y: y, h: rowHeight)
            } else {
                for (index, item) in sheetItems.enumerated() {
                    var rowValues = itemRowValues(
                        item,
                        options: options,
                        currencyDisplayMode: template.currencyDisplayMode
                    )
                    rowValues[0] = "\(index + 1)"
                    y = drawImageRow(rowValues, columns, x: 14, y: y, h: rowHeight)
                }
            }

            y = drawImageTotalsSection(template: template, options: options, at: CGPoint(x: 14, y: y + 10), width: totalWidth - 28)
            _ = drawImageSignatureSection(template: template, at: CGPoint(x: 14, y: y + 10), width: totalWidth - 28)
        }
    }

    private static func makeTemplate(
        sheetItems: [MaterialSheetItem],
        exportProjectName: String,
        exportPreparer: String
    ) -> ExportTemplate {
        ExportTemplate(
            title: text("materialSheet.export.title"),
            projectName: exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines),
            preparer: exportPreparer.trimmingCharacters(in: .whitespacesAndNewlines),
            exportDate: Formatters.date.string(from: Date()),
            itemCount: sheetItems.count,
            totalEstimate: totalEstimateValue(for: sheetItems),
            totalLabor: totalLaborValue(for: sheetItems),
            currencyDisplayMode: currentCurrencyDisplayMode()
        )
    }

    private static func totalEstimateValue(for sheetItems: [MaterialSheetItem]) -> MoneyValue {
        sheetItems.reduce(MoneyValue.zero) { total, item in
            total + lineTotalValue(for: item)
        }
    }

    private static func totalLaborValue(for sheetItems: [MaterialSheetItem]) -> MoneyValue {
        sheetItems.reduce(MoneyValue.zero) { total, item in
            total + MoneyValue(text: item.laborCost)
        }
    }

    private static func lineTotalValue(for item: MaterialSheetItem) -> MoneyValue {
        QuantityValue(text: item.quantity) * MoneyValue(text: item.unitPrice)
    }

    private static func activeColumns(options: MaterialSheetExportOptions, pageWidth: CGFloat) -> [ExportColumn] {
        var columns: [ExportColumn] = [
            .init(title: text("materialSheet.export.table.index"), width: 30),
            .init(title: text("materialSheet.export.table.name"), width: 110),
            .init(title: text("materialSheet.export.table.specification"), width: 64),
            .init(title: text("materialSheet.export.table.unit"), width: 30),
            .init(title: text("materialSheet.export.table.quantity"), width: 38)
        ]
        if options.showLocation {
            columns.append(.init(title: text("materialSheet.export.table.location"), width: 60))
        }
        if options.showPrice {
            columns.append(.init(title: text("materialSheet.export.table.unitPrice"), width: 50))
            columns.append(.init(title: text("materialSheet.export.table.amount"), width: 62))
        }
        if options.showLabor {
            columns.append(.init(title: text("materialSheet.export.table.laborCost"), width: 54))
        }
        if options.showSupplier {
            columns.append(.init(title: text("materialSheet.export.table.supplier"), width: 58))
        }
        if options.showNote {
            columns.append(.init(title: text("materialSheet.export.table.note"), width: 64))
        }

        let fixedWidth = columns.dropFirst().reduce(CGFloat(0)) { $0 + $1.width }
        let contentWidth = pageWidth - 60
        let nameWidth = max(CGFloat(70), contentWidth - fixedWidth)
        columns[1] = .init(title: text("materialSheet.export.table.name"), width: nameWidth)
        return columns
    }

    private static func itemRowValues(
        _ item: MaterialSheetItem,
        options: MaterialSheetExportOptions,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> [String] {
        let quantity = item.quantity
        let lineTotal = lineTotalValue(for: item)
        var values: [String] = ["", item.name, item.specification, item.unit, quantity]
        if options.showLocation {
            values.append(displayText(item.usageLocation))
        }
        if options.showPrice {
            values.append(amountDisplay(rawText: item.unitPrice, currencyDisplayMode: currencyDisplayMode))
            values.append(lineTotal.isPositive ? amountDisplay(lineTotal, currencyDisplayMode: currencyDisplayMode) : "-")
        }
        if options.showLabor {
            values.append(amountDisplay(rawText: item.laborCost, currencyDisplayMode: currencyDisplayMode))
        }
        if options.showSupplier {
            values.append(displayText(item.supplier))
        }
        if options.showNote {
            values.append(displayText(item.note))
        }
        return values
    }

    private static func emptyRowValues(columns: [ExportColumn]) -> [String] {
        var values = Array(repeating: "-", count: columns.count)
        if values.indices.contains(1) {
            values[1] = text("materialSheet.export.noItems")
        }
        return values
    }

    private static func csvHeader(options: MaterialSheetExportOptions) -> String {
        var headers = ["index", "name", "specification", "unit", "quantity"]
        if options.showLocation {
            headers.append("usage_location")
        }
        if options.showPrice {
            headers.append(contentsOf: ["unit_price_raw", "unit_price_display", "amount_raw", "amount_display"])
        }
        if options.showLabor {
            headers.append(contentsOf: ["labor_cost_raw", "labor_cost_display"])
        }
        if options.showSupplier {
            headers.append("supplier")
        }
        if options.showNote {
            headers.append("note")
        }
        return ReportBuilder.csv(headers)
    }

    private static func csvItemRow(
        _ item: MaterialSheetItem,
        index: Int,
        options: MaterialSheetExportOptions,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> String {
        let lineTotal = lineTotalValue(for: item)
        var values = ["\(index + 1)", item.name, item.specification, item.unit, item.quantity]
        if options.showLocation {
            values.append(item.usageLocation)
        }
        if options.showPrice {
            values.append(parsedAmountRaw(item.unitPrice))
            values.append(amountDisplay(rawText: item.unitPrice, currencyDisplayMode: currencyDisplayMode))
            values.append(lineTotal.isPositive ? amountRaw(lineTotal) : "")
            values.append(lineTotal.isPositive ? amountDisplay(lineTotal, currencyDisplayMode: currencyDisplayMode) : "")
        }
        if options.showLabor {
            values.append(parsedAmountRaw(item.laborCost))
            values.append(amountDisplay(rawText: item.laborCost, currencyDisplayMode: currencyDisplayMode))
        }
        if options.showSupplier {
            values.append(item.supplier)
        }
        if options.showNote {
            values.append(item.note)
        }
        return ReportBuilder.csv(values)
    }

    private static func drawDocumentHeader(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
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

    private static func drawSummarySection(
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

    private static func drawTotalsSection(
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

    private static func drawSignatureSection(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
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

    private static func drawImageDocumentHeader(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
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

    private static func drawImageSummarySection(
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

    private static func drawImageTotalsSection(
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

    private static func drawImageSignatureSection(template: ExportTemplate, at origin: CGPoint, width: CGFloat) -> CGFloat {
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

    private static func drawSectionTitle(_ title: String, at origin: CGPoint, width: CGFloat) -> CGFloat {
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

    private static func drawImageSectionTitle(_ title: String, at origin: CGPoint, width: CGFloat) -> CGFloat {
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

    private static func drawSummaryCell(label: String, value: String, in rect: CGRect, fontSize: CGFloat = 9) {
        tableBorderColor.setStroke()
        UIBezierPath(rect: rect).stroke()
        let labelWidth = min(CGFloat(74), rect.width * 0.36)
        drawCellText(label, in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: labelWidth, height: rect.height - 8), font: .boldSystemFont(ofSize: fontSize), color: mutedColor)
        drawCellText(value, in: CGRect(x: rect.minX + labelWidth + 8, y: rect.minY + 5, width: rect.width - labelWidth - 12, height: rect.height - 8), font: .systemFont(ofSize: fontSize), color: bodyColor)
    }

    private static func drawSignatureCell(label: String, value: String, in rect: CGRect, fontSize: CGFloat = 9) {
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

    private static func drawImageText(
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

    private static func drawImageHeader(_ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
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

    private static func drawImageRow(_ values: [String], _ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
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

    private static func drawText(
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

    private static func drawHeader(_ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
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

    private static func drawRow(_ values: [String], _ columns: [ExportColumn], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
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

    private static func drawCellText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: color
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    private static func amountRaw(_ value: MoneyValue) -> String {
        ReportBuilder.amountRaw(value.doubleValue)
    }

    private static func parsedAmountRaw(_ text: String) -> String {
        guard let decimal = DataValueParser.decimalValueIfPresent(from: text) else {
            return ""
        }
        return ReportBuilder.amountRaw(NSDecimalNumber(decimal: decimal).doubleValue)
    }

    private static func amountDisplay(
        _ value: MoneyValue,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> String {
        ReportBuilder.amountDisplay(value.doubleValue, currencyDisplayMode: currencyDisplayMode)
    }

    private static func amountDisplay(
        rawText: String,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        guard let decimal = DataValueParser.decimalValueIfPresent(from: trimmed) else {
            return trimmed
        }
        return ReportBuilder.amountDisplay(
            NSDecimalNumber(decimal: decimal).doubleValue,
            currencyDisplayMode: currencyDisplayMode
        )
    }

    private static func displayText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private static func currentCurrencyDisplayMode() -> ExportCurrencyDisplayMode {
        let rawValue = UserPreferences.string(
            UserPreferenceKeys.exportCurrencyDisplayMode,
            default: ExportCurrencyDisplayMode.defaultMode.rawValue
        )
        return StringEnumFallback.value(rawValue, default: ExportCurrencyDisplayMode.defaultMode)
    }

    private static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }

    private static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    private static var accentColor: UIColor {
        AppTheme.current.palette.inventoryUIColor
    }

    private static var titleColor: UIColor {
        UIColor(red: 0.12, green: 0.16, blue: 0.14, alpha: 1)
    }

    private static var bodyColor: UIColor {
        UIColor(red: 0.20, green: 0.24, blue: 0.22, alpha: 1)
    }

    private static var mutedColor: UIColor {
        UIColor(red: 0.48, green: 0.52, blue: 0.49, alpha: 1)
    }

    private static var tableBorderColor: UIColor {
        UIColor(red: 0.78, green: 0.82, blue: 0.79, alpha: 1)
    }

    private static var tableHeaderFillColor: UIColor {
        accentColor.withAlphaComponent(0.12)
    }

    private static var sectionFillColor: UIColor {
        accentColor.withAlphaComponent(0.08)
    }
}
