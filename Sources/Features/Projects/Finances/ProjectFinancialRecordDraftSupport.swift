import SwiftUI

extension ProjectFinancialRecordAddSheet {
    var draftStore: BusinessDraftStore { .scoped(to: store.storeURL) }
    var draftKey: BusinessDraftStore.Key { .finance(projectID: projectId) }
    var formDraft: FinancialFormDraft {
        FinancialFormDraft(recordID: draftRecordID, date: date, direction: direction, category: category,
            amount: amount, counterparty: counterparty, invoiceNumber: invoiceNumber, status: status,
            hasDueDate: hasDueDate, dueDateText: dueDate.storageText, reminderStatus: reminderStatus, note: note,
            scanAfterSave: scanAfterSave)
    }

    func loadDraft() {
        guard !draftLoaded else { return }
        do {
            if let saved = try draftStore.load(FinancialFormDraft.self, key: draftKey) {
                restore(saved)
            } else if let preset { apply(record: preset) }
            draftLoaded = true
        } catch { draftError = String(format: AppLocalization.string("读取草稿失败，原文件已保留：%@"), error.localizedDescription) }
    }

    func restore(_ value: FinancialFormDraft) {
        draftRecordID = value.recordID
        date = value.date
        direction = value.direction
        category = value.category
        amount = value.amount
        counterparty = value.counterparty
        invoiceNumber = value.invoiceNumber
        status = value.status
        hasDueDate = value.hasDueDate
        dueDate = BusinessDateValue(legacyText: value.dueDateText)
        reminderStatus = value.reminderStatus
        note = value.note
        scanAfterSave = value.scanAfterSave
        pendingRestoration = nil
    }

    func persistDraft() {
        guard draftLoaded, !draftCompleted, !isSaving, pendingRestoration == nil else { return }
        do {
            try draftStore.save(formDraft, key: draftKey)
            draftError = nil
        } catch { draftError = String(format: AppLocalization.string("草稿保存失败，请保留此页面并重试：%@"), error.localizedDescription) }
    }

    var draftSection: some View {
        Section {
            if let draftError { Text(draftError).foregroundStyle(.red) } else { Text(AppLocalization.string("自动保留草稿，关闭后可继续填写。")).foregroundStyle(.secondary) }
            if store.projectFinancialRecords.contains(where: { $0.id == draftRecordID }) {
                Text(AppLocalization.string("这份草稿对应的记录已保存，请丢弃草稿或作为新记录继续。"))
                Button(AppLocalization.string("作为新记录继续")) { draftRecordID = UUID()
                persistDraft() }
            }
            if isSaving { ProgressView(AppLocalization.string("正在保存，请稍候…")) }
            if let pendingRestoration {
                Text(AppLocalization.string("恢复草稿只会填入表单；请核对当前记录后再保存。"))
                Button(AppLocalization.string("恢复草稿")) { restore(pendingRestoration) }
                    .accessibilityIdentifier("finance-restore-draft")
                Button(AppLocalization.string("保留当前记录并丢弃草稿"), role: .destructive) {
                    do {
                        try draftStore.discard(key: draftKey)
                        self.pendingRestoration = nil
                    } catch { draftError = error.localizedDescription }
                }
            }
            Button(AppLocalization.string("丢弃草稿"), role: .destructive) { showDiscardDraft = true }
                .accessibilityIdentifier("finance-discard-draft")
        }
    }
}

extension ProjectFinancialRecordEditSheet {
    var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    var linkedOCRCandidates: [ProjectDocument] {
        ProjectFinancialReceiptOCRSupport.ocrCandidates(from: linkedDocuments)
    }

    var duplicateWarnings: [ProjectFinancialDuplicateWarning] {
        ProjectFinancialDuplicateDetector.warnings(
            for: updatedRecord,
            in: existingRecords,
            ignoring: record.id
        )
    }

    var updatedRecord: ProjectFinancialRecord {
        var value = store.projectFinancialRecords.first(where: { $0.id == record.id }) ?? record
        value.date = date
        value.direction = direction
        value.category = ProjectFinancialCategory.normalized(category, for: direction)
        value.amount = NumericInputSupport.money(amount)
        value.counterparty = counterparty
        value.invoiceNumber = invoiceNumber
        value.status = status
        value.dueDate = hasDueDate ? dueDate : (record.hasDueReminder ? .empty : record.dueDate)
        value.reminderStatus = hasDueDate ? reminderStatus : .none
        value.note = note
        return value
    }

    func commitSave(_ pendingRecord: ProjectFinancialRecord) {
        guard !isSaving, draftLoaded, pendingRestoration == nil else { return }
        do {
            try ProjectPaymentMetrics.validateAllocation(pendingRecord, projects: store.projects, records: store.projectFinancialRecords)
        } catch {
            draftError = error.localizedDescription
            return
        }
        guard let current = store.projectFinancialRecords.first(where: { $0.id == record.id }),
              BusinessDraftStore.fingerprint(current) == editingBase else {
            draftError = AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。")
            return
        }
        persistDraft()
        guard draftError == nil else { return }
        isSaving = true
        let previous = store.projectFinancialRecords.first(where: { $0.id == pendingRecord.id })
        Task { @MainActor in
            defer { isSaving = false }
            var committed = false
            do {
                await store.awaitInitialLoad()
                guard store.loadState == .ready, !store.isApplyingBackup,
                      let current = store.projectFinancialRecords.first(where: { $0.id == record.id }),
                      BusinessDraftStore.fingerprint(current) == editingBase else {
                    throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。"))
                }
                if store.projectFinancialRecords.contains(where: { $0.id == pendingRecord.id }) {
                    try ProjectPaymentMetrics.validateAllocation(pendingRecord, projects: store.projects, records: store.projectFinancialRecords)
                    store.updateProjectFinancialRecord(pendingRecord)
                } else {
                    throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已不存在，请关闭页面并核对数据。"))
                }
                try await draftStore.complete(key: draftKey) {
                    try await store.flushSaveOrThrow()
                    committed = true
                    editingBase = BusinessDraftStore.fingerprint(pendingRecord)
                }
                draftCompleted = true
                // A different window may have changed the record while persistence awaited.
                // Report current state so the parent callback cannot replay older form values.
                if let saved = store.projectFinancialRecords.first(where: { $0.id == pendingRecord.id }) {
                    onSave(saved)
                }
                dismiss()
            } catch {
                if !committed,
                   let live = store.projectFinancialRecords.first(where: { $0.id == pendingRecord.id }),
                   BusinessDraftStore.fingerprint(live) == BusinessDraftStore.fingerprint(pendingRecord) {
                    if let previous { store.updateProjectFinancialRecord(previous) } else { store.removeProjectFinancialRecords(ids: [pendingRecord.id]) }
                }
                draftError = String(format: AppLocalization.string("保存失败，草稿已保留：%@"), error.localizedDescription)
            }
        }
    }

    var draftStore: BusinessDraftStore { .scoped(to: store.storeURL) }
    var draftKey: BusinessDraftStore.Key { .financeEdit(record.id) }
    var formDraft: FinancialFormDraft {
        FinancialFormDraft(baseRecord: editingBase, recordID: record.id, date: date, direction: direction, category: category,
            amount: amount, counterparty: counterparty, invoiceNumber: invoiceNumber, status: status,
            hasDueDate: hasDueDate, dueDateText: dueDate.storageText, reminderStatus: reminderStatus, note: note,
            scanAfterSave: false)
    }

    func loadDraft() {
        guard !draftLoaded else { return }
        do {
            if let saved = try draftStore.load(FinancialFormDraft.self, key: draftKey) {
                pendingRestoration = saved
            }
            draftLoaded = true
        } catch { draftError = String(format: AppLocalization.string("读取草稿失败，原文件已保留：%@"), error.localizedDescription) }
    }

    func restore(_ value: FinancialFormDraft) {
        draftRecordID = value.recordID
        date = value.date
        direction = value.direction
        category = value.category
        amount = value.amount
        counterparty = value.counterparty
        invoiceNumber = value.invoiceNumber
        status = value.status
        hasDueDate = value.hasDueDate
        dueDate = BusinessDateValue(legacyText: value.dueDateText)
        reminderStatus = value.reminderStatus
        note = value.note
        editingBase = store.projectFinancialRecords.first(where: { $0.id == record.id }).flatMap { BusinessDraftStore.fingerprint($0) }
        pendingRestoration = nil
    }

    func persistDraft() {
        guard draftLoaded, !draftCompleted, !isSaving, pendingRestoration == nil else { return }
        do {
            try draftStore.save(formDraft, key: draftKey)
            draftError = nil
        } catch { draftError = String(format: AppLocalization.string("草稿保存失败，请保留此页面并重试：%@"), error.localizedDescription) }
    }

    var draftSection: some View {
        Section {
            if let draftError { Text(draftError).foregroundStyle(.red) } else { Text(AppLocalization.string("自动保留草稿，关闭后可继续填写。")).foregroundStyle(.secondary) }
            if isSaving { ProgressView(AppLocalization.string("正在保存，请稍候…")) }
            if let pendingRestoration {
                if pendingRestoration.baseRecord != BusinessDraftStore.fingerprint(record) {
                    Text(AppLocalization.string("原记录在草稿保存后已有变化，恢复后请逐项核对。")).foregroundStyle(.orange)
                }
                Text(AppLocalization.string("恢复草稿只会填入表单；请核对当前记录后再保存。"))
                Button(AppLocalization.string("恢复草稿")) { restore(pendingRestoration) }
                    .accessibilityIdentifier("finance-restore-draft")
                Button(AppLocalization.string("保留当前记录并丢弃草稿"), role: .destructive) {
                    do {
                        try draftStore.discard(key: draftKey)
                        self.pendingRestoration = nil
                    } catch { draftError = error.localizedDescription }
                }
            }
            Button(AppLocalization.string("丢弃草稿"), role: .destructive) { showDiscardDraft = true }
                .accessibilityIdentifier("finance-discard-draft")
        }
    }
}
