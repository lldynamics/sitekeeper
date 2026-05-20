import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    var currentTextSchemeTitle: String {
        "\(selectedTextEncoding.displayName) / \(selectedTextBigFont.displayName)"
    }

    var standardTopBar: some View {
        VStack(spacing: 8) {
            cadCommandHeader(chrome: .standard)

            if isCADFile, let hint = engineStatusHint {
                Label(
                    hint,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.appWarning)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if canUseCADTextRepair {
                HStack(spacing: 6) {
                    Image(systemName: "character.textbox")
                        .foregroundStyle(.secondary)
                    Text("\(String(localized: "当前文字方案"))：\(currentTextSchemeTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let autoDetectScore = textSchemeSnapshot.autoDetectScore {
                        Text("\(String(localized: "识别评分"))：\(autoDetectScore)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            if allowsOverlayEditing {
                cadPrimaryCommandBar(chrome: .standard)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    func overlayStrokeWidth(for tool: CADOverlayTool) -> Double {
        switch tool {
        case .annotation:
            return 4
        case .cloud:
            return 3.4
        case .arrow:
            return 2.4
        default:
            return 3
        }
    }

    func pathView(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    func closedPath(points: [CGPoint]) -> Path {
        var path = pathView(points: points)
        if points.count >= 3 {
            path.closeSubpath()
        }
        return path
    }

    func measurementPolyline(_ points: [CGPoint]) -> Path {
        pathView(points: points)
    }

    func arrowShape(start: CGPoint, end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 14
        let wing: CGFloat = .pi * 0.78
        let p1 = CGPoint(x: end.x + cos(angle + wing) * length, y: end.y + sin(angle + wing) * length)
        let p2 = CGPoint(x: end.x + cos(angle - wing) * length, y: end.y + sin(angle - wing) * length)
        path.move(to: p1)
        path.addLine(to: end)
        path.addLine(to: p2)
        return path
    }

    func measurementBadge(text: String, isHighlighted: Bool = false) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isHighlighted ? Color.appWarning.opacity(0.2) : Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(isHighlighted ? Color.appWarning : Color.appStrokeSecondary, lineWidth: isHighlighted ? 1.4 : 0.8)
            )
    }

    func countMarkerBadge(number: Int, category: String, isHighlighted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isHighlighted ? Color.appWarning : Color.appPrimaryAction, in: Capsule())
            Text(category)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isHighlighted ? Color.appWarning : .primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            isHighlighted ? Color.appWarning.opacity(0.17) : Color(uiColor: .secondarySystemGroupedBackground),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(isHighlighted ? Color.appWarning : Color.appStrokeSecondary, lineWidth: isHighlighted ? 1.4 : 0.8)
        )
    }

    func issueMarkerBadge(_ marker: CADFallbackIssueMarker) -> some View {
        HStack(spacing: 6) {
            Image(systemName: marker.photoFileName == nil ? "mappin.circle.fill" : "camera.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(colorFromHex(issueMarkerColorHex(marker), fallback: Color.appRisk), in: Circle())
            Text(marker.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .overlay(
            Capsule().stroke(colorFromHex(issueMarkerColorHex(marker), fallback: Color.appRisk), lineWidth: 1)
        )
    }

    func centerPoint(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { result, point in
            CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    var annotationStrokeCount: Int {
        snapshot.strokes.count + snapshot.arrowAnnotations.count
    }
}
