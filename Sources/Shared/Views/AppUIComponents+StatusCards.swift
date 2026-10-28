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
            .black.opacity(0.025)
        case .card:
            .black.opacity(0.04)
        case .overlay:
            .black.opacity(0.08)
        }
    }

    var radius: CGFloat {
        switch self {
        case .none:
            0
        case .subtle:
            4
        case .card:
            8
        case .overlay:
            14
        }
    }

    var y: CGFloat {
        switch self {
        case .none:
            0
        case .subtle:
            1
        case .card:
            2.5
        case .overlay:
            5
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
            .background(backgroundShape)
            .overlay {
                if let stroke, strokeWidth > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: strokeWidth)
                }
            }
            .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tone.fillStyle)
    }
}

struct AppPanel<Content: View>: View {
    let tone: AppSurfaceTone
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = AppSpacing.normal
    var shadow: AppSurfaceShadow = .card
    var stroke: Color? = Color(uiColor: .separator).opacity(0.18)
    @ViewBuilder let content: Content

    init(
        tone: AppSurfaceTone = .grouped,
        cornerRadius: CGFloat = 16,
        padding: CGFloat = AppSpacing.normal,
        shadow: AppSurfaceShadow = .card,
        stroke: Color? = Color(uiColor: .separator).opacity(0.18),
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
