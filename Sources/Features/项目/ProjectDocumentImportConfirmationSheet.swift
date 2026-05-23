import SwiftUI
import UniformTypeIdentifiers

struct ProjectDocumentImportLedgerSettings: Equatable {
    var category: ProjectDocumentCategory
    var submissionStatus: ProjectDocumentSubmissionStatus
    var formedAt: String
    var responsiblePerson: String
    var workSection: String

    init(
        category: ProjectDocumentCategory = .constructionRecord,
        submissionStatus: ProjectDocumentSubmissionStatus = .notSubmitted,
        formedAt: String = "",
        responsiblePerson: String = "",
        workSection: String = ""
    ) {
        self.category = category
        self.submissionStatus = submissionStatus
        self.formedAt = formedAt
        self.responsiblePerson = responsiblePerson
        self.workSection = workSection
    }

    var normalized: ProjectDocumentImportLedgerSettings {
        ProjectDocumentImportLedgerSettings(
            category: category,
            submissionStatus: submissionStatus,
            formedAt: formedAt.trimmingCharacters(in: .whitespacesAndNewlines),
            responsiblePerson: responsiblePerson.trimmingCharacters(in: .whitespacesAndNewlines),
            workSection: workSection.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct ProjectDocumentImportConfirmationRequest: Identifiable {
    let id = UUID()
    var urls: [URL]
    var defaultSettings: ProjectDocumentImportLedgerSettings
}

struct ProjectDocumentImportConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    let defaultSettings: ProjectDocumentImportLedgerSettings
    let onConfirm: (ProjectDocumentImportLedgerSettings) -> Void

    @State private var category: ProjectDocumentCategory
    @State private var submissionStatus: ProjectDocumentSubmissionStatus
    @State private var hasFormedAt: Bool
    @State private var formedAtDate: Date
    @State private var responsiblePerson: String
    @State private var workSection: String

    init(
        urls: [URL],
        defaultSettings: ProjectDocumentImportLedgerSettings,
        onConfirm: @escaping (ProjectDocumentImportLedgerSettings) -> Void
    ) {
        self.urls = urls
        self.defaultSettings = defaultSettings
        self.onConfirm = onConfirm
        _category = State(initialValue: defaultSettings.category)
        _submissionStatus = State(initialValue: defaultSettings.submissionStatus)
        let normalizedFormedAt = defaultSettings.formedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        _hasFormedAt = State(initialValue: !normalizedFormedAt.isEmpty)
        _formedAtDate = State(initialValue: ProjectDocumentFormDate.date(from: normalizedFormedAt) ?? Date())
        _responsiblePerson = State(initialValue: defaultSettings.responsiblePerson)
        _workSection = State(initialValue: defaultSettings.workSection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "导入文件")) {
                    LabeledContent(
                        String(localized: "文件数量"),
                        value: String(format: String(localized: "%lld 个"), Int64(urls.count))
                    )
                    ForEach(urls, id: \.self) { url in
                        HStack(spacing: AppSpacing.tight) {
                            Image(systemName: iconName(for: url))
                                .foregroundStyle(Color.appDoc)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.callout)
                                    .lineLimit(1)
                                Text(fileTypeText(for: url))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(String(localized: "台账信息")) {
                    Picker(String(localized: "资料类型"), selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    Picker(String(localized: "报验状态"), selection: $submissionStatus) {
                        ForEach(ProjectDocumentSubmissionStatus.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    Toggle(String(localized: "填写形成日期"), isOn: $hasFormedAt)
                    if hasFormedAt {
                        DatePicker(
                            String(localized: "形成日期"),
                            selection: $formedAtDate,
                            displayedComponents: .date
                        )
                    }
                    TextField(String(localized: "责任人"), text: $responsiblePerson)
                    TextField(String(localized: "分部/工序"), text: $workSection)
                }
            }
            .navigationTitle(String(localized: "确认导入资料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "导入")) {
                        onConfirm(settings)
                        dismiss()
                    }
                    .disabled(urls.isEmpty)
                }
            }
        }
    }

    private var settings: ProjectDocumentImportLedgerSettings {
        ProjectDocumentImportLedgerSettings(
            category: category,
            submissionStatus: submissionStatus,
            formedAt: hasFormedAt ? Formatters.date.string(from: formedAtDate) : "",
            responsiblePerson: responsiblePerson,
            workSection: workSection
        )
        .normalized
    }

    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return "doc.richtext.fill" }
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .image) {
            return "photo.fill"
        }
        return "doc.fill"
    }

    private func fileTypeText(for url: URL) -> String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? String(localized: "文件") : ext.uppercased()
    }
}
