import SwiftUI

struct CADMeasurementPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    var scaleEditor: some View {
        let candidateMeasurements = calibrationCandidateMeasurements
        return NavigationStack {
            Form {
                Section(String(localized: "基准线标定（推荐）")) {
                    if candidateMeasurements.isEmpty {
                        Text(String(localized: "先用“线长”或“连续长度”画一条基准线，再输入该线的实际长度。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            String(localized: "基准线"),
                            selection: Binding(
                                get: { selectedCalibrationMeasurementID ?? candidateMeasurements.first?.id ?? UUID() },
                                set: { selectedCalibrationMeasurementID = $0 }
                            )
                        ) {
                            ForEach(candidateMeasurements) { measurement in
                                let drawingUnitLengthText = Formatters.number(
                                    drawingUnitLength(for: measurement.points.map(\.cgPoint)),
                                    minFraction: 2,
                                    maxFraction: 4
                                )
                                Text("\(measurement.name) · \(drawingUnitLengthText) \(String(localized: "图纸单位"))")
                                    .tag(measurement.id)
                            }
                        }
                        TextField(String(localized: "该基准线实际长度（米）"), text: $calibrationActualMetersDraft)
                            .keyboardType(.decimalPad)
                        if let computedScale = calibrationComputedScale {
                            Text(String(localized: "将应用：1 图纸单位 = \(Formatters.number(computedScale, minFraction: 0, maxFraction: 8)) m"))
                                .font(.caption)
                                .foregroundStyle(Color.appSuccess)
                        } else {
                            Text(String(localized: "请输入大于 0 的实际长度，系统会自动换算标定系数。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(String(localized: "应用基准线标定")) {
                            applyTwoPointCalibration()
                        }
                        .disabled(calibrationComputedScale == nil)
                    }
                }

                Section(String(localized: "图纸单位预设")) {
                    ForEach(CADDrawingUnitPreset.allCases) { preset in
                        Button {
                            scaleDraft = Formatters.number(preset.metersPerDrawingUnit, minFraction: 0, maxFraction: 8)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.title)
                                        .foregroundStyle(.primary)
                                    Text(preset.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if preset.isMatching(ReportBuilder.number(scaleDraft)) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(String(localized: "手动输入：图纸单位 → 米")) {
                    TextField(measurementScalePrompt, text: $scaleDraft)
                        .keyboardType(.decimalPad)
                    Text(measurementScaleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "例如毫米图纸填 0.001，厘米图纸填 0.01，米制图纸填 1。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "辅助估算，现场以规范和专业判断为准。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "测量标定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showScaleSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        let parsed = ReportBuilder.number(scaleDraft)
                        guard parsed > 0 else { return }
                        recordUndoSnapshot()
                        snapshot.metersPerDrawingUnit = parsed
                        showScaleSheet = false
                    }
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }

    var quantitySheet: some View {
        NavigationStack {
            List {
                Section(String(localized: "测量结果快速入算量")) {
                    if snapshot.lengthMeasurements.isEmpty && snapshot.areaMeasurements.isEmpty {
                        Text(String(localized: "先做线长或面积测量，再一键加入算量。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.lengthMeasurements) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(lengthLabel(for: item.points.map(\.cgPoint)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    appendQuantityFromLength(item)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        ForEach(snapshot.areaMeasurements) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(areaLabel(for: item.points.map(\.cgPoint)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    appendQuantityFromArea(item)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(String(localized: "数数结果快速入算量")) {
                    if countCategoryStats.isEmpty {
                        Text(String(localized: "先在图纸上使用“数数”点位，再按类别加入算量。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(countCategoryStats, id: \.category) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.category)
                                    Text("\(item.count) \(String(localized: "个"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    appendQuantityFromCountCategory(item.category)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(String(localized: "半自动算量清单")) {
                    if snapshot.quantityItems.isEmpty {
                        Text(String(localized: "还没有算量条目。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($snapshot.quantityItems) { $item in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(String(localized: "名称"), text: $item.name)
                                HStack {
                                    TextField(String(localized: "数量"), text: $item.quantity)
                                        .keyboardType(.decimalPad)
                                    TextField(String(localized: "单位"), text: $item.unit)
                                        .frame(width: 54)
                                    TextField(String(localized: "单价"), text: $item.unitPrice)
                                        .keyboardType(.decimalPad)
                                }
                                HStack {
                                    TextField(String(localized: "损耗率%"), text: $item.wasteRate)
                                        .keyboardType(.decimalPad)
                                    Text(item.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                HStack {
                                    Button(String(localized: "定位回图纸")) {
                                        locateQuantitySource(item)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(quantityHighlightTarget(for: item) == nil)
                                    Spacer(minLength: 0)
                                }
                                Text("\(String(localized: "小计"))：¥\(Formatters.money(quantitySubtotal(item)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryAction)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    recordUndoSnapshot()
                                    snapshot.quantityItems.removeAll { $0.id == item.id }
                                } label: {
                                    Label(String(localized: "删除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "汇总")) {
                    LabeledContent(String(localized: "合计"), value: "¥\(Formatters.money(quantityTotal))")
                    Text(String(localized: "本期算量为半自动：由测量结果生成基础数量后，人工可继续修正数量、单位、损耗率和单价。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "辅助估算，现场以规范和专业判断为准。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "半自动算量"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { showQuantitySheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appendManualQuantityItem()
                    } label: {
                        Image(systemName: "plus").visibleIconStyle()
                    }
                    .buttonStyle(.appIcon())
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }
}
