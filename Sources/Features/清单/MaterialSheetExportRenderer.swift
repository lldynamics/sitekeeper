import Foundation
import UIKit

enum MaterialSheetExportRenderer {
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
        let columns = activeColumns(options: options)
        let rowHeight: CGFloat = 22

        let projectTitle = exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preparer = exportPreparer.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalEstimateValue = totalEstimateValue(for: sheetItems)
        let totalLaborValue = totalLaborValue(for: sheetItems)
        let grandTotalValue = totalEstimateValue + totalLaborValue

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 30
            y = drawText("材料单", at: CGPoint(x: margin, y: y), w: maxWidth, f: .boldSystemFont(ofSize: 20), a: .center) + 4
            if !projectTitle.isEmpty {
                y = drawText("项目: \(projectTitle)", at: CGPoint(x: margin, y: y), w: maxWidth, f: .systemFont(ofSize: 11), a: .center)
            }
            var infoLine = "导出日期: \(Formatters.date.string(from: Date()))"
            if !preparer.isEmpty {
                infoLine += "    编制人: \(preparer)"
            }
            y = drawText(infoLine, at: CGPoint(x: margin, y: y), w: maxWidth, f: .systemFont(ofSize: 9), a: .center)
            y = drawText("共 \(sheetItems.count) 项    \(AppBrand.displayName)", at: CGPoint(x: margin, y: y), w: maxWidth, f: .systemFont(ofSize: 8), a: .center) + 10
            y = drawHeader(columns, x: margin, y: y, h: rowHeight)

            for (index, item) in sheetItems.enumerated() {
                if y > page.height - 90 {
                    context.beginPage()
                    y = 44
                    y = drawHeader(columns, x: margin, y: y, h: rowHeight)
                }
                var rowValues = itemRowValues(item, options: options)
                rowValues[0] = "\(index + 1)"
                y = drawRow(rowValues, columns, x: margin, y: y, h: rowHeight)
            }

            y += 8
            if options.showPrice, totalEstimateValue.isPositive {
                y = drawText("材料估价合计: ¥\(String(format: "%.2f", totalEstimateValue.doubleValue))", at: CGPoint(x: margin, y: y), w: maxWidth, f: .systemFont(ofSize: 10))
            }
            if options.showLabor, totalLaborValue.isPositive {
                y = drawText("人工费合计: ¥\(String(format: "%.2f", totalLaborValue.doubleValue))", at: CGPoint(x: margin, y: y), w: maxWidth, f: .systemFont(ofSize: 10))
            }
            if totalEstimateValue.isPositive || totalLaborValue.isPositive {
                y = drawText("总计: ¥\(String(format: "%.2f", grandTotalValue.doubleValue))", at: CGPoint(x: margin, y: y), w: maxWidth, f: .boldSystemFont(ofSize: 12))
            }
            y += 16
            _ = drawText("—— 本材料单由 \(AppBrand.displayName) 生成 ——", at: CGPoint(x: margin, y: y), w: maxWidth, f: .systemFont(ofSize: 8), a: .center)
        }
    }

    static func generateCSV(
        sheetItems: [MaterialSheetItem],
        options: MaterialSheetExportOptions
    ) -> String {
        var lines = [csvHeader(options: options)]
        for (index, item) in sheetItems.enumerated() {
            lines.append(csvItemRow(item, index: index, options: options))
        }
        return lines.joined(separator: "\n")
    }

    static func generateImage(
        sheetItems: [MaterialSheetItem],
        options: MaterialSheetExportOptions,
        exportProjectName: String,
        exportPreparer: String
    ) -> Data? {
        let columns = activeColumns(options: options)
        let rowHeight: CGFloat = 24
        let headerHeight: CGFloat = 120
        let footerHeight: CGFloat = 76
        let totalHeight = headerHeight + CGFloat(sheetItems.count) * rowHeight + footerHeight
        let totalWidth: CGFloat = columns.reduce(30) { $0 + $1.1 } + 20

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: max(totalHeight, 100)))
        let projectTitle = exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preparer = exportPreparer.trimmingCharacters(in: .whitespacesAndNewlines)
        let exportDate = Formatters.date.string(from: Date())
        let grandTotalValue = grandTotalValue(for: sheetItems)

        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: max(totalHeight, 100)))
            UIColor.black.setStroke()

            var y: CGFloat = 10
            y = drawImageText("材料单", at: CGPoint(x: 10, y: y), w: totalWidth - 20, f: .boldSystemFont(ofSize: 22), a: .center) + 4
            if !projectTitle.isEmpty {
                y = drawImageText("项目: \(projectTitle)", at: CGPoint(x: 10, y: y), w: totalWidth - 20, f: .systemFont(ofSize: 13), a: .center)
            }
            var infoLine = "导出日期: \(exportDate)"
            if !preparer.isEmpty {
                infoLine += "    编制人: \(preparer)"
            }
            y = drawImageText(infoLine, at: CGPoint(x: 10, y: y), w: totalWidth - 20, f: .systemFont(ofSize: 11), a: .center)
            y = drawImageText("共 \(sheetItems.count) 项    \(AppBrand.displayName)", at: CGPoint(x: 10, y: y), w: totalWidth - 20, f: .systemFont(ofSize: 10), a: .center) + 6
            y = drawImageHeader(columns, x: 10, y: y, h: rowHeight)

            for (index, item) in sheetItems.enumerated() {
                var rowValues = itemRowValues(item, options: options)
                rowValues[0] = "\(index + 1)"
                y = drawImageRow(rowValues, columns, x: 10, y: y, h: rowHeight)
            }

            y += 8
            if grandTotalValue.isPositive {
                y = drawImageText("总计: ¥\(String(format: "%.2f", grandTotalValue.doubleValue))", at: CGPoint(x: 10, y: y), w: totalWidth - 20, f: .boldSystemFont(ofSize: 14))
            }
            y += 8
            _ = drawImageText("—— 本材料单由工地掌柜生成 ——", at: CGPoint(x: 10, y: y), w: totalWidth - 20, f: .systemFont(ofSize: 10), a: .center)
        }
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

    private static func grandTotalValue(for sheetItems: [MaterialSheetItem]) -> MoneyValue {
        totalEstimateValue(for: sheetItems) + totalLaborValue(for: sheetItems)
    }

    private static func lineTotalValue(for item: MaterialSheetItem) -> MoneyValue {
        QuantityValue(text: item.quantity) * MoneyValue(text: item.unitPrice)
    }

    private static func activeColumns(options: MaterialSheetExportOptions) -> [(String, CGFloat)] {
        var columns: [(String, CGFloat)] = [("序号", 30), ("材料名称", 110), ("规格/型号", 64), ("单位", 30), ("数量", 38)]
        if options.showLocation { columns.append(("使用部位", 60)) }
        if options.showPrice {
            columns.append(("单价", 46))
            columns.append(("金额", 52))
        }
        if options.showLabor { columns.append(("人工费", 46)) }
        if options.showSupplier { columns.append(("供应商", 56)) }
        if options.showNote { columns.append(("备注", 60)) }
        let fixedWidth = columns.dropFirst().reduce(0) { $0 + $1.1 }
        let nameWidth = max(70, 595 - 60 - fixedWidth)
        columns[1] = ("材料名称", nameWidth)
        return columns
    }

    private static func itemRowValues(_ item: MaterialSheetItem, options: MaterialSheetExportOptions) -> [String] {
        let quantity = item.quantity
        let unitPrice = item.unitPrice
        let lineTotal = lineTotalValue(for: item)
        var values: [String] = ["", item.name, item.specification, item.unit, quantity]
        if options.showLocation { values.append(item.usageLocation.isEmpty ? "-" : item.usageLocation) }
        if options.showPrice {
            values.append(unitPrice.isEmpty ? "-" : unitPrice)
            values.append(lineTotal.isPositive ? String(format: "%.2f", lineTotal.doubleValue) : "-")
        }
        if options.showLabor { values.append(item.laborCost.isEmpty ? "-" : item.laborCost) }
        if options.showSupplier { values.append(item.supplier.isEmpty ? "-" : item.supplier) }
        if options.showNote { values.append(item.note.isEmpty ? "-" : item.note) }
        return values
    }

    private static func csvHeader(options: MaterialSheetExportOptions) -> String {
        var headers = ["序号", "材料名称", "规格/型号", "单位", "数量"]
        if options.showLocation { headers.append("使用部位") }
        if options.showPrice { headers.append(contentsOf: ["单价", "金额"]) }
        if options.showLabor { headers.append("人工费") }
        if options.showSupplier { headers.append("供应商") }
        if options.showNote { headers.append("备注") }
        return headers.map { "\"\($0)\"" }.joined(separator: ",")
    }

    private static func csvItemRow(_ item: MaterialSheetItem, index: Int, options: MaterialSheetExportOptions) -> String {
        let escaping: (String) -> String = { $0.replacingOccurrences(of: "\"", with: "\"\"") }
        let quantity = item.quantity
        let unitPrice = item.unitPrice
        let lineTotal = lineTotalValue(for: item)
        var values = ["\"\(index + 1)\"", "\"\(escaping(item.name))\"", "\"\(escaping(item.specification))\"", "\"\(escaping(item.unit))\"", "\"\(quantity)\""]
        if options.showLocation { values.append("\"\(escaping(item.usageLocation))\"") }
        if options.showPrice {
            values.append("\"\(unitPrice)\"")
            values.append(lineTotal.isPositive ? "\"\(String(format: "%.2f", lineTotal.doubleValue))\"" : "\"\"")
        }
        if options.showLabor { values.append("\"\(item.laborCost)\"") }
        if options.showSupplier { values.append("\"\(escaping(item.supplier))\"") }
        if options.showNote { values.append("\"\(escaping(item.note))\"") }
        return values.joined(separator: ",")
    }

    private static func drawImageText(_ text: String, at origin: CGPoint, w: CGFloat, f: UIFont, a: NSTextAlignment = .left) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = a
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: f,
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.black
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

    private static func drawImageHeader(_ columns: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        for column in columns {
            let rect = CGRect(x: currentX, y: y, width: column.1, height: h)
            UIBezierPath(rect: rect).stroke()
            NSAttributedString(string: column.0, attributes: attributes)
                .draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: rect.height - 8))
            currentX += column.1
        }
        return y + h
    }

    private static func drawImageRow(_ values: [String], _ columns: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.black
        ]
        for (index, column) in columns.enumerated() {
            let rect = CGRect(x: currentX, y: y, width: column.1, height: h)
            UIBezierPath(rect: rect).stroke()
            let value = values.indices.contains(index) ? values[index] : ""
            NSAttributedString(string: value, attributes: attributes)
                .draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: rect.height - 8))
            currentX += column.1
        }
        return y + h
    }

    private static func drawText(_ text: String, at origin: CGPoint, w: CGFloat, f: UIFont, a: NSTextAlignment = .left) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = a
        paragraph.lineBreakMode = .byWordWrapping
        let attributes = NSAttributedString(
            string: text,
            attributes: [.font: f, .paragraphStyle: paragraph]
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

    private static func drawHeader(_ columns: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        for column in columns {
            let rect = CGRect(x: currentX, y: y, width: column.1, height: h)
            UIBezierPath(rect: rect).stroke()
            NSAttributedString(
                string: column.0,
                attributes: [.font: UIFont.boldSystemFont(ofSize: 9), .foregroundColor: UIColor.black]
            )
            .draw(in: CGRect(x: rect.minX + 3, y: rect.minY + 5, width: rect.width - 6, height: rect.height - 6))
            currentX += column.1
        }
        return y + h
    }

    private static func drawRow(_ values: [String], _ columns: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var currentX = x
        for (index, column) in columns.enumerated() {
            let rect = CGRect(x: currentX, y: y, width: column.1, height: h)
            UIBezierPath(rect: rect).stroke()
            let value = values.indices.contains(index) ? values[index] : ""
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            NSAttributedString(
                string: value,
                attributes: [.font: UIFont.systemFont(ofSize: 9), .paragraphStyle: paragraph, .foregroundColor: UIColor.black]
            )
            .draw(in: CGRect(x: rect.minX + 3, y: rect.minY + 5, width: rect.width - 6, height: rect.height - 6))
            currentX += column.1
        }
        return y + h
    }
}
