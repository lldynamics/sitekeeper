import SwiftUI

enum AppSurfaceTone {
    case grouped
    case secondary
    case tertiary
    case materialThin
    case materialThick
    case tinted(Color)

    var fillStyle: AnyShapeStyle {
        switch self {
        case .grouped:
            AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
        case .secondary:
            AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        case .tertiary:
            AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground))
        case .materialThin:
            AnyShapeStyle(.ultraThinMaterial)
        case .materialThick:
            AnyShapeStyle(.ultraThickMaterial)
        case .tinted(let color):
            AnyShapeStyle(color)
        }
    }
}

enum AppSurfaceShadow {
    case none
    case subtle
    case card
    case overlay

    var color: Color {
        switch self {
        case .none:
            .clear
        case .subtle:
            Color(light: UIColor(white: 0, alpha: 0.02), dark: UIColor.clear)
        case .card:
            Color(light: UIColor(white: 0, alpha: 0.035), dark: UIColor.clear)
        case .overlay:
            Color(light: UIColor(white: 0, alpha: 0.06), dark: UIColor.clear)
        }
    }

    var radius: CGFloat {
        switch self {
        case .none:
            0
        case .subtle:
            4
        case .card:
            10
        case .overlay:
            16
        }
    }

    var y: CGFloat {
        switch self {
        case .none:
            0
        case .subtle:
            1
        case .card:
            3
        case .overlay:
            6
        }
    }
}

struct AppSurface<Content: View>: View {
    let tone: AppSurfaceTone
    var cornerRadius: CGFloat = 16
    var shadow: AppSurfaceShadow = .none
    var stroke: Color? = nil
    var strokeWidth: CGFloat = 0.5
    @ViewBuilder let content: Content

    init(
        tone: AppSurfaceTone = .grouped,
        cornerRadius: CGFloat = 16,
        shadow: AppSurfaceShadow = .none,
        stroke: Color? = nil,
        strokeWidth: CGFloat = 0.5,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.content = content()
    }

    var body: some View {
        content
            .background {
                backgroundShape
                    .shadow(
                        color: shadow.color,
                        radius: shadow.radius,
                        y: shadow.y
                    )
            }
            .overlay {
                if let stroke, strokeWidth > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: strokeWidth)
                }
            }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tone.fillStyle)
    }
}

enum AppSurfaceDefaults {
    static var stroke: Color {
        Color(light: UIColor(white: 0, alpha: 0.04), dark: UIColor(white: 1, alpha: 0.08))
    }
}

struct AppPanel<Content: View>: View {
    let tone: AppSurfaceTone
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = AppSpacing.normal
    var shadow: AppSurfaceShadow = .card
    var stroke: Color? = AppSurfaceDefaults.stroke
    @ViewBuilder let content: Content

    init(
        tone: AppSurfaceTone = .grouped,
        cornerRadius: CGFloat = 16,
        padding: CGFloat = AppSpacing.normal,
        shadow: AppSurfaceShadow = .card,
        stroke: Color? = AppSurfaceDefaults.stroke,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.shadow = shadow
        self.stroke = stroke
        self.content = content()
    }

    var body: some View {
        AppSurface(
            tone: tone,
            cornerRadius: cornerRadius,
            shadow: shadow,
            stroke: stroke
        ) {
            content
                .padding(padding)
        }
    }
}
