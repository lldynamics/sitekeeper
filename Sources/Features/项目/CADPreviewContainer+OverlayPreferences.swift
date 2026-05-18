import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    private var overlayStrokeLayerDefaults: [String] {
        [
            String(localized: "现场批注"),
            String(localized: "复核标记"),
            String(localized: "整改记录")
        ]
    }

    var overlayVisibilityGroups: [CADOverlayVisibilityGroup] {
        [.annotation, .measurement, .notes, .counts, .issues]
    }

    var overlayStrokeLayerOptions: [String] {
        var result: [String] = []
        func append(_ value: String?) {
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !result.contains(text) else { return }
            result.append(text)
        }
        overlayStrokeLayerDefaults.forEach(append)
        snapshot.customStrokeLayerNames.forEach(append)
        snapshot.strokes.forEach { append(strokeLayerName($0)) }
        snapshot.arrowAnnotations.forEach { append(strokeLayerName($0)) }
        append(selectedStrokeLayer)
        return result
    }

    private var defaultOverlayColorOptions: [CADOverlayColorOption] {
        [
            .init(name: String(localized: "桃红"), hex: "E24A7A"),
            .init(name: String(localized: "柳绿"), hex: "67A866"),
            .init(name: String(localized: "蓝色"), hex: "2F80ED"),
            .init(name: String(localized: "橙色"), hex: "F2994A"),
            .init(name: String(localized: "紫色"), hex: "8E6AD8"),
            .init(name: String(localized: "黑色"), hex: "333333")
        ]
    }

    var overlayColorOptions: [CADOverlayColorOption] {
        var result: [CADOverlayColorOption] = []
        func append(_ option: CADOverlayColorOption) {
            let normalized = normalizedColorHex(option.hex)
            guard !result.contains(where: { normalizedColorHex($0.hex) == normalized }) else { return }
            result.append(CADOverlayColorOption(name: option.name, hex: normalized))
        }
        func appendHex(_ hex: String?) {
            let normalized = normalizedColorHex(hex)
            guard !result.contains(where: { normalizedColorHex($0.hex) == normalized }) else { return }
            result.append(CADOverlayColorOption(name: "#\(normalized)", hex: normalized))
        }

        defaultOverlayColorOptions.forEach(append)
        snapshot.customOverlayColors.forEach(append)
        appendHex(selectedAnnotationColorHex)
        appendHex(selectedMeasurementColorHex)
        appendHex(selectedNoteColorHex)
        snapshot.strokes.forEach { appendHex(strokeColorHex($0)) }
        snapshot.arrowAnnotations.forEach { appendHex(arrowColorHex($0)) }
        snapshot.lengthMeasurements.forEach { appendHex(lengthMeasurementColorHex($0)) }
        snapshot.areaMeasurements.forEach { appendHex(areaMeasurementColorHex($0)) }
        snapshot.notes.forEach { appendHex(noteColorHex($0)) }
        snapshot.issueMarkers.forEach { appendHex(issueMarkerColorHex($0)) }
        return result
    }

    var overlayColorVisibilityOptions: [CADOverlayColorOption] {
        var result: [CADOverlayColorOption] = []
        func append(name: String, hex: String) {
            let normalized = normalizedColorHex(hex)
            guard overlayColorItemCount(for: normalized) > 0,
                  !result.contains(where: { normalizedColorHex($0.hex) == normalized }) else { return }
            result.append(CADOverlayColorOption(name: name, hex: normalized))
        }

        overlayColorOptions.forEach { append(name: $0.name, hex: $0.hex) }
        snapshot.strokes.forEach { append(name: colorDisplayName(for: strokeColorHex($0)), hex: strokeColorHex($0)) }
        snapshot.arrowAnnotations.forEach { append(name: colorDisplayName(for: arrowColorHex($0)), hex: arrowColorHex($0)) }
        snapshot.lengthMeasurements.forEach { append(name: colorDisplayName(for: lengthMeasurementColorHex($0)), hex: lengthMeasurementColorHex($0)) }
        snapshot.areaMeasurements.forEach { append(name: colorDisplayName(for: areaMeasurementColorHex($0)), hex: areaMeasurementColorHex($0)) }
        snapshot.notes.forEach { append(name: colorDisplayName(for: noteColorHex($0)), hex: noteColorHex($0)) }
        snapshot.issueMarkers.forEach { append(name: colorDisplayName(for: issueMarkerColorHex($0)), hex: issueMarkerColorHex($0)) }
        return result
    }

    var snapModeSummaryText: String {
        let orderedModes = CADSnapMode.allCases.filter { enabledSnapModes.contains($0) }
        guard !orderedModes.isEmpty else { return String(localized: "已关闭吸附") }
        return orderedModes.map(\.title).joined(separator: " · ")
    }

    var visibleStrokes: [CADStroke] {
        snapshot.strokes.filter { stroke in
            isOverlayGroupVisible(.annotation) &&
            isStrokeLayerVisible(strokeLayerName(stroke)) &&
            isOverlayColorVisible(strokeColorHex(stroke))
        }
    }

    var visibleArrows: [CADArrowAnnotation] {
        snapshot.arrowAnnotations.filter { arrow in
            isOverlayGroupVisible(.annotation) &&
            isStrokeLayerVisible(strokeLayerName(arrow)) &&
            isOverlayColorVisible(arrowColorHex(arrow))
        }
    }

    var visibleLengthMeasurements: [CADLengthMeasurement] {
        guard isOverlayGroupVisible(.measurement) else { return [] }
        return snapshot.lengthMeasurements.filter {
            isOverlayColorVisible(lengthMeasurementColorHex($0))
        }
    }

    var visibleAreaMeasurements: [CADAreaMeasurement] {
        guard isOverlayGroupVisible(.measurement) else { return [] }
        return snapshot.areaMeasurements.filter {
            isOverlayColorVisible(areaMeasurementColorHex($0))
        }
    }

    var visibleNotes: [CADTextNote] {
        guard isOverlayGroupVisible(.notes) else { return [] }
        return snapshot.notes.filter {
            isOverlayColorVisible(noteColorHex($0))
        }
    }

    var visibleIssueMarkers: [CADFallbackIssueMarker] {
        guard isOverlayGroupVisible(.issues) else { return [] }
        return snapshot.issueMarkers.filter {
            isOverlayColorVisible(issueMarkerColorHex($0))
        }
    }

    func restoredSnapshot(for request: ProjectCADPreviewRequest) -> CADOverlaySnapshot {
        if var decoded = decodedSnapshotData(request.overlaySnapshotData, displayName: request.displayName) {
            if decoded.coordinateSpace == .canvas, !decoded.hasOverlayContent {
                decoded.coordinateSpace = .drawing
            }
            return decoded
        }
        return CADOverlaySnapshot()
    }

    private func decodedSnapshotData(_ raw: String, displayName: String) -> CADOverlaySnapshot? {
        guard !raw.isEmpty,
              let data = Data(base64Encoded: raw) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CADOverlaySnapshot.self, from: data)
        } catch {
            StorageIssueLog.record("CAD 快照解析失败：\(displayName)，\(error.localizedDescription)")
            return nil
        }
    }

    func applyOverlayDisplayPreferences(from snapshot: CADOverlaySnapshot) {
        let groups = snapshot.hiddenOverlayGroupIDs.compactMap(CADOverlayVisibilityGroup.init(rawValue:))
        hiddenOverlayGroups = Set(groups)
        hiddenStrokeLayers = Set(snapshot.hiddenStrokeLayerNames)
        hiddenOverlayColorHexes = Set(snapshot.hiddenOverlayColorHexes.map { normalizedColorHex($0) })

        let layer = (snapshot.selectedStrokeLayerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        selectedStrokeLayer = layer.isEmpty ? String(localized: "现场批注") : layer

        selectedAnnotationColorHex = normalizedColorHex(snapshot.selectedAnnotationColorHex, fallback: "2F80ED")
        selectedMeasurementColorHex = normalizedColorHex(snapshot.selectedMeasurementColorHex, fallback: "2F80ED")
        selectedNoteColorHex = normalizedColorHex(snapshot.selectedNoteColorHex, fallback: "F2994A")

        let snapModes = snapshot.enabledSnapModeIDs.compactMap(CADSnapMode.init(rawValue:))
        if snapModes.isEmpty {
            enabledSnapModes = Set(CADSnapMode.allCases)
        } else {
            enabledSnapModes = Set(snapModes)
        }
    }

    func updateOverlayDisplayPreferences() {
        snapshot.hiddenOverlayGroupIDs = hiddenOverlayGroups.map(\.rawValue).sorted()
        snapshot.hiddenStrokeLayerNames = hiddenStrokeLayers.sorted()
        snapshot.hiddenOverlayColorHexes = hiddenOverlayColorHexes.map { normalizedColorHex($0) }.sorted()
        snapshot.selectedStrokeLayerName = selectedStrokeLayer
        snapshot.selectedAnnotationColorHex = normalizedColorHex(selectedAnnotationColorHex, fallback: "2F80ED")
        snapshot.selectedMeasurementColorHex = normalizedColorHex(selectedMeasurementColorHex, fallback: "2F80ED")
        snapshot.selectedNoteColorHex = normalizedColorHex(selectedNoteColorHex, fallback: "F2994A")
        snapshot.enabledSnapModeIDs = CADSnapMode.allCases
            .filter { enabledSnapModes.contains($0) }
            .map(\.rawValue)
    }

    func revealAllOverlayContent() {
        hiddenOverlayGroups.removeAll()
        hiddenStrokeLayers.removeAll()
        hiddenOverlayColorHexes.removeAll()
        updateOverlayDisplayPreferences()
    }

    func revealOverlayContent(for group: CADOverlayVisibilityGroup) {
        hiddenOverlayGroups.remove(group)
        switch group {
        case .annotation:
            snapshot.strokes.forEach { stroke in
                hiddenStrokeLayers.remove(strokeLayerName(stroke))
                hiddenOverlayColorHexes.remove(strokeColorHex(stroke))
            }
            snapshot.arrowAnnotations.forEach { arrow in
                hiddenStrokeLayers.remove(strokeLayerName(arrow))
                hiddenOverlayColorHexes.remove(arrowColorHex(arrow))
            }
        case .measurement:
            snapshot.lengthMeasurements.forEach { hiddenOverlayColorHexes.remove(lengthMeasurementColorHex($0)) }
            snapshot.areaMeasurements.forEach { hiddenOverlayColorHexes.remove(areaMeasurementColorHex($0)) }
        case .notes:
            snapshot.notes.forEach { hiddenOverlayColorHexes.remove(noteColorHex($0)) }
        case .counts:
            break
        case .issues:
            snapshot.issueMarkers.forEach { hiddenOverlayColorHexes.remove(issueMarkerColorHex($0)) }
        }
        updateOverlayDisplayPreferences()
    }

    func copyOverlayDisplayPreferences(
        from source: CADOverlaySnapshot,
        to destination: inout CADOverlaySnapshot
    ) {
        destination.hiddenOverlayGroupIDs = source.hiddenOverlayGroupIDs
        destination.hiddenStrokeLayerNames = source.hiddenStrokeLayerNames
        destination.hiddenOverlayColorHexes = source.hiddenOverlayColorHexes
        destination.customStrokeLayerNames = source.customStrokeLayerNames
        destination.customOverlayColors = source.customOverlayColors
        destination.selectedStrokeLayerName = source.selectedStrokeLayerName
        destination.selectedAnnotationColorHex = source.selectedAnnotationColorHex
        destination.selectedRedlineColorHex = source.selectedRedlineColorHex
        destination.selectedMeasurementColorHex = source.selectedMeasurementColorHex
        destination.selectedNoteColorHex = source.selectedNoteColorHex
        destination.enabledSnapModeIDs = source.enabledSnapModeIDs
    }

    func encodedSnapshotData(_ snapshot: CADOverlaySnapshot) -> String {
        do {
            let data = try JSONEncoder().encode(snapshot)
            return data.base64EncodedString()
        } catch {
            StorageIssueLog.record("CAD 快照编码失败：\(activeRequest.displayName)，\(error.localizedDescription)")
            return ""
        }
    }

    @MainActor
    func debouncePersistSnapshot(_ value: CADOverlaySnapshot) async {
        guard await DebouncedTask.wait(for: .milliseconds(350)) else { return }
        persistSnapshotIfNeeded(value)
    }

    func persistSnapshotIfNeeded(_ value: CADOverlaySnapshot) {
        let encoded = encodedSnapshotData(value)
        guard encoded != lastPersistedSnapshotData else { return }
        lastPersistedSnapshotData = encoded
        activeRequest.onOverlaySnapshotChange(activeRequest.drawingID, encoded)
    }


    func strokeColor(_ stroke: CADStroke) -> Color {
        colorFromHex(strokeColorHex(stroke), fallback: strokeColor(stroke.kind))
    }

    func strokeColor(_ kind: CADStroke.StrokeKind) -> Color {
        .appPrimaryAction
    }

    func selectedStrokeColorHex(for kind: CADStroke.StrokeKind) -> String {
        normalizedColorHex(selectedAnnotationColorHex, fallback: defaultStrokeColorHex(for: kind))
    }

    private func defaultStrokeColorHex(for kind: CADStroke.StrokeKind) -> String {
        "2F80ED"
    }

    func strokeColorHex(_ stroke: CADStroke) -> String {
        normalizedColorHex(stroke.colorHex, fallback: defaultStrokeColorHex(for: stroke.kind))
    }

    func lengthMeasurementColorHex(_ measurement: CADLengthMeasurement) -> String {
        normalizedColorHex(measurement.colorHex, fallback: "2F80ED")
    }

    func areaMeasurementColorHex(_ measurement: CADAreaMeasurement) -> String {
        normalizedColorHex(measurement.colorHex, fallback: "67A866")
    }

    func noteColorHex(_ note: CADTextNote) -> String {
        normalizedColorHex(note.colorHex, fallback: "F2994A")
    }

    func arrowColorHex(_ arrow: CADArrowAnnotation) -> String {
        normalizedColorHex(arrow.colorHex, fallback: "2F80ED")
    }

    func issueMarkerColorHex(_ marker: CADFallbackIssueMarker) -> String {
        normalizedColorHex(marker.colorHex, fallback: "E24A7A")
    }

    func selectedMeasurementOverlayColorHex() -> String {
        normalizedColorHex(selectedMeasurementColorHex, fallback: "2F80ED")
    }

    func selectedNoteOverlayColorHex() -> String {
        normalizedColorHex(selectedNoteColorHex, fallback: "F2994A")
    }

    func strokeLayerName(_ stroke: CADStroke) -> String {
        let text = (stroke.layerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "现场批注") : text
    }

    func strokeLayerName(_ arrow: CADArrowAnnotation) -> String {
        let text = (arrow.layerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "现场批注") : text
    }

    func isOverlayGroupVisible(_ group: CADOverlayVisibilityGroup) -> Bool {
        !hiddenOverlayGroups.contains(group)
    }

    private func isStrokeLayerVisible(_ layer: String) -> Bool {
        !hiddenStrokeLayers.contains(layer)
    }

    func isOverlayColorVisible(_ hex: String) -> Bool {
        !hiddenOverlayColorHexes.contains(normalizedColorHex(hex))
    }

    func overlayGroupVisibleBinding(_ group: CADOverlayVisibilityGroup) -> Binding<Bool> {
        Binding(
            get: { isOverlayGroupVisible(group) },
            set: { isVisible in
                if isVisible {
                    hiddenOverlayGroups.remove(group)
                } else {
                    hiddenOverlayGroups.insert(group)
                }
            }
        )
    }

    func strokeLayerVisibleBinding(_ layer: String) -> Binding<Bool> {
        Binding(
            get: { isStrokeLayerVisible(layer) },
            set: { isVisible in
                if isVisible {
                    hiddenStrokeLayers.remove(layer)
                } else {
                    hiddenStrokeLayers.insert(layer)
                }
            }
        )
    }

    func overlayColorVisibleBinding(_ hex: String) -> Binding<Bool> {
        let normalized = normalizedColorHex(hex)
        return Binding(
            get: { isOverlayColorVisible(normalized) },
            set: { isVisible in
                if isVisible {
                    hiddenOverlayColorHexes.remove(normalized)
                } else {
                    hiddenOverlayColorHexes.insert(normalized)
                }
            }
        )
    }

    func snapModeEnabledBinding(_ mode: CADSnapMode) -> Binding<Bool> {
        Binding(
            get: { enabledSnapModes.contains(mode) },
            set: { isEnabled in
                if isEnabled {
                    enabledSnapModes.insert(mode)
                } else {
                    enabledSnapModes.remove(mode)
                }
                if enabledSnapModes.isEmpty {
                    enabledSnapModes = Set(CADSnapMode.allCases)
                }
            }
        )
    }

    func overlayItemCount(for group: CADOverlayVisibilityGroup) -> Int {
        switch group {
        case .annotation:
            return annotationStrokeCount
        case .measurement:
            return snapshot.lengthMeasurements.count + snapshot.areaMeasurements.count
        case .notes:
            return snapshot.notes.count
        case .counts:
            return snapshot.countMarkers.count
        case .issues:
            return snapshot.issueMarkers.count
        }
    }

    func colorFromHex(_ hex: String?, fallback: Color) -> Color {
        guard let hex else { return fallback }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return fallback
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    func normalizedColorHex(_ hex: String?, fallback: String = "2F80ED") -> String {
        let cleaned = (hex ?? "").trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        if cleaned.count == 6, UInt64(cleaned, radix: 16) != nil {
            return cleaned
        }
        let fallbackCleaned = fallback.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        return fallbackCleaned.count == 6 ? fallbackCleaned : "2F80ED"
    }

    private func hexString(from color: Color) -> String? {
#if os(iOS)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(
            format: "%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
#else
        return nil
#endif
    }

    func addCustomStrokeLayer() {
        let layer = newOverlayLayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !layer.isEmpty else { return }
        if !snapshot.customStrokeLayerNames.contains(layer) {
            snapshot.customStrokeLayerNames.append(layer)
        }
        selectedStrokeLayer = layer
        hiddenStrokeLayers.remove(layer)
        newOverlayLayerName = ""
        updateOverlayDisplayPreferences()
        AppHaptics.impact(.light, intensity: 0.55)
    }

    @discardableResult
    func addCustomOverlayColor(_ color: Color) -> String? {
        guard let hex = hexString(from: color) else { return nil }
        let normalized = normalizedColorHex(hex)
        if !snapshot.customOverlayColors.contains(where: { normalizedColorHex($0.hex) == normalized }) {
            snapshot.customOverlayColors.append(
                CADOverlayColorOption(name: "#\(normalized)", hex: normalized)
            )
        }
        hiddenOverlayColorHexes.remove(normalized)
        AppHaptics.impact(.light, intensity: 0.55)
        return normalized
    }

    private func colorDisplayName(for hex: String) -> String {
        let normalized = normalizedColorHex(hex)
        if let option = overlayColorOptions.first(where: { normalizedColorHex($0.hex) == normalized }) {
            return option.name
        }
        return "#\(normalized)"
    }

    func overlayColorItemCount(for hex: String) -> Int {
        let normalized = normalizedColorHex(hex)
        let strokeCount = snapshot.strokes.filter { strokeColorHex($0) == normalized }.count
        let arrowCount = snapshot.arrowAnnotations.filter { arrowColorHex($0) == normalized }.count
        let lengthCount = snapshot.lengthMeasurements.filter { lengthMeasurementColorHex($0) == normalized }.count
        let areaCount = snapshot.areaMeasurements.filter { areaMeasurementColorHex($0) == normalized }.count
        let noteCount = snapshot.notes.filter { noteColorHex($0) == normalized }.count
        let issueCount = snapshot.issueMarkers.filter { issueMarkerColorHex($0) == normalized }.count
        return strokeCount + arrowCount + lengthCount + areaCount + noteCount + issueCount
    }
}
