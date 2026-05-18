import SwiftUI

struct CADMeasurementPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct CADScaleEditorContext {
    let candidateMeasurements: [CADLengthMeasurement]
    let selectedMeasurementID: Binding<UUID>
    let calibrationActualMetersDraft: Binding<String>
    let scaleDraft: Binding<String>
    let computedScale: Double?
    let measurementScalePrompt: String
    let measurementScaleDescription: String
    let drawingUnitLengthText: (CADLengthMeasurement) -> String
    let isPresetSelected: (CADDrawingUnitPreset) -> Bool
    let selectPreset: (CADDrawingUnitPreset) -> Void
    let applyCalibration: () -> Void
    let cancel: () -> Void
    let save: () -> Void
}

struct CADQuantitySheetContext {
    let lengthMeasurements: [CADLengthMeasurement]
    let areaMeasurements: [CADAreaMeasurement]
    let countCategoryStats: [(category: String, count: Int)]
    let quantityItems: Binding<[CADQuantityItem]>
    let lengthSummary: (CADLengthMeasurement) -> String
    let areaSummary: (CADAreaMeasurement) -> String
    let appendLengthMeasurement: (CADLengthMeasurement) -> Void
    let appendAreaMeasurement: (CADAreaMeasurement) -> Void
    let appendCountCategory: (String) -> Void
    let canLocateItem: (CADQuantityItem) -> Bool
    let locateItem: (CADQuantityItem) -> Void
    let quantitySubtotal: (CADQuantityItem) -> Double
    let deleteItem: (CADQuantityItem) -> Void
    let quantityTotal: Double
    let addManualItem: () -> Void
    let close: () -> Void
}

struct CADScaleEditorView: View {
    let context: CADScaleEditorContext

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "基准线标定（推荐）")) {
                    if context.candidateMeasurements.isEmpty {
                        Text(String(localized: "先用“线长”或“连续长度”画一条基准线，再输入该线的实际长度。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(String(localized: "基准线"), selection: context.selectedMeasurementID) {
                            ForEach(context.candidateMeasurements) { measurement in
                                Text("\(measurement.name) · \(context.drawingUnitLengthText(measurement)) \(String(localized: "图纸单位"))")
                                    .tag(measurement.id)
                            }
                        }
                        TextField(String(localized: "该基准线实际长度（米）"), text: context.calibrationActualMetersDraft)
                            .keyboardType(.decimalPad)
                        if let computedScale = context.computedScale {
                            Text(
                                String(
                                    format: String(localized: "将应用：1 图纸单位 = %@ m"),
                                    Formatters.number(computedScale, minFraction: 0, maxFraction: 8)
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                        } else {
                            Text(String(localized: "请输入大于 0 的实际长度，系统会自动换算标定系数。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(String(localized: "应用基准线标定")) {
                            context.applyCalibration()
                        }
                        .disabled(context.computedScale == nil)
                    }
                }

                Section(String(localized: "图纸单位预设")) {
                    ForEach(CADDrawingUnitPreset.allCases) { preset in
                        Button {
                            context.selectPreset(preset)
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
                                if context.isPresetSelected(preset) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(String(localized: "手动输入：图纸单位 → 米")) {
                    TextField(context.measurementScalePrompt, text: context.scaleDraft)
                        .keyboardType(.decimalPad)
                    Text(context.measurementScaleDescription)
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
                    Button(String(localized: "取消")) {
                        context.cancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        context.save()
                    }
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }
}

struct CADQuantitySheetView: View {
    let context: CADQuantitySheetContext

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "测量结果快速入算量")) {
                    if context.lengthMeasurements.isEmpty && context.areaMeasurements.isEmpty {
                        Text(String(localized: "先做线长或面积测量，再一键加入算量。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(context.lengthMeasurements) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(context.lengthSummary(item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    context.appendLengthMeasurement(item)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        ForEach(context.areaMeasurements) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(context.areaSummary(item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    context.appendAreaMeasurement(item)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(String(localized: "数数结果快速入算量")) {
                    if context.countCategoryStats.isEmpty {
                        Text(String(localized: "先在图纸上使用“数数”点位，再按类别加入算量。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(context.countCategoryStats, id: \.category) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.category)
                                    Text("\(item.count) \(String(localized: "个"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    context.appendCountCategory(item.category)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(String(localized: "半自动算量清单")) {
                    if context.quantityItems.wrappedValue.isEmpty {
                        Text(String(localized: "还没有算量条目。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(context.quantityItems) { $item in
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
                                        context.locateItem(item)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!context.canLocateItem(item))
                                    Spacer(minLength: 0)
                                }
                                Text("\(String(localized: "小计"))：¥\(Formatters.money(context.quantitySubtotal(item)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryAction)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    context.deleteItem(item)
                                } label: {
                                    Label(String(localized: "删除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "汇总")) {
                    LabeledContent(String(localized: "合计"), value: "¥\(Formatters.money(context.quantityTotal))")
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
                    Button(String(localized: "关闭")) {
                        context.close()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        context.addManualItem()
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
