import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

struct ReceiptOCRAmountCandidate: Identifiable, Equatable {
    var amount: String
    var confidence: Double
    var sourceLine: String

    var id: String {
        "\(amount)|\(sourceLine)"
    }

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }
}

struct ReceiptOCRResult {
    var amount: String?
    var amountCandidates: [ReceiptOCRAmountCandidate]
    var date: String?
    var counterparty: String?
    var invoiceNumber: String?
    var recognizedText: String

    var hasStructuredValue: Bool {
        !amountCandidates.isEmpty ||
        amount?.isEmpty == false ||
        date?.isEmpty == false ||
        counterparty?.isEmpty == false ||
        invoiceNumber?.isEmpty == false
    }
}

enum ReceiptOCRServiceError: LocalizedError {
    case unsupportedFile
    case recognizeFailed
    case noStructuredResult

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return String(localized: "仅支持图片或 PDF 票据识别。")
        case .recognizeFailed:
            return String(localized: "未能识别票据文字，请换一张更清晰的图片。")
        case .noStructuredResult:
            return String(localized: "已识别到文字，但未提取到金额/日期/单位等关键字段。")
        }
    }
}

enum ReceiptOCRService {
    static func recognize(from url: URL) async throws -> ReceiptOCRResult {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let recognizedText = try await FileIOTaskRunner.run(
            priority: .userInitiated,
            logContext: .init(
                event: "receipt_ocr.recognize",
                source: "ReceiptOCRService.recognize",
                category: .fileStorage,
                details: ["file_name": url.lastPathComponent]
            )
        ) {
            try recognizeTextSynchronously(from: url)
        }
        let result = parseStructuredResult(from: recognizedText)
        guard result.hasStructuredValue else {
            throw ReceiptOCRServiceError.noStructuredResult
        }
        return result
    }

    private static func recognizeTextSynchronously(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            let text = try recognizeFromPDF(url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReceiptOCRServiceError.recognizeFailed
            }
            return text
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            let text = try recognizeFromImageURL(url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReceiptOCRServiceError.recognizeFailed
            }
            return text
        }
        throw ReceiptOCRServiceError.unsupportedFile
    }

    private static func recognizeFromImageURL(_ url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func recognizeFromPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ReceiptOCRServiceError.recognizeFailed
        }
        let pagesToScan = min(document.pageCount, 2)
        var collectedLines: [String] = []
        for index in 0..<pagesToScan {
            guard let page = document.page(at: index),
                  let image = renderedImage(for: page),
                  let cgImage = image.cgImage else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            collectedLines.append(contentsOf: lines)
        }
        return collectedLines.joined(separator: "\n")
    }

    private static func renderedImage(for page: PDFPage) -> UIImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }
        let maxSide: CGFloat = 2_000
        let scale = min(maxSide / max(pageBounds.width, pageBounds.height), 1)
        let size = CGSize(width: max(pageBounds.width * scale, 1), height: max(pageBounds.height * scale, 1))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private static func parseStructuredResult(from text: String) -> ReceiptOCRResult {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { normalizeLine(String($0)) }
            .filter { !$0.isEmpty }
        let amountCandidates = parseAmountCandidates(from: lines)
        return ReceiptOCRResult(
            amount: amountCandidates.first?.amount,
            amountCandidates: amountCandidates,
            date: parseDate(from: lines),
            counterparty: parseCounterparty(from: lines),
            invoiceNumber: parseInvoiceNumber(from: lines),
            recognizedText: lines.joined(separator: "\n")
        )
    }

    private static func normalizeLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseAmountCandidates(from lines: [String]) -> [ReceiptOCRAmountCandidate] {
        let keywordWeights: [(String, Double)] = [
            ("价税合计", 0.72),
            ("收款金额", 0.70),
            ("付款金额", 0.70),
            ("合计", 0.66),
            ("含税金额", 0.64),
            ("实收", 0.60),
            ("实付", 0.60),
            ("金额", 0.58),
            ("应收", 0.56),
            ("应付", 0.56),
            ("小写", 0.55)
        ]
        var bestByAmount: [String: (amount: Decimal, score: Double, sourceLine: String)] = [:]

        for line in lines where !line.contains("年") {
            let numbers = numberCandidates(in: line)
                .filter { $0 > 0 && $0 < 100_000_000 }
            guard !numbers.isEmpty else { continue }

            var baseScore = 0.18
            for (keyword, weight) in keywordWeights where line.contains(keyword) {
                baseScore = max(baseScore, weight)
            }
            if line.contains("￥") || line.contains("¥") || line.contains("元") {
                baseScore += 0.08
            }
            if line.contains("%") || line.contains("税率") {
                baseScore -= 0.12
            }
            if line.contains("数量") || line.contains("单价") {
                baseScore -= 0.08
            }

            for amount in numbers {
                let score = clamped(baseScore + magnitudeConfidence(for: amount), minValue: 0.05, maxValue: 0.99)
                let amountText = moneyText(from: amount)
                if let existing = bestByAmount[amountText], existing.score >= score {
                    continue
                }
                bestByAmount[amountText] = (amount, score, line)
            }
        }

        return bestByAmount
            .values
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.amount > rhs.amount
                }
                return lhs.score > rhs.score
            }
            .prefix(5)
            .map { value in
                ReceiptOCRAmountCandidate(
                    amount: moneyText(from: value.amount),
                    confidence: value.score,
                    sourceLine: value.sourceLine
                )
            }
    }

    private static func magnitudeConfidence(for amount: Decimal) -> Double {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        switch value {
        case ..<1:
            return 0.12
        case ..<10:
            return 0.20
        case ..<100:
            return 0.28
        case ..<1_000:
            return 0.34
        case ..<10_000:
            return 0.40
        case ..<1_000_000:
            return 0.36
        default:
            return 0.26
        }
    }

    private static func clamped(_ value: Double, minValue: Double, maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }

    private static func parseDate(from lines: [String]) -> String? {
        let dateKeywords = ["开票日期", "日期", "交易日期", "记账日期", "发生日期"]
        for line in lines where dateKeywords.contains(where: { line.contains($0) }) {
            if let date = extractDate(from: line) {
                return date
            }
        }
        for line in lines {
            if let date = extractDate(from: line) {
                return date
            }
        }
        return nil
    }

    private static func parseCounterparty(from lines: [String]) -> String? {
        let regex = try? NSRegularExpression(
            pattern: "(销售方名称|购买方名称|销方名称|购方名称|收款方|付款方|单位名称|公司名称|对方单位|名称)\\s*[:：]\\s*(.+)$",
            options: [.caseInsensitive]
        )
        for line in lines {
            guard let regex,
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 3,
                  let valueRange = Range(match.range(at: 2), in: line) else { continue }
            let value = line[valueRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "（", with: "")
                .replacingOccurrences(of: "）", with: "")
            if isValidCounterparty(String(value)) {
                return String(value)
            }
        }

        for line in lines.prefix(12) where line.contains("公司") || line.contains("有限") {
            if isValidCounterparty(line) {
                return line
            }
        }
        return nil
    }

    private static func parseInvoiceNumber(from lines: [String]) -> String? {
        let patterns = [
            "(发票号码|票据号码|单据编号|票号|No\\.?|NO\\.?)[：:\\s]*([A-Za-z0-9\\-]{6,24})",
            "(发票代码)[：:\\s]*([A-Za-z0-9\\-]{6,24})"
        ]
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for line in lines {
                guard let regex,
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      match.numberOfRanges >= 3,
                      let valueRange = Range(match.range(at: 2), in: line) else { continue }
                let value = line[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 6 {
                    return value
                }
            }
        }
        return nil
    }

    private static func numberCandidates(in line: String) -> [Decimal] {
        let pattern = "([0-9]{1,3}(?:[,，][0-9]{3})*(?:\\.[0-9]{1,2})|[0-9]+(?:\\.[0-9]{1,2})?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: line) else { return nil }
            let cleaned = line[valueRange]
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "，", with: "")
            return Decimal(string: cleaned)
        }
    }

    private static func moneyText(from decimal: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(decimal)"
    }

    private static func extractDate(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "(20\\d{2})\\s*[年\\-\\./]\\s*(\\d{1,2})\\s*[月\\-\\./]\\s*(\\d{1,2})\\s*日?",
            options: []
        ) else {
            return nil
        }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 4,
              let yearRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let dayRange = Range(match.range(at: 3), in: text),
              let year = Int(text[yearRange]),
              let month = Int(text[monthRange]),
              let day = Int(text[dayRange]) else {
            return nil
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func isValidCounterparty(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 40 else { return false }
        let blockers = ["税号", "地址", "电话", "开户行", "账号", "机器编号", "校验码"]
        guard blockers.allSatisfy({ !trimmed.contains($0) }) else { return false }
        return true
    }
}
