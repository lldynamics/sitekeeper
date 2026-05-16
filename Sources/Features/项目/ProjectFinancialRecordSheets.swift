import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

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
                        ProgressView("识别中…")
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
            .navigationTitle("项目记账")
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
            .alert("票据识别失败", isPresented: $showOCRError) {
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
            ocrErrorMessage = "打开票据失败：\(error.localizedDescription)"
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
                StorageIssueLog.record("票据 OCR 识别失败：\(url.lastPathComponent)，\(message)")
                ocrErrorMessage = message
                showOCRError = true
                AppHaptics.error()
            }
        }
    }

    @MainActor
    private func applyOCRResult(_ result: ReceiptOCRResult) {
        if let amountText = result.amount, !amountText.isEmpty {
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
                                ? "已关联票据暂不支持识别（仅图片/PDF）"
                                : "从已关联票据一键回填（\(linkedOCRCandidates.count)）",
                                systemImage: "doc.text.viewfinder"
                            )
                        }
                        .disabled(isRecognizingReceipt || linkedOCRCandidates.isEmpty)
                    }

                    if isRecognizingReceipt {
                        ProgressView("识别中…")
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
            .navigationTitle("编辑账目")
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
            .alert("删除这条账目？", isPresented: $showDeleteConfirm) {
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
            .alert("票据识别失败", isPresented: $showOCRError) {
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
            ocrErrorMessage = "打开票据失败：\(error.localizedDescription)"
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
                StorageIssueLog.record("票据 OCR 识别失败：\(url.lastPathComponent)，\(message)")
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
            ocrErrorMessage = "已关联票据暂不支持识别，请使用图片或 PDF。"
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
                    StorageIssueLog.record("关联票据 OCR 识别失败：\(document.fileName)，\(message)")
                    if firstFailureMessage == nil {
                        firstFailureMessage = message
                    }
                }
            }
            if let firstFailureMessage {
                ocrErrorMessage = "已尝试 \(candidates.count) 份关联票据，仍未提取到可回填字段（\(firstFailureMessage)）。"
            } else {
                ocrErrorMessage = "已尝试 \(candidates.count) 份关联票据，仍未提取到可回填字段。"
            }
            showOCRError = true
            AppHaptics.error()
        }
    }

    @MainActor
    private func applyOCRResult(_ result: ReceiptOCRResult) {
        if let amountText = result.amount, !amountText.isEmpty {
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
            lines.append("金额：\(amount)")
        }
        if let date = result.date, !date.isEmpty {
            lines.append("日期：\(date)")
        }
        if let counterparty = result.counterparty, !counterparty.isEmpty {
            lines.append("单位：\(counterparty)")
        }
        if let invoice = result.invoiceNumber, !invoice.isEmpty {
            lines.append("票号：\(invoice)")
        }
        if lines.isEmpty {
            lines.append("未提取到结构化字段，可手动补录。")
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

struct ProjectFinancialAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: ProjectFinancialRecord
    let documents: [ProjectDocument]
    let onDetach: (ProjectDocument) -> Void
    let onAttach: (ProjectDocument) -> Void
    let onBulkSetCategory: ([ProjectDocument], ProjectDocumentCategory) -> Void
    let onScan: () -> Void
    let onImportFiles: ([URL]) -> Void
    let onImportImage: (UIImage, String) -> Void

    @State private var showFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedLinkedDocumentIds: Set<UUID> = []
    @State private var selectedUnlinkedDocumentIds: Set<UUID> = []
    @State private var bulkCategory: ProjectDocumentCategory = .receipt
    @State private var previewURL: URL?

    private static let allowedImportTypes: [UTType] = [.item]

    private var linkedDocuments: [ProjectDocument] {
        let idSet = Set(record.linkedDocumentIds)
        return documents.filter { $0.linkedFinancialRecordId == record.id || idSet.contains($0.id) }
    }

    private var unlinkedDocuments: [ProjectDocument] {
        let linkedSet = Set(linkedDocuments.map(\.id))
        return documents.filter { !linkedSet.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedDocuments: [ProjectDocument] {
        let ids = selectedLinkedDocumentIds.union(selectedUnlinkedDocumentIds)
        return documents.filter { ids.contains($0.id) }
    }

    private var selectedDocumentURLs: [URL] {
        selectedDocuments.map { ProjectDocumentStorage.fileURL(for: $0.fileName) }
    }

    private var autoMatchedDocuments: [FinancialRecordDocumentSuggestion] {
        ProjectFinancialDocumentMatcher.suggestedDocuments(
            for: record,
            in: unlinkedDocuments,
            limit: 3
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedDocuments.isEmpty {
                    Section(String(localized: "选中操作")) {
                        LabeledContent("已选附件", value: "\(selectedDocuments.count) 份")
                        Button {
                            if let firstDoc = selectedDocuments.first { previewURL = ProjectDocumentStorage.fileURL(for: firstDoc.fileName) }
                        } label: {
                            Label(String(localized: "预览第一份"), systemImage: "eye")
                        }
                        ShareLink(items: selectedDocumentURLs) {
                            Label(String(localized: "导出/分享选中附件"), systemImage: "square.and.arrow.up")
                        }
                        Picker(String(localized: "批量分类"), selection: $bulkCategory) {
                            ForEach(ProjectDocumentCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        Button {
                            onBulkSetCategory(selectedDocuments, bulkCategory)
                            selectedLinkedDocumentIds.removeAll()
                            selectedUnlinkedDocumentIds.removeAll()
                        } label: {
                            Label(String(localized: "应用分类到选中附件"), systemImage: "tag.fill")
                        }
                    }
                }

                Section(String(format: String(localized: "已关联附件 (%d)"), linkedDocuments.count)) {
                    if linkedDocuments.isEmpty {
                        ContentUnavailableView(
                            "暂无附件",
                            systemImage: "paperclip",
                            description: Text(String(localized: "可拍照、扫描或关联已有项目资料。"))
                        )
                    } else {
                        if !selectedLinkedDocumentIds.isEmpty {
                            Button(String(format: String(localized: "移除选中 %d 项"), selectedLinkedDocumentIds.count)) {
                                for document in linkedDocuments where selectedLinkedDocumentIds.contains(document.id) {
                                    onDetach(document)
                                }
                                selectedLinkedDocumentIds.removeAll()
                            }
                            .font(.caption.weight(.semibold))
                        }
                        ForEach(linkedDocuments) { document in
                            ProjectFinancialAttachmentRow(
                                document: document,
                                isSelected: selectedLinkedDocumentIds.contains(document.id),
                                trailingTitle: "移除",
                                onToggleSelection: { toggleLinked(document.id) },
                                onAction: { onDetach(document) }
                            )
                        }
                    }
                }

                Section(String(localized: "新增附件")) {
                    Button(String(localized: "扫描添加")) {
                        onScan()
                    }
                    Button(String(localized: "从文件导入附件")) {
                        showFileImporter = true
                    }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(String(localized: "从相册选择照片"), systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(String(localized: "拍照保存")) {
                            imagePickerSource = .camera
                            showImagePicker = true
                        }
                    }
                }

                Section(String(localized: "缺票自动匹配")) {
                    if autoMatchedDocuments.isEmpty {
                        ContentUnavailableView(
                            "暂无匹配建议",
                            systemImage: "wand.and.stars",
                            description: Text(String(localized: "建议先在资料里补录金额、日期或单位名称，再回来一键关联。"))
                        )
                    } else {
                        ForEach(autoMatchedDocuments) { suggestion in
                            HStack(alignment: .top, spacing: AppSpacing.tight) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.document.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(suggestion.document.category.displayName)
                                        if suggestion.document.amountValue.isPositive {
                                            Text(ReportBuilder.money(suggestion.document.amountValue.doubleValue))
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    Text(suggestion.document.createdAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "关联")) {
                                    onAttach(suggestion.document)
                                }
                                .buttonStyle(.appProminent())
                                .font(.caption2.weight(.semibold))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section(String(localized: "关联已有资料")) {
                    if unlinkedDocuments.isEmpty {
                        ContentUnavailableView(
                            "暂无可关联资料",
                            systemImage: "doc.badge.plus",
                            description: Text(String(localized: "导入项目资料后可在这里关联到当前流水。"))
                        )
                    } else {
                        if !selectedUnlinkedDocumentIds.isEmpty {
                            Button(String(format: String(localized: "关联选中 %d 项"), selectedUnlinkedDocumentIds.count)) {
                                for document in unlinkedDocuments where selectedUnlinkedDocumentIds.contains(document.id) {
                                    onAttach(document)
                                }
                                selectedUnlinkedDocumentIds.removeAll()
                            }
                            .font(.caption.weight(.semibold))
                        }
                        ForEach(unlinkedDocuments) { document in
                            ProjectFinancialAttachmentRow(
                                document: document,
                                isSelected: selectedUnlinkedDocumentIds.contains(document.id),
                                trailingTitle: "关联",
                                warning: document.linkedFinancialRecordId != nil && document.linkedFinancialRecordId != record.id ? "已关联其他账目，点击后将重新关联" : nil,
                                onToggleSelection: { toggleUnlinked(document.id) },
                                onAction: { onAttach(document) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("票据附件管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                onImportFiles(urls)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSource) { image in
                onImportImage(image, "来源: 拍照")
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await importPhotoLibraryItem(item)
            }
        }
    }

    private func importPhotoLibraryItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await MainActor.run {
                selectedPhotoItem = nil
            }
            return
        }
        await MainActor.run {
            if let image = UIImage(data: data) {
                onImportImage(image, "来源: 相册")
            }
            selectedPhotoItem = nil
        }
    }

    private func toggleLinked(_ id: UUID) {
        if selectedLinkedDocumentIds.contains(id) {
            selectedLinkedDocumentIds.remove(id)
        } else {
            selectedLinkedDocumentIds.insert(id)
        }
    }

    private func toggleUnlinked(_ id: UUID) {
        if selectedUnlinkedDocumentIds.contains(id) {
            selectedUnlinkedDocumentIds.remove(id)
        } else {
            selectedUnlinkedDocumentIds.insert(id)
        }
    }
}

private struct ProjectFinancialAttachmentRow: View {
    let document: ProjectDocument
    let isSelected: Bool
    let trailingTitle: String
    var warning: String?
    let onToggleSelection: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.appPrimaryAction : .secondary)
            }
            .buttonStyle(.plain)
            ProjectDocumentPDFThumbnail(document: document)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.callout.weight(.medium))
                Text(metaText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let warning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(Color.appPrimaryAction)
                }
            }
            Spacer()
            Button(trailingTitle, action: onAction)
                .font(.caption.weight(.semibold))
        }
    }

    private var metaText: String {
        let fileType = document.fileType.isEmpty ? "附件" : document.fileType.uppercased()
        let pageText = document.fileType.lowercased() == "pdf" ? " · \(document.pageCount) 页" : ""
        return "\(document.category.displayName) · \(fileType)\(pageText) · \(document.createdAt)"
    }
}

private struct ProjectDocumentPDFThumbnail: View {
    let document: ProjectDocument
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .font(.title3)
                    .foregroundStyle(Color.appDoc)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appDocSurfaceSubtle)
            }
        }
        .frame(width: 44, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appStrokeSeparator, lineWidth: 0.5))
        .task(id: document.fileName) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        thumbnail = nil
        guard let data = await ProjectDocumentStorage.dataAsync(for: document.fileName) else { return }
        let fileType = document.fileType.lowercased()
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            if fileType != "pdf", let image = UIImage(data: data) {
                return image
            }
            guard let pdf = PDFDocument(data: data),
                  let page = pdf.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 88, height: 108), for: .cropBox)
        }.value
        guard !Task.isCancelled else { return }
        thumbnail = loaded
    }

    private var fallbackIcon: String {
        switch document.fileType.lowercased() {
        case "jpg", "jpeg", "png", "heic", "webp":
            return "photo"
        case "mov", "mp4", "m4v":
            return "video.fill"
        case "dwg", "dxf":
            return "ruler"
        case "xls", "xlsx", "csv", "numbers":
            return "tablecells"
        case "doc", "docx", "pages":
            return "doc.text"
        default:
            return ProjectDetailFinanceDocumentHelper.documentIcon(document.category)
        }
    }
}
