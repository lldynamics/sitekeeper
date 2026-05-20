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
        NavigationStack {
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
            .navigationTitle(String(localized: "项目记账"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: direction) { _, newDirection in
                category = ProjectFinancialCategory.normalized(category, for: newDirection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        isInputFocused = false
                        let record = ProjectFinancialRecord(
                            projectId: projectId,
                            date: Formatters.dateTime.string(from: date),
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
                        onSave(record, scanAfterSave)
                        dismiss()
                    }
                    .disabled(!InputValidator.validate(amount, kind: .amount, requirement: .requiredPositive).isValid)
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
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
            .onDisappear {
                ocrTask?.cancel()
            }
        }
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
                StorageIssueLog.record(String(format: String(localized: "票据 OCR 识别失败：%@，%@"), url.lastPathComponent, message))
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

struct ProjectFinancialRecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: ProjectFinancialRecord
    let linkedDocuments: [ProjectDocument]
    let linkedAttachmentCount: Int
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
        onSave: @escaping (ProjectFinancialRecord) -> Void,
        onDelete: @escaping (ProjectFinancialRecord) -> Void,
        onScan: @escaping (ProjectFinancialRecord) -> Void,
        onManageAttachments: @escaping (ProjectFinancialRecord) -> Void
    ) {
        self.record = record
        self.linkedDocuments = linkedDocuments
        self.linkedAttachmentCount = linkedAttachmentCount
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
        NavigationStack {
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
                Section {
                    Button(String(localized: "删除账目"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "编辑账目"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: direction) { _, newDirection in
                category = ProjectFinancialCategory.normalized(category, for: newDirection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        isInputFocused = false
                        onSave(updatedRecord)
                        dismiss()
                    }
                    .disabled(!InputValidator.validate(amount, kind: .amount, requirement: .requiredPositive).isValid)
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
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
            .onDisappear {
                ocrTask?.cancel()
            }
        }
    }

    private var updatedRecord: ProjectFinancialRecord {
        var value = record
        value.date = Formatters.dateTime.string(from: date)
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
                StorageIssueLog.record(String(format: String(localized: "票据 OCR 识别失败：%@，%@"), url.lastPathComponent, message))
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
                    StorageIssueLog.record(String(format: String(localized: "关联票据 OCR 识别失败：%@，%@"), document.fileName, message))
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

private struct ReceiptOCRAmountCandidatesView: View {
    let candidates: [ReceiptOCRAmountCandidate]
    let onApply: (ReceiptOCRAmountCandidate) -> Void

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: String(localized: "识别到 %lld 个金额候选，请点选确认："), Int64(candidates.count)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(candidates) { candidate in
                    HStack(alignment: .top, spacing: 6) {
                        Button {
                            onApply(candidate)
                        } label: {
                            Text(String(format: String(localized: "回填金额：%@"), candidate.amount))
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        Text(
                            String(
                                format: String(localized: "置信度：%lld%%"),
                                Int64(candidate.confidencePercent)
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Text(candidate.sourceLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private enum ProjectFinancialReceiptOCRSupport {
    static let allowedImportTypes: [UTType] = [.image, .pdf]

    static func ocrCandidates(from documents: [ProjectDocument]) -> [ProjectDocument] {
        documents
            .filter { isRecognizableDocument($0) }
            .sorted { lhs, rhs in
                let left = Formatters.parseDateOrDateTime(lhs.createdAt) ?? .distantPast
                let right = Formatters.parseDateOrDateTime(rhs.createdAt) ?? .distantPast
                return left > right
            }
    }

    static func summaryLines(from result: ReceiptOCRResult) -> [String] {
        var lines: [String] = []
        if let amount = result.amount, !amount.isEmpty {
            lines.append(String(format: String(localized: "金额：%@"), amount))
        }
        if let date = result.date, !date.isEmpty {
            lines.append(String(format: String(localized: "日期：%@"), date))
        }
        if let counterparty = result.counterparty, !counterparty.isEmpty {
            lines.append(String(format: String(localized: "单位：%@"), counterparty))
        }
        if let invoice = result.invoiceNumber, !invoice.isEmpty {
            lines.append(String(format: String(localized: "票号：%@"), invoice))
        }
        if lines.isEmpty {
            lines.append(String(localized: "未提取到结构化字段，可手动补录。"))
        }
        return lines
    }

    static func mergeDate(_ recognizedDay: Date, keepingTimeOf reference: Date) -> Date {
        let calendar = Calendar.current
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: recognizedDay)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: reference)
        dayComponents.hour = timeComponents.hour
        dayComponents.minute = timeComponents.minute
        return calendar.date(from: dayComponents) ?? recognizedDay
    }

    private static func isRecognizableDocument(_ document: ProjectDocument) -> Bool {
        let ext = normalizedExtension(for: document)
        if ext == "pdf" { return true }
        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    private static func normalizedExtension(for document: ProjectDocument) -> String {
        let fileType = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !fileType.isEmpty { return fileType }
        return URL(fileURLWithPath: document.fileName).pathExtension.lowercased()
    }
}
