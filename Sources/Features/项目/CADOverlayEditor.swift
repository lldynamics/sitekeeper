import SwiftUI

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
                pathView(points: canvasPoints(fromStored: stroke.points.map(\.cgPoint)))
                    .stroke(
                        isSelected ? Color.appWarning.opacity(0.42) : strokeColor(stroke),
                        style: StrokeStyle(
                            lineWidth: isSelected ? stroke.lineWidth + 7 : stroke.lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                pathView(points: canvasPoints(fromStored: stroke.points.map(\.cgPoint)))
                    .stroke(
                        strokeColor(stroke),
                        style: StrokeStyle(
                            lineWidth: isSelected ? stroke.lineWidth + 1.4 : stroke.lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .shadow(color: strokeColor(stroke).opacity(isSelected ? 0.32 : 0.18), radius: isSelected ? 5 : (stroke.kind == .redline ? 3 : 1.5))
            }

            if isOverlayGroupVisible(.measurement) {
                ForEach(snapshot.lengthMeasurements) { measurement in
                    let isHighlighted = highlightedLengthMeasurementID == measurement.id
                    let storedPoints = measurement.points.map(\.cgPoint)
                    let renderedPoints = canvasPoints(fromStored: storedPoints)
                    measurementPolyline(renderedPoints)
                        .stroke(
                            isHighlighted ? Color.appWarning : Color.appStrokeInfo,
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
                ForEach(snapshot.areaMeasurements) { area in
                    let isHighlighted = highlightedAreaMeasurementID == area.id
                    let storedPoints = area.points.map(\.cgPoint)
                    let renderedPoints = canvasPoints(fromStored: storedPoints)
                    if renderedPoints.count >= 3 {
                        Path { path in
                            path.move(to: renderedPoints[0])
                            for point in renderedPoints.dropFirst() {
                                path.addLine(to: point)
                            }
                            path.closeSubpath()
                        }
                        .fill(isHighlighted ? Color.appWarning.opacity(0.22) : Color.appSuccessSurfaceSubtle)

                        Path { path in
                            path.move(to: renderedPoints[0])
                            for point in renderedPoints.dropFirst() {
                                path.addLine(to: point)
                            }
                            path.closeSubpath()
                        }
                        .stroke(
                            isHighlighted ? Color.appWarning : Color.appStrokeSuccess,
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
                ForEach(snapshot.notes) { note in
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
                            .stroke(Color.appStrokeWarning, lineWidth: 1)
                    )
                    .position(canvasPoint(fromStored: note.point.cgPoint))
                }
            }

            if isOverlayGroupVisible(.counts) {
                ForEach(Array(snapshot.countMarkers.enumerated()), id: \.element.id) { index, marker in
                    countMarkerBadge(
                        number: index + 1,
                        category: marker.category,
                        isHighlighted: highlightedCountMarkerIDs.contains(marker.id) || highlightedCountCategory == marker.category
                    )
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
                pathView(points: canvasPoints(fromStored: activeStrokePoints))
                    .stroke(
                        colorFromHex(selectedStrokeColorHex(for: tool == .redline ? .redline : .annotation), fallback: strokeColor(tool == .redline ? .redline : .annotation)),
                        style: StrokeStyle(lineWidth: overlayStrokeWidth(for: tool), lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: colorFromHex(selectedStrokeColorHex(for: tool == .redline ? .redline : .annotation), fallback: strokeColor(tool == .redline ? .redline : .annotation)).opacity(0.22), radius: 3)
            }

            if !activeDragLengthPoints.isEmpty {
                let renderedPoints = canvasPoints(fromStored: activeDragLengthPoints)
                measurementPolyline(renderedPoints)
                    .stroke(Color.appStrokeInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if let center = centerPoint(of: renderedPoints) {
                    measurementBadge(text: lengthLabel(for: activeDragLengthPoints))
                        .position(center)
                }
            }

            if !pendingLengthPoints.isEmpty {
                measurementPolyline(canvasPoints(fromStored: pendingLengthPoints))
                    .stroke(Color.appStrokeInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 2]))
            }

            if !pendingAreaPoints.isEmpty {
                measurementPolyline(canvasPoints(fromStored: pendingAreaPoints))
                    .stroke(Color.appStrokeSuccess, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3]))
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
                case .annotation, .redline:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: activeStrokePoints.isEmpty) else { return }
                    if activeStrokePoints.isEmpty {
                        guard let start = storedDrawingPoint(fromCanvas: value.startLocation) else { return }
                        activeStrokePoints.append(start)
                    }
                    guard let point = storedDrawingPoint(fromCanvas: value.location) else { return }
                    activeStrokePoints.append(point)
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
            .onEnded { _ in
                switch tool {
                case .annotation, .redline:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false) else {
                        activeStrokePoints.removeAll()
                        return
                    }
                    guard activeStrokePoints.count > 1 else {
                        activeStrokePoints.removeAll()
                        return
                    }
                    let stroke = CADStroke(
                        kind: tool == .redline ? .redline : .annotation,
                        points: activeStrokePoints.map(CADPoint.init),
                        lineWidth: overlayStrokeWidth(for: tool),
                        colorHex: selectedStrokeColorHex(for: tool == .redline ? .redline : .annotation),
                        layerName: selectedStrokeLayer
                    )
                    hiddenStrokeLayers.remove(strokeLayerName(stroke))
                    snapshot.strokes.append(stroke)
                    activeStrokePoints.removeAll()
                    AppHaptics.impact(.light, intensity: 0.65)
                case .length:
                    guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false) else {
                        activeDragLengthPoints.removeAll()
                        return
                    }
                    guard activeDragLengthPoints.count == 2 else { return }
                    snapshot.lengthMeasurements.append(
                        CADLengthMeasurement(points: activeDragLengthPoints.map(CADPoint.init), name: "\(String(localized: "线长")) \(snapshot.lengthMeasurements.count + 1)")
                    )
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
                    if let removeIndex = nearestNoteIndex(toCanvasPoint: value.location) {
                        snapshot.notes.remove(at: removeIndex)
                    } else {
                        pendingNotePoint = snapped
                        noteDraft = ""
                        showNoteSheet = true
                    }
                case .count:
                    guard ensureDrawingCoordinateCaptureAvailable() else { return }
                    guard let snapped = snappedOverlayPoint(value.location) else { return }
                    if let removeIndex = nearestCountMarkerIndex(toCanvasPoint: value.location) {
                        snapshot.countMarkers.remove(at: removeIndex)
                    } else {
                        snapshot.countMarkers.append(
                            CADCountMarker(
                                point: CADPoint(snapped),
                                category: selectedCountCategory,
                                createdAt: Formatters.now()
                            )
                        )
                        AppHaptics.impact(.light, intensity: 0.65)
                    }
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

                Text(String(localized: "点空白新增，点编号删除"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(String(localized: "撤销一个")) {
                    if !snapshot.countMarkers.isEmpty {
                        _ = snapshot.countMarkers.removeLast()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.countMarkers.isEmpty)

                Button(String(localized: "加入算量")) {
                    appendQuantityFromCountCategory(selectedCountCategory)
                }
                .buttonStyle(.bordered)
                .disabled(selectedCategoryCount == 0)
            case .annotation:
                overlayStrokeControlStrip(kind: .annotation)
                Button(String(localized: "撤销一笔")) {
                    removeLastStroke(kind: .annotation)
                }
                .buttonStyle(.bordered)
                .disabled(annotationStrokeCount == 0)
            case .redline:
                overlayStrokeControlStrip(kind: .redline)
                Button(String(localized: "撤销一笔")) {
                    removeLastStroke(kind: .redline)
                }
                .buttonStyle(.bordered)
                .disabled(redlineStrokeCount == 0)
            case .length:
                Text(tool.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(String(localized: "吸附"))：\(snapModeSummaryText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一条")) {
                    removeLastLengthMeasurement()
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.lengthMeasurements.isEmpty)
            case .note:
                Text(String(localized: "点空白新增，点现有批注删除"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一个")) {
                    removeLastNote()
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.notes.isEmpty)
            default:
                if tool == .browse {
                    Text("\(String(localized: "批注")) \(snapshot.strokes.count) · \(String(localized: "测量")) \(snapshot.lengthMeasurements.count + snapshot.areaMeasurements.count) · \(String(localized: "数数")) \(snapshot.countMarkers.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
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
                            Text(String(localized: "点按已有批注或红线进行编辑"))
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
                        Label(layer, systemImage: selectedStrokeLayer == layer ? "checkmark" : "square.3.layers.3d")
                    }
                }
            } label: {
                Label(selectedStrokeLayer, systemImage: "square.3.layers.3d")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(overlayColorOptions) { option in
                    Button {
                        if kind == .redline {
                            selectedRedlineColorHex = option.hex
                        } else {
                            selectedAnnotationColorHex = option.hex
                        }
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
            Text(stroke.kind == .redline ? String(localized: "已选红线") : String(localized: "已选批注"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(stroke.kind == .redline ? Color.appRisk : Color.appPrimaryAction)

            Menu {
                ForEach(overlayStrokeLayerOptions, id: \.self) { layer in
                    Button {
                        updateSelectedStrokeLayer(layer)
                    } label: {
                        Label(layer, systemImage: strokeLayerName(stroke) == layer ? "checkmark" : "square.3.layers.3d")
                    }
                }
            } label: {
                Label(strokeLayerName(stroke), systemImage: "square.3.layers.3d")
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
        String(localized: "CAD 图纸覆盖层")
    }

    var overlayAccessibilityValue: String {
        "\(String(localized: "当前工具"))：\(tool.title)，\(String(localized: "批注"))\(snapshot.strokes.count)\(String(localized: "条"))，\(String(localized: "线长"))\(snapshot.lengthMeasurements.count)\(String(localized: "条"))，\(String(localized: "面积"))\(snapshot.areaMeasurements.count)\(String(localized: "条"))，\(String(localized: "文字批注"))\(snapshot.notes.count)\(String(localized: "条"))，\(String(localized: "数数"))\(snapshot.countMarkers.count)\(String(localized: "个"))"
    }

    var overlayLayerEditor: some View {
        NavigationStack {
            List {
                Section(String(localized: "显示覆盖层")) {
                    ForEach(CADOverlayVisibilityGroup.allCases, id: \.self) { group in
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
                }

                Section {
                    ForEach(overlayStrokeLayerOptions, id: \.self) { layer in
                        Toggle(isOn: strokeLayerVisibleBinding(layer)) {
                            Label(layer, systemImage: "square.3.layers.3d")
                        }
                    }
                } header: {
                    Text(String(localized: "批注/红线图层"))
                } footer: {
                    Text(String(localized: "关闭图层只影响当前查看，不会删除已画内容。"))
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

                    overlayColorPicker(
                        title: String(localized: "批注颜色"),
                        selectedHex: $selectedAnnotationColorHex
                    )
                    overlayColorPicker(
                        title: String(localized: "红线颜色"),
                        selectedHex: $selectedRedlineColorHex
                    )
                }
            }
            .navigationTitle(String(localized: "覆盖层设置"))
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

    func overlayColorPicker(title: String, selectedHex: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(overlayColorOptions) { option in
                    Button {
                        selectedHex.wrappedValue = option.hex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(colorFromHex(option.hex, fallback: .appPrimaryAction))
                                .frame(width: 28, height: 28)
                            if selectedHex.wrappedValue == option.hex {
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
        }
        .padding(.vertical, 4)
    }
}
