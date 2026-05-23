import SwiftUI
import Foundation

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
