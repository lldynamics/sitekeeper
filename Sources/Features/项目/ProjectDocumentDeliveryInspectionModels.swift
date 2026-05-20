import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ProjectDocumentDeliveryInspectionIssueKind: CaseIterable {
    case missingCategories
    case missingFiles
    case returnedDocuments
    case unarchivedDocuments
    case missingResponsiblePerson
    case missingFormedDate

    var title: String {
        switch self {
        case .missingCategories: return String(localized: "project.deliveryInspection.issue.missingCategories")
        case .missingFiles: return String(localized: "project.deliveryInspection.issue.missingFiles")
        case .returnedDocuments: return String(localized: "project.deliveryInspection.issue.returnedDocuments")
        case .unarchivedDocuments: return String(localized: "project.deliveryInspection.issue.unarchivedDocuments")
        case .missingResponsiblePerson: return String(localized: "project.deliveryInspection.issue.missingResponsiblePerson")
        case .missingFormedDate: return String(localized: "project.deliveryInspection.issue.missingFormedDate")
        }
    }

    var systemImage: String {
        switch self {
        case .missingCategories: return "folder.badge.questionmark"
        case .missingFiles: return "exclamationmark.triangle.fill"
        case .returnedDocuments: return "arrow.uturn.backward.circle.fill"
        case .unarchivedDocuments: return "archivebox"
        case .missingResponsiblePerson: return "person.crop.circle.badge.exclamationmark"
        case .missingFormedDate: return "calendar.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .missingCategories, .missingFiles, .returnedDocuments:
            return .appRisk
        case .unarchivedDocuments, .missingResponsiblePerson, .missingFormedDate:
            return .appWarning
        }
    }

    var preferredHealthFilter: ProjectFileHealthFilter {
        switch self {
        case .missingCategories:
            return .all
        case .missingFiles:
            return .missing
        case .returnedDocuments:
            return .returnedDocuments
        case .unarchivedDocuments:
            return .unarchivedDocuments
        case .missingResponsiblePerson, .missingFormedDate:
            return .incompleteDocumentLedger
        }
    }

    var preferredCategory: ProjectFileCategory? {
        switch self {
        case .returnedDocuments, .unarchivedDocuments, .missingResponsiblePerson, .missingFormedDate:
            return .documents
        case .missingCategories, .missingFiles:
            return nil
        }
    }

    var actionTitle: String {
        switch self {
        case .missingCategories:
            return String(localized: "project.deliveryInspection.action.viewCategories")
        case .missingFiles:
            return String(localized: "project.deliveryInspection.action.filterMissingFiles")
        case .returnedDocuments:
            return String(localized: "project.deliveryInspection.action.filterReturnedDocuments")
        case .unarchivedDocuments:
            return String(localized: "project.deliveryInspection.action.filterUnarchivedDocuments")
        case .missingResponsiblePerson, .missingFormedDate:
            return String(localized: "project.deliveryInspection.action.filterLedgerIssues")
        }
    }
}

struct ProjectDocumentDeliveryInspectionIssue: Identifiable {
    let kind: ProjectDocumentDeliveryInspectionIssueKind
    let count: Int
    let samples: [String]

    var id: ProjectDocumentDeliveryInspectionIssueKind { kind }
}

struct ProjectDocumentDeliveryInspection: Identifiable {
    let project: Project
    let missingCategories: [ProjectDocumentCategory]
    let missingFiles: [String]
    let returnedDocuments: [ProjectDocument]
    let unarchivedDocuments: [ProjectDocument]
    let missingResponsibleDocuments: [ProjectDocument]
    let missingFormedDateDocuments: [ProjectDocument]

    var id: UUID { project.id }

    @MainActor
    init(project: Project, projectStore: ProjectStore) {
        self.init(
            project: project,
            documents: projectStore.projectDocuments(for: project.id),
            drawings: projectStore.projectDrawings(for: project.id),
            logs: projectStore.dailyLogs(for: project.id),
            quickNotes: projectStore.quickNotes(for: project.id)
        )
    }

    @MainActor
    init(project: Project, store: DataStore) {
        self.init(project: project, projectStore: store.projectStore)
    }

    init(
        project: Project,
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) {
        let projectDocuments = documents.sorted { $0.createdAt > $1.createdAt }
        let checklist = DocumentArchiveChecklistSnapshot(
            documents: projectDocuments,
            requiredCategories: project.requiredDocumentCategories
        )

        self.project = project
        missingCategories = checklist.items.filter(\.isMissing).map(\.category)
        missingFiles = ProjectDetailImportExportActions.missingProjectPackageFiles(
            documents: projectDocuments,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes
        )
        returnedDocuments = projectDocuments.filter { $0.submissionStatus == .returned }
        unarchivedDocuments = projectDocuments.filter { $0.submissionStatus != .archived }
        missingResponsibleDocuments = projectDocuments.filter {
            Self.isBlank($0.responsiblePerson)
        }
        missingFormedDateDocuments = projectDocuments.filter {
            Self.isBlank($0.formedAt)
        }
    }

    var issues: [ProjectDocumentDeliveryInspectionIssue] {
        [
            makeIssue(
                kind: .missingCategories,
                count: missingCategories.count,
                samples: missingCategories.map(\.displayName)
            ),
            makeIssue(
                kind: .missingFiles,
                count: missingFiles.count,
                samples: missingFiles
            ),
            makeIssue(
                kind: .returnedDocuments,
                count: returnedDocuments.count,
                samples: returnedDocuments.map(\.title)
            ),
            makeIssue(
                kind: .unarchivedDocuments,
                count: unarchivedDocuments.count,
                samples: unarchivedDocuments.map { "\($0.title) · \($0.submissionStatus.displayName)" }
            ),
            makeIssue(
                kind: .missingResponsiblePerson,
                count: missingResponsibleDocuments.count,
                samples: missingResponsibleDocuments.map(\.title)
            ),
            makeIssue(
                kind: .missingFormedDate,
                count: missingFormedDateDocuments.count,
                samples: missingFormedDateDocuments.map(\.title)
            )
        ].compactMap { $0 }
    }

    var issueGroupCount: Int {
        issues.count
    }

    var issueDetailCount: Int {
        issues.reduce(0) { $0 + $1.count }
    }

    var isReadyForDelivery: Bool {
        issues.isEmpty
    }

    private func makeIssue(
        kind: ProjectDocumentDeliveryInspectionIssueKind,
        count: Int,
        samples: [String]
    ) -> ProjectDocumentDeliveryInspectionIssue? {
        guard count > 0 else { return nil }
        return ProjectDocumentDeliveryInspectionIssue(
            kind: kind,
            count: count,
            samples: samples
        )
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProjectDocumentDeliveryInspectionTodoDraft: Identifiable, Equatable {
    let id: String
    let title: String
    let note: String
    let priority: TodoPriority
    let issueType: TodoIssueType
}

extension ProjectDocumentDeliveryInspection {
    var remediationTodoDrafts: [ProjectDocumentDeliveryInspectionTodoDraft] {
        var drafts: [ProjectDocumentDeliveryInspectionTodoDraft] = []

        for missingFile in missingFiles {
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "missing-file-\(missingFile)",
                title: String(format: String(localized: "project.deliveryInspection.todo.missingFile.title.format"), missingFile),
                note: String(format: String(localized: "project.deliveryInspection.todo.missingFile.note.format"), missingFile),
                priority: .high,
                issueType: .general
            ))
        }

        for document in returnedDocuments {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "returned-\(document.id.uuidString)",
                title: String(format: String(localized: "project.deliveryInspection.todo.returnedDocument.title.format"), title),
                note: String(format: String(localized: "project.deliveryInspection.todo.returnedDocument.note.format"), Self.documentLedgerDetail(document)),
                priority: .high,
                issueType: .quality
            ))
        }

        for document in unarchivedDocuments where document.submissionStatus != .returned {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "unarchived-\(document.id.uuidString)",
                title: String(format: String(localized: "project.deliveryInspection.todo.unarchivedDocument.title.format"), title),
                note: String(format: String(localized: "project.deliveryInspection.todo.unarchivedDocument.note.format"), Self.documentLedgerDetail(document)),
                priority: .medium,
                issueType: .general
            ))
        }

        for document in missingResponsibleDocuments {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "missing-owner-\(document.id.uuidString)",
                title: String(format: String(localized: "project.deliveryInspection.todo.missingResponsiblePerson.title.format"), title),
                note: String(format: String(localized: "project.deliveryInspection.todo.missingResponsiblePerson.note.format"), Self.documentLedgerDetail(document)),
                priority: .medium,
                issueType: .general
            ))
        }

        for document in missingFormedDateDocuments {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "missing-formed-date-\(document.id.uuidString)",
                title: String(format: String(localized: "project.deliveryInspection.todo.missingFormedDate.title.format"), title),
                note: String(format: String(localized: "project.deliveryInspection.todo.missingFormedDate.note.format"), Self.documentLedgerDetail(document)),
                priority: .medium,
                issueType: .general
            ))
        }

        return drafts
    }

    fileprivate static func documentDisplayName(_ document: ProjectDocument) -> String {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let fileName = document.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileName.isEmpty ? String(localized: "project.deliveryInspection.document.untitled") : fileName
    }

    fileprivate static func documentLedgerDetail(_ document: ProjectDocument) -> String {
        [
            document.category.displayName,
            document.versionDisplayText,
            document.submissionStatus.displayName,
            document.formedAt.isEmpty ? nil : String(format: String(localized: "project.deliveryInspection.document.formedAt.format"), document.formedAt),
            document.responsiblePerson.isEmpty ? nil : String(format: String(localized: "project.deliveryInspection.document.responsiblePerson.format"), document.responsiblePerson),
            document.workSection.isEmpty ? nil : document.workSection
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

enum ProjectDocumentDeliveryInspectionExportFormat {
    case pdf
    case csv

    var contentType: UTType {
        switch self {
        case .pdf:
            return .pdf
        case .csv:
            return .commaSeparatedText
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf:
            return "pdf"
        case .csv:
            return "csv"
        }
    }

    var defaultFileName: String {
        String(format: String(localized: "project.deliveryInspection.export.filename.format"), Formatters.date.string(from: Date()), fileExtension)
    }
}

@MainActor
enum ProjectDocumentDeliveryInspectionExport {
    static func makePayload(
        for inspections: [ProjectDocumentDeliveryInspection],
        format: ProjectDocumentDeliveryInspectionExportFormat
    ) -> ExportPayload {
        let data: Data
        switch format {
        case .pdf:
            data = pdfData(for: inspections)
        case .csv:
            data = csvData(for: inspections)
        }

        return ExportPayload(
            data: data,
            contentType: format.contentType,
            defaultFilename: format.defaultFileName
        )
    }

    static func csvData(for inspections: [ProjectDocumentDeliveryInspection]) -> Data {
        let header = [
            String(localized: "project.deliveryInspection.export.csv.project"),
            String(localized: "project.deliveryInspection.export.csv.issueType"),
            String(localized: "project.deliveryInspection.export.csv.item"),
            String(localized: "project.deliveryInspection.export.csv.status"),
            String(localized: "project.deliveryInspection.export.csv.detail")
        ]
        let lines = [csvLine(header)] + inspections.flatMap(rows).map { row in
            csvLine([row.projectName, row.issueTitle, row.itemTitle, row.status, row.detail])
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\n")).utf8)
    }

    static func pdfData(for inspections: [ProjectDocumentDeliveryInspection]) -> Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let margin: CGFloat = 36
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let issueProjects = inspections.filter { !$0.isReadyForDelivery }.count
        let issueCount = inspections.reduce(0) { $0 + $1.issueDetailCount }

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            func draw(
                _ text: String,
                font: UIFont,
                color: UIColor = .label,
                indent: CGFloat = 0,
                spacingAfter: CGFloat = 6
            ) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let width = pageBounds.width - margin * 2 - indent
                let rect = text.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                ).integral
                if y + rect.height > pageBounds.height - margin {
                    context.beginPage()
                    y = margin
                }
                text.draw(
                    with: CGRect(x: margin + indent, y: y, width: width, height: rect.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                y += rect.height + spacingAfter
            }

            draw(String(localized: "project.deliveryInspection.export.pdf.title"), font: .boldSystemFont(ofSize: 22), spacingAfter: 10)
            draw(
                String(
                    format: String(localized: "project.deliveryInspection.export.pdf.summary.format"),
                    Formatters.now(),
                    Int64(inspections.count),
                    Int64(issueProjects),
                    Int64(issueCount)
                ),
                font: .systemFont(ofSize: 10),
                color: .secondaryLabel,
                spacingAfter: 14
            )

            for inspection in inspections {
                draw(
                    inspection.project.name,
                    font: .boldSystemFont(ofSize: 14),
                    color: inspection.isReadyForDelivery ? .systemGreen : .label,
                    spacingAfter: 4
                )
                for row in rows(for: inspection) {
                    let line = "\(row.issueTitle) · \(row.itemTitle) · \(row.status)"
                    draw(line, font: .systemFont(ofSize: 11), indent: 12, spacingAfter: 3)
                    if !row.detail.isEmpty {
                        draw(row.detail, font: .systemFont(ofSize: 9), color: .secondaryLabel, indent: 24, spacingAfter: 5)
                    }
                }
                y += 8
            }
        }
    }

    private static func rows(for inspection: ProjectDocumentDeliveryInspection) -> [ProjectDocumentDeliveryInspectionExportRow] {
        var rows: [ProjectDocumentDeliveryInspectionExportRow] = []

        for category in inspection.missingCategories {
            rows.append(ProjectDocumentDeliveryInspectionExportRow(
                projectName: inspection.project.name,
                issueTitle: ProjectDocumentDeliveryInspectionIssueKind.missingCategories.title,
                itemTitle: category.displayName,
                status: String(localized: "project.deliveryInspection.export.status.missingCategory"),
                detail: String(localized: "project.deliveryInspection.export.detail.missingCategory")
            ))
        }

        for missingFile in inspection.missingFiles {
            rows.append(ProjectDocumentDeliveryInspectionExportRow(
                projectName: inspection.project.name,
                issueTitle: ProjectDocumentDeliveryInspectionIssueKind.missingFiles.title,
                itemTitle: missingFile,
                status: String(localized: "project.deliveryInspection.export.status.missingFile"),
                detail: String(localized: "project.deliveryInspection.export.detail.missingFile")
            ))
        }

        for document in inspection.returnedDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .returnedDocuments,
                status: document.submissionStatus.displayName,
                detail: String(localized: "project.deliveryInspection.export.detail.returnedDocument")
            ))
        }

        for document in inspection.unarchivedDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .unarchivedDocuments,
                status: document.submissionStatus.displayName,
                detail: String(localized: "project.deliveryInspection.export.detail.unarchivedDocument")
            ))
        }

        for document in inspection.missingResponsibleDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .missingResponsiblePerson,
                status: String(localized: "project.deliveryInspection.export.status.missingResponsiblePerson"),
                detail: String(localized: "project.deliveryInspection.export.detail.missingResponsiblePerson")
            ))
        }

        for document in inspection.missingFormedDateDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .missingFormedDate,
                status: String(localized: "project.deliveryInspection.export.status.missingFormedDate"),
                detail: String(localized: "project.deliveryInspection.export.detail.missingFormedDate")
            ))
        }

        if rows.isEmpty {
            rows.append(ProjectDocumentDeliveryInspectionExportRow(
                projectName: inspection.project.name,
                issueTitle: String(localized: "project.deliveryInspection.export.issue.passed"),
                itemTitle: "-",
                status: String(localized: "project.deliveryInspection.export.status.passed"),
                detail: String(localized: "project.deliveryInspection.export.detail.passed")
            ))
        }

        return rows
    }

    private static func documentRow(
        inspection: ProjectDocumentDeliveryInspection,
        document: ProjectDocument,
        kind: ProjectDocumentDeliveryInspectionIssueKind,
        status: String,
        detail: String
    ) -> ProjectDocumentDeliveryInspectionExportRow {
        let ledgerDetail = ProjectDocumentDeliveryInspection.documentLedgerDetail(document)
        return ProjectDocumentDeliveryInspectionExportRow(
            projectName: inspection.project.name,
            issueTitle: kind.title,
            itemTitle: ProjectDocumentDeliveryInspection.documentDisplayName(document),
            status: status,
            detail: ledgerDetail.isEmpty ? detail : "\(detail) \(ledgerDetail)"
        )
    }

    private static func csvLine(_ fields: [String]) -> String {
        fields.map { field in
            let escaped = field
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            return "\"\(escaped)\""
        }
        .joined(separator: ",")
    }
}

private struct ProjectDocumentDeliveryInspectionExportRow {
    let projectName: String
    let issueTitle: String
    let itemTitle: String
    let status: String
    let detail: String
}
