import SwiftUI
import UIKit
import VisionKit

enum CameraWatermarkTemplate: String, CaseIterable, Codable, Sendable {
    case constructionLog
    case rectification
    case paymentProof
    case receipt

    var displayName: String {
        switch self {
        case .constructionLog: AppLocalization.string("施工日志")
        case .rectification: AppLocalization.string("整改记录")
        case .paymentProof: AppLocalization.string("请款取证")
        case .receipt: AppLocalization.string("票据留存")
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

struct CameraWatermarkContext: Codable, Equatable, Sendable {
    var projectName: String?
    var template: CameraWatermarkTemplate = .constructionLog
    var tag: String = ""
    var photographer: String = ""
    var locationText: String = ""
    var workSection: String = ""
    var floor: String = ""
    var process: String = ""
    var issueNumber: String = ""
    var completedQuantity: String = ""
    var receiptNote: String = ""
    var style: WatermarkCameraStyle = .init()
    var locationSnapshot: WatermarkLocationSnapshot?

    init(
        projectName: String?, template: CameraWatermarkTemplate = .constructionLog,
        tag: String = "", photographer: String = "", locationText: String = "",
        workSection: String = "", floor: String = "", process: String = "",
        issueNumber: String = "", completedQuantity: String = "", receiptNote: String = "",
        style: WatermarkCameraStyle = .init(), locationSnapshot: WatermarkLocationSnapshot? = nil
    ) {
        self.projectName = projectName
        self.template = template
        self.tag = tag
        self.photographer = photographer
        self.locationText = locationText
        self.workSection = workSection
        self.floor = floor
        self.process = process
        self.issueNumber = issueNumber
        self.completedQuantity = completedQuantity
        self.receiptNote = receiptNote
        self.style = style
        self.locationSnapshot = locationSnapshot
    }

    private enum CodingKeys: String, CodingKey {
        case projectName, template, tag, photographer, locationText, workSection, floor, process
        case issueNumber, completedQuantity, receiptNote, style, locationSnapshot
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try values.decodeIfPresent(String.self, forKey: .projectName)
        template = try values.decodeIfPresent(CameraWatermarkTemplate.self, forKey: .template) ?? .constructionLog
        tag = try values.decodeIfPresent(String.self, forKey: .tag) ?? ""
        photographer = try values.decodeIfPresent(String.self, forKey: .photographer) ?? ""
        locationText = try values.decodeIfPresent(String.self, forKey: .locationText) ?? ""
        workSection = try values.decodeIfPresent(String.self, forKey: .workSection) ?? ""
        floor = try values.decodeIfPresent(String.self, forKey: .floor) ?? ""
        process = try values.decodeIfPresent(String.self, forKey: .process) ?? ""
        issueNumber = try values.decodeIfPresent(String.self, forKey: .issueNumber) ?? ""
        completedQuantity = try values.decodeIfPresent(String.self, forKey: .completedQuantity) ?? ""
        receiptNote = try values.decodeIfPresent(String.self, forKey: .receiptNote) ?? ""
        style = try values.decodeIfPresent(WatermarkCameraStyle.self, forKey: .style) ?? .init()
        locationSnapshot = try values.decodeIfPresent(WatermarkLocationSnapshot.self, forKey: .locationSnapshot)
    }

    func lines(capturedAt: Date) -> [String] {
        func cleaned(_ value: String) -> String {
            value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        func field(_ title: String, _ value: String) -> String {
            let value = cleaned(value)
            return String(format: AppLocalization.string("%@: %@"), title, value.isEmpty ? AppLocalization.string("未填写") : value)
        }
        let project = cleaned(projectName ?? "")
        var result = [String(format: AppLocalization.string("工程: %@"), project.isEmpty ? AppLocalization.string("未指定项目") : project),
                      String(format: AppLocalization.string("时间: %@"), Formatters.dateTime.string(from: capturedAt))]
        if style.detail == .full { result.append(String(format: AppLocalization.string("模板: %@"), template.displayName)) }
        if style.detail == .full {
            result.append(field(AppLocalization.string("施工段"), workSection))
            if template != .receipt { result.append(field(AppLocalization.string("楼层/部位"), floor)) }
        }
        switch template {
        case .constructionLog:
            result.append(field(AppLocalization.string("施工工序"), process))
        case .rectification:
            result.append(field(AppLocalization.string("问题编号"), issueNumber))
            if style.detail == .full { result.append(field(AppLocalization.string("整改工序"), process)) }
        case .paymentProof:
            result.append(field(AppLocalization.string("完成工程量"), completedQuantity))
            if style.detail == .full { result.append(field(AppLocalization.string("施工工序"), process)) }
        case .receipt:
            result.append(field(AppLocalization.string("票据说明"), receiptNote))
        }
        if style.detail == .full {
            for (title, value) in [(AppLocalization.string("标签"), tag), (AppLocalization.string("拍摄"), photographer), (AppLocalization.string("位置"), locationText)] {
                if !cleaned(value).isEmpty { result.append(field(title, value)) }
            }
            if let snapshot = locationSnapshot, snapshot.provenance == .device,
               snapshot.text == locationText {
                let provenance: String
                switch snapshot.freshness(at: capturedAt) {
                case .fresh: provenance = AppLocalization.string("设备定位")
                case .stale: provenance = AppLocalization.string("历史定位")
                case .invalid: provenance = AppLocalization.string("无效定位，请核对")
                case .manual: provenance = AppLocalization.string("手动填写")
                }
                let fixTime = snapshot.timestamp.map { Formatters.dateTime.string(from: $0) } ?? AppLocalization.string("未知时间")
                result.append(String(format: AppLocalization.string("定位: %@ · %@"), provenance, fixTime))
            }
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
            onError(String(format: AppLocalization.string("扫描失败：%@"), error.localizedDescription))
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
        let watermarkContext = context ?? CameraWatermarkContext(projectName: nil)
        let baseRect = CGRect(origin: .zero, size: size)
        guard size.width > 0, size.height > 0 else { return self }
        let layout = WatermarkCameraLayout.make(context: watermarkContext, capturedAt: capturedAt, canvasSize: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: baseRect)
            layout.draw()
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
