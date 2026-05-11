import Foundation
import UIKit
import CoreGraphics

enum ProjectDetailFinanceDocumentHelper {
    static func makeCompressedPDF(from image: UIImage) -> Data {
        let maxEdge: CGFloat = 1600
        let resized = resize(image, longEdge: maxEdge)
        let jpeg = resized.jpegData(compressionQuality: 0.72) ?? Data()
        let finalImage = UIImage(data: jpeg) ?? resized
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: finalImage.size))
        return renderer.pdfData { context in
            context.beginPage()
            finalImage.draw(in: CGRect(origin: .zero, size: finalImage.size))
        }
    }

    static func compressedJPEGData(from image: UIImage) -> Data? {
        let resized = resize(image, longEdge: 1800)
        return resized.jpegData(compressionQuality: 0.78)
    }

    static func pdfPageCount(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider) else { return 1 }
        return max(doc.numberOfPages, 1)
    }

    static func pdfPageCount(at url: URL) -> Int {
        guard let doc = CGPDFDocument(url as CFURL) else { return 1 }
        return max(doc.numberOfPages, 1)
    }

    static func documentCategory(for financialCategory: ProjectFinancialCategory) -> ProjectDocumentCategory {
        switch financialCategory {
        case .paymentRequest:
            return .paymentRequest
        case .collection, .invoice:
            return .invoice
        case .refund, .receipt, .reimbursement:
            return .receipt
        case .material, .labor, .other:
            return .other
        }
    }

    static func documentCategory(for financialCategory: String) -> ProjectDocumentCategory {
        documentCategory(for: StringEnumFallback.value(financialCategory, default: ProjectFinancialCategory.receipt))
    }

    static func documentIcon(_ category: ProjectDocumentCategory) -> String {
        switch category {
        case .paymentRequest:
            return "doc.text.fill"
        case .construction:
            return "hammer.fill"
        case .invoice:
            return "doc.richtext.fill"
        case .receipt:
            return "receipt.fill"
        case .contract:
            return "signature"
        case .acceptance:
            return "checkmark.seal.fill"
        case .other:
            return "folder.fill"
        }
    }

    static func documentIcon(_ category: String) -> String {
        documentIcon(StringEnumFallback.value(category, default: ProjectDocumentCategory.other))
    }

    private static func resize(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let currentLongEdge = max(image.size.width, image.size.height)
        guard currentLongEdge > longEdge, currentLongEdge > 0 else { return image }
        let ratio = longEdge / currentLongEdge
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
