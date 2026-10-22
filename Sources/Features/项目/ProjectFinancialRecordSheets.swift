import SwiftUI
import UniformTypeIdentifiers

struct ProjectFinancialRecordAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let preset: ProjectFinancialRecord?
    let recentRecords: [ProjectFinancialRecord]
    let onSave: (ProjectFinancialRecord, Bool) -> Void

    @State private var date = Date()
    @State private var direction: ProjectFinancialDirection = .expense
    @State private var category: ProjectFinancialCategory = ProjectFinancialDirection.expense.defaultCategory
    @State private var amount = ""
    @State private var counterparty = ""
    @State private var invoiceNumber = ""
    @State private var status: ProjectFinancialStatus = .active
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var reminderStatus: ProjectFinancialReminderStatus = .pending
    @State private var note = ""
    @State private var scanAfterSave = false
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
            title: String(localized: "项目记账"),
            isPrimaryActionDisabled: !InputValidator.validate(amount, kind: .amount, requirement: .requiredPositive).isValid,
            onCancel: { dismiss() },
            onPrimaryAction: {
                isInputFocused = false
                saveWithDuplicateCheck()
            }
        ) {
            Form {
                if !recentRecords.isEmpty {
                    Section(String(localized: "快速录入")) {
                        if let lastRecord = recentRecords.first {
                            Button(String(localized: "套用上一笔")) { apply(record: lastRecord) }
                        }
                        if let lastIncome = recentRecords.first(where: { $0.normalizedDirection == .income }) {
                            Button(String(localized: "套用最近收入")) { apply(record: lastIncome) }
                        }
                        if let lastExpense = recentRecords.first(where: { $0.normalizedDirection == .expense }) {
                            Button(String(localized: "套用最近支出")) { apply(record: lastExpense) }
                        }
                    }
                }
                Section(String(localized: "智能录入（票据 OCR）")) {
                    Button {
                        showOCRImporter = true
                    } label: {
                        Label(String(localized: "从图片/PDF识别金额、日期、单位"), systemImage: "text.viewfinder")
                    }
                    .disabled(isRecognizingReceipt)

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
                Section(String(localized: "附件")) {
                    Toggle(String(localized: "保存后立即扫描票据（可选）"), isOn: $scanAfterSave)
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
            .onAppear {
                if let preset {
                    apply(record: preset)
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

    private var draftRecord: ProjectFinancialRecord {
        ProjectFinancialRecord(
            projectId: projectId,
            date: Formatters.timestamp(date),
            direction: direction,
            category: category,
            amount: NumericInputSupport.normalizedStorageText(amount, kind: .amount),
            counterparty: counterparty,
            invoiceNumber: invoiceNumber,
            status: status,
            dueDate: hasDueDate ? Formatters.date.string(from: dueDate) : "",
            reminderStatus: hasDueDate ? reminderStatus : .none,
            note: note
        )
    }

    private var duplicateWarnings: [ProjectFinancialDuplicateWarning] {
        ProjectFinancialDuplicateDetector.warnings(for: draftRecord, in: recentRecords)
    }

    private func apply(record: ProjectFinancialRecord) {
        // 新增账目时日期时间始终保持当前时间，套用仅复制业务字段
        date = Date()
        direction = record.normalizedDirection
        category = record.normalizedCategory
        amount = record.amount
        counterparty = record.counterparty
        invoiceNumber = record.invoiceNumber
        status = record.normalizedStatus
        if let parsedDueDate = Formatters.date.date(from: record.dueDate), record.normalizedReminderStatus != .none {
            hasDueDate = true
            dueDate = parsedDueDate
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
        onSave(record, scanAfterSave)
        dismiss()
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
                        "source": "ProjectFinancialRecordCreateSheet.startOCR",
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
