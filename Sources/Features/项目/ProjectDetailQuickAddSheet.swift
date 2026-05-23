import SwiftUI

struct QuickAddSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sheet: DetailSheet
    let projectId: UUID
    let constructionMethods: [ConstructionMethod]

    @State private var name = ""
    @State private var qty = ""
    @State private var unit = ""
    @State private var unitPrice = ""
    @State private var materialSpecification = ""
    @State private var materialBrand = ""
    @State private var materialSupplier = ""
    @State private var materialPurchaseStatus: MaterialPurchaseStatus = .notPurchased
    @State private var materialArrivalDate = ""
    @State private var price = ""
    @State private var quoteVersionName = "V1"
    @State private var quoteStatus: QuoteStatus = .draft
    @State private var quoteConfirmedDate = ""
    @State private var quoteContractAmount = ""
    @State private var workers = ""
    @State private var laborTeamName = ""
    @State private var laborIsSettled = false
    @State private var laborLines: [QuickAddLaborLine] = [.init()]
    @State private var content = ""
    @State private var weather = String(localized: "晴")
    @State private var safety = ""
    @State private var materials = ""
    @State private var tomorrowPlan = ""
    @State private var qualityIssue = ""
    @State private var rectification = ""
    @State private var confirmer = ""
    @State private var logDate = Date()
    @State private var laborDate = Date()
    @State private var linkedMethodIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                switch sheet {
                case .material:
                    TextField(String(localized: "材料名称"), text: $name)
                    LabeledContent(String(localized: "数量")) {
                        TextField("0", text: $qty.numericInput(.quantity))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单位")) {
                        TextField(String(localized: "米 / 卷 / 个"), text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单价")) {
                        TextField("0", text: $unitPrice.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField(String(localized: "规格型号"), text: $materialSpecification)
                    TextField(String(localized: "品牌"), text: $materialBrand)
                    TextField(String(localized: "供应商"), text: $materialSupplier)
                    Picker(String(localized: "采购状态"), selection: $materialPurchaseStatus) {
                        ForEach(MaterialPurchaseStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    OptionalProjectDatePicker(String(localized: "进场日期"), text: $materialArrivalDate)
                case .quote:
                    TextField(String(localized: "项目名称"), text: $name)
                    LabeledContent(String(localized: "单价 ¥")) {
                        TextField("0", text: $price.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "数量")) {
                        TextField("0", text: $qty.numericInput(.quantity))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单位")) {
                        TextField(String(localized: "项 / 米 / 台"), text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField(String(localized: "版本"), text: $quoteVersionName)
                    Picker(String(localized: "状态"), selection: $quoteStatus) {
                        ForEach(QuoteStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    OptionalProjectDatePicker(String(localized: "客户确认日期"), text: $quoteConfirmedDate)
                    TextField(String(localized: "转合同金额"), text: $quoteContractAmount.numericInput(.amount))
                        .keyboardType(.decimalPad)
                case .log:
                    DatePicker(String(localized: "日期"), selection: $logDate, displayedComponents: .date)
                    Picker(String(localized: "天气"), selection: $weather) {
                        ForEach([String(localized: "晴"), String(localized: "多云"), String(localized: "阴"), String(localized: "小雨"), String(localized: "大雨"), String(localized: "雪")], id: \.self) { Text($0).tag($0) }
                    }
                    TextField(String(localized: "人数"), text: $workers)
                    TextField(String(localized: "内容"), text: $content, axis: .vertical).lineLimit(3...6)
                    TextField(String(localized: "安全事项"), text: $safety, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "材料进场"), text: $materials, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "明日计划"), text: $tomorrowPlan, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "质量问题"), text: $qualityIssue, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "整改记录"), text: $rectification, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "现场确认人"), text: $confirmer)
                    Section(String(localized: "关联施工工艺")) {
                        if constructionMethods.isEmpty {
                            Text(String(localized: "暂无可关联工艺，请先在施工工艺库新增条目。"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(constructionMethods) { method in
                                Toggle(isOn: methodBinding(for: method.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(methodTitle(method))
                                        HStack(spacing: 6) {
                                            if !method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(method.trade)
                                            }
                                            Text(method.versionName.isEmpty ? "V1" : method.versionName)
                                            Text(method.publishStatus.displayName)
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                case .labor:
                    DatePicker(String(localized: "日期"), selection: $laborDate, displayedComponents: .date)
                    TextField(String(localized: "班组（可选）"), text: $laborTeamName)
                    Toggle(String(localized: "已结算"), isOn: $laborIsSettled)
                    ForEach($laborLines) { $line in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(format: String(localized: "工种 %@"), laborLineTitle(for: line.id)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if laborLines.count > 1 {
                                    Button(role: .destructive) {
                                        removeLaborLine(id: line.id)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            TextField(String(localized: "工种"), text: $line.workType)
                            HStack(spacing: 10) {
                                TextField(String(localized: "人数"), text: $line.workers.numericInput(.quantity))
                                    .keyboardType(.numberPad)
                                TextField(String(localized: "工时 (h)"), text: $line.hours.numericInput(.days))
                                    .keyboardType(.decimalPad)
                            }
                            TextField(String(localized: "工价（每工时）"), text: $line.unitRate.numericInput(.laborRate))
                                .keyboardType(.decimalPad)
                            TextField(String(localized: "备注"), text: $line.note)
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        laborLines.append(.init())
                    } label: {
                        Label(String(localized: "添加工种"), systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(sheetTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        if save() {
                            dismiss()
                        }
                    }
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }

    private var sheetTitle: String {
        switch sheet {
        case .material: return String(localized: "添加材料")
        case .quote: return String(localized: "添加报价")
        case .log: return String(localized: "写施工日志")
        case .labor: return String(localized: "记人工")
        }
    }

    private func save() -> Bool {
        switch sheet {
        case .material:
            guard !name.isEmpty else { return false }
            store.appendMaterialItem(
                MaterialItem(
                    name: name,
                    quantity: NumericInputSupport.normalizedStorageText(qty, kind: .quantity),
                    unit: unit,
                    unitPrice: NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount),
                    specification: materialSpecification.trimmingCharacters(in: .whitespacesAndNewlines),
                    brand: materialBrand.trimmingCharacters(in: .whitespacesAndNewlines),
                    supplier: materialSupplier.trimmingCharacters(in: .whitespacesAndNewlines),
                    purchaseStatus: materialPurchaseStatus,
                    arrivalDate: ProjectDateInput.normalizedStorageText(materialArrivalDate),
                    projectId: projectId
                )
            )
            store.scheduleSave()
            return true
        case .quote:
            guard !name.isEmpty else { return false }
            store.appendQuoteItem(
                QuoteItem(
                    name: name,
                    unitPrice: NumericInputSupport.normalizedStorageText(price, kind: .amount),
                    quantity: NumericInputSupport.normalizedStorageText(qty, kind: .quantity),
                    unit: unit,
                    notes: "",
                    taxRate: "0",
                    discountRate: "0",
                    versionName: quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: quoteStatus,
                    customerConfirmedDate: ProjectDateInput.normalizedStorageText(quoteConfirmedDate),
                    contractAmount: NumericInputSupport.normalizedStorageText(quoteContractAmount, kind: .amount),
                    projectId: projectId
                )
            )
            store.scheduleSave()
            return true
        case .log:
            store.insertDailyLogAtTop(DailyLog(
                date: Formatters.date.string(from: logDate),
                weather: weather,
                content: content,
                workers: workers,
                photoFileName: nil,
                safety: safety,
                materials: materials,
                tomorrowPlan: tomorrowPlan,
                qualityIssue: qualityIssue,
                rectification: rectification,
                confirmer: confirmer,
                linkedConstructionMethodIDs: sortedLinkedMethodIDs(),
                projectId: projectId
            ))
            store.scheduleSave()
            return true
        case .labor:
            guard canSaveLaborLines else { return false }
            let teamName = laborTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = Formatters.date.string(from: laborDate)
            var appendedCount = 0
            for line in laborLines where line.hasContent {
                let workers = line.workers.trimmingCharacters(in: .whitespacesAndNewlines)
                let hours = line.hours.trimmingCharacters(in: .whitespacesAndNewlines)
                let unitRate = line.unitRate.trimmingCharacters(in: .whitespacesAndNewlines)
                let workType = line.workType.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = line.note.trimmingCharacters(in: .whitespacesAndNewlines)
                store.appendLaborRecord(
                    LaborRecord(
                        date: date,
                        workers: NumericInputSupport.normalizedStorageText(workers, kind: .quantity),
                        hours: NumericInputSupport.normalizedStorageText(hours, kind: .days),
                        unitRate: NumericInputSupport.normalizedStorageText(unitRate, kind: .laborRate),
                        workType: workType,
                        teamName: teamName,
                        isSettled: laborIsSettled,
                        note: note,
                        projectId: projectId
                    )
                )
                appendedCount += 1
            }
            guard appendedCount > 0 else { return false }
            store.scheduleSave()
            return true
        }
    }

    private func laborLineTitle(for id: UUID) -> String {
        if let index = laborLines.firstIndex(where: { $0.id == id }) {
            return "#\(index + 1)"
        }
        return ""
    }

    private func removeLaborLine(id: UUID) {
        guard laborLines.count > 1 else { return }
        laborLines.removeAll { $0.id == id }
    }

    private var canSaveLaborLines: Bool {
        let filledLines = laborLines.filter(\.hasContent)
        guard !filledLines.isEmpty else { return false }
        return filledLines.allSatisfy { line in
            let workers = line.workers.trimmingCharacters(in: .whitespacesAndNewlines)
            let hours = line.hours.trimmingCharacters(in: .whitespacesAndNewlines)
            let unitRate = line.unitRate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard InputValidator.validate(workers, kind: .quantity, requirement: .requiredNonNegative).isValid,
                  InputValidator.validate(hours, kind: .days, requirement: .requiredNonNegative).isValid else { return false }
            return InputValidator.validate(unitRate, kind: .laborRate, requirement: .optionalNonNegative).isValid
        }
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isOn in
                if isOn {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        linkedMethodIDs.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "未命名工艺") : title
    }
}

private struct QuickAddLaborLine: Identifiable {
    var id = UUID()
    var workType = ""
    var workers = ""
    var hours = ""
    var unitRate = ""
    var note = ""

    var hasContent: Bool {
        !workType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !hours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !unitRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
