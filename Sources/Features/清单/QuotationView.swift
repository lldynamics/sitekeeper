import SwiftUI
import Foundation

struct QuotationView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.companyName) private var companyName = ""
    @AppStorage(UserPreferenceKeys.companyPhone) private var companyPhone = ""
    @AppStorage(UserPreferenceKeys.companyAddress) private var companyAddress = ""
    @AppStorage(UserPreferenceKeys.quoteValidityDays) private var quoteValidityDays = 15
    let focusedQuoteId: UUID?
    @State private var searchText = ""
    @State private var projectFilter: UUID?
    @State private var statusFilter: QuoteStatus?
    @State private var activeSheet: QuotationSheetRoute?
    @State private var editingId: UUID?
    @State private var didOpenFocusedQuote = false

    // 表单字段
    @State private var formName = ""
    @State private var formUnit = String(localized: "项")
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
    @State private var showQuoteDeleteConfirm = false
    @State private var generateProjectId: UUID?
    @State private var defaultMaterialPrice = ""
    @State private var defaultLaborRate = "120"
    @State private var generateTax = "0"
    @State private var generateDiscount = "0"
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var quoteCustomerName = ""
    @State private var quoteProjectAddress = ""
    @State private var quoteSignerName = String(localized: "项目负责人")
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
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
            QuotationScopeSection(
                projects: store.projects,
                projectFilter: $projectFilter,
                statusChipBinding: statusChipBinding,
                projectQuoteSummaries: projectQuoteSummaries
            )

            QuotationItemsSection(
                items: filtered,
                projects: store.projects,
                statusColor: statusColor(_:),
                onEdit: openEdit(_:),
                onDelete: { idx in
                    let ids = idx.map { filtered[$0].id }
                    deleteQuotesWithUndo(ids: ids)
                }
            )

            QuotationTotalsSection(
                subtotalBeforeValue: subtotalBeforeValue,
                totalTaxValue: totalTaxValue,
                totalDiscountValue: totalDiscountValue,
                grandTotalValue: grandTotalValue
            )
        }
        .searchable(text: $searchText, prompt: String(localized: "搜索报价名称"))
        .navigationTitle(String(localized: "预结算信息"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                QuotationToolbarMenu(
                    materialItems: store.materialItems,
                    onOpenGenerate: {
                        activeSheet = .generate
                    },
                    onOpenExport: {
                        openQuotationExportSheet()
                    },
                    onAppendFromMaterial: { material in
                        appendQuote(from: material)
                    }
                )
                Button { openAdd() } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel(String(localized: "新建报价"))
            }
            if let projectFilter, store.projects.contains(where: { $0.id == projectFilter }) {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "写入合同")) {
                        applyGrandTotalToProjectContract()
                    }
                    .accessibilityLabel(String(localized: "将当前筛选报价合计写入项目合同金额"))
                }
            }
        }
        .sheet(item: $activeSheet) { route in
            switch route {
            case .edit:
                quoteForm
            case .generate:
                generateQuoteForm
            case .export:
                quotationExportForm
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .pdf,
            defaultFilename: exportPayload?.defaultFilename ?? String(localized: "报价单.pdf")
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
        .onAppear(perform: openFocusedQuoteIfNeeded)
        .onDisappear {
            flushPendingQuoteDeletionIfNeeded()
        }
        .operationToast(notice: $operationNotice)
    }

    // MARK: - Form

    private var quoteForm: some View {
        QuotationEditSheetView(
            isEditing: editingId != nil,
            canSaveQuoteForm: canSaveQuoteForm,
            validationMessages: quoteFormValidationMessages,
            templates: store.templates,
            projects: store.projects,
            formName: $formName,
            formUnit: $formUnit,
            formPrice: $formPrice,
            formQty: $formQty,
            formNotes: $formNotes,
            formTax: $formTax,
            formDiscount: $formDiscount,
            formVersionName: $formVersionName,
            formStatus: $formStatus,
            formCustomerConfirmedDate: $formCustomerConfirmedDate,
            formContractAmount: $formContractAmount,
            formProjectId: $formProjectId,
            focusedField: $quoteFormFocusedField,
            showQuoteDeleteConfirm: $showQuoteDeleteConfirm,
            onApplyTemplate: applyQuotationTemplate(_:),
            onCancel: { activeSheet = nil },
            onSave: {
                saveItem()
                activeSheet = nil
            },
            onDelete: {
                if let editingId {
                    deleteQuotesWithUndo(ids: [editingId])
                    activeSheet = nil
                }
            }
        )
    }

    private var generateQuoteForm: some View {
        QuotationGenerateSheetView(
            projects: store.projects,
            generateProjectId: $generateProjectId,
            defaultMaterialPrice: $defaultMaterialPrice,
            defaultLaborRate: $defaultLaborRate,
            generateTax: $generateTax,
            generateDiscount: $generateDiscount,
            focusedField: $generateQuoteFocusedField,
            canGenerateQuoteForm: canGenerateQuoteForm,
            onCancel: { activeSheet = nil },
            onGenerate: {
                generateQuoteItems()
                activeSheet = nil
            }
        )
    }

    private var quotationExportForm: some View {
        QuotationExportSheetView(
            quoteCustomerName: $quoteCustomerName,
            quoteProjectAddress: $quoteProjectAddress,
            quoteSignerName: $quoteSignerName,
            companyName: $companyName,
            companyPhone: $companyPhone,
            companyAddress: $companyAddress,
            quoteValidityDays: quoteValidityDays,
            isCompanyProfileComplete: isCompanyProfileComplete,
            isPrimaryActionDisabled: filtered.isEmpty || !isCompanyProfileComplete,
            onCancel: { activeSheet = nil },
            onExport: {
                activeSheet = nil
                exportQuotationPDF()
            }
        )
    }

    private func appendQuote(from material: MaterialItem) {
        store.appendQuoteItem(
            QuoteItem(
                name: material.name,
                unitPrice: "",
                quantity: material.quantity,
                unit: material.unit,
                notes: "",
                taxRate: "0",
                discountRate: "0",
                projectId: material.projectId
            )
        )
        store.scheduleSave()
    }

    private func openAdd() {
        editingId = nil
        formName = ""
        formUnit = String(localized: "项")
        formPrice = ""
        formQty = ""
        formNotes = ""
        formTax = "0"
        formDiscount = "0"
        formVersionName = "V1"
        formStatus = .draft
        formCustomerConfirmedDate = ""
        formContractAmount = ""
        formProjectId = nil
        activeSheet = .edit
    }

    private func openEdit(_ item: QuoteItem) {
        editingId = item.id
        formName = item.name
        formUnit = item.unit
        formPrice = item.unitPrice
        formQty = item.quantity
        formNotes = item.notes
        formTax = item.taxRate
        formDiscount = item.discountRate
        formVersionName = item.versionName
        formStatus = item.status
        formCustomerConfirmedDate = item.customerConfirmedDate
        formContractAmount = item.contractAmount
        formProjectId = item.projectId
        activeSheet = .edit
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
            name: formName,
            unitPrice: NumericInputSupport.normalizedStorageText(formPrice, kind: .amount),
            quantity: NumericInputSupport.normalizedStorageText(formQty, kind: .quantity),
            unit: formUnit,
            notes: formNotes,
            taxRate: NumericInputSupport.normalizedStorageText(formTax, kind: .taxRate),
            discountRate: NumericInputSupport.normalizedStorageText(formDiscount, kind: .discountRate),
            versionName: formVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : formVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
            status: formStatus,
            customerConfirmedDate: ProjectDateInput.normalizedStorageText(formCustomerConfirmedDate),
            contractAmount: NumericInputSupport.normalizedStorageText(formContractAmount, kind: .amount),
            projectId: formProjectId
        )
        if editingId != nil, store.updateQuoteItem(newItem) {
        } else {
            store.appendQuoteItem(newItem)
        }
        store.scheduleSave()
        operationNotice = .info(editingId == nil ? String(localized: "已新增报价") : String(localized: "已更新报价"))
    }

    private func applyQuotationTemplate(_ template: ProjectTemplate) {
        guard let line = template.content
            .split(separator: "\n")
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else { return }
        let parsed = NumericInputSupport.parseQuotationTemplateLine(line, defaultPrice: "0")
        formName = parsed.name.isEmpty ? template.name : parsed.name
        formPrice = parsed.price
        if let parsedUnit = parsed.unit, !parsedUnit.isEmpty {
            formUnit = parsedUnit
        }
        if formQty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formQty = "1" }
        if formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formUnit = String(localized: "项") }
        if formNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formNotes = String(localized: "模板导入") }
    }

    private func generateQuoteItems() {
        let materials = store.materialItems.filter { $0.projectId == generateProjectId }
        let labor = store.laborRecords.filter { $0.projectId == generateProjectId }
        for material in materials {
            store.appendQuoteItem(QuoteItem(
                name: material.name,
                unitPrice: NumericInputSupport.normalizedStorageText(defaultMaterialPrice, kind: .amount),
                quantity: material.quantity,
                unit: material.unit,
                notes: String(localized: "材料清单导入"),
                taxRate: NumericInputSupport.normalizedStorageText(generateTax, kind: .taxRate),
                discountRate: NumericInputSupport.normalizedStorageText(generateDiscount, kind: .discountRate),
                versionName: "V1",
                status: .draft,
                projectId: material.projectId
            ))
        }
        for record in labor {
            let workers = firstNumber(in: record.workers)
            let hours = firstNumber(in: record.hours)
            let quantity = workers > 0 ? workers * hours : hours
            let laborPrice = defaultLaborRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? record.unitRate
            : NumericInputSupport.normalizedStorageText(defaultLaborRate, kind: .laborRate)
            store.appendQuoteItem(QuoteItem(
                name: String(format: String(localized: "人工费 %@"), record.date),
                unitPrice: laborPrice,
                quantity: quantity > 0 ? trim(quantity) : record.hours,
                unit: String(localized: "工时"),
                notes: record.note,
                taxRate: NumericInputSupport.normalizedStorageText(generateTax, kind: .taxRate),
                discountRate: NumericInputSupport.normalizedStorageText(generateDiscount, kind: .discountRate),
                versionName: "V1",
                status: .draft,
                projectId: record.projectId
            ))
        }
        store.scheduleSave()
        operationNotice = .info(String(localized: "已从材料/人工生成报价"))
    }

    private func exportQuotationPDF() {
        let meta = quotationDocumentMeta()
        let data = ReportBuilder.makeQuotationPDF(title: String(localized: "报价单"), items: filtered, projects: store.projects, meta: meta)
        exportPayload = ExportPayload(data: data, contentType: .pdf, defaultFilename: String(localized: "报价单.pdf"))
        AppHaptics.impact(.light)
        showExporter = true
    }

    private func quotationDocumentMeta() -> QuotationDocumentMeta {
        let validUntil = Formatters.date.string(
            from: Calendar.current.date(byAdding: .day, value: max(1, quoteValidityDays), to: Date()) ?? Date()
        )
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = companyPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = companyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuotationDocumentMeta(
            companyName: company.isEmpty ? String(localized: "未填写") : company,
            companyPhone: phone.isEmpty ? String(localized: "未填写") : phone,
            companyAddress: address.isEmpty ? String(localized: "未填写") : address,
            customerName: quoteCustomerName.isEmpty ? String(localized: "未填写") : quoteCustomerName,
            projectAddress: quoteProjectAddress.isEmpty ? String(localized: "未填写") : quoteProjectAddress,
            validUntil: validUntil,
            signerName: quoteSignerName.isEmpty ? String(localized: "项目负责人") : quoteSignerName
        )
    }

    private func openQuotationExportSheet() {
        if let project = singleProjectInFiltered() {
            quoteProjectAddress = project.location
        }
        if quoteSignerName.isEmpty {
            quoteSignerName = String(localized: "项目负责人")
        }
        activeSheet = .export
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
        if unassigned > 0 { rows.append((String(localized: "未归属"), unassigned)) }
        return rows
    }

    private var canSaveQuoteForm: Bool {
        !formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputValidator.validate(formPrice, kind: .amount, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(formQty, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(formTax, kind: .taxRate, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(formDiscount, kind: .discountRate, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(formContractAmount, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    private var quoteFormValidationMessages: [String] {
        var messages: [String] = []
        if formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(String(localized: "请填写报价名称"))
        }
        if formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(String(localized: "请填写报价单位"))
        }
        return messages
    }

    private var canGenerateQuoteForm: Bool {
        InputValidator.validate(defaultMaterialPrice, kind: .amount, requirement: .optionalNonNegative).isValid &&
        InputValidator.validate(defaultLaborRate, kind: .laborRate, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(generateTax, kind: .taxRate, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(generateDiscount, kind: .discountRate, requirement: .requiredNonNegative).isValid
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
        var project = store.projects[projectIndex]
        project.contractAmount = String(format: "%.2f", grandTotalValue.doubleValue)
        guard store.updateProject(project) else { return }
        store.scheduleSave()
        operationNotice = .info(String(localized: "已同步到项目合同金额"))
    }

    private func deleteQuotesWithUndo(ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        let targets = store.quoteItems.filter { idSet.contains($0.id) }
        guard !targets.isEmpty else { return }
        let deletion = store.removeQuoteItems(
            ids: idSet,
            audit: DataStoreDeletionAuditContext(
                summary: String(localized: "删除报价"),
                detail: ListFormatter.localizedString(byJoining: targets.map(\.name)),
                source: "QuotationView"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条报价"), Int64(deletion.deletedCount)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreQuoteItems(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func flushPendingQuoteDeletionIfNeeded() {
        undoableDeletion.flushPendingCommit()
    }
}
