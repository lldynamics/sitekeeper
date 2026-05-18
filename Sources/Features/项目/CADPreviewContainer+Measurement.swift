import SwiftUI

extension CADPreviewContainer {
    var scaleEditor: some View {
        CADScaleEditorView(context: scaleEditorContext)
    }

    var unitHint: String {
        "\(measurementScalePresetTitle)：\(String(localized: "1")) \(measurementUnitName) = \(measurementScaleText) m"
    }

    private var measurementUnitName: String {
        String(localized: "图纸单位")
    }

    private var measurementScalePresetTitle: String {
        let value = snapshot.metersPerDrawingUnit
        if let preset = CADDrawingUnitPreset.allCases.first(where: { $0.isMatching(value) }) {
            return preset.title
        }
        return String(localized: "自定义标定")
    }

    private var measurementScaleText: String {
        Formatters.number(snapshot.metersPerDrawingUnit, minFraction: 0, maxFraction: 6)
    }

    private var measurementScalePrompt: String {
        String(localized: "1 图纸单位对应多少米")
    }

    private var measurementScaleDescription: String {
        if shouldUseFallbackViewer {
            return String(localized: "兼容预览使用归一化图纸坐标保存批注和问题点，不写回 CAD 原文件。")
        }
        if hasNativeDrawingCoordinateSpace {
            return String(localized: "测量按 DWG 图纸坐标计算，再通过“图纸单位 → 米”换算，缩放和平移不会改变线长/面积结果。")
        }
        return String(localized: "当前图纸坐标尚未就绪，测量/数数已禁用，避免把屏幕坐标写入算量数据。")
    }

    private var calibrationCandidateMeasurements: [CADLengthMeasurement] {
        snapshot.lengthMeasurements.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedCalibrationMeasurement: CADLengthMeasurement? {
        guard let selectedCalibrationMeasurementID else { return calibrationCandidateMeasurements.first }
        return calibrationCandidateMeasurements.first(where: { $0.id == selectedCalibrationMeasurementID }) ?? calibrationCandidateMeasurements.first
    }

    private var calibrationComputedScale: Double? {
        guard let measurement = selectedCalibrationMeasurement else { return nil }
        let actualMeters = ReportBuilder.number(calibrationActualMetersDraft)
        guard actualMeters > 0 else { return nil }
        let sourceLength = drawingUnitLength(for: measurement.points.map(\.cgPoint))
        guard sourceLength > 0 else { return nil }
        return actualMeters / sourceLength
    }

    func openScaleCalibrationSheet() {
        scaleDraft = measurementScaleText
        if let first = calibrationCandidateMeasurements.first {
            if selectedCalibrationMeasurementID == nil ||
                !calibrationCandidateMeasurements.contains(where: { $0.id == selectedCalibrationMeasurementID }) {
                selectedCalibrationMeasurementID = first.id
            }
            if calibrationActualMetersDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let suggested = lengthInMeters(for: first.points.map(\.cgPoint))
                calibrationActualMetersDraft = Formatters.number(suggested, minFraction: 2, maxFraction: 3)
            }
        } else {
            selectedCalibrationMeasurementID = nil
            calibrationActualMetersDraft = ""
        }
        showScaleSheet = true
    }

    private func applyTwoPointCalibration() {
        guard let computedScale = calibrationComputedScale else { return }
        recordUndoSnapshot()
        snapshot.metersPerDrawingUnit = computedScale
        scaleDraft = Formatters.number(computedScale, minFraction: 0, maxFraction: 8)
        showScaleSheet = false
        alertMessage = String(
            format: String(localized: "已更新标定：1 图纸单位 = %@ m"),
            Formatters.number(computedScale, minFraction: 0, maxFraction: 8)
        )
        showAlert = true
    }

    func lengthInMeters(for points: [CGPoint]) -> Double {
        drawingUnitLength(for: points) * snapshot.metersPerDrawingUnit
    }

    private func drawingUnitLength(for points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var sum: Double = 0
        for idx in 1..<points.count {
            let dx = points[idx].x - points[idx - 1].x
            let dy = points[idx].y - points[idx - 1].y
            sum += sqrt(dx * dx + dy * dy)
        }
        return sum
    }

    func areaInSquareMeters(for points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var shoelace: Double = 0
        for idx in points.indices {
            let next = (idx + 1) % points.count
            shoelace += (points[idx].x * points[next].y) - (points[next].x * points[idx].y)
        }
        let drawingUnitArea = abs(shoelace) / 2
        return drawingUnitArea * snapshot.metersPerDrawingUnit * snapshot.metersPerDrawingUnit
    }

    func lengthLabel(for points: [CGPoint]) -> String {
        "\(Formatters.number(lengthInMeters(for: points), minFraction: 2, maxFraction: 3)) m"
    }

    func areaLabel(for points: [CGPoint]) -> String {
        "\(Formatters.number(areaInSquareMeters(for: points), minFraction: 2, maxFraction: 3)) m²"
    }

    private var scaleEditorContext: CADScaleEditorContext {
        CADScaleEditorContext(
            candidateMeasurements: calibrationCandidateMeasurements,
            selectedMeasurementID: Binding(
                get: { selectedCalibrationMeasurementID ?? calibrationCandidateMeasurements.first?.id ?? UUID() },
                set: { selectedCalibrationMeasurementID = $0 }
            ),
            calibrationActualMetersDraft: $calibrationActualMetersDraft,
            scaleDraft: $scaleDraft,
            computedScale: calibrationComputedScale,
            measurementScalePrompt: measurementScalePrompt,
            measurementScaleDescription: measurementScaleDescription,
            drawingUnitLengthText: { measurement in
                Formatters.number(
                    drawingUnitLength(for: measurement.points.map(\.cgPoint)),
                    minFraction: 2,
                    maxFraction: 4
                )
            },
            isPresetSelected: { preset in
                preset.isMatching(ReportBuilder.number(scaleDraft))
            },
            selectPreset: { preset in
                scaleDraft = Formatters.number(preset.metersPerDrawingUnit, minFraction: 0, maxFraction: 8)
            },
            applyCalibration: {
                applyTwoPointCalibration()
            },
            cancel: {
                showScaleSheet = false
            },
            save: {
                let parsed = ReportBuilder.number(scaleDraft)
                guard parsed > 0 else { return }
                recordUndoSnapshot()
                snapshot.metersPerDrawingUnit = parsed
                showScaleSheet = false
            }
        )
    }

    enum AreaClosureCheckResult {
        case valid(points: [CGPoint], autoClosed: Bool)
        case selfIntersecting
    }

    private func validateAreaClosure(points: [CGPoint]) -> AreaClosureCheckResult? {
        guard points.count >= 3 else { return nil }
        var normalized = points
        let tolerance = areaClosureToleranceInDrawingUnits()

        let first = normalized[0]
        let last = normalized[normalized.count - 1]
        let isAlreadyClosed = hypot(first.x - last.x, first.y - last.y) <= tolerance
        if isAlreadyClosed {
            normalized.removeLast()
        }
        guard normalized.count >= 3 else { return nil }

        if polygonHasSelfIntersection(normalized) {
            return .selfIntersecting
        }
        return .valid(points: normalized, autoClosed: !isAlreadyClosed)
    }

    private func areaClosureToleranceInDrawingUnits() -> CGFloat {
        guard let nativeCanvasTransform else { return 0.5 }
        let baseCanvasPoint = CGPoint(x: nativeCanvasTransform.size.width * 0.5, y: nativeCanvasTransform.size.height * 0.5)
        let rightCanvasPoint = CGPoint(x: baseCanvasPoint.x + overlaySnapTolerance, y: baseCanvasPoint.y)
        let p0 = nativeCanvasTransform.drawingPoint(fromCanvas: baseCanvasPoint)
        let p1 = nativeCanvasTransform.drawingPoint(fromCanvas: rightCanvasPoint)
        let tolerance = hypot(p1.x - p0.x, p1.y - p0.y)
        return max(tolerance, 0.0001)
    }

    private func polygonHasSelfIntersection(_ points: [CGPoint]) -> Bool {
        guard points.count >= 4 else { return false }
        let count = points.count
        for i in 0..<count {
            let a1 = points[i]
            let a2 = points[(i + 1) % count]
            for j in (i + 1)..<count {
                if abs(i - j) <= 1 { continue }
                if i == 0 && j == count - 1 { continue }
                let b1 = points[j]
                let b2 = points[(j + 1) % count]
                if segmentsIntersect(a1, a2, b1, b2) {
                    return true
                }
            }
        }
        return false
    }

    private func segmentsIntersect(_ p1: CGPoint, _ q1: CGPoint, _ p2: CGPoint, _ q2: CGPoint) -> Bool {
        let o1 = orientation(p1, q1, p2)
        let o2 = orientation(p1, q1, q2)
        let o3 = orientation(p2, q2, p1)
        let o4 = orientation(p2, q2, q1)

        if o1 != o2 && o3 != o4 { return true }

        if o1 == 0 && pointOnSegment(p2, p1, q1) { return true }
        if o2 == 0 && pointOnSegment(q2, p1, q1) { return true }
        if o3 == 0 && pointOnSegment(p1, p2, q2) { return true }
        if o4 == 0 && pointOnSegment(q1, p2, q2) { return true }
        return false
    }

    private func orientation(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Int {
        let value = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
        if abs(value) <= 1e-7 { return 0 }
        return value > 0 ? 1 : 2
    }

    private func pointOnSegment(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Bool {
        p.x <= max(q.x, r.x) + 1e-7 &&
        p.x >= min(q.x, r.x) - 1e-7 &&
        p.y <= max(q.y, r.y) + 1e-7 &&
        p.y >= min(q.y, r.y) - 1e-7
    }

    func finalizeContinuousLength() {
        guard ensureDrawingCoordinateCaptureAvailable() else { return }
        guard pendingLengthPoints.count >= 2 else { return }
        recordUndoSnapshot()
        let measurement = CADLengthMeasurement(
            points: pendingLengthPoints.map(CADPoint.init),
            name: "\(String(localized: "连续长度")) \(snapshot.lengthMeasurements.count + 1)",
            colorHex: selectedMeasurementOverlayColorHex()
        )
        hiddenOverlayColorHexes.remove(lengthMeasurementColorHex(measurement))
        snapshot.lengthMeasurements.append(measurement)
        pendingLengthPoints.removeAll()
        AppHaptics.impact(.light, intensity: 0.65)
    }

    func finalizeAreaMeasurement() {
        guard ensureDrawingCoordinateCaptureAvailable() else { return }
        guard pendingAreaPoints.count >= 3 else { return }
        guard let closure = validateAreaClosure(points: pendingAreaPoints) else { return }
        switch closure {
        case .selfIntersecting:
            alertMessage = String(localized: "面积边界存在自交，无法闭合计算。请调整点位后重试。")
            showAlert = true
            return
        case let .valid(points, autoClosed):
            recordUndoSnapshot()
            let measurement = CADAreaMeasurement(
                points: points.map(CADPoint.init),
                name: "\(String(localized: "面积")) \(snapshot.areaMeasurements.count + 1)",
                colorHex: selectedMeasurementOverlayColorHex()
            )
            hiddenOverlayColorHexes.remove(areaMeasurementColorHex(measurement))
            snapshot.areaMeasurements.append(measurement)
            pendingAreaPoints.removeAll()
            if autoClosed {
                alertMessage = String(localized: "已自动补齐闭合边，面积已加入测量。")
                showAlert = true
            }
            AppHaptics.impact(.light, intensity: 0.65)
        }
    }
}
