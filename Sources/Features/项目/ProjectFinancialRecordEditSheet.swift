import SwiftUI

struct ProjectFinancialRecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: ProjectFinancialRecord
    let linkedDocuments: [ProjectDocument]
    let linkedAttachmentCount: Int
    let existingRecords: [ProjectFinancialRecord]
    let onSave: (ProjectFinancialRecord) -> Void
    let onDelete: (ProjectFinancialRecord) -> Void
    let onScan: (ProjectFinancialRecord) -> Void
    let onManageAttachments: (ProjectFinancialRecord) -> Void

    @State private var date: Date
    @State private var direction: ProjectFinancialDirection
    @State private var category: ProjectFinancialCategory
    @State private var amount: String
    @State private var counterparty: String
    @State private var invoiceNumber: String
    @State private var status: ProjectFinancialStatus
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var reminderStatus: ProjectFinancialReminderStatus
    @State private var note: String
    @State private var showDeleteConfirm = false
    @State private var showOCRImporter = false
    @State private var isRecognizingReceipt = false
    @State private var ocrPreview: ReceiptOCRResult?
    @State private var ocrErrorMessage = ""
    @State private var showOCRError = false
    @State private var ocrTask: Task<Void, Never>?
    @State private var duplicateConfirmMessage = ""
    @State private var pendingDuplicateRecord: ProjectFinancialRecord?
    @State private var showDuplicateConfirm = false
    @FocusState private var isInputFocused: Bool

    private var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    private var linkedOCRCandidates: [ProjectDocument] {
        ProjectFinancialReceiptOCRSupport.ocrCandidates(from: linkedDocuments)
    }

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
        self.linkedDocuments = linkedDocuments
        self.linkedAttachmentCount = linkedAttachmentCount
        self.existingRecords = existingRecords
        self.onSave = onSave
        self.onDelete = onDelete
        self.onScan = onScan
        self.onManageAttachments = onManageAttachments
        let initialDirection = record.direction
        _date = State(initialValue: Formatters.parseDateOrDateTime(record.date) ?? Date())
        _direction = State(initialValue: initialDirection)
        _category = State(initialValue: ProjectFinancialCategory.normalized(record.category, for: initialDirection))
        _amount = State(initialValue: record.amount)
        _counterparty = State(initialValue: record.counterparty)
        _invoiceNumber = State(initialValue: record.invoiceNumber)
        _status = State(initialValue: record.normalizedStatus)
        let parsedDueDate = Formatters.date.date(from: record.dueDate)
        _hasDueDate = State(initialValue: parsedDueDate != nil && record.normalizedReminderStatus != .none)
        _dueDate = State(initialValue: parsedDueDate ?? (Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()))
        _reminderStatus = State(initialValue: record.normalizedReminderStatus == .none ? .pending : record.normalizedReminderStatus)
        _note = State(initialValue: record.note)
    }

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "编辑账目"),
            isPrimaryActionDisabled: !InputValidator.validate(amount, kind: .amount, requirement: .requiredPositive).isValid,
            onCancel: { dismiss() },
            onPrimaryAction: {
                isInputFocused = false
                saveWithDuplicateCheck()
            }
        ) {
            Form {
                Section(String(localized: "智能录入（票据 OCR）")) {
                    Button {
                        showOCRImporter = true
                    } label: {
                        Label(String(localized: "从图片/PDF识别金额、日期、单位"), systemImage: "text.viewfinder")
                    }
                    .disabled(isRecognizingReceipt)

                    if linkedAttachmentCount > 0 {
                        Button {
                            startOCRFromLinkedDocuments()
                        } label: {
                            Label(
                                linkedOCRCandidates.isEmpty
                                ? String(localized: "已关联票据暂不支持识别（仅图片/PDF）")
                                : String(format: String(localized: "从已关联票据一键回填（%lld）"), Int64(linkedOCRCandidates.count)),
                                systemImage: "doc.text.viewfinder"
                            )
                        }
                        .disabled(isRecognizingReceipt || linkedOCRCandidates.isEmpty)
                    }

                    if isRecognizingReceipt {
                        ProgressView(String(localized: "识别中…"))
                            .font(.caption)
                    }

                    if let ocrPreview {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "识别结果"))
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
                Section(String(localized: "账目")) {
                    DatePicker(String(localized: "日期时间"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker(String(localized: "类型"), selection: $direction) {
                        ForEach(ProjectFinancialDirection.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(String(localized: "分类"), selection: $category) {
                        ForEach(availableCategories, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "金额（元）"), text: $amount.numericInput(.amount))
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                    NumericInputValidationHint(
                        validation: InputValidator.validate(
                            amount,
                            kind: .amount,
                            requirement: .requiredPositive
                        ),
                        alignment: .leading
                    )
                    TextField(String(localized: "对方单位/个人"), text: $counterparty)
                        .focused($isInputFocused)
                    TextField(String(localized: "发票号/收据号"), text: $invoiceNumber)
                        .focused($isInputFocused)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                }
                Section(String(localized: "应收/应付提醒")) {
                    Toggle(String(localized: "设置到期提醒"), isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker(String(localized: "到期日"), selection: $dueDate, displayedComponents: .date)
                        Picker(String(localized: "提醒状态"), selection: $reminderStatus) {
                            ForEach(ProjectFinancialReminderStatus.allCases.filter { $0 != .none }, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                    }
                }
                Section(String(localized: "票据")) {
                    Button(String(localized: "补扫/追加票据")) {
                        onScan(updatedRecord)
                    }
                    Button(String(format: String(localized: "管理票据附件（%d）"), linkedAttachmentCount)) {
                        onManageAttachments(updatedRecord)
                    }
                }
                AppBusinessFormDestructiveActionSection(title: String(localized: "删除账目")) {
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
        .alert(String(localized: "删除这条账目？"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive) {
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
        .alert(String(localized: "票据识别失败"), isPresented: $showOCRError) {
            Button(String(localized: "知道了"), role: .cancel) {}
        } message: {
            Text(ocrErrorMessage)
        }
        .alert(String(localized: "可能重复票据"), isPresented: $showDuplicateConfirm) {
            Button(String(localized: "返回检查"), role: .cancel) {}
            Button(String(localized: "仍然保存")) {
                if let pendingDuplicateRecord {
                    commitSave(pendingDuplicateRecord)
                }
            }
        } message: {
            Text(duplicateConfirmMessage)
        }
        .onDisappear {
            ocrTask?.cancel()
        }
    }

    private var duplicateWarnings: [ProjectFinancialDuplicateWarning] {
        ProjectFinancialDuplicateDetector.warnings(
            for: updatedRecord,
            in: existingRecords,
            ignoring: record.id
        )
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

    private func commitSave(_ pendingRecord: ProjectFinancialRecord) {
        onSave(pendingRecord)
        dismiss()
    }

    private var updatedRecord: ProjectFinancialRecord {
        var value = record
        value.date = Formatters.timestamp(date)
        value.direction = direction
        value.category = ProjectFinancialCategory.normalized(category, for: direction)
        value.amount = NumericInputSupport.normalizedStorageText(amount, kind: .amount)
        value.counterparty = counterparty
        value.invoiceNumber = invoiceNumber
        value.status = status
        value.dueDate = hasDueDate ? Formatters.date.string(from: dueDate) : ""
        value.reminderStatus = hasDueDate ? reminderStatus : .none
        value.note = note
        return value
    }

    @MainActor
    private func handleOCRImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let size = QuickNoteAttachmentStorage.fileSize(at: url)
            if size > ImportLimitPolicy.maxImportBytes {
                ocrErrorMessage = ImportLimitPolicy.fileTooLargeMessage(fileName: url.lastPathComponent, size: size)
                showOCRError = true
                AppHaptics.warning()
                return
            }
            startOCR(for: url)
        case .failure(let error):
            ocrErrorMessage = String(format: String(localized: "打开票据失败：%@"), error.localizedDescription)
            showOCRError = true
            AppHaptics.error()
        }
    }

    @MainActor
    private func startOCR(for url: URL) {
        ocrTask?.cancel()
        isRecognizingReceipt = true
        ocrTask = Task { @MainActor in
            defer {
                isRecognizingReceipt = false
                ocrTask = nil
            }
            do {
                let parsed = try await ReceiptOCRService.recognize(from: url)
                applyOCRResult(parsed)
                ocrPreview = parsed
                AppHaptics.success()
            } catch is CancellationError {
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                StorageIssueLog.recordEvent(
                    "project_finance.receipt_ocr_failed",
                    category: .fileStorage,
                    details: [
                        "source": "ProjectFinancialRecordEditSheet.startOCR",
                        "file_name": url.lastPathComponent
                    ],
                    error: error
                )
                ocrErrorMessage = message
                showOCRError = true
                AppHaptics.error()
            }
        }
    }

    @MainActor
    private func startOCRFromLinkedDocuments() {
        let candidates = linkedOCRCandidates
        guard !candidates.isEmpty else {
            ocrErrorMessage = String(localized: "已关联票据暂不支持识别，请使用图片或 PDF。")
            showOCRError = true
            AppHaptics.warning()
            return
        }
        ocrTask?.cancel()
        isRecognizingReceipt = true
        ocrTask = Task { @MainActor in
            defer {
                isRecognizingReceipt = false
                ocrTask = nil
            }
            var firstFailureMessage: String?
            for document in candidates {
                if Task.isCancelled { return }
                let url = ProjectDocumentStorage.fileURL(for: document.fileName)
                do {
                    let parsed = try await ReceiptOCRService.recognize(from: url)
                    applyOCRResult(parsed)
                    ocrPreview = parsed
                    AppHaptics.success()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    StorageIssueLog.recordEvent(
                        "project_finance.linked_receipt_ocr_failed",
                        category: .fileStorage,
                        details: [
                            "source": "ProjectFinancialRecordEditSheet.startOCRFromLinkedDocuments",
                            "file_name": document.fileName
                        ],
                        error: error
                    )
                    if firstFailureMessage == nil {
                        firstFailureMessage = message
                    }
                }
            }
            if let firstFailureMessage {
                ocrErrorMessage = String(
                    format: String(localized: "已尝试 %lld 份关联票据，仍未提取到可回填字段（%@）。"),
                    Int64(candidates.count),
                    firstFailureMessage
                )
            } else {
                ocrErrorMessage = String(
                    format: String(localized: "已尝试 %lld 份关联票据，仍未提取到可回填字段。"),
                    Int64(candidates.count)
                )
            }
            showOCRError = true
            AppHaptics.error()
        }
    }

    @MainActor
    private func applyOCRResult(_ result: ReceiptOCRResult) {
        if result.amountCandidates.isEmpty,
           let amountText = result.amount,
           !amountText.isEmpty {
            amount = NumericInputSupport.sanitize(amountText, kind: .amount)
        }
        if let party = result.counterparty, !party.isEmpty {
            counterparty = party
        }
        if let number = result.invoiceNumber, !number.isEmpty {
            invoiceNumber = number
        }
        if let dateText = result.date,
           let recognizedDate = Formatters.date.date(from: dateText) {
            date = ProjectFinancialReceiptOCRSupport.mergeDate(recognizedDate, keepingTimeOf: date)
        }
    }

    @MainActor
    private func applyOCRAmountCandidate(_ candidate: ReceiptOCRAmountCandidate) {
        amount = NumericInputSupport.sanitize(candidate.amount, kind: .amount)
        AppHaptics.success()
    }
}
