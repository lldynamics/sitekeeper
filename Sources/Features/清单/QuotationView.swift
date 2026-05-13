import SwiftUI
import Foundation

struct QuotationView: View {
    private enum QuoteFormField: Hashable {
        case price
        case quantity
        case contractAmount
        case taxRate
        case discountRate
    }

    private enum GenerateQuoteField: Hashable {
        case materialPrice
        case laborRate
        case taxRate
        case discountRate
    }

    private enum QuotationExportFormat: String, CaseIterable, Identifiable {
        case pdf
        case excel

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pdf:
                return "PDF"
            case .excel:
                return "Excel 表格"
            }
        }
    }

    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    @AppStorage(UserPreferenceKeys.companyName) private var companyName = ""
    @AppStorage(UserPreferenceKeys.companyPhone) private var companyPhone = ""
    @AppStorage(UserPreferenceKeys.companyAddress) private var companyAddress = ""
    @AppStorage(UserPreferenceKeys.quoteValidityDays) private var quoteValidityDays = 15
    let focusedQuoteId: UUID?
    @State private var searchText = ""
    @State private var projectFilter: UUID?
    @State private var statusFilter: QuoteStatus?
    @State private var showForm = false
    @State private var editingId: UUID?
    @State private var didOpenFocusedQuote = false

    // 表单字段
    @State private var formName = ""
    @State private var formUnit = "项"
    @State private var formPrice = ""
    @State private var formQty = ""
    @State private var formNotes = ""
    @State private var formTax = "0"
    @State private var formDiscount = "0"
    @State private var formVersionName = "V1"
    @State private var formStatus: QuoteStatus = .draft
    @State private var formCustomerConfirmedDate = ""
    @State private var formContractAmount = ""
    @State private var formProjectId: UUID?
    @State private var showGenerateSheet = false
    @State private var generateProjectId: UUID?
    @State private var defaultMaterialPrice = ""
    @State private var defaultLaborRate = "120"
    @State private var generateTax = "0"
    @State private var generateDiscount = "0"
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var showQuoteExportSheet = false
    @State private var showCompanyInfoPrompt = false
    @State private var quoteCustomerName = ""
    @State private var quoteProjectAddress = ""
    @State private var quoteSignerName = "项目负责人"
    @State private var quoteExportFormat: QuotationExportFormat = .pdf
    @State private var operationMessage: String?
    @FocusState private var quoteFormFocusedField: QuoteFormField?
    @FocusState private var generateQuoteFocusedField: GenerateQuoteField?

    init(focusedQuoteId: UUID? = nil) {
        self.focusedQuoteId = focusedQuoteId
    }

    private var filtered: [QuoteItem] {
        var result = store.quoteItems
        if let projectFilter {
            result = result.filter { $0.projectId == projectFilter }
        }
        result = SearchMatcher.filter(result, keyword: searchText)
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        return result
    }

    private var subtotalBeforeValue: MoneyValue {
        filtered.reduce(MoneyValue.zero) { total, item in
            total + ReportBuilder.quoteLineTotalValue(item)
        }
    }

    private var totalTaxValue: MoneyValue {
        filtered.reduce(MoneyValue.zero) { total, item in
            total + ReportBuilder.quoteTaxValue(item)
        }
    }

    private var totalDiscountValue: MoneyValue {
        filtered.reduce(MoneyValue.zero) { total, item in
            total + ReportBuilder.quoteDiscountValue(item)
        }
    }

    private var grandTotalValue: MoneyValue {
        subtotalBeforeValue + totalTaxValue - totalDiscountValue
    }

    var grandTotal: Double { grandTotalValue.doubleValue }

    private var statusChipBinding: Binding<QuoteStatusChip> {
        Binding(
            get: { QuoteStatusChip(status: statusFilter) },
            set: { statusFilter = $0.status }
        )
    }

    var body: some View {
        List {
            Section("范围") {
                ProjectContextStrip(
                    title: "当前工程",
                    projects: store.projects,
                    selectedProjectId: $projectFilter,
                    emptyText: "全部项目"
                )
                FilterChipBar(
                    options: QuoteStatusChip.allCases,
                    selection: statusChipBinding,
                    title: { $0.title }
                )
                if projectFilter == nil {
                    ForEach(projectQuoteSummaries, id: \.name) { summary in
                        LabeledContent(summary.name, value: ReportBuilder.money(summary.total))
                    }
                }
            }

            ForEach(filtered) { item in
                let total = ReportBuilder.quoteGrandTotal(item)
                let projectText = item.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? "未归属"
                let statusText = "\(item.versionName) · \(item.status.displayName)"
                let amountText = "单价 ¥\(item.unitPrice) × \(item.quantity)\(item.unit)"
                let extraText = item.customerConfirmedDate.isEmpty ? "" : "确认 \(item.customerConfirmedDate)"
                Button {
                    openEdit(item)
                } label: {
                    BusinessRecordRow(
                        icon: "doc.text.fill",
                        iconColor: statusColor(item.status),
                        title: item.name,
                        meta: [amountText, projectText, statusText].joined(separator: " · "),
                        note: [extraText, item.notes].filter { !$0.isEmpty }.joined(separator: " · "),
                        trailing: ReportBuilder.money(total),
                        trailingColor: Color.appPrimaryAction
                    )
                }
            }
            .onDelete { idx in
                let ids = idx.map { filtered[$0].id }
                store.quoteItems.removeAll { ids.contains($0.id) }
                store.scheduleSave()
                operationMessage = "已删除 \(ids.count) 条报价"
            }

            Section {
                VStack(spacing: 4) {
                    HStack { Text("小计").foregroundStyle(.secondary); Spacer(); Text(ReportBuilder.money(subtotalBeforeValue.doubleValue)) }
                    if totalTaxValue.isPositive { HStack { Text("税额").foregroundStyle(.appRisk); Spacer(); Text(ReportBuilder.money(totalTaxValue.doubleValue)).foregroundStyle(.appRisk) } }
                    if totalDiscountValue.isPositive { HStack { Text("折扣").foregroundStyle(.appSuccess); Spacer(); Text("-\(ReportBuilder.money(totalDiscountValue.doubleValue))").foregroundStyle(.appSuccess) } }
                    Divider()
                    HStack {
                        Text("合计").font(.title3.weight(.bold))
                        Spacer()
                        Text(ReportBuilder.money(grandTotalValue.doubleValue)).font(.title3.weight(.bold)).foregroundStyle(.appWarning)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索报价名称")
        .navigationTitle("预结算信息")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showGenerateSheet = true
                    } label: {
                        Label("从材料/人工生成报价", systemImage: "wand.and.stars")
                    }
                    Button {
                        openQuotationExportSheet()
                    } label: {
                        Label("导出当前报价", systemImage: "doc.richtext")
                    }
                    Divider()
                    ForEach(store.materialItems) { m in
                        Button {
                            store.quoteItems.append(QuoteItem(
                                name: m.name, unitPrice: "", quantity: m.quantity, unit: m.unit,
                                notes: "", taxRate: "0", discountRate: "0", projectId: m.projectId
                            ))
                            store.scheduleSave()
                        } label: { Text("\(m.name) (\(m.quantity) \(m.unit))") }
                    }
                    if store.materialItems.isEmpty { Text("材料清单为空").foregroundStyle(.secondary) }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .accessibilityLabel("更多操作")
                .buttonStyle(.appIcon())
                Button { openAdd() } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel("新建报价")
            }
            if let projectFilter, store.projects.contains(where: { $0.id == projectFilter }) {
                ToolbarItem(placement: .topBarLeading) {
                    Button("写入合同") {
                        applyGrandTotalToProjectContract()
                    }
                    .accessibilityLabel("将当前筛选报价合计写入项目合同金额")
                }
            }
        }
        .sheet(isPresented: $showForm) {
            quoteForm
        }
        .sheet(isPresented: $showGenerateSheet) {
            generateQuoteForm
        }
        .sheet(isPresented: $showQuoteExportSheet) {
            quotationExportForm
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .pdf,
            defaultFilename: exportPayload?.defaultFilename ?? "报价单.pdf"
        ) { result in
            switch result {
            case .success:
                AppHaptics.success()
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    AppHaptics.error()
                }
            }
        }
        .alert("先填写公司信息", isPresented: $showCompanyInfoPrompt) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请先填写公司名称、电话和地址。导出的报价单会使用这些信息。")
        }
        .onAppear(perform: openFocusedQuoteIfNeeded)
        .operationToast(message: $operationMessage)
    }

    // MARK: - Form

    private var quoteForm: some View {
        NavigationStack {
            Form {
                Section("必填信息") {
                    if !store.templates.filter({ $0.category == .quotation }).isEmpty {
                        Menu("套用报价模板") {
                            ForEach(store.templates.filter { $0.category == .quotation }) { template in
                                Button(template.name) { applyQuotationTemplate(template) }
                            }
                        }
                    }
                    TextField("项目名称", text: $formName)
                    LabeledContent("单价 ¥") {
                        TextField("0", text: $formPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($quoteFormFocusedField, equals: .price)
                    }
                    LabeledContent("数量") {
                        TextField("0", text: $formQty)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($quoteFormFocusedField, equals: .quantity)
                    }
                    LabeledContent("单位") {
                        TextField("项 / 米 / 台", text: $formUnit)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("版本（如 V1）", text: $formVersionName)
                    Picker("状态", selection: $formStatus) {
                        ForEach(QuoteStatus.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }
                Section("商务信息") {
                    TextField("客户确认日期（yyyy-MM-dd）", text: $formCustomerConfirmedDate)
                    LabeledContent("合同金额") {
                        TextField("0", text: $formContractAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($quoteFormFocusedField, equals: .contractAmount)
                    }
                }
                Section("归属项目") {
                    Picker("选择工程", selection: $formProjectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(store.projects) { p in
                            Text(p.name).tag(p.id as UUID?)
                        }
                    }
                }
                Section("费率") {
                    HStack {
                        Text("税率 (%)")
                        Spacer()
                        TextField("0", text: $formTax)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($quoteFormFocusedField, equals: .taxRate)
                    }
                    HStack {
                        Text("折扣 (%)")
                        Spacer()
                        TextField("0", text: $formDiscount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($quoteFormFocusedField, equals: .discountRate)
                    }
                }
                Section("备注") {
                    TextField("备注", text: $formNotes)
                }
            }
            .navigationTitle(editingId == nil ? "添加报价" : "编辑报价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showForm = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveItem(); showForm = false }
                        .disabled(!canSaveQuoteForm)
                }
                KeyboardNavigationToolbar(
                    focusedField: $quoteFormFocusedField,
                    fields: [.price, .quantity, .contractAmount, .taxRate, .discountRate]
                )
            }
        }
    }

    private var generateQuoteForm: some View {
        NavigationStack {
            Form {
                Section("范围") {
                    Picker("选择工程", selection: $generateProjectId) {
                        Text("全部未分项目").tag(nil as UUID?)
                        ForEach(store.projects) { p in
                            Text(p.name).tag(p.id as UUID?)
                        }
                    }
                }
                Section("默认价格") {
                    LabeledContent("材料默认单价") {
                        TextField("留空表示待补", text: $defaultMaterialPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($generateQuoteFocusedField, equals: .materialPrice)
                    }
                    LabeledContent("人工单价 ¥/工时") {
                        TextField("120", text: $defaultLaborRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($generateQuoteFocusedField, equals: .laborRate)
                    }
                }
                Section("费率") {
                    LabeledContent("税率 %") {
                        TextField("0", text: $generateTax)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($generateQuoteFocusedField, equals: .taxRate)
                    }
                    LabeledContent("折扣 %") {
                        TextField("0", text: $generateDiscount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($generateQuoteFocusedField, equals: .discountRate)
                    }
                }
                Section {
                    Button("生成报价") {
                        generateQuoteItems()
                        showGenerateSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("生成报价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showGenerateSheet = false }
                }
                KeyboardNavigationToolbar(
                    focusedField: $generateQuoteFocusedField,
                    fields: [.materialPrice, .laborRate, .taxRate, .discountRate]
                )
            }
        }
    }

    private func openAdd() {
        editingId = nil
        formName = ""; formUnit = "项"; formPrice = ""; formQty = ""; formNotes = ""; formTax = "0"; formDiscount = "0"
        formVersionName = "V1"; formStatus = .draft; formCustomerConfirmedDate = ""; formContractAmount = ""
        formProjectId = nil
        showForm = true
    }

    private func openEdit(_ item: QuoteItem) {
        editingId = item.id
        formName = item.name; formUnit = item.unit; formPrice = item.unitPrice; formQty = item.quantity
        formNotes = item.notes; formTax = item.taxRate; formDiscount = item.discountRate
        formVersionName = item.versionName
        formStatus = item.status
        formCustomerConfirmedDate = item.customerConfirmedDate
        formContractAmount = item.contractAmount
        formProjectId = item.projectId
        showForm = true
    }

    private func openFocusedQuoteIfNeeded() {
        guard let focusedQuoteId, !didOpenFocusedQuote,
              let item = store.quoteItems.first(where: { $0.id == focusedQuoteId }) else { return }
        didOpenFocusedQuote = true
        searchText = ""
        projectFilter = item.projectId
        statusFilter = nil
        Task { @MainActor in
            openEdit(item)
        }
    }

    private func saveItem() {
        guard canSaveQuoteForm else { return }
        let newItem = QuoteItem(
            id: editingId ?? UUID(),
            name: formName, unitPrice: formPrice, quantity: formQty, unit: formUnit,
            notes: formNotes, taxRate: formTax, discountRate: formDiscount,
            versionName: formVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : formVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
            status: formStatus,
            customerConfirmedDate: formCustomerConfirmedDate.trimmingCharacters(in: .whitespacesAndNewlines),
            contractAmount: formContractAmount,
            projectId: formProjectId
        )
        if let eid = editingId, let idx = store.quoteItems.firstIndex(where: { $0.id == eid }) {
            store.quoteItems[idx] = newItem
        } else {
            store.quoteItems.append(newItem)
        }
        store.scheduleSave()
        operationMessage = editingId == nil ? "已新增报价" : "已更新报价"
    }

    private func applyQuotationTemplate(_ template: ProjectTemplate) {
        guard let line = template.content.split(separator: "\n").first else { return }
        let parts = line.split(separator: "¥").map { $0.trimmingCharacters(in: .whitespaces) }
        formName = parts.first ?? template.name
        let pricePart = parts.count > 1 ? parts[1] : ""
        formPrice = pricePart.filter { "0123456789.".contains($0) }
        if formPrice.isEmpty { formPrice = "0" }
        if formQty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formQty = "1" }
        if formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formUnit = "项" }
        if formNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formNotes = "模板导入" }
    }

    private func generateQuoteItems() {
        let materials = store.materialItems.filter { $0.projectId == generateProjectId }
        let labor = store.laborRecords.filter { $0.projectId == generateProjectId }
        for material in materials {
            store.quoteItems.append(QuoteItem(
                name: material.name,
                unitPrice: defaultMaterialPrice,
                quantity: material.quantity,
                unit: material.unit,
                notes: "材料清单导入",
                taxRate: generateTax,
                discountRate: generateDiscount,
                versionName: "V1",
                status: .draft,
                projectId: material.projectId
            ))
        }
        for record in labor {
            let workers = firstNumber(in: record.workers)
            let hours = firstNumber(in: record.hours)
            let quantity = workers > 0 ? workers * hours : hours
            let laborPrice = defaultLaborRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.unitRate : defaultLaborRate
            store.quoteItems.append(QuoteItem(
                name: "人工费 \(record.date)",
                unitPrice: laborPrice,
                quantity: quantity > 0 ? trim(quantity) : record.hours,
                unit: "工时",
                notes: record.note,
                taxRate: generateTax,
                discountRate: generateDiscount,
                versionName: "V1",
                status: .draft,
                projectId: record.projectId
            ))
        }
        store.scheduleSave()
        operationMessage = "已从材料/人工生成报价"
    }

    private func exportQuotationPDF() {
        let meta = quotationDocumentMeta()
        let data = ReportBuilder.makeQuotationPDF(title: "报价单", items: filtered, projects: store.projects, meta: meta)
        exportPayload = ExportPayload(data: data, contentType: .pdf, defaultFilename: "报价单.pdf")
        AppHaptics.impact(.light)
        showExporter = true
    }

    private func exportQuotationExcel() {
        let meta = quotationDocumentMeta()
        let data = ReportBuilder.makeQuotationExcelHTML(
            title: "报价单",
            items: filtered,
            projects: store.projects,
            meta: meta
        )
        exportPayload = ExportPayload(data: data, contentType: .excelHTML, defaultFilename: "报价单表格.xls")
        AppHaptics.impact(.light)
        showExporter = true
    }

    private func performQuotationExport() {
        switch quoteExportFormat {
        case .pdf:
            exportQuotationPDF()
        case .excel:
            exportQuotationExcel()
        }
    }

    private func quotationDocumentMeta() -> QuotationDocumentMeta {
        let validUntil = Formatters.date.string(
            from: Calendar.current.date(byAdding: .day, value: max(1, quoteValidityDays), to: Date()) ?? Date()
        )
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = companyPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = companyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuotationDocumentMeta(
            companyName: company.isEmpty ? "未填写" : company,
            companyPhone: phone.isEmpty ? "未填写" : phone,
            companyAddress: address.isEmpty ? "未填写" : address,
            customerName: quoteCustomerName.isEmpty ? "未填写" : quoteCustomerName,
            projectAddress: quoteProjectAddress.isEmpty ? "未填写" : quoteProjectAddress,
            validUntil: validUntil,
            signerName: quoteSignerName.isEmpty ? "项目负责人" : quoteSignerName
        )
    }

    private var quotationExportForm: some View {
        NavigationStack {
            Form {
                Section("客户信息") {
                    TextField("客户名称", text: $quoteCustomerName)
                    TextField("项目地址", text: $quoteProjectAddress, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("签字人", text: $quoteSignerName)
                }
                Section("公司信息") {
                    TextField("公司名称", text: $companyName)
                    TextField("公司电话", text: $companyPhone)
                        .keyboardType(.phonePad)
                    TextField("公司地址", text: $companyAddress, axis: .vertical)
                        .lineLimit(2...4)
                    LabeledContent("有效期", value: "\(quoteValidityDays) 天")
                    if !isCompanyProfileComplete {
                        Text("请补全公司信息后再导出。")
                            .font(.caption)
                            .foregroundStyle(.appWarning)
                    }
                }
                Section("导出格式") {
                    Picker("格式", selection: $quoteExportFormat) {
                        ForEach(QuotationExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("导出\(quoteExportFormat.displayName)") {
                        showQuoteExportSheet = false
                        performQuotationExport()
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(filtered.isEmpty || (quoteExportFormat == .pdf && !isCompanyProfileComplete))
                }
            }
            .navigationTitle("报价单模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showQuoteExportSheet = false }
                }
            }
        }
    }

    private func openQuotationExportSheet() {
        if let project = singleProjectInFiltered() {
            quoteProjectAddress = project.location
        }
        if quoteSignerName.isEmpty {
            quoteSignerName = "项目负责人"
        }
        if !isCompanyProfileComplete {
            showCompanyInfoPrompt = true
        }
        showQuoteExportSheet = true
    }

    private func singleProjectInFiltered() -> Project? {
        let ids = Set(filtered.compactMap(\.projectId))
        guard ids.count == 1, let id = ids.first else { return nil }
        return store.projects.first(where: { $0.id == id })
    }

    private func firstNumber(in text: String) -> Double {
        DataValueParser.double(from: text)
    }

    private func trim(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private var projectQuoteSummaries: [(name: String, total: Double)] {
        var rows: [(name: String, total: Double)] = []
        for project in store.projects {
            let total = store.quoteItems
                .filter { $0.projectId == project.id }
                .reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) }
            if total > 0 { rows.append((project.name, total)) }
        }
        let unassigned = store.quoteItems
            .filter { $0.projectId == nil }
            .reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) }
        if unassigned > 0 { rows.append(("未归属", unassigned)) }
        return rows
    }

    private var canSaveQuoteForm: Bool {
        !formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputValidator.nonNegativeNumber(formPrice) &&
        InputValidator.nonNegativeNumber(formQty) &&
        (formContractAmount.isEmpty || InputValidator.nonNegativeNumber(formContractAmount))
    }

    private func statusColor(_ status: QuoteStatus) -> Color {
        switch status {
        case .draft: return .secondary
        case .sent: return .appWarning
        case .confirmed: return .appSuccess
        }
    }

    private var isCompanyProfileComplete: Bool {
        !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !companyPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !companyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyGrandTotalToProjectContract() {
        guard let pid = projectFilter, let projectIndex = store.projects.firstIndex(where: { $0.id == pid }) else { return }
        store.projects[projectIndex].contractAmount = String(format: "%.2f", grandTotalValue.doubleValue)
        store.scheduleSave()
        operationMessage = "已同步到项目合同金额"
    }
}

private enum QuoteStatusChip: CaseIterable, Hashable {
    case all
    case draft
    case sent
    case confirmed

    init(status: QuoteStatus?) {
        switch status {
        case .draft: self = .draft
        case .sent: self = .sent
        case .confirmed: self = .confirmed
        case nil: self = .all
        }
    }

    var status: QuoteStatus? {
        switch self {
        case .all: return nil
        case .draft: return .draft
        case .sent: return .sent
        case .confirmed: return .confirmed
        }
    }

    var title: String {
        switch self {
        case .all: return "全部"
        case .draft: return "草稿"
        case .sent: return "已发送"
        case .confirmed: return "已确认"
        }
    }
}
