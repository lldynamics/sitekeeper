import SwiftUI

struct ProjectFinancialRecordEditSheet: View {
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
    @State var editingBase: Data?
    let record: ProjectFinancialRecord
    let linkedDocuments: [ProjectDocument]
    let linkedAttachmentCount: Int
    let existingRecords: [ProjectFinancialRecord]
    let onSave: (ProjectFinancialRecord) -> Void
    let onDelete: (ProjectFinancialRecord) -> Void
    let onScan: (ProjectFinancialRecord) -> Void
    let onManageAttachments: (ProjectFinancialRecord) -> Void

    @State var date: BusinessDateValue
    @State var direction: ProjectFinancialDirection
    @State var category: ProjectFinancialCategory
    @State var amount: String
    @State var counterparty: String
    @State var invoiceNumber: String
    @State var status: ProjectFinancialStatus
    @State var hasDueDate: Bool
    @State var dueDate: BusinessDateValue
    @State var reminderStatus: ProjectFinancialReminderStatus
    @State var note: String
    @State var showDeleteConfirm = false
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

    init(
        record: ProjectFinancialRecord,
        linkedDocuments: [ProjectDocument],
        linkedAttachmentCount: Int,
        existingRecords: [ProjectFinancialRecord] = [],
        onSave: @escaping (ProjectFinancialRecord) -> Void,
        onDelete: @escaping (ProjectFinancialRecord) -> Void,
        onScan: @escaping (ProjectFinancialRecord) -> Void,
        onManageAttachments: @escaping (ProjectFinancialRecord) -> Void
    ) {
        self.record = record
        _editingBase = State(initialValue: BusinessDraftStore.fingerprint(record))
        self.linkedDocuments = linkedDocuments
        self.linkedAttachmentCount = linkedAttachmentCount
        self.existingRecords = existingRecords
        self.onSave = onSave
        self.onDelete = onDelete
        self.onScan = onScan
        self.onManageAttachments = onManageAttachments
        let initialDirection = record.direction
        _date = State(initialValue: record.date)
        _direction = State(initialValue: initialDirection)
        _category = State(initialValue: ProjectFinancialCategory.normalized(record.category, for: initialDirection))
        _amount = State(initialValue: record.amount.wireText)
        _counterparty = State(initialValue: record.counterparty)
        _invoiceNumber = State(initialValue: record.invoiceNumber)
        _status = State(initialValue: record.normalizedStatus)
        let originalDueDate = record.dueDate
        _hasDueDate = State(initialValue: !originalDueDate.isEmpty && record.normalizedReminderStatus != .none)
        _dueDate = State(initialValue: originalDueDate.isEmpty ? .day(CalendarDay(date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())) : originalDueDate)
        _reminderStatus = State(initialValue: record.normalizedReminderStatus == .none ? .pending : record.normalizedReminderStatus)
        _note = State(initialValue: record.note)
    }

    var body: some View {
        AppBusinessEditForm(
            title: AppLocalization.string("编辑账目"),
            isPrimaryActionDisabled: isSaving || !draftLoaded || pendingRestoration != nil || !InputValidator.validate(amount, kind: .amount, requirement: .requiredPositive).isValid,
            onCancel: { persistDraft()
            if draftError == nil || !draftLoaded { dismiss() } },
            onPrimaryAction: {
                isInputFocused = false
                saveWithDuplicateCheck()
            }
        ) {
            Form {
                draftSection
                if let allocation = record.paymentAllocation {
                    Section(AppLocalization.string("分期收付款")) {
                        let plan = store.projects.first(where: { $0.id == record.projectId })?.paymentPlans.first(where: { $0.id == allocation.planID })
                        Text(plan?.title ?? AppLocalization.string("关联记录不存在，已保留输入，请重新选择。"))
                        if let installment = plan?.installments.first(where: { $0.id == allocation.installmentID }) { Text(installment.title).foregroundStyle(.secondary) }
                    }
                }
                if record.origin?.warehouseMovementID != nil {
                    Section(AppLocalization.string("入库记账")) {
                        Text(AppLocalization.string("请核对实际结算单价。生成的账目为草稿，票据关联会一并保留。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section(AppLocalization.string("智能录入（票据 OCR）")) {
                    Button {
                        showOCRImporter = true
                    } label: {
                        Label(AppLocalization.string("从图片/PDF识别金额、日期、单位"), systemImage: "text.viewfinder")
                    }
                    .disabled(isRecognizingReceipt)

                    if linkedAttachmentCount > 0 {
                        Button {
                            startOCRFromLinkedDocuments()
                        } label: {
                            Label(
                                linkedOCRCandidates.isEmpty
                                ? AppLocalization.string("已关联票据暂不支持识别（仅图片/PDF）")
                                : String(format: AppLocalization.string("从已关联票据一键回填（%lld）"), Int64(linkedOCRCandidates.count)),
                                systemImage: "doc.text.viewfinder"
                            )
                        }
                        .disabled(isRecognizingReceipt || linkedOCRCandidates.isEmpty)
                    }

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
                Section(AppLocalization.string("票据")) {
                    Button(AppLocalization.string("补扫/追加票据")) {
                        onScan(updatedRecord)
                    }
                    Button(String(format: AppLocalization.string("管理票据附件（%d）"), linkedAttachmentCount)) {
                        onManageAttachments(updatedRecord)
                    }
                }
                AppBusinessFormDestructiveActionSection(title: AppLocalization.string("删除账目")) {
                    showDeleteConfirm = true
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
        .alert(AppLocalization.string("删除这条账目？"), isPresented: $showDeleteConfirm) {
            Button(AppLocalization.string("取消"), role: .cancel) {}
            Button(AppLocalization.string("删除"), role: .destructive) {
                onDelete(record)
                dismiss()
            }
        }
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
        .onAppear { loadDraft() }
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

    private func saveWithDuplicateCheck() {
        let pendingRecord = updatedRecord
        let warnings = ProjectFinancialDuplicateDetector.warnings(
            for: pendingRecord,
            in: existingRecords,
            ignoring: record.id
        )
        guard warnings.isEmpty else {
            pendingDuplicateRecord = pendingRecord
            duplicateConfirmMessage = ProjectFinancialReceiptOCRSupport.duplicateConfirmationMessage(from: warnings)
            showDuplicateConfirm = true
            AppHaptics.warning()
            return
        }
        commitSave(pendingRecord)
    }
}
