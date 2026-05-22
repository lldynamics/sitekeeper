import SwiftUI
import UIKit

struct WatermarkCapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let capturedAt: Date
}

enum WatermarkExportQuality: String, CaseIterable {
    case standard
    case high

    var displayName: String {
        switch self {
        case .standard:
            return String(localized: "wm_camera_export_quality_standard")
        case .high:
            return String(localized: "wm_camera_export_quality_high")
        }
    }

    var compression: CGFloat {
        switch self {
        case .standard:
            return 0.88
        case .high:
            return 0.96
        }
    }
}

enum WatermarkToastStyle {
    case success
    case error

    var tint: Color {
        switch self {
        case .success:
            return .appSuccess
        case .error:
            return .appRisk
        }
    }

    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct WatermarkToast: Identifiable {
    let id = UUID()
    let message: String
    let style: WatermarkToastStyle
}

struct WatermarkToastView: View {
    let toast: WatermarkToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.style.icon)
                .font(.callout.weight(.semibold))
            Text(toast.message)
                .font(.callout)
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(toast.style.tint.opacity(0.92))
        )
    }
}
