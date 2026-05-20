import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ProjectFileCategory: CaseIterable {
    case images
    case drawings
    case documents
    case quickNoteAttachments

    var title: String {
        switch self {
        case .images: return "图片"
        case .drawings: return "CAD与图纸"
        case .documents: return "票据资料"
        case .quickNoteAttachments: return "随手记附件"
        }
    }

    var description: String {
        switch self {
        case .images: return "施工日志、待办整改、随手记图片"
        case .drawings: return "DWG、DXF、PDF 图纸"
        case .documents: return "发票、收据、合同、施工资料"
        case .quickNoteAttachments: return "视频、文档、表格等附件"
        }
    }

    var systemImage: String {
        switch self {
        case .images: return "photo.on.rectangle"
        case .drawings: return "doc.viewfinder"
        case .documents: return "doc.richtext"
        case .quickNoteAttachments: return "paperclip"
        }
    }

    var tint: Color {
        switch self {
        case .images: return .appDoc
        case .drawings: return .appPrimaryAction
        case .documents: return .appPrimaryAction
        case .quickNoteAttachments: return .appPrimaryAction
        }
    }
}

enum ProjectFileHealthFilter: String, CaseIterable {
    case all
    case missing
    case actionDocuments
    case returnedDocuments
    case unarchivedDocuments
    case incompleteDocumentLedger
    case largeFiles

    var title: String {
        switch self {
        case .all: return "全部"
        case .missing: return "文件缺失"
        case .actionDocuments: return "待处理"
        case .returnedDocuments: return "退回修改"
        case .unarchivedDocuments: return "未归档"
        case .incompleteDocumentLedger: return "台账缺项"
        case .largeFiles: return "大文件"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .missing: return "exclamationmark.triangle.fill"
        case .actionDocuments: return "clock.badge.exclamationmark"
        case .returnedDocuments: return "arrow.uturn.backward.circle.fill"
        case .unarchivedDocuments: return "archivebox"
        case .incompleteDocumentLedger: return "list.clipboard"
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .appPrimaryAction
        case .missing, .returnedDocuments, .largeFiles: return .appRisk
        case .actionDocuments, .unarchivedDocuments, .incompleteDocumentLedger: return .appWarning
        }
    }

    func matches(_ item: ProjectFileItem) -> Bool {
        switch self {
        case .all:
            return true
        case .missing:
            return !item.exists
        case .actionDocuments:
            return item.documentStatus?.requiresArchiveAttention == true
        case .returnedDocuments:
            return item.documentStatus == .returned
        case .unarchivedDocuments:
            guard let status = item.documentStatus else { return false }
            return status != .archived
        case .incompleteDocumentLedger:
            return item.documentLedgerIssueCount > 0
        case .largeFiles:
            return item.isLargeFile
        }
    }
}

@MainActor
struct ProjectFileSummary {
    let imageCount: Int
    let drawingCount: Int
    let documentCount: Int
    let quickNoteAttachmentCount: Int

    var totalCount: Int {
        imageCount + drawingCount + documentCount + quickNoteAttachmentCount
    }

    init(projectId: UUID, store: DataStore) {
        imageCount = ProjectFileCollector.count(for: projectId, category: .images, store: store)
        drawingCount = ProjectFileCollector.count(for: projectId, category: .drawings, store: store)
        documentCount = ProjectFileCollector.count(for: projectId, category: .documents, store: store)
        quickNoteAttachmentCount = ProjectFileCollector.count(for: projectId, category: .quickNoteAttachments, store: store)
    }

    func count(for category: ProjectFileCategory) -> Int {
        switch category {
        case .images: return imageCount
        case .drawings: return drawingCount
        case .documents: return documentCount
        case .quickNoteAttachments: return quickNoteAttachmentCount
        }
    }
}

enum ProjectDocumentDeliveryInspectionIssueKind: CaseIterable {
    case missingCategories
    case missingFiles
    case returnedDocuments
    case unarchivedDocuments
    case missingResponsiblePerson
    case missingFormedDate

    var title: String {
        switch self {
        case .missingCategories: return String(localized: "缺类别")
        case .missingFiles: return String(localized: "文件丢失")
        case .returnedDocuments: return String(localized: "退回修改")
        case .unarchivedDocuments: return String(localized: "未归档")
        case .missingResponsiblePerson: return String(localized: "缺责任人")
        case .missingFormedDate: return String(localized: "缺形成日期")
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
            return String(localized: "查看资料分类")
        case .missingFiles:
            return String(localized: "筛选缺失文件")
        case .returnedDocuments:
            return String(localized: "筛选退回资料")
        case .unarchivedDocuments:
            return String(localized: "筛选未归档资料")
        case .missingResponsiblePerson, .missingFormedDate:
            return String(localized: "筛选台账缺项")
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
    init(project: Project, store: DataStore) {
        self.init(
            project: project,
            documents: store.projectDocuments.filter { $0.projectId == project.id },
            drawings: store.projectDrawings.filter { $0.projectId == project.id },
            logs: store.dailyLogs.filter { $0.projectId == project.id },
            quickNotes: store.quickNotes.filter { $0.projectId == project.id }
        )
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
                title: String(format: String(localized: "补齐交付缺失文件：%@"), missingFile),
                note: String(format: String(localized: "交付体检发现原件缺失：%@。请补齐文件后重新进入项目资料页体检。"), missingFile),
                priority: .high,
                issueType: .general
            ))
        }

        for document in returnedDocuments {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "returned-\(document.id.uuidString)",
                title: String(format: String(localized: "处理退回资料：%@"), title),
                note: String(format: String(localized: "交付体检发现资料处于退回修改：%@。请补正后重新报验，并在资料详情更新状态。"), Self.documentLedgerDetail(document)),
                priority: .high,
                issueType: .quality
            ))
        }

        for document in unarchivedDocuments where document.submissionStatus != .returned {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "unarchived-\(document.id.uuidString)",
                title: String(format: String(localized: "归档项目资料：%@"), title),
                note: String(format: String(localized: "交付体检发现资料未归档：%@。请完成报验闭环后设为已归档。"), Self.documentLedgerDetail(document)),
                priority: .medium,
                issueType: .general
            ))
        }

        for document in missingResponsibleDocuments {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "missing-owner-\(document.id.uuidString)",
                title: String(format: String(localized: "补录资料责任人：%@"), title),
                note: String(format: String(localized: "交付体检发现资料台账缺责任人：%@。请补录责任人后重新体检。"), Self.documentLedgerDetail(document)),
                priority: .medium,
                issueType: .general
            ))
        }

        for document in missingFormedDateDocuments {
            let title = Self.documentDisplayName(document)
            drafts.append(ProjectDocumentDeliveryInspectionTodoDraft(
                id: "missing-formed-date-\(document.id.uuidString)",
                title: String(format: String(localized: "补录资料形成日期：%@"), title),
                note: String(format: String(localized: "交付体检发现资料台账缺形成日期：%@。请补录形成日期后重新体检。"), Self.documentLedgerDetail(document)),
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
        return fileName.isEmpty ? String(localized: "未命名资料") : fileName
    }

    fileprivate static func documentLedgerDetail(_ document: ProjectDocument) -> String {
        [
            document.category.displayName,
            document.versionDisplayText,
            document.submissionStatus.displayName,
            document.formedAt.isEmpty ? nil : String(format: String(localized: "形成 %@"), document.formedAt),
            document.responsiblePerson.isEmpty ? nil : String(format: String(localized: "责任人 %@"), document.responsiblePerson),
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
        String(format: String(localized: "交付体检清单-%@.%@"), Formatters.date.string(from: Date()), fileExtension)
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
            String(localized: "项目"),
            String(localized: "问题类型"),
            String(localized: "对象"),
            String(localized: "当前状态"),
            String(localized: "说明")
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

            draw(String(localized: "交付体检清单"), font: .boldSystemFont(ofSize: 22), spacingAfter: 10)
            draw(
                String(
                    format: String(localized: "导出时间 %@ · 体检项目 %lld 个 · 问题项目 %lld 个 · 问题项 %lld 条"),
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
                status: String(localized: "缺项"),
                detail: String(localized: "当前项目资料清单要求该类别，但未发现可归档资料。")
            ))
        }

        for missingFile in inspection.missingFiles {
            rows.append(ProjectDocumentDeliveryInspectionExportRow(
                projectName: inspection.project.name,
                issueTitle: ProjectDocumentDeliveryInspectionIssueKind.missingFiles.title,
                itemTitle: missingFile,
                status: String(localized: "文件丢失"),
                detail: String(localized: "台账记录存在，但本机文件未找到。")
            ))
        }

        for document in inspection.returnedDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .returnedDocuments,
                status: document.submissionStatus.displayName,
                detail: String(localized: "需要补正后重新报验。")
            ))
        }

        for document in inspection.unarchivedDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .unarchivedDocuments,
                status: document.submissionStatus.displayName,
                detail: String(localized: "交付前需要完成归档状态。")
            ))
        }

        for document in inspection.missingResponsibleDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .missingResponsiblePerson,
                status: String(localized: "责任人为空"),
                detail: String(localized: "补齐资料责任人，方便报验和追溯。")
            ))
        }

        for document in inspection.missingFormedDateDocuments {
            rows.append(documentRow(
                inspection: inspection,
                document: document,
                kind: .missingFormedDate,
                status: String(localized: "形成日期为空"),
                detail: String(localized: "补齐资料形成日期，避免台账日期口径不统一。")
            ))
        }

        if rows.isEmpty {
            rows.append(ProjectDocumentDeliveryInspectionExportRow(
                projectName: inspection.project.name,
                issueTitle: String(localized: "体检通过"),
                itemTitle: "-",
                status: String(localized: "通过"),
                detail: String(localized: "暂未发现缺类别、文件丢失、退回、未归档、缺责任人或缺形成日期。")
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

struct ProjectFileItem: Identifiable {
    static let largeFileWarningBytes = 100 * 1024 * 1024

    let id: String
    let title: String
    let subtitle: String
    let fileType: String
    let url: URL
    let exists: Bool
    let size: Int
    let category: ProjectFileCategory
    let systemImage: String
    let thumbnailToken: ProjectFileThumbnailToken?
    let sortDate: Date
    let documentStatus: ProjectDocumentSubmissionStatus?
    var documentLedgerIssueCount = 0

    var formattedSize: String {
        size > 0 ? QuickNoteAttachmentStorage.formattedFileSize(size) : "-"
    }

    var isLargeFile: Bool {
        size >= Self.largeFileWarningBytes
    }

    var hasDocumentLedgerIssues: Bool {
        documentLedgerIssueCount > 0
    }
}

enum ProjectFileThumbnailToken: Hashable {
    case photo(fileName: String)
    case quickNote(kind: QuickNoteAttachmentKind, fileName: String)

    var cacheKey: String {
        switch self {
        case .photo(let fileName):
            return "photo:\(fileName)"
        case .quickNote(let kind, let fileName):
            return "quick:\(kind.rawValue):\(fileName)"
        }
    }

    func loadImageAsync() async -> UIImage? {
        switch self {
        case .photo(let fileName):
            return await PhotoStorage.thumbnailAsync(for: fileName)
        case .quickNote(let kind, let fileName):
            switch kind {
            case .photo, .drawing:
                guard let data = await QuickNoteAttachmentStorage.dataAsync(for: fileName) else { return nil }
                return await Task.detached(priority: .utility) {
                    Self.downsampleImage(data, maxPixelSize: 256)
                }.value
            case .video:
                return await Task.detached(priority: .utility) {
                    QuickNoteAttachmentStorage.videoThumbnail(for: fileName)
                }.value
            case .audio, .file:
                return nil
            }
        }
    }

    private static func downsampleImage(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

enum ProjectFileThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

@MainActor
enum ProjectFileCollector {
    private struct RecentSeed {
        let id: String
        let title: String
        let subtitle: String
        let fileType: String
        let url: URL
        let category: ProjectFileCategory
        let systemImage: String
        let sortDate: Date
        let thumbnailToken: ProjectFileThumbnailToken?
        let existsProvider: () -> Bool
        let sizeProvider: () -> Int
    }

    static func items(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> [ProjectFileItem] {
        switch category {
        case .images:
            return imageItems(for: projectId, store: store)
        case .drawings:
            return drawingItems(for: projectId, store: store)
        case .documents:
            return documentItems(for: projectId, store: store)
        case .quickNoteAttachments:
            return quickNoteAttachmentItems(for: projectId, store: store)
        }
    }

    static func allItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        ProjectFileCategory.allCases.flatMap { category in
            items(for: projectId, category: category, store: store)
        }
    }

    static func count(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> Int {
        switch category {
        case .images:
            let logPhotoCount = store.dailyLogs
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.photoAttachments.count }
            let todoPhotoCount = store.siteTodos
                .filter { $0.projectId == projectId }
                .reduce(0) { count, todo in
                    count
                        + (todo.rectificationBeforePhotoFileName == nil ? 0 : 1)
                        + (todo.rectificationAfterPhotoFileName == nil ? 0 : 1)
                }
            let quickNotePhotoCount = store.quickNotes
                .filter { $0.projectId == projectId }
                .flatMap(\.attachments)
                .filter { [.photo, .drawing].contains($0.attachmentKind) }
                .count
            return logPhotoCount + todoPhotoCount + quickNotePhotoCount
        case .drawings:
            return store.projectDrawings.filter { $0.projectId == projectId }.count
        case .documents:
            return store.projectDocuments.filter { $0.projectId == projectId }.count
        case .quickNoteAttachments:
            return store.quickNotes
                .filter { $0.projectId == projectId }
                .flatMap(\.attachments)
                .filter { ![QuickNoteAttachmentKind.photo, .drawing].contains($0.attachmentKind) }
                .count
        }
    }

    static func allRecent(for projectId: UUID, limit: Int, store: DataStore) -> [ProjectFileItem] {
        recentSeeds(for: projectId, store: store)
            .sorted { $0.sortDate > $1.sortDate }
            .prefix(limit)
            .map { seed in
                ProjectFileItem(
                    id: seed.id,
                    title: seed.title,
                    subtitle: seed.subtitle,
                    fileType: seed.fileType,
                    url: seed.url,
                    exists: seed.existsProvider(),
                    size: seed.sizeProvider(),
                    category: seed.category,
                    systemImage: seed.systemImage,
                    thumbnailToken: seed.thumbnailToken,
                    sortDate: seed.sortDate,
                    documentStatus: nil
                )
            }
    }

    private static func recentSeeds(for projectId: UUID, store: DataStore) -> [RecentSeed] {
        var seeds: [RecentSeed] = []

        for log in store.dailyLogs where log.projectId == projectId {
            for photo in log.photoAttachments {
                let fileName = photo.fileName
                let url = PhotoStorage.fileURL(for: fileName)
                seeds.append(
                    RecentSeed(
                        id: "log-\(log.id.uuidString)-\(fileName)",
                        title: photo.note.isEmpty ? "施工日志照片" : photo.note,
                        subtitle: "\(log.date) · \(photo.tag.displayName)",
                        fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
                        url: url,
                        category: .images,
                        systemImage: "photo",
                        sortDate: parsedDate(from: log.date),
                        thumbnailToken: .photo(fileName: fileName),
                        existsProvider: { PhotoStorage.exists(fileName: fileName) },
                        sizeProvider: { PhotoStorage.fileSize(for: fileName) }
                    )
                )
            }
        }

        for todo in store.siteTodos where todo.projectId == projectId {
            if let fileName = todo.rectificationBeforePhotoFileName {
                let url = PhotoStorage.fileURL(for: fileName)
                let sortText = todo.dueDate
                seeds.append(
                    RecentSeed(
                        id: "todo-before-\(todo.id.uuidString)",
                        title: "\(todo.title) · 整改前",
                        subtitle: sortText,
                        fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
                        url: url,
                        category: .images,
                        systemImage: "photo",
                        sortDate: parsedDate(from: sortText),
                        thumbnailToken: .photo(fileName: fileName),
                        existsProvider: { PhotoStorage.exists(fileName: fileName) },
                        sizeProvider: { PhotoStorage.fileSize(for: fileName) }
                    )
                )
            }
            if let fileName = todo.rectificationAfterPhotoFileName {
                let url = PhotoStorage.fileURL(for: fileName)
                let sortText = todo.completedAt ?? todo.dueDate
                seeds.append(
                    RecentSeed(
                        id: "todo-after-\(todo.id.uuidString)",
                        title: "\(todo.title) · 整改后",
                        subtitle: sortText,
                        fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
                        url: url,
                        category: .images,
                        systemImage: "photo",
                        sortDate: parsedDate(from: sortText),
                        thumbnailToken: .photo(fileName: fileName),
                        existsProvider: { PhotoStorage.exists(fileName: fileName) },
                        sizeProvider: { PhotoStorage.fileSize(for: fileName) }
                    )
                )
            }
        }

        for note in store.quickNotes where note.projectId == projectId {
            for attachment in note.attachments {
                let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
                let displayName = attachment.displayName == attachment.fileName ? attachment.attachmentKind.title : attachment.displayName
                let sortDate = parsedDate(from: note.createdAt)
                switch attachment.attachmentKind {
                case .photo, .drawing:
                    seeds.append(
                        RecentSeed(
                            id: "quicknote-\(note.id.uuidString)-\(attachment.id.uuidString)",
                            title: displayName,
                            subtitle: "\(note.createdAt) · \(attachment.attachmentKind.title)",
                            fileType: url.pathExtension.isEmpty ? attachment.attachmentKind.title : url.pathExtension,
                            url: url,
                            category: .images,
                            systemImage: attachment.attachmentKind.systemImage,
                            sortDate: sortDate,
                            thumbnailToken: .quickNote(kind: attachment.attachmentKind, fileName: attachment.fileName),
                            existsProvider: { QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) },
                            sizeProvider: { QuickNoteAttachmentStorage.fileSize(for: attachment.fileName) }
                        )
                    )
                case .video, .audio, .file:
                    seeds.append(
                        RecentSeed(
                            id: "quicknote-\(note.id.uuidString)-\(attachment.id.uuidString)",
                            title: displayName,
                            subtitle: "\(note.createdAt) · \(attachment.attachmentKind.title)",
                            fileType: url.pathExtension.isEmpty ? attachment.attachmentKind.title : url.pathExtension,
                            url: url,
                            category: .quickNoteAttachments,
                            systemImage: attachment.attachmentKind.systemImage,
                            sortDate: sortDate,
                            thumbnailToken: .quickNote(kind: attachment.attachmentKind, fileName: attachment.fileName),
                            existsProvider: { QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) },
                            sizeProvider: { QuickNoteAttachmentStorage.fileSize(for: attachment.fileName) }
                        )
                    )
                }
            }
        }

        for drawing in store.projectDrawings where drawing.projectId == projectId {
            let fileName = drawing.fileName
            let url = DrawingStorage.fileURL(for: fileName)
            seeds.append(
                RecentSeed(
                    id: "drawing-\(drawing.id.uuidString)",
                    title: drawing.name,
                    subtitle: "\(drawing.version) · \(drawing.importedAt)",
                    fileType: drawing.fileType,
                    url: url,
                    category: .drawings,
                    systemImage: ProjectDetailDrawingHelper.drawingIcon(drawing.fileType),
                    sortDate: parsedDate(from: drawing.importedAt),
                    thumbnailToken: nil,
                    existsProvider: { DrawingStorage.exists(fileName: fileName) },
                    sizeProvider: { DrawingStorage.fileSize(for: fileName) }
                )
            )
        }

        for document in store.projectDocuments where document.projectId == projectId {
            let fileName = document.fileName
            let url = ProjectDocumentStorage.fileURL(for: fileName)
            seeds.append(
                RecentSeed(
                    id: "document-\(document.id.uuidString)",
                    title: document.title,
                    subtitle: "\(document.category.displayName) · \(document.createdAt)",
                    fileType: document.fileType,
                    url: url,
                    category: .documents,
                    systemImage: ProjectDetailFinanceDocumentHelper.documentIcon(document.category),
                    sortDate: parsedDate(from: document.createdAt),
                    thumbnailToken: nil,
                    existsProvider: { ProjectDocumentStorage.exists(fileName: fileName) },
                    sizeProvider: { ProjectDocumentStorage.fileSize(for: fileName) }
                )
            )
        }

        return seeds
    }

    private static func imageItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        var result: [ProjectFileItem] = []

        for log in store.dailyLogs where log.projectId == projectId {
            for photo in log.photoAttachments {
                result.append(photoItem(
                    id: "log-\(log.id.uuidString)-\(photo.fileName)",
                    title: photo.note.isEmpty ? "施工日志照片" : photo.note,
                    subtitle: "\(log.date) · \(photo.tag.displayName)",
                    sortText: log.date,
                    fileName: photo.fileName
                ))
            }
        }

        for todo in store.siteTodos where todo.projectId == projectId {
            if let fileName = todo.rectificationBeforePhotoFileName {
                result.append(photoItem(
                    id: "todo-before-\(todo.id.uuidString)",
                    title: "\(todo.title) · 整改前",
                    subtitle: todo.dueDate,
                    sortText: todo.dueDate,
                    fileName: fileName
                ))
            }
            if let fileName = todo.rectificationAfterPhotoFileName {
                result.append(photoItem(
                    id: "todo-after-\(todo.id.uuidString)",
                    title: "\(todo.title) · 整改后",
                    subtitle: todo.completedAt ?? todo.dueDate,
                    sortText: todo.completedAt ?? todo.dueDate,
                    fileName: fileName
                ))
            }
        }

        for note in store.quickNotes where note.projectId == projectId {
            for attachment in note.attachments where [.photo, .drawing].contains(attachment.attachmentKind) {
                result.append(quickNoteItem(
                    note: note,
                    attachment: attachment,
                    category: .images,
                    title: attachment.displayName == attachment.fileName ? attachment.attachmentKind.title : attachment.displayName
                ))
            }
        }

        return result.sorted { $0.sortDate > $1.sortDate }
    }

    private static func drawingItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        store.projectDrawings
            .filter { $0.projectId == projectId }
            .map { drawing in
                let url = DrawingStorage.fileURL(for: drawing.fileName)
                return ProjectFileItem(
                    id: "drawing-\(drawing.id.uuidString)",
                    title: drawing.name,
                    subtitle: "\(drawing.version) · \(drawing.importedAt)",
                    fileType: drawing.fileType,
                    url: url,
                    exists: DrawingStorage.exists(fileName: drawing.fileName),
                    size: DrawingStorage.fileSize(for: drawing.fileName),
                    category: .drawings,
                    systemImage: ProjectDetailDrawingHelper.drawingIcon(drawing.fileType),
                    thumbnailToken: nil,
                    sortDate: parsedDate(from: drawing.importedAt),
                    documentStatus: nil
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func documentItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        store.projectDocuments
            .filter { $0.projectId == projectId }
            .map { document in
                let url = ProjectDocumentStorage.fileURL(for: document.fileName)
                return ProjectFileItem(
                    id: "document-\(document.id.uuidString)",
                    title: document.title,
                    subtitle: "\(document.category.displayName) · \(document.createdAt)",
                    fileType: document.fileType,
                    url: url,
                    exists: ProjectDocumentStorage.exists(fileName: document.fileName),
                    size: ProjectDocumentStorage.fileSize(for: document.fileName),
                    category: .documents,
                    systemImage: ProjectDetailFinanceDocumentHelper.documentIcon(document.category),
                    thumbnailToken: nil,
                    sortDate: parsedDate(from: document.createdAt),
                    documentStatus: document.submissionStatus,
                    documentLedgerIssueCount: documentLedgerIssueCount(document)
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func documentLedgerIssueCount(_ document: ProjectDocument) -> Int {
        let missingResponsible = document.responsiblePerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingFormedDate = document.formedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (missingResponsible ? 1 : 0) + (missingFormedDate ? 1 : 0)
    }

    private static func quickNoteAttachmentItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        store.quickNotes
            .filter { $0.projectId == projectId }
            .flatMap { note in
                note.attachments
                    .filter { ![QuickNoteAttachmentKind.photo, .drawing].contains($0.attachmentKind) }
                    .map { attachment in
                        quickNoteItem(note: note, attachment: attachment, category: .quickNoteAttachments)
                    }
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func photoItem(id: String, title: String, subtitle: String, sortText: String, fileName: String) -> ProjectFileItem {
        let url = PhotoStorage.fileURL(for: fileName)
        return ProjectFileItem(
            id: id,
            title: title,
            subtitle: subtitle,
            fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
            url: url,
            exists: PhotoStorage.exists(fileName: fileName),
            size: PhotoStorage.fileSize(for: fileName),
            category: .images,
            systemImage: "photo",
            thumbnailToken: .photo(fileName: fileName),
            sortDate: parsedDate(from: sortText),
            documentStatus: nil
        )
    }

    private static func quickNoteItem(
        note: QuickNote,
        attachment: QuickNoteAttachment,
        category: ProjectFileCategory,
        title: String? = nil
    ) -> ProjectFileItem {
        let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
        return ProjectFileItem(
            id: "quicknote-\(note.id.uuidString)-\(attachment.id.uuidString)",
            title: title ?? attachment.displayName,
            subtitle: "\(note.createdAt) · \(attachment.attachmentKind.title)",
            fileType: url.pathExtension.isEmpty ? attachment.attachmentKind.title : url.pathExtension,
            url: url,
            exists: QuickNoteAttachmentStorage.exists(fileName: attachment.fileName),
            size: QuickNoteAttachmentStorage.fileSize(for: attachment.fileName),
            category: category,
            systemImage: attachment.attachmentKind.systemImage,
            thumbnailToken: .quickNote(kind: attachment.attachmentKind, fileName: attachment.fileName),
            sortDate: parsedDate(from: note.createdAt),
            documentStatus: nil
        )
    }

    private static func parsedDate(from raw: String) -> Date {
        if let date = Formatters.dateTime.date(from: raw) {
            return date
        }
        if let date = Formatters.date.date(from: raw) {
            return date
        }
        return .distantPast
    }
}
