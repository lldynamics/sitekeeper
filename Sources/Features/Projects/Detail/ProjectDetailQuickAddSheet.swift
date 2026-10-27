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
    @State private var materialArrivalDate: BusinessDateValue = .empty
    @State private var price = ""
    @State private var quoteVersionName = "V1"
    @State private var quoteStatus: QuoteStatus = .draft
    @State private var quoteConfirmedDate: BusinessDateValue = .empty
    @State private var quoteContractAmount = ""
    @State private var workers = ""
    @State private var laborTeamName = ""
    @State private var laborIsSettled = false
    @State private var laborLines: [QuickAddLaborLine] = [.init()]
    @State private var content = ""
    @State private var weather = ""
    @State private var safety = ""
    @State private var materials = ""
    @State private var tomorrowPlan = ""
    @State private var qualityIssue = ""
    @State private var rectification = ""
    @State private var confirmer = ""
    @State private var logDate = Date()
    @State private var laborDate = Date()
    @State private var linkedMethodIDs: Set<UUID> = []

    @ViewBuilder
    var body: some View {
        if case .log = sheet {
            DailyLogView(initialProjectId: projectId, standaloneComposer: true)
        } else {
            otherEntryForm
        }
    }

    private var otherEntryForm: some View {
        NavigationStack {
            Form {
                switch sheet {
                case .material:
                    QuickAddMaterialFields(
                        name: $name, quantity: $qty, unit: $unit, unitPrice: $unitPrice,
                        specification: $materialSpecification, brand: $materialBrand,
                        supplier: $materialSupplier, purchaseStatus: $materialPurchaseStatus,
                        arrivalDate: $materialArrivalDate
                    )
                case .quote:
                    QuickAddQuoteFields(
                        name: $name, price: $price, quantity: $qty, unit: $unit,
                        versionName: $quoteVersionName, status: $quoteStatus,
                        confirmedDate: $quoteConfirmedDate, contractAmount: $quoteContractAmount
                    )
                case .log:
                    DatePicker(AppLocalization.string("日期"), selection: $logDate, displayedComponents: .date)
                    Picker(AppLocalization.string("天气"), selection: $weather) {
                        Text(AppLocalization.string("待填写")).tag("")
                        ForEach([AppLocalization.string("晴"), AppLocalization.string("多云"), AppLocalization.string("阴"), AppLocalization.string("小雨"), AppLocalization.string("大雨"), AppLocalization.string("雪")], id: \.self) { Text($0).tag($0) }
                    }
                    TextField(AppLocalization.string("人数"), text: $workers)
                    TextField(AppLocalization.string("内容"), text: $content, axis: .vertical).lineLimit(3...6)
                    TextField(AppLocalization.string("安全事项"), text: $safety, axis: .vertical).lineLimit(2...4)
                    TextField(AppLocalization.string("材料进场"), text: $materials, axis: .vertical).lineLimit(2...4)
                    TextField(AppLocalization.string("明日计划"), text: $tomorrowPlan, axis: .vertical).lineLimit(2...4)
                    TextField(AppLocalization.string("质量问题"), text: $qualityIssue, axis: .vertical).lineLimit(2...4)
                    TextField(AppLocalization.string("整改记录"), text: $rectification, axis: .vertical).lineLimit(2...4)
                    TextField(AppLocalization.string("现场确认人"), text: $confirmer)
                    Section(AppLocalization.string("关联施工工艺")) {
                        if constructionMethods.isEmpty {
                            Text(AppLocalization.string("暂无可关联工艺，请先在施工工艺库新增条目。"))
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
                    DatePicker(AppLocalization.string("日期"), selection: $laborDate, displayedComponents: .date)
                    TextField(AppLocalization.string("班组（可选）"), text: $laborTeamName)
                    Toggle(AppLocalization.string("已结算"), isOn: $laborIsSettled)
                    ForEach($laborLines) { $line in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(format: AppLocalization.string("工种 %@"), laborLineTitle(for: line.id)))
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
                            TextField(AppLocalization.string("工种"), text: $line.workType)
                            HStack(spacing: 10) {
                                TextField(AppLocalization.string("人数"), text: $line.workers.numericInput(.quantity))
                                    .keyboardType(.numberPad)
                                TextField(AppLocalization.string("工时 (h)"), text: $line.hours.numericInput(.days))
                                    .keyboardType(.decimalPad)
                            }
                            TextField(AppLocalization.string("工价（每工时）"), text: $line.unitRate.numericInput(.laborRate))
                                .keyboardType(.decimalPad)
                            TextField(AppLocalization.string("备注"), text: $line.note)
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        laborLines.append(.init())
                    } label: {
                        Label(AppLocalization.string("添加工种"), systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(sheetTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        if save() {
                            dismiss()
                        }
                    }
                }
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }

    private var sheetTitle: String {
        switch sheet {
        case .material: return AppLocalization.string("添加材料")
        case .quote: return AppLocalization.string("添加报价")
        case .log: return AppLocalization.string("写施工日志")
        case .labor: return AppLocalization.string("记人工")
        }
    }
}

private extension QuickAddSheet {
    func save() -> Bool {
        switch sheet {
        case .material: return saveMaterial()
        case .quote: return saveQuote()
        case .log: return false // Logs use DailyLogView's durable composer.
        case .labor: return saveLabor()
        }
    }

    func saveMaterial() -> Bool {
        guard !name.isEmpty else { return false }
        store.appendMaterialItem(
            MaterialItem(
                name: name,
                quantity: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(qty, kind: .quantity)),
                unit: unit,
                unitPrice: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount)),
                specification: materialSpecification.trimmingCharacters(in: .whitespacesAndNewlines),
                brand: materialBrand.trimmingCharacters(in: .whitespacesAndNewlines),
                supplier: materialSupplier.trimmingCharacters(in: .whitespacesAndNewlines),
                purchaseStatus: materialPurchaseStatus,
                arrivalDate: materialArrivalDate,
                projectId: projectId
            )
        )
        store.scheduleSave()
        return true
    }

    func saveQuote() -> Bool {
        guard !name.isEmpty else { return false }
        store.appendQuoteItem(
            QuoteItem(
                name: name,
                unitPrice: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(price, kind: .amount)),
                quantity: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(qty, kind: .quantity)),
                unit: unit,
                notes: "",
                taxRate: NumericInputSupport.quantity("0"),
                discountRate: NumericInputSupport.quantity("0"),
                versionName: quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
                status: quoteStatus,
                customerConfirmedDate: quoteConfirmedDate,
                contractAmount: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(quoteContractAmount, kind: .amount)),
                projectId: projectId
            )
        )
        store.scheduleSave()
        return true
    }

    func saveLabor() -> Bool {
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
                    date: BusinessDateValue(legacyText: date),
                    workers: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(workers, kind: .quantity)),
                    hours: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(hours, kind: .days)),
                    workloadUnit: .hour,
                    unitRate: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(unitRate, kind: .laborRate)),
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

    func laborLineTitle(for id: UUID) -> String {
        if let index = laborLines.firstIndex(where: { $0.id == id }) {
            return "#\(index + 1)"
        }
        return ""
    }

    func removeLaborLine(id: UUID) {
        guard laborLines.count > 1 else { return }
        laborLines.removeAll { $0.id == id }
    }

    var canSaveLaborLines: Bool {
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

    func methodBinding(for id: UUID) -> Binding<Bool> {
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

    func sortedLinkedMethodIDs() -> [UUID] {
        linkedMethodIDs.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }

    func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? AppLocalization.string("未命名工艺") : title
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
