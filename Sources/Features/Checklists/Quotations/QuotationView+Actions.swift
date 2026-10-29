import SwiftUI
import Foundation

enum LaborQuoteGenerator {
    static func makeQuoteItem(
        from record: LaborRecord,
        defaultRate: MoneyValue,
        taxRate: QuantityValue,
        discountRate: QuantityValue
    ) -> QuoteItem? {
        guard let quoteUnit = record.workloadUnit.quoteUnit else { return nil }
        let rate = defaultRate.isEmpty
            ? record.unitRate
            : defaultRate
        return QuoteItem(
            name: String(format: AppLocalization.string("人工费 %@"), record.date.storageText),
            unitPrice: rate,
            quantity: record.totalWorkload,
            unit: quoteUnit,
            notes: record.note,
            taxRate: taxRate,
            discountRate: discountRate,
            versionName: "V1",
            status: .draft,
            projectId: record.projectId
        )
    }
}

extension QuotationView {
    func saveBusinessQuoteVersion(_ version: String?, project: Project) {
        guard !isSavingBusinessQuoteVersion else { return }
        isSavingBusinessQuoteVersion = true
        Task { @MainActor in
            defer { isSavingBusinessQuoteVersion = false }
            do {
                try await ProjectBusinessQuoteSelectionService.save(
                    version: version,
                    projectID: project.id,
                    expectedSelection: project.businessQuoteVersion,
                    store: store,
                    quotes: { store.quoteItems }
                )
                operationNotice = .info(AppLocalization.string("quote_business_selection_saved"))
            } catch {
                operationNotice = .info(error.localizedDescription)
            }
        }
    }

    func appendQuote(from material: MaterialItem) {
        store.appendQuoteItem(MaterialQuoteGenerator.makeQuoteItem(from: material, mode: .leaveUnpriced))
        store.scheduleSave()
    }

    func openAdd() {
        editingId = nil
        formName = ""
        formUnit = AppLocalization.string("项")
        formPrice = ""
        formQty = ""
        formNotes = ""
        formTax = "0"
        formDiscount = "0"
        formVersionName = "V1"
        formStatus = .draft
        formCustomerConfirmedDate = .empty
        formContractAmount = ""
        formProjectId = nil
        activeSheet = .edit
    }

    func openEdit(_ item: QuoteItem) {
        editingId = item.id
        formName = item.name
        formUnit = item.unit
        formPrice = item.unitPrice.wireText
        formQty = item.quantity.wireText
        formNotes = item.notes
        formTax = item.taxRate.wireText
        formDiscount = item.discountRate.wireText
        formVersionName = item.versionName
        formStatus = item.status
        formCustomerConfirmedDate = item.customerConfirmedDate
        formContractAmount = item.contractAmount.wireText
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
            unitPrice: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(formPrice, kind: .amount)),
            quantity: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(formQty, kind: .quantity)),
            unit: formUnit,
            notes: formNotes,
            taxRate: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(formTax, kind: .taxRate)),
            discountRate: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(formDiscount, kind: .discountRate)),
            versionName: formVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : formVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
            status: formStatus,
            customerConfirmedDate: formCustomerConfirmedDate,
            contractAmount: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(formContractAmount, kind: .amount)),
            projectId: formProjectId
        )
        if editingId != nil, store.updateQuoteItem(newItem) {
        } else {
            store.appendQuoteItem(newItem)
        }
        store.scheduleSave()
        operationNotice = .info(editingId == nil ? AppLocalization.string("已新增报价") : AppLocalization.string("已更新报价"))
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
        if formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formUnit = AppLocalization.string("项") }
        if formNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { formNotes = AppLocalization.string("模板导入") }
    }

    func generateQuoteItems() {
        let materials = store.materialItems.filter { $0.projectId == generateProjectId }
        let labor = store.laborRecords.filter { $0.projectId == generateProjectId }
        guard materials.isEmpty || materialQuotePriceMode != nil else { return }
        let resolvedMaterialPriceMode = materialQuotePriceMode ?? .leaveUnpriced
        let unconfirmedCount = labor.filter { $0.workloadUnit == .legacyUnspecified }.count
        guard unconfirmedCount == 0 else {
            operationNotice = .info(String(
                format: AppLocalization.string("有 %lld 条人工记录待确认计量单位，请先编辑确认后再生成报价。"),
                Int64(unconfirmedCount)
            ))
            return
        }
        for material in materials {
            store.appendQuoteItem(MaterialQuoteGenerator.makeQuoteItem(
                from: material,
                mode: resolvedMaterialPriceMode,
                overridePrice: NumericInputSupport.money(defaultMaterialPrice),
                taxRate: NumericInputSupport.quantity(generateTax),
                discountRate: NumericInputSupport.quantity(generateDiscount)
            ))
        }
        for record in labor {
            guard let quote = LaborQuoteGenerator.makeQuoteItem(
                from: record,
                defaultRate: NumericInputSupport.money(defaultLaborRate),
                taxRate: NumericInputSupport.quantity(generateTax),
                discountRate: NumericInputSupport.quantity(generateDiscount)
            ) else { continue }
            store.appendQuoteItem(quote)
        }
        store.scheduleSave()
        operationNotice = .info(AppLocalization.string("已从材料/人工生成报价"))
    }

    func exportQuotationPDF() {
        let meta = quotationDocumentMeta()
        let data = ReportBuilder.makeQuotationPDF(title: AppLocalization.string("报价单"), items: filtered, projects: store.projects, meta: meta)
        exportPayload = ExportPayload(data: data, contentType: .pdf, defaultFilename: AppLocalization.string("报价单.pdf"))
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
            companyName: company.isEmpty ? AppLocalization.string("未填写") : company,
            companyPhone: phone.isEmpty ? AppLocalization.string("未填写") : phone,
            companyAddress: address.isEmpty ? AppLocalization.string("未填写") : address,
            customerName: quoteCustomerName.isEmpty ? AppLocalization.string("未填写") : quoteCustomerName,
            projectAddress: quoteProjectAddress.isEmpty ? AppLocalization.string("未填写") : quoteProjectAddress,
            validUntil: validUntil,
            signerName: quoteSignerName.isEmpty ? AppLocalization.string("项目负责人") : quoteSignerName
        )
    }

    func openQuotationExportSheet() {
        if let project = singleProjectInFiltered() {
            quoteProjectAddress = project.location
        }
        if quoteSignerName.isEmpty {
            quoteSignerName = AppLocalization.string("项目负责人")
        }
        activeSheet = .export
    }

    func openContractWriteSheet() {
        guard let projectId = projectFilter,
              let firstVersion = QuotationContractWritePlanner.confirmedVersions(
                  projectId: projectId,
                  quotes: store.quoteItems
              ).first else {
            operationNotice = .info(AppLocalization.string("当前工程没有可写入合同的已确认报价。"))
            return
        }
        contractWriteVersion = firstVersion
        refreshContractWritePlan(versionName: firstVersion)
        activeSheet = .contractWrite
    }

    func refreshContractWritePlan(versionName: String) {
        guard let projectId = projectFilter,
              let project = store.projects.first(where: { $0.id == projectId }) else {
            contractWritePlan = nil
            return
        }
        contractWritePlan = QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: versionName,
            quotes: store.quoteItems
        )
        contractWriteRefreshMessage = ""
    }

    @discardableResult
    func applyContractWritePlan(versionName: String) -> Bool {
        guard let projectId = projectFilter,
              let projectIndex = store.projects.firstIndex(where: { $0.id == projectId }) else { return false }
        guard let currentPlan = QuotationContractWritePlanner.makePlan(
            project: store.projects[projectIndex],
            versionName: versionName,
            quotes: store.quoteItems
        ) else {
            contractWritePlan = nil
            contractWriteRefreshMessage = AppLocalization.string("所选报价版本已变化或不再是已确认状态，请重新选择。"
            )
            return false
        }
        guard let previewPlan = contractWritePlan, currentPlan == previewPlan else {
            contractWritePlan = currentPlan
            contractWriteRefreshMessage = AppLocalization.string("报价数据已变化，预览已刷新。请核对后再次确认。")
            return false
        }
        guard currentPlan.canApply else { return false }
        var project = store.projects[projectIndex]
        project.contractAmount = currentPlan.newAmount
        guard store.updateProject(project) else { return false }
        store.scheduleSave()
        operationNotice = .info(AppLocalization.string("已同步到项目合同金额"))
        contractWritePlan = nil
        contractWriteRefreshMessage = ""
        return true
    }

    func deleteQuotesWithUndo(ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        let targets = store.quoteItems.filter { idSet.contains($0.id) }
        guard !targets.isEmpty else { return }
        let deletion = store.removeQuoteItems(
            ids: idSet,
            audit: DataStoreDeletionAuditContext(
                summary: AppLocalization.string("删除报价"),
                detail: ListFormatter.localizedString(byJoining: targets.map(\.name)),
                source: "QuotationView"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: AppLocalization.string("已删除 %lld 条报价"), Int64(deletion.deletedCount)),
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
