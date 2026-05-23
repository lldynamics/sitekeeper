import Foundation
import UIKit

enum MaterialSheetExportRenderer {
    struct ExportTemplate {
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

    struct ExportColumn {
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
}
