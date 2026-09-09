import SwiftUI
import Foundation

enum LaborQuoteGenerator {
    static func makeQuoteItem(
        from record: LaborRecord,
        defaultRate: String,
        taxRate: String,
        discountRate: String
    ) -> QuoteItem? {
        guard let quoteUnit = record.workloadUnit.quoteUnit else { return nil }
        let rate = defaultRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? record.unitRate
            : NumericInputSupport.normalizedStorageText(defaultRate, kind: .laborRate)
        return QuoteItem(
            name: String(format: String(localized: "人工费 %@"), record.date),
            unitPrice: rate,
            quantity: trim(record.totalWorkloadValue.doubleValue),
            unit: quoteUnit,
            notes: record.note,
            taxRate: NumericInputSupport.normalizedStorageText(taxRate, kind: .taxRate),
            discountRate: NumericInputSupport.normalizedStorageText(discountRate, kind: .discountRate),
            versionName: "V1",
            status: .draft,
            projectId: record.projectId
        )
    }

    private static func trim(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_000_1 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

extension QuotationView {
    func appendQuote(from material: MaterialItem) {
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

    func openAdd() {
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

    func openEdit(_ item: QuoteItem) {
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

    func openFocusedQuoteIfNeeded() {
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

    func saveItem() {
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

    func applyQuotationTemplate(_ template: ProjectTemplate) {
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

    func generateQuoteItems() {
        let materials = store.materialItems.filter { $0.projectId == generateProjectId }
        let labor = store.laborRecords.filter { $0.projectId == generateProjectId }
        let unconfirmedCount = labor.filter { $0.workloadUnit == .legacyUnspecified }.count
        guard unconfirmedCount == 0 else {
            operationNotice = .info(String(
                format: String(localized: "有 %lld 条人工记录待确认计量单位，请先编辑确认后再生成报价。"),
                Int64(unconfirmedCount)
            ))
            return
        }
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
            guard let quote = LaborQuoteGenerator.makeQuoteItem(
                from: record,
                defaultRate: defaultLaborRate,
                taxRate: generateTax,
                discountRate: generateDiscount
            ) else { continue }
            store.appendQuoteItem(quote)
        }
        store.scheduleSave()
        operationNotice = .info(String(localized: "已从材料/人工生成报价"))
    }

    func exportQuotationPDF() {
        let meta = quotationDocumentMeta()
        let data = ReportBuilder.makeQuotationPDF(title: String(localized: "报价单"), items: filtered, projects: store.projects, meta: meta)
        exportPayload = ExportPayload(data: data, contentType: .pdf, defaultFilename: String(localized: "报价单.pdf"))
        AppHaptics.impact(.light)
        showExporter = true
    }

    func quotationDocumentMeta() -> QuotationDocumentMeta {
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

    func openQuotationExportSheet() {
        if let project = singleProjectInFiltered() {
            quoteProjectAddress = project.location
        }
        if quoteSignerName.isEmpty {
            quoteSignerName = String(localized: "项目负责人")
        }
        activeSheet = .export
    }

    func applyGrandTotalToProjectContract() {
        guard let pid = projectFilter, let projectIndex = store.projects.firstIndex(where: { $0.id == pid }) else { return }
        var project = store.projects[projectIndex]
        project.contractAmount = String(format: "%.2f", grandTotalValue.doubleValue)
        guard store.updateProject(project) else { return }
        store.scheduleSave()
        operationNotice = .info(String(localized: "已同步到项目合同金额"))
    }

    func deleteQuotesWithUndo(ids: [UUID]) {
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

    func flushPendingQuoteDeletionIfNeeded() {
        undoableDeletion.flushPendingCommit()
    }
}
