import Foundation

struct WatermarkCameraStyle: Codable, Equatable, Sendable {
    enum Position: String, CaseIterable, Codable, Sendable {
        case bottomLeft, bottomRight
        var displayName: String { self == .bottomLeft ? AppLocalization.string("左下角") : AppLocalization.string("右下角") }
    }
    enum Detail: String, CaseIterable, Codable, Sendable {
        case full, compact
        var displayName: String { self == .full ? AppLocalization.string("完整信息") : AppLocalization.string("精简信息") }
    }
    var position: Position = .bottomRight
    var detail: Detail = .full
}

/// Preferences belong to this tool and remain part of its managed reset/backup inventory.
enum WatermarkCameraPreferenceKeys {
    static let projectDetails = "watermarkCamera.projectDetails"
    static let workSection = "watermarkCamera.workSection"
    static let floor = "watermarkCamera.floor"
    static let process = "watermarkCamera.process"
    static let issueNumber = "watermarkCamera.issueNumber"
    static let completedQuantity = "watermarkCamera.completedQuantity"
    static let receiptNote = "watermarkCamera.receiptNote"
    static let stylePosition = "watermarkCamera.stylePosition"
    static let styleDetail = "watermarkCamera.styleDetail"
    static let locationSnapshot = "watermarkCamera.locationSnapshot"
    static let all = [projectDetails, workSection, floor, process, issueNumber, completedQuantity, receiptNote,
                      stylePosition, styleDetail, locationSnapshot]
}
