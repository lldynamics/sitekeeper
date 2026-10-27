import SwiftUI
import UniformTypeIdentifiers

struct ProjectFinancialRecordAddSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(DataStore.self) var store
    @Environment(\.scenePhase) var scenePhase
    @State var draftLoaded = false
    @State var draftCompleted = false
    @State var draftError: String?
    @State var isSaving = false
    @State var showDiscardDraft = false
    @State var pendingRestoration: FinancialFormDraft?
    @State var draftRecordID = UUID()
    let projectId: UUID
    let preset: ProjectFinancialRecord?
    let recentRecords: [ProjectFinancialRecord]
    let onSave: (ProjectFinancialRecord, Bool) -> Void

    @State var date = BusinessDateValue.now()
    @State var direction: ProjectFinancialDirection = .expense
    @State var category: ProjectFinancialCategory = ProjectFinancialDirection.expense.defaultCategory
    @State var amount = ""
    @State var counterparty = ""
    @State var invoiceNumber = ""
    @State var status: ProjectFinancialStatus = .active
    @State var hasDueDate = false
    @State var dueDate = BusinessDateValue.day(CalendarDay(date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()))
    @State var reminderStatus: ProjectFinancialReminderStatus = .pending
    @State var note = ""
    @State var scanAfterSave = false
    @State var showOCRImporter = false
    @State var isRecognizingReceipt = false
    @State var ocrPreview: ReceiptOCRResult?
    @State var ocrErrorMessage = ""
    @State var showOCRError = false
    @State var ocrTask: Task<Void, Never>?
    @State var duplicateConfirmMessage = ""
    @State var pendingDuplicateRecord: ProjectFinancialRecord?
    @State var showDuplicateConfirm = false
    @FocusState var isInputFocused: Bool

    var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    init(
        projectId: UUID,
        preset: ProjectFinancialRecord? = nil,
        recentRecords: [ProjectFinancialRecord] = [],
        onSave: @escaping (ProjectFinancialRecord, Bool) -> Void
    ) {
        self.projectId = projectId
        self.preset = preset
        self.recentRecords = recentRecords
        self.onSave = onSave
    }

    var body: some View {
        AppBusinessEditForm(
            title: AppLocalization.string("项目记账"),
            isPrimaryActionDisabled: store.projectFinancialRecords.contains(where: { $0.id == draftRecordID }) || isSaving || !draftLoaded || pendingRestoration != nil || !InputValidator.validate(amount, kind: .amount, requirement: .requiredPositive).isValid,
            onCancel: { persistDraft()
            if draftError == nil || !draftLoaded { dismiss() } },
            onPrimaryAction: {
                isInputFocused = false
                saveWithDuplicateCheck()
            }
        ) {
            Form {
                draftSection
                if !recentRecords.isEmpty {
                    Section(AppLocalization.string("快速录入")) {
                        if let lastRecord = recentRecords.first {
                            Button(AppLocalization.string("套用上一笔")) { apply(record: lastRecord) }
                        }
                        if let lastIncome = recentRecords.first(where: { $0.normalizedDirection == .income }) {
                            Button(AppLocalization.string("套用最近收入")) { apply(record: lastIncome) }
                        }
                        if let lastExpense = recentRecords.first(where: { $0.normalizedDirection == .expense }) {
                            Button(AppLocalization.string("套用最近支出")) { apply(record: lastExpense) }
                        }
                    }
                }
                Section(AppLocalization.string("智能录入（票据 OCR）")) {
                    Button {
                        showOCRImporter = true
                    } label: {
                        Label(AppLocalization.string("从图片/PDF识别金额、日期、单位"), systemImage: "text.viewfinder")
                    }
                    .disabled(isRecognizingReceipt)

                    if isRecognizingReceipt {
                        ProgressView(AppLocalization.string("识别中…"))
                            .font(.caption)
                    }

                    if let ocrPreview {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLocalization.string("识别结果"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(ProjectFinancialReceiptOCRSupport.summaryLines(from: ocrPreview), id: \.self) { line in
                                Text(line)
                                    .font(.caption2)
                            }
                            ReceiptOCRAmountCandidatesView(candidates: ocrPreview.amountCandidates) { candidate in
                                applyOCRAmountCandidate(candidate)
                            }
                        }
                    }
                }
                if !duplicateWarnings.isEmpty {
                    ProjectFinancialDuplicateWarningsSection(warnings: duplicateWarnings)
                }
                ProjectFinancialEntrySections(
                    date: $date, direction: $direction, category: $category, amount: $amount,
                    counterparty: $counterparty, invoiceNumber: $invoiceNumber, note: $note,
                    hasDueDate: $hasDueDate, dueDate: $dueDate, reminderStatus: $reminderStatus,
                    focused: $isInputFocused
                )
                Section(AppLocalization.string("附件")) {
                    Toggle(AppLocalization.string("保存后立即扫描票据（可选）"), isOn: $scanAfterSave)
                }
            }
            .onChange(of: direction) { _, newDirection in
                category = ProjectFinancialCategory.normalized(category, for: newDirection)
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
            .onAppear { loadDraft() }
            .fileImporter(
                isPresented: $showOCRImporter,
                allowedContentTypes: ProjectFinancialReceiptOCRSupport.allowedImportTypes,
                allowsMultipleSelection: false
            ) { result in
                handleOCRImportResult(result)
            }
            .alert(AppLocalization.string("票据识别失败"), isPresented: $showOCRError) {
                Button(AppLocalization.string("知道了"), role: .cancel) {}
            } message: {
                Text(ocrErrorMessage)
            }
            .alert(AppLocalization.string("可能重复票据"), isPresented: $showDuplicateConfirm) {
                Button(AppLocalization.string("返回检查"), role: .cancel) {}
                Button(AppLocalization.string("仍然保存")) {
                    if let pendingDuplicateRecord {
                        commitSave(pendingDuplicateRecord)
                    }
                }
            } message: {
                Text(duplicateConfirmMessage)
            }
        .onChange(of: formDraft) { _, _ in persistDraft() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persistDraft() } }
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving || draftError != nil)
        .confirmationDialog(AppLocalization.string("丢弃草稿？"), isPresented: $showDiscardDraft, titleVisibility: .visible) {
            Button(AppLocalization.string("丢弃草稿"), role: .destructive) {
                do {
                    try draftStore.discard(key: draftKey)
                    draftCompleted = true
                    dismiss()
                } catch { draftError = error.localizedDescription }
            }
        }
            .onDisappear {
                persistDraft()
                ocrTask?.cancel()
            }
    }

    var draftRecord: ProjectFinancialRecord {
        ProjectFinancialRecord(
            id: draftRecordID,
            projectId: projectId,
            date: date,
            direction: direction,
            category: category,
            amount: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(amount, kind: .amount)),
            counterparty: counterparty,
            invoiceNumber: invoiceNumber,
            status: status,
            dueDate: hasDueDate ? dueDate : .empty,
            reminderStatus: hasDueDate ? reminderStatus : .none,
            note: note
        )
    }

    var duplicateWarnings: [ProjectFinancialDuplicateWarning] {
        ProjectFinancialDuplicateDetector.warnings(for: draftRecord, in: recentRecords)
    }

    func apply(record: ProjectFinancialRecord) {
        // 新增账目时日期时间始终保持当前时间，套用仅复制业务字段
        date = .now()
        direction = record.normalizedDirection
        category = record.normalizedCategory
        amount = record.amount.wireText
        counterparty = record.counterparty
        invoiceNumber = record.invoiceNumber
        status = record.normalizedStatus
        if !record.dueDate.isEmpty, record.normalizedReminderStatus != .none {
            hasDueDate = true
            dueDate = record.dueDate
            reminderStatus = record.normalizedReminderStatus
        }
        note = record.note
    }

    private func saveWithDuplicateCheck() {
        let record = draftRecord
        let warnings = ProjectFinancialDuplicateDetector.warnings(for: record, in: recentRecords)
        guard warnings.isEmpty else {
            pendingDuplicateRecord = record
            duplicateConfirmMessage = ProjectFinancialReceiptOCRSupport.duplicateConfirmationMessage(from: warnings)
            showDuplicateConfirm = true
            AppHaptics.warning()
            return
        }
        commitSave(record)
    }

    private func commitSave(_ record: ProjectFinancialRecord) {
        guard !isSaving, draftLoaded, pendingRestoration == nil,
              !store.projectFinancialRecords.contains(where: { $0.id == draftRecordID }) else { return }
        persistDraft()
        guard draftError == nil else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await draftStore.commitNewFinancialRecord(record, in: store)
                draftCompleted = true
                onSave(record, scanAfterSave)
                dismiss()
            } catch {
                draftError = String(format: AppLocalization.string("保存失败，草稿已保留：%@"), error.localizedDescription)
            }
        }
    }
}
