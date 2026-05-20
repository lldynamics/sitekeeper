import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CADOverlayEditorContext {
    let visibleStrokes: [CADStroke]
    let selectedStrokeID: UUID?
    let visibleArrows: [CADArrowAnnotation]
    let visibleLengthMeasurements: [CADLengthMeasurement]
    let highlightedLengthMeasurementID: UUID?
    let visibleAreaMeasurements: [CADAreaMeasurement]
    let highlightedAreaMeasurementID: UUID?
    let visibleNotes: [CADTextNote]
    let countMarkers: [CADCountMarker]
    let highlightedCountMarkerIDs: Set<UUID>
    let highlightedCountCategory: String?
    let visibleIssueMarkers: [CADFallbackIssueMarker]
    let quantityHighlightCanvasRect: CGRect?
    let activeStrokePoints: [CGPoint]
    let activeDragLengthPoints: [CGPoint]
    let activeDragArrowPoints: [CGPoint]
    let pendingLengthPoints: [CGPoint]
    let pendingAreaPoints: [CGPoint]
    let currentTool: CADOverlayTool
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let isOverlayGroupVisible: (CADOverlayVisibilityGroup) -> Bool
    let canvasPoint: (CGPoint) -> CGPoint
    let canvasPoints: ([CGPoint]) -> [CGPoint]
    let pathView: ([CGPoint]) -> Path
    let closedPath: ([CGPoint]) -> Path
    let measurementPolyline: ([CGPoint]) -> Path
    let arrowShape: (CGPoint, CGPoint) -> Path
    let overlayStrokeWidth: (CADOverlayTool) -> Double
    let strokeColor: (CADStroke) -> Color
    let colorFromHex: (String?, Color) -> Color
    let lengthMeasurementColorHex: (CADLengthMeasurement) -> String
    let areaMeasurementColorHex: (CADAreaMeasurement) -> String
    let noteColorHex: (CADTextNote) -> String
    let issueMarkerColorHex: (CADFallbackIssueMarker) -> String
    let centerPoint: ([CGPoint]) -> CGPoint?
    let measurementBadge: (String, Bool) -> AnyView
    let countMarkerBadge: (Int, String, Bool) -> AnyView
    let issueMarkerBadge: (CADFallbackIssueMarker) -> AnyView
    let lengthLabel: ([CGPoint]) -> String
    let areaLabel: ([CGPoint]) -> String
    let annotationDraftColor: Color
    let arrowDraftColor: Color
    let lengthDraftColor: Color
    let areaDraftColor: Color
}

struct CADOverlayEditor: View {
    let size: CGSize
    let context: CADOverlayEditorContext

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.001))

            ForEach(context.visibleStrokes) { stroke in
                let isSelected = context.selectedStrokeID == stroke.id
                let renderedPoints = context.canvasPoints(stroke.points.map(\.cgPoint))
                let renderedPath = context.pathView(renderedPoints)
                let color = context.strokeColor(stroke)
                renderedPath
                    .stroke(
                        isSelected ? Color.appWarning.opacity(0.42) : color,
                        style: StrokeStyle(
                            lineWidth: isSelected ? stroke.lineWidth + 7 : stroke.lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: stroke.kind == .cloud ? [8, 5] : []
                        )
                    )
                renderedPath
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: isSelected ? stroke.lineWidth + 1.4 : stroke.lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: stroke.kind == .cloud ? [8, 5] : []
                        )
                    )
                    .shadow(color: color.opacity(isSelected ? 0.32 : 0.18), radius: isSelected ? 5 : 1.5)
            }

            ForEach(context.visibleArrows) { arrow in
                context.arrowShape(
                    context.canvasPoint(arrow.start.cgPoint),
                    context.canvasPoint(arrow.end.cgPoint)
                )
                .stroke(
                    context.colorFromHex(arrow.colorHex, Color.appPrimaryAction),
                    style: StrokeStyle(lineWidth: arrow.lineWidth, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: context.colorFromHex(arrow.colorHex, Color.appPrimaryAction).opacity(0.16), radius: 2)
            }

            if context.isOverlayGroupVisible(.measurement) {
                ForEach(context.visibleLengthMeasurements) { measurement in
                    let isHighlighted = context.highlightedLengthMeasurementID == measurement.id
                    let storedPoints = measurement.points.map(\.cgPoint)
                    let renderedPoints = context.canvasPoints(storedPoints)
                    let color = context.colorFromHex(
                        context.lengthMeasurementColorHex(measurement),
                        Color.appStrokeInfo
                    )
                    context.measurementPolyline(renderedPoints)
                        .stroke(
                            isHighlighted ? Color.appWarning : color,
                            style: StrokeStyle(
                                lineWidth: isHighlighted ? 3.6 : 2,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: measurement.points.count > 2 ? [4, 2] : []
                            )
                        )
                    if let center = context.centerPoint(renderedPoints) {
                        context.measurementBadge(context.lengthLabel(storedPoints), isHighlighted)
                            .position(center)
                    }
                }
            }

            if context.isOverlayGroupVisible(.measurement) {
                ForEach(context.visibleAreaMeasurements) { area in
                    let isHighlighted = context.highlightedAreaMeasurementID == area.id
                    let storedPoints = area.points.map(\.cgPoint)
                    let renderedPoints = context.canvasPoints(storedPoints)
                    let color = context.colorFromHex(
                        context.areaMeasurementColorHex(area),
                        Color.appStrokeSuccess
                    )
                    if renderedPoints.count >= 3 {
                        let renderedPath = context.closedPath(renderedPoints)
                        renderedPath
                            .fill(isHighlighted ? Color.appWarning.opacity(0.22) : color.opacity(0.14))

                        renderedPath
                            .stroke(
                                isHighlighted ? Color.appWarning : color,
                                style: StrokeStyle(lineWidth: isHighlighted ? 3 : 2, lineJoin: .round, dash: [5, 3])
                            )

                        if let center = context.centerPoint(renderedPoints) {
                            context.measurementBadge(context.areaLabel(storedPoints), isHighlighted)
                                .position(center)
                        }
                    }
                }
            }

            if context.isOverlayGroupVisible(.notes) {
                ForEach(context.visibleNotes) { note in
                    let color = context.colorFromHex(context.noteColorHex(note), Color.appStrokeWarning)
                    noteBadge(note: note, color: color)
                        .position(context.canvasPoint(note.point.cgPoint))
                }
            }

            if context.isOverlayGroupVisible(.counts) {
                let highlightedIDs = context.highlightedCountMarkerIDs
                let highlightedCategory = context.highlightedCountCategory
                ForEach(Array(context.countMarkers.enumerated()), id: \.element.id) { index, marker in
                    context.countMarkerBadge(
                        index + 1,
                        marker.category,
                        highlightedIDs.contains(marker.id) || highlightedCategory == marker.category
                    )
                    .position(context.canvasPoint(marker.point.cgPoint))
                }
            }

            if context.isOverlayGroupVisible(.issues) {
                ForEach(context.visibleIssueMarkers) { marker in
                    context.issueMarkerBadge(marker)
                        .position(context.canvasPoint(marker.point.cgPoint))
                }
            }

            if let highlightRect = context.quantityHighlightCanvasRect {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.appWarning, style: StrokeStyle(lineWidth: 2.4, dash: [8, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.appWarning.opacity(0.08))
                    )
                    .frame(width: highlightRect.width, height: highlightRect.height)
                    .position(x: highlightRect.midX, y: highlightRect.midY)
                    .allowsHitTesting(false)
            }

            if !context.activeStrokePoints.isEmpty {
                let renderedPoints = context.canvasPoints(context.activeStrokePoints)
                context.pathView(renderedPoints)
                    .stroke(
                        context.annotationDraftColor,
                        style: StrokeStyle(
                            lineWidth: context.overlayStrokeWidth(context.currentTool),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .shadow(color: context.annotationDraftColor.opacity(0.22), radius: 3)
            }

            if !context.activeDragLengthPoints.isEmpty {
                let renderedPoints = context.canvasPoints(context.activeDragLengthPoints)
                context.measurementPolyline(renderedPoints)
                    .stroke(context.lengthDraftColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if let center = context.centerPoint(renderedPoints) {
                    context.measurementBadge(context.lengthLabel(context.activeDragLengthPoints), false)
                        .position(center)
                }
            }

            if context.activeDragArrowPoints.count == 2 {
                let renderedPoints = context.canvasPoints(context.activeDragArrowPoints)
                draftArrow(points: renderedPoints)
            }

            if !context.pendingLengthPoints.isEmpty {
                let renderedPoints = context.canvasPoints(context.pendingLengthPoints)
                pendingLengthPath(points: renderedPoints)
            }

            if !context.pendingAreaPoints.isEmpty {
                let renderedPoints = context.canvasPoints(context.pendingAreaPoints)
                pendingAreaPath(points: renderedPoints)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.accessibilityLabel)
        .accessibilityValue(context.accessibilityValue)
        .accessibilityHint(context.accessibilityHint)
    }

    private func noteBadge(note: CADTextNote, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "批注"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(note.text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color, lineWidth: 1)
        )
    }

    private func draftArrow(points: [CGPoint]) -> some View {
        context.arrowShape(points[0], points[1])
            .stroke(
                context.arrowDraftColor,
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
    }

    private func pendingLengthPath(points: [CGPoint]) -> some View {
        context.measurementPolyline(points)
            .stroke(
                context.lengthDraftColor,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 2])
            )
    }

    private func pendingAreaPath(points: [CGPoint]) -> some View {
        context.measurementPolyline(points)
            .stroke(
                context.areaDraftColor,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3])
            )
    }
}
