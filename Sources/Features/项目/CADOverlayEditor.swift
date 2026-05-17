import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CADOverlayEditor<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    @ViewBuilder
    func overlayLayer(size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.001))

            ForEach(visibleStrokes) { stroke in
                let isSelected = selectedStrokeID == stroke.id
                let renderedPoints = canvasPoints(fromStored: stroke.points.map(\.cgPoint))
                let renderedPath = pathView(points: renderedPoints)
                let color = strokeColor(stroke)
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

            ForEach(visibleArrows) { arrow in
                arrowShape(
                    start: canvasPoint(fromStored: arrow.start.cgPoint),
                    end: canvasPoint(fromStored: arrow.end.cgPoint)
                )
                .stroke(
                    colorFromHex(arrowColorHex(arrow), fallback: Color.appPrimaryAction),
                    style: StrokeStyle(lineWidth: arrow.lineWidth, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: colorFromHex(arrowColorHex(arrow), fallback: Color.appPrimaryAction).opacity(0.16), radius: 2)
            }

            if isOverlayGroupVisible(.measurement) {
                ForEach(visibleLengthMeasurements) { measurement in
                    let isHighlighted = highlightedLengthMeasurementID == measurement.id
                    let storedPoints = measurement.points.map(\.cgPoint)
                    let renderedPoints = canvasPoints(fromStored: storedPoints)
                    let color = colorFromHex(lengthMeasurementColorHex(measurement), fallback: Color.appStrokeInfo)
                    measurementPolyline(renderedPoints)
                        .stroke(
                            isHighlighted ? Color.appWarning : color,
                            style: StrokeStyle(
                                lineWidth: isHighlighted ? 3.6 : 2,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: measurement.points.count > 2 ? [4, 2] : []
                            )
                        )
                    if let center = centerPoint(of: renderedPoints) {
                        measurementBadge(
                            text: lengthLabel(for: storedPoints),
                            isHighlighted: isHighlighted
                        )
                        .position(center)
                    }
                }
            }

            if isOverlayGroupVisible(.measurement) {
                ForEach(visibleAreaMeasurements) { area in
                    let isHighlighted = highlightedAreaMeasurementID == area.id
                    let storedPoints = area.points.map(\.cgPoint)
                    let renderedPoints = canvasPoints(fromStored: storedPoints)
                    let color = colorFromHex(areaMeasurementColorHex(area), fallback: Color.appStrokeSuccess)
                    if renderedPoints.count >= 3 {
                        let renderedPath = closedPath(points: renderedPoints)
                        renderedPath
                        .fill(isHighlighted ? Color.appWarning.opacity(0.22) : color.opacity(0.14))

                        renderedPath
                        .stroke(
                            isHighlighted ? Color.appWarning : color,
                            style: StrokeStyle(lineWidth: isHighlighted ? 3 : 2, lineJoin: .round, dash: [5, 3])
                        )

                        if let center = centerPoint(of: renderedPoints) {
                            measurementBadge(text: areaLabel(for: storedPoints), isHighlighted: isHighlighted)
                                .position(center)
                        }
                    }
                }
            }

            if isOverlayGroupVisible(.notes) {
                ForEach(visibleNotes) { note in
                    let color = colorFromHex(noteColorHex(note), fallback: Color.appStrokeWarning)
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
                    .position(canvasPoint(fromStored: note.point.cgPoint))
                }
            }

            if isOverlayGroupVisible(.counts) {
                let highlightedIDs = highlightedCountMarkerIDs
                let highlightedCategory = highlightedCountCategory
                ForEach(Array(snapshot.countMarkers.enumerated()), id: \.element.id) { index, marker in
                    countMarkerBadge(
                        number: index + 1,
                        category: marker.category,
                        isHighlighted: highlightedIDs.contains(marker.id) || highlightedCategory == marker.category
                    )
                    .position(canvasPoint(fromStored: marker.point.cgPoint))
                }
            }

            if isOverlayGroupVisible(.issues) {
                ForEach(visibleIssueMarkers) { marker in
                    issueMarkerBadge(marker)
                        .position(canvasPoint(fromStored: marker.point.cgPoint))
                }
            }

            if let highlightRect = quantityHighlightCanvasRect {
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

            if !activeStrokePoints.isEmpty {
                let kind: CADStroke.StrokeKind = .annotation
                let color = colorFromHex(selectedStrokeColorHex(for: kind), fallback: strokeColor(kind))
                pathView(points: canvasPoints(fromStored: activeStrokePoints))
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: overlayStrokeWidth(for: tool), lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: color.opacity(0.22), radius: 3)
            }

            if !activeDragLengthPoints.isEmpty {
                let renderedPoints = canvasPoints(fromStored: activeDragLengthPoints)
                let color = colorFromHex(selectedMeasurementOverlayColorHex(), fallback: Color.appStrokeInfo)
                measurementPolyline(renderedPoints)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if let center = centerPoint(of: renderedPoints) {
                    measurementBadge(text: lengthLabel(for: activeDragLengthPoints))
                        .position(center)
                }
            }

            if activeDragArrowPoints.count == 2 {
                let renderedPoints = canvasPoints(fromStored: activeDragArrowPoints)
                arrowShape(start: renderedPoints[0], end: renderedPoints[1])
                    .stroke(
                        colorFromHex(selectedStrokeColorHex(for: .annotation), fallback: Color.appPrimaryAction),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
            }

            if !pendingLengthPoints.isEmpty {
                let renderedPoints = canvasPoints(fromStored: pendingLengthPoints)
                let color = colorFromHex(selectedMeasurementOverlayColorHex(), fallback: Color.appStrokeInfo)
                measurementPolyline(renderedPoints)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 2]))
            }

            if !pendingAreaPoints.isEmpty {
                let renderedPoints = canvasPoints(fromStored: pendingAreaPoints)
                let color = colorFromHex(selectedMeasurementOverlayColorHex(), fallback: Color.appStrokeSuccess)
                measurementPolyline(renderedPoints)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3]))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .highPriorityGesture(overlayDragGesture)
        .simultaneousGesture(overlayTapGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overlayAccessibilityLabel)
        .accessibilityValue(overlayAccessibilityValue)
        .accessibilityHint(String(localized: "拖动绘制，点按可测量/数数，自动吸附附近关键点并自动保存。"))
    }

    var overlayDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                switch tool {
                case .annotation, .cloud:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: activeStrokePoints.isEmpty) else { return }
                    if activeStrokePoints.isEmpty {
                        appendActiveStrokePoint(fromCanvas: value.startLocation, force: true)
                    }
                    appendActiveStrokePoint(fromCanvas: value.location)
                case .arrow:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: activeDragArrowPoints.isEmpty) else { return }
                    if activeDragArrowPoints.isEmpty {
                        guard let start = snappedOverlayPoint(value.startLocation),
                              let end = snappedOverlayPoint(value.location) else { return }
                        activeDragArrowPoints = [start, end]
                    } else {
                        guard let end = snappedOverlayPoint(value.location) else { return }
                        activeDragArrowPoints[1] = end
                    }
                case .length:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: activeDragLengthPoints.isEmpty) else { return }
                    if activeDragLengthPoints.isEmpty {
                        guard let start = snappedOverlayPoint(value.startLocation),
                              let end = snappedOverlayPoint(value.location) else { return }
                        activeDragLengthPoints = [start, end]
                    } else {
                        guard let end = snappedOverlayPoint(value.location) else { return }
                        activeDragLengthPoints[1] = end
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                switch tool {
                case .annotation, .cloud:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false) else {
                        activeStrokePoints.removeAll()
                        return
                    }
                    appendActiveStrokePoint(fromCanvas: value.location, force: true)
                    guard activeStrokePoints.count > 1 else {
                        activeStrokePoints.removeAll()
                        return
                    }
                    let stroke = CADStroke(
                        kind: tool == .cloud ? .cloud : .annotation,
                        points: activeStrokePoints.map(CADPoint.init),
                        lineWidth: overlayStrokeWidth(for: tool),
                        colorHex: selectedStrokeColorHex(for: .annotation),
                        layerName: selectedStrokeLayer
                    )
                    hiddenStrokeLayers.remove(strokeLayerName(stroke))
                    hiddenOverlayColorHexes.remove(strokeColorHex(stroke))
                    recordUndoSnapshot()
                    snapshot.strokes.append(stroke)
                    activeStrokePoints.removeAll()
                    AppHaptics.impact(.light, intensity: 0.65)
                case .arrow:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false) else {
                        activeDragArrowPoints.removeAll()
                        return
                    }
                    guard activeDragArrowPoints.count == 2 else { return }
                    recordUndoSnapshot()
                    let arrow = CADArrowAnnotation(
                        start: CADPoint(activeDragArrowPoints[0]),
                        end: CADPoint(activeDragArrowPoints[1]),
                        lineWidth: 2.4,
                        colorHex: selectedStrokeColorHex(for: .annotation),
                        layerName: selectedStrokeLayer,
                        createdAt: Formatters.now()
                    )
                    hiddenStrokeLayers.remove(strokeLayerName(arrow))
                    hiddenOverlayColorHexes.remove(arrowColorHex(arrow))
                    snapshot.arrowAnnotations.append(arrow)
                    activeDragArrowPoints.removeAll()
                    AppHaptics.impact(.light, intensity: 0.65)
                case .length:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false) else {
                        activeDragLengthPoints.removeAll()
                        return
                    }
                    guard activeDragLengthPoints.count == 2 else { return }
                    recordUndoSnapshot()
                    let measurement = CADLengthMeasurement(
                        points: activeDragLengthPoints.map(CADPoint.init),
                        name: "\(String(localized: "线长")) \(snapshot.lengthMeasurements.count + 1)",
                        colorHex: selectedMeasurementOverlayColorHex()
                    )
                    hiddenOverlayColorHexes.remove(lengthMeasurementColorHex(measurement))
                    snapshot.lengthMeasurements.append(measurement)
                    activeDragLengthPoints.removeAll()
                    AppHaptics.impact(.light, intensity: 0.65)
                default:
                    break
                }
            }
    }

    var overlayTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if isDeletingOverlayItem {
                    deleteOverlayItem(atCanvasPoint: value.location)
                    return
                }

                switch tool {
                case .browse:
                    guard isSelectingStroke else { return }
                    selectedStrokeID = nearestStrokeID(toCanvasPoint: value.location)
                    if selectedStrokeID != nil {
                        AppHaptics.impact(.light, intensity: 0.55)
                    }
                case .continuousLength:
                    guard ensureDrawingCoordinateCaptureAvailable() else { return }
                    guard let snapped = snappedOverlayPoint(value.location) else { return }
                    pendingLengthPoints.append(snapped)
                case .area:
                    guard ensureDrawingCoordinateCaptureAvailable() else { return }
                    guard let snapped = snappedOverlayPoint(value.location) else { return }
                    pendingAreaPoints.append(snapped)
                case .note:
                    guard ensureDrawingCoordinateCaptureAvailable() else { return }
                    guard let snapped = snappedOverlayPoint(value.location) else { return }
                    guard nearestNoteIndex(toCanvasPoint: value.location) == nil else { return }
                    pendingNotePoint = snapped
                    noteDraft = ""
                    showNoteSheet = true
                case .issueMarker:
                    guard ensureDrawingCoordinateCaptureAvailable() else { return }
                    guard let snapped = snappedOverlayPoint(value.location) else { return }
                    pendingIssueMarkerPoint = snapped
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showIssuePhotoCamera = true
                    } else {
                        appendIssueMarker(photo: nil)
                    }
                case .count:
                    guard ensureDrawingCoordinateCaptureAvailable() else { return }
                    guard let snapped = snappedOverlayPoint(value.location) else { return }
                    guard nearestCountMarkerIndex(toCanvasPoint: value.location) == nil else { return }
                    recordUndoSnapshot()
                    snapshot.countMarkers.append(
                        CADCountMarker(
                            point: CADPoint(snapped),
                            layoutId: SiteKeeperCADKernel.CADLayout.modelSpace.id,
                            worldPoint: CADPoint(snapped),
                            category: selectedCountCategory,
                            createdAt: Formatters.now()
                        )
                    )
                    AppHaptics.impact(.light, intensity: 0.65)
                default:
                    break
                }
            }
    }

    var bottomControlBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            bottomControlBarContent
        }
        .background(.thinMaterial)
    }

    var bottomControlBarContent: some View {
        HStack(spacing: 10) {
            Button {
                undoLastOverlayChange()
            } label: {
                Label(String(localized: "撤销"), systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!canUndoOverlayChange)

            Button {
                redoOverlayChange()
            } label: {
                Label(String(localized: "前进"), systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .disabled(!canRedoOverlayChange)

            Button {
                deleteCurrentOverlayItem()
            } label: {
                Label(
                    isDeletingOverlayItem ? String(localized: "退出删除") : String(localized: "删除"),
                    systemImage: isDeletingOverlayItem ? "xmark.circle" : "trash"
                )
            }
            .buttonStyle(.bordered)
            .tint(isDeletingOverlayItem ? Color.appRisk : nil)
            .disabled(!canDeleteCurrentOverlayItem && !isDeletingOverlayItem)

            switch tool {
            case .continuousLength:
                Button(String(localized: "完成连续测量")) {
                    finalizeContinuousLength()
                }
                .buttonStyle(.appProminent())
                .disabled(pendingLengthPoints.count < 2)
                Text("\(String(localized: "吸附"))：\(snapModeSummaryText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一点")) {
                    if !pendingLengthPoints.isEmpty { _ = pendingLengthPoints.removeLast() }
                }
                .buttonStyle(.bordered)
                .disabled(pendingLengthPoints.isEmpty)
            case .area:
                Button(String(localized: "闭合并计算面积")) {
                    finalizeAreaMeasurement()
                }
                .buttonStyle(.appProminent())
                .disabled(pendingAreaPoints.count < 3)
                Text("\(String(localized: "吸附"))：\(snapModeSummaryText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一点")) {
                    if !pendingAreaPoints.isEmpty { _ = pendingAreaPoints.removeLast() }
                }
                .buttonStyle(.bordered)
                .disabled(pendingAreaPoints.isEmpty)
            case .count:
                Menu {
                    ForEach(countCategoryOptions, id: \.self) { category in
                        Button(category) {
                            selectedCountCategory = category
                        }
                    }
                } label: {
                    Label(selectedCountCategory, systemImage: "number.circle")
                }
                .buttonStyle(.appProminent())

                Text("\(String(localized: "当前类别")) \(selectedCategoryCount)\(String(localized: "个"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(String(localized: "吸附"))：\(snapModeSummaryText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(String(localized: "点空白新增，删除请用删除模式"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(String(localized: "加入算量")) {
                    appendQuantityFromCountCategory(selectedCountCategory)
                }
                .buttonStyle(.bordered)
                .disabled(selectedCategoryCount == 0)
            case .annotation, .cloud:
                overlayStrokeControlStrip(kind: .annotation)
            case .arrow:
                overlayStrokeControlStrip(kind: .annotation)
            case .length:
                Text(tool.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(String(localized: "吸附"))：\(snapModeSummaryText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .note:
                Text(String(localized: "点空白新增，删除请用删除模式"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .issueMarker:
                Text(String(localized: "点图纸位置创建问题点，可拍照作为现场反馈。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                if tool == .browse {
                    Text("\(String(localized: "批注")) \(snapshot.strokes.count + snapshot.arrowAnnotations.count) · \(String(localized: "测量")) \(snapshot.lengthMeasurements.count + snapshot.areaMeasurements.count) · \(String(localized: "问题")) \(snapshot.issueMarkers.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !snapshot.issueMarkers.isEmpty {
                        Menu {
                            ForEach(snapshot.issueMarkers) { marker in
                                Menu(marker.title) {
                                    Button {
                                        createTodoAndQuickNote(fromCADIssue: marker)
                                    } label: {
                                        Label(String(localized: "转待办 + 随手记"), systemImage: "square.and.pencil")
                                    }
                                    Button {
                                        createSiteTodo(fromCADIssue: marker)
                                    } label: {
                                        Label(String(localized: "只转现场待办"), systemImage: "checklist")
                                    }
                                    Button {
                                        createQuickNote(fromCADIssue: marker)
                                    } label: {
                                        Label(String(localized: "只转随手记"), systemImage: "bubble.left.and.text.bubble.right")
                                    }
                                }
                            }
                        } label: {
                            Label(String(localized: "转记录"), systemImage: "arrowshape.turn.up.right")
                        }
                        .buttonStyle(.appProminent(tint: .appPrimaryAction))
                    }
                    if isDeletingOverlayItem {
                        Text(String(localized: "点要删除的批注、测量、文字或编号"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appRisk)
                    }
                    if let selectedStroke {
                        selectedStrokeControlStrip(stroke: selectedStroke)
                    } else {
                        if isSelectingStroke {
                            Button(String(localized: "退出选择")) {
                                isSelectingStroke = false
                                selectedStrokeID = nil
                            }
                            .buttonStyle(.appProminent(tint: .appPrimaryAction))
                            .disabled(snapshot.strokes.isEmpty)
                            Text(String(localized: "点按已有批注进行编辑"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(String(localized: "选择批注")) {
                                isSelectingStroke = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(snapshot.strokes.isEmpty)
                        }
                    }
                    if quantityHighlightTarget != nil {
                        Text(String(localized: "已高亮算量来源"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appWarning)
                        Button(String(localized: "清除高亮")) {
                            quantityHighlightTarget = nil
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("\(String(localized: "当前工具"))：\(tool.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if tool != .browse {
                Button(String(localized: "切回浏览")) {
                    tool = .browse
                    clearInProgress()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func overlayStrokeControlStrip(kind: CADStroke.StrokeKind) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(overlayStrokeLayerOptions, id: \.self) { layer in
                    Button {
                        selectedStrokeLayer = layer
                    } label: {
                        Label(layer, systemImage: selectedStrokeLayer == layer ? "checkmark" : "square.on.square")
                    }
                }
            } label: {
                Label(selectedStrokeLayer, systemImage: "square.on.square")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(overlayColorOptions) { option in
                    Button {
                        selectedAnnotationColorHex = option.hex
                    } label: {
                        Label(option.name, systemImage: selectedStrokeColorHex(for: kind) == option.hex ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorFromHex(selectedStrokeColorHex(for: kind), fallback: strokeColor(kind)))
                        .frame(width: 14, height: 14)
                    Text(String(localized: "颜色"))
                }
            }
            .buttonStyle(.bordered)

            Text(tool.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    func selectedStrokeControlStrip(stroke: CADStroke) -> some View {
        HStack(spacing: 8) {
            Text(String(localized: "已选批注"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appPrimaryAction)

            Menu {
                ForEach(overlayStrokeLayerOptions, id: \.self) { layer in
                    Button {
                        updateSelectedStrokeLayer(layer)
                    } label: {
                        Label(layer, systemImage: strokeLayerName(stroke) == layer ? "checkmark" : "square.on.square")
                    }
                }
            } label: {
                Label(strokeLayerName(stroke), systemImage: "square.on.square")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(overlayColorOptions) { option in
                    Button {
                        updateSelectedStrokeColor(option.hex)
                    } label: {
                        Label(option.name, systemImage: stroke.colorHex == option.hex ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(strokeColor(stroke))
                        .frame(width: 14, height: 14)
                    Text(String(localized: "颜色"))
                }
            }
            .buttonStyle(.bordered)

            Button(String(localized: "删除")) {
                deleteSelectedStroke()
            }
            .buttonStyle(.bordered)
            .tint(Color.appRisk)

            Button(String(localized: "取消选择")) {
                selectedStrokeID = nil
            }
            .buttonStyle(.bordered)
        }
    }

    var overlayAccessibilityLabel: String {
        String(localized: "CAD 图纸显示和标记")
    }

    var overlayAccessibilityValue: String {
        "\(String(localized: "当前工具"))：\(tool.title)，\(String(localized: "批注"))\(snapshot.strokes.count + snapshot.arrowAnnotations.count)\(String(localized: "条"))，\(String(localized: "线长"))\(snapshot.lengthMeasurements.count)\(String(localized: "条"))，\(String(localized: "面积"))\(snapshot.areaMeasurements.count)\(String(localized: "条"))，\(String(localized: "文字批注"))\(snapshot.notes.count)\(String(localized: "条"))，\(String(localized: "数数"))\(snapshot.countMarkers.count)\(String(localized: "个"))，\(String(localized: "问题点"))\(snapshot.issueMarkers.count)\(String(localized: "个"))"
    }

    var overlayLayerEditor: some View {
        NavigationStack {
            List {
                if shouldUseCADKernelRenderer {
                    Section(String(localized: "图纸显示")) {
                        Button {
                            openDrawingLayerPanelFromDisplayPanel()
                        } label: {
                            Label(String(localized: "图纸图层"), systemImage: "rectangle.3.group")
                        }
                        Button {
                            openDrawingTextSearchPanel()
                        } label: {
                            Label(String(localized: "文字搜索"), systemImage: "magnifyingglass")
                        }
                        Button {
                            showOverlayLayerSheet = false
                            DispatchQueue.main.async {
                                showTextEncodingDialog = true
                            }
                        } label: {
                            Label(String(localized: "文字修复"), systemImage: "character.textbox")
                        }
                    }
                }

                Section(String(localized: "我的标记")) {
                    ForEach(overlayVisibilityGroups, id: \.self) { group in
                        Toggle(isOn: overlayGroupVisibleBinding(group)) {
                            Label {
                                HStack {
                                    Text(group.title)
                                    Spacer(minLength: 8)
                                    Text("\(overlayItemCount(for: group))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: group.icon)
                            }
                        }
                    }
                    Button {
                        revealAllOverlayContent()
                    } label: {
                        Label(String(localized: "显示全部标记"), systemImage: "eye")
                    }
                }

                Section {
                    ForEach(overlayStrokeLayerOptions, id: \.self) { layer in
                        Toggle(isOn: strokeLayerVisibleBinding(layer)) {
                            Label(layer, systemImage: "square.on.square")
                        }
                    }
                } header: {
                    Text(String(localized: "我的标记图层"))
                } footer: {
                    Text(String(localized: "关闭图层只影响当前查看，不会删除已画内容。"))
                }

                if !overlayColorVisibilityOptions.isEmpty {
                    Section {
                        ForEach(overlayColorVisibilityOptions) { option in
                            Toggle(isOn: overlayColorVisibleBinding(option.hex)) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(colorFromHex(option.hex, fallback: .appPrimaryAction))
                                        .frame(width: 12, height: 12)
                                    Text(option.name)
                                    Spacer(minLength: 8)
                                    Text("\(overlayColorItemCount(for: option.hex))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text(String(localized: "按颜色显示"))
                    } footer: {
                        Text(String(localized: "按颜色隐藏只影响当前查看；批注、测量和文字批注都会按颜色一起筛选。"))
                    }
                }

                Section(String(localized: "吸附策略")) {
                    ForEach(CADSnapMode.allCases, id: \.self) { mode in
                        Toggle(isOn: snapModeEnabledBinding(mode)) {
                            Label(mode.title, systemImage: mode.icon)
                        }
                    }
                    Text(String(localized: "测量/数数仅吸附你开启的类型：端点、中点、圆心。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "新绘制属性")) {
                    Picker(String(localized: "图层"), selection: $selectedStrokeLayer) {
                        ForEach(overlayStrokeLayerOptions, id: \.self) { layer in
                            Text(layer).tag(layer)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(String(localized: "新增图层名称"), text: $newOverlayLayerName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(String(localized: "新增")) {
                            addCustomStrokeLayer()
                        }
                        .disabled(newOverlayLayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    overlayColorPicker(
                        title: String(localized: "批注颜色"),
                        selectedHex: $selectedAnnotationColorHex
                    )
                    overlayColorPicker(
                        title: String(localized: "测量颜色"),
                        selectedHex: $selectedMeasurementColorHex
                    )
                    overlayColorPicker(
                        title: String(localized: "文字批注颜色"),
                        selectedHex: $selectedNoteColorHex
                    )
                }
            }
            .navigationTitle(String(localized: "显示"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) {
                        showOverlayLayerSheet = false
                    }
                }
            }
        }
    }

    func openDrawingLayerPanelFromDisplayPanel() {
        showOverlayLayerSheet = false
        NotificationCenter.default.post(
            name: .cadOpenDrawingLayerPanel,
            object: nil,
            userInfo: ["filePath": activeRequest.fileURL.path]
        )
    }

    func openDrawingTextSearchPanel() {
        showOverlayLayerSheet = false
        NotificationCenter.default.post(
            name: .cadOpenTextSearchPanel,
            object: nil,
            userInfo: ["filePath": activeRequest.fileURL.path]
        )
    }

    func overlayColorPicker(title: String, selectedHex: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(overlayColorOptions) { option in
                    Button {
                        selectedHex.wrappedValue = normalizedColorHex(option.hex)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(colorFromHex(option.hex, fallback: .appPrimaryAction))
                                .frame(width: 28, height: 28)
                            if normalizedColorHex(selectedHex.wrappedValue) == normalizedColorHex(option.hex) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                }
            }
            HStack(spacing: 10) {
                ColorPicker(String(localized: "自定义"), selection: $customOverlayColor, supportsOpacity: false)
                    .labelsHidden()
                Button(String(localized: "新增颜色")) {
                    if let hex = addCustomOverlayColor(customOverlayColor) {
                        selectedHex.wrappedValue = hex
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
