import SwiftUI
import UIKit
import VisionKit

enum CameraWatermarkTemplate: String, CaseIterable {
    case constructionLog
    case rectification
    case paymentProof
    case receipt

    var displayName: String {
        switch self {
        case .constructionLog: "施工日志"
        case .rectification: "整改记录"
        case .paymentProof: "请款取证"
        case .receipt: "票据留存"
        }
    }

    var icon: String {
        switch self {
        case .constructionLog: "book.pages.fill"
        case .rectification: "wrench.adjustable.fill"
        case .paymentProof: "doc.text.magnifyingglass"
        case .receipt: "receipt.fill"
        }
    }
}

struct CameraWatermarkContext {
    var projectName: String?
    var template: CameraWatermarkTemplate = .constructionLog
    var tag: String = ""
    var photographer: String = ""
    var locationText: String = ""

    func lines(capturedAt: Date) -> [String] {
        let normalizedProject = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var result = [
            "工程: \(normalizedProject.isEmpty ? "未指定项目" : normalizedProject)",
            "时间: \(Formatters.dateTime.string(from: capturedAt))"
        ]
        result.append("模板: \(template.displayName)")
        if !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append("标签: \(tag)")
        }
        if !photographer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append("拍摄: \(photographer)")
        }
        if !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append("位置: \(locationText)")
        }
        return result
    }
}

struct ProjectScanTarget: Identifiable {
    let id = UUID()
    var title: String
    var category: ProjectDocumentCategory
    var amount: MoneyValue
    var linkedFinancialRecordId: UUID?
    var linkedConstructionMethodIDs: [UUID] = []
    var submissionStatus: ProjectDocumentSubmissionStatus = .notSubmitted
    var responsiblePerson: String = ""
    var formedAt: BusinessDateValue = .empty
    var archiveNumber: String = ""
    var workSection: String = ""
    var note: String
}

struct DocumentScannerView: UIViewControllerRepresentable {
    let onSave: (Data, Int) -> Void
    var onError: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave, onError: onError)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onSave: (Data, Int) -> Void
        let onError: (String) -> Void

        init(onSave: @escaping (Data, Int) -> Void, onError: @escaping (String) -> Void) {
            self.onSave = onSave
            self.onError = onError
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let data = makePDF(from: scan)
            onSave(data, scan.pageCount)
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onError("扫描失败：\(error.localizedDescription)")
            controller.dismiss(animated: true)
        }

        private func makePDF(from scan: VNDocumentCameraScan) -> Data {
            let firstImage = scan.pageCount > 0 ? scan.imageOfPage(at: 0).resizedForDocument(longEdge: 1800) : UIImage()
            let pageSize = firstImage.size == .zero ? CGSize(width: 595, height: 842) : firstImage.size
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
            return renderer.pdfData { context in
                for index in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: index).resizedForDocument(longEdge: 1800)
                    let compressed = UIImage(data: image.jpegData(compressionQuality: 0.7) ?? Data()) ?? image
                    context.beginPage()
                    compressed.draw(in: CGRect(origin: .zero, size: pageSize))
                }
            }
        }
    }
}

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let watermarkContext: CameraWatermarkContext?
    let onPickedWithTimestamp: ((UIImage, Date) -> Void)?
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        sourceType: UIImagePickerController.SourceType,
        watermarkContext: CameraWatermarkContext? = nil,
        onPickedWithTimestamp: ((UIImage, Date) -> Void)? = nil,
        onPicked: @escaping (UIImage) -> Void
    ) {
        self.sourceType = sourceType
        self.watermarkContext = watermarkContext
        self.onPickedWithTimestamp = onPickedWithTimestamp
        self.onPicked = onPicked
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sourceType: sourceType,
            watermarkContext: watermarkContext,
            onPickedWithTimestamp: onPickedWithTimestamp,
            onPicked: onPicked,
            dismiss: dismiss
        )
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let sourceType: UIImagePickerController.SourceType
        let watermarkContext: CameraWatermarkContext?
        let onPickedWithTimestamp: ((UIImage, Date) -> Void)?
        let onPicked: (UIImage) -> Void
        let dismiss: DismissAction

        init(
            sourceType: UIImagePickerController.SourceType,
            watermarkContext: CameraWatermarkContext?,
            onPickedWithTimestamp: ((UIImage, Date) -> Void)?,
            onPicked: @escaping (UIImage) -> Void,
            dismiss: DismissAction
        ) {
            self.sourceType = sourceType
            self.watermarkContext = watermarkContext
            self.onPickedWithTimestamp = onPickedWithTimestamp
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                let outputImage: UIImage
                if sourceType == .camera {
                    let capturedAt = Date()
                    outputImage = watermarkContext.map {
                        image.applyingCameraWatermark(context: $0, capturedAt: capturedAt)
                    } ?? image
                    if let onPickedWithTimestamp {
                        onPickedWithTimestamp(outputImage, capturedAt)
                    } else {
                        onPicked(outputImage)
                    }
                } else {
                    outputImage = image
                    onPicked(outputImage)
                }
            }
            dismiss()
        }
    }
}

extension UIImage {
    func applyingCameraWatermark(context: CameraWatermarkContext?, capturedAt: Date) -> UIImage {
        let lines = (context ?? CameraWatermarkContext(projectName: nil)).lines(capturedAt: capturedAt)

        let baseRect = CGRect(origin: .zero, size: size)
        let minEdge = min(size.width, size.height)
        let fontSize = max(16, minEdge * 0.038)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]
        let horizontalPadding = max(12, minEdge * 0.026)
        let verticalPadding = max(10, minEdge * 0.022)
        let margin = max(12, minEdge * 0.028)
        let maxTextWidth = max(160, size.width - margin * 2 - horizontalPadding * 2)
        let lineSizes = lines.map {
            ($0 as NSString)
                .boundingRect(
                    with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                .size
        }
        let maxLineWidth = lineSizes.map(\.width).max() ?? 0
        let totalTextHeight = lineSizes.reduce(0) { $0 + ceil($1.height) } + CGFloat(max(0, lines.count - 1)) * (fontSize * 0.24)
        let watermarkWidth = min(maxLineWidth + horizontalPadding * 2, size.width - margin * 2)
        let watermarkHeight = totalTextHeight + verticalPadding * 2
        let watermarkRect = CGRect(
            x: baseRect.maxX - watermarkWidth - margin,
            y: baseRect.maxY - watermarkHeight - margin,
            width: watermarkWidth,
            height: watermarkHeight
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: baseRect)
            let path = UIBezierPath(roundedRect: watermarkRect, cornerRadius: max(8, minEdge * 0.015))
            UIColor.black.withAlphaComponent(0.58).setFill()
            path.fill()

            var cursorY = watermarkRect.minY + verticalPadding
            for (index, line) in lines.enumerated() {
                let lineSize = lineSizes[index]
                let textRect = CGRect(
                    x: watermarkRect.minX + horizontalPadding,
                    y: cursorY,
                    width: watermarkRect.width - horizontalPadding * 2,
                    height: ceil(lineSize.height)
                )
                (line as NSString).draw(in: textRect, withAttributes: attributes)
                cursorY += ceil(lineSize.height) + fontSize * 0.24
            }
        }
    }

    func resizedForDocument(longEdge: CGFloat) -> UIImage {
        let currentLongEdge = max(size.width, size.height)
        guard currentLongEdge > longEdge, currentLongEdge > 0 else { return self }
        let ratio = longEdge / currentLongEdge
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
