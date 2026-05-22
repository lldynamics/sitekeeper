import Foundation

extension ReportBuilder {
    enum ProjectPackageSchema {
        static let version = "1"
        static let type = "project_delivery_package"
        static let readmeFileName = "README.txt"
        static let deliveryDirectory = "00-delivery"
        static let documentDirectory = "01-documents"
        static let drawingDirectory = "02-drawings"
        static let photoDirectory = "03-site-photos"
        static let quickNoteDirectory = "04-quick-notes"
        static let contactDirectory = "05-contacts"
        static let checklistFileName = "delivery_checklist.txt"
        static let preDeliveryInspectionFileName = "pre_delivery_inspection.tsv"
        static let documentChecklistFileName = "document_checklist.tsv"
        static let currentDrawingRegisterFileName = "current_drawings.tsv"
        static let drawingMissingCheckFileName = "drawing_missing_check.tsv"
        static let openDrawingIssuesFileName = "open_drawing_issues.tsv"
        static let quickNotesFileName = "quick_notes.tsv"
        static let contactsFileName = "contacts.tsv"

        static func pdfFileName(folder: String) -> String {
            "\(folder)_project_delivery_package.pdf"
        }
    }

    enum ProjectDeliveryPackageHealthCheck: String, CaseIterable {
        case receipts
        case drawings
        case todos
        case backup
        case originals
        case currentDrawingVersions

        var displayName: String {
            switch self {
            case .receipts:
                return ReportBuilder.loc("缺票据")
            case .drawings:
                return ReportBuilder.loc("缺图纸")
            case .todos:
                return ReportBuilder.loc("未完成待办")
            case .backup:
                return ReportBuilder.loc("未备份")
            case .originals:
                return ReportBuilder.loc("资料缺原件")
            case .currentDrawingVersions:
                return ReportBuilder.loc("当前版缺失")
            }
        }
    }

    struct ProjectDeliveryPackageBackupState {
        let latestBackupDate: Date?
        let reminderDays: Int
        let referenceDate: Date

        static func current(referenceDate: Date = Date()) -> ProjectDeliveryPackageBackupState {
            let preferenceStore = UserPreferencesStore.shared
            let reminderDays = preferenceStore.backupReminderDays
            let latestBackupDate = preferenceStore.latestSuccessfulBackupDate

            return ProjectDeliveryPackageBackupState(
                latestBackupDate: latestBackupDate,
                reminderDays: reminderDays,
                referenceDate: referenceDate
            )
        }

        var isFresh: Bool {
            guard latestBackupDate != nil else { return false }
            return daysSinceLatestBackup < reminderDays
        }

        var daysSinceLatestBackup: Int {
            guard let latestBackupDate else { return Int.max }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: latestBackupDate)
            let end = calendar.startOfDay(for: referenceDate)
            return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
        }

        var detail: String {
            guard let latestBackupDate else {
                return ReportBuilder.loc("尚未记录成功备份")
            }
            if daysSinceLatestBackup == 0 {
                return ReportBuilder.locFormat("今天已备份，提醒阈值 %lld 天", Int64(reminderDays))
            }
            return ReportBuilder.locFormat(
                "最近备份 %@，已过 %lld 天",
                Formatters.dateTime.string(from: latestBackupDate),
                Int64(daysSinceLatestBackup)
            )
        }

        var latestBackupExportValue: String {
            latestBackupDate.map { Formatters.dateTime.string(from: $0) } ?? ""
        }
    }

    struct ProjectDeliveryPackageHealthReport {
        let missingReceiptCount: Int
        let drawingCount: Int
        let openTodoCount: Int
        let backupState: ProjectDeliveryPackageBackupState
        let missingOriginalEntries: [String]
        let drawingGroupsWithoutCurrent: [String]

        var failedChecks: [ProjectDeliveryPackageHealthCheck] {
            ProjectDeliveryPackageHealthCheck.allCases.filter { !isPassed($0) }
        }

        var score: Int {
            max(0, 100 - failedChecks.count * 20)
        }

        var isDeliverable: Bool {
            failedChecks.isEmpty
        }

        var machineVerdict: String {
            isDeliverable ? "deliverable" : "not_deliverable"
        }

        var verdictDisplayName: String {
            isDeliverable ? ReportBuilder.loc("可交付") : ReportBuilder.loc("不可交付")
        }

        var failedCheckKeys: String {
            failedChecks.map(\.rawValue).joined(separator: ",")
        }

        var failedCheckDisplayText: String {
            guard !failedChecks.isEmpty else { return ReportBuilder.loc("全部通过") }
            return failedChecks.map(\.displayName).joined(separator: ReportBuilder.loc("、"))
        }

        func isPassed(_ check: ProjectDeliveryPackageHealthCheck) -> Bool {
            switch check {
            case .receipts:
                return missingReceiptCount == 0
            case .drawings:
                return drawingCount > 0
            case .todos:
                return openTodoCount == 0
            case .backup:
                return backupState.isFresh
            case .originals:
                return missingOriginalEntries.isEmpty
            case .currentDrawingVersions:
                return drawingGroupsWithoutCurrent.isEmpty
            }
        }
    }

    struct ProjectPreDeliveryInspectionRow {
        let checkKey: String
        let checkDisplay: String
        let statusRaw: String
        let statusDisplay: String
        let severity: String
        let objectType: String
        let objectId: String
        let objectName: String
        let owner: String
        let dueDate: String
        let fileName: String
        let detail: String
        let recommendedAction: String

        var fields: [String] {
            [
                checkKey,
                checkDisplay,
                statusRaw,
                statusDisplay,
                severity,
                objectType,
                objectId,
                objectName,
                owner,
                dueDate,
                fileName,
                detail,
                recommendedAction
            ]
        }
    }

    struct ProjectDrawingOpenIssueRow {
        let drawing: ProjectDrawing
        let openTodos: [SiteTodo]

        var summary: String {
            let note = drawing.issueNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
            let titles = openTodos.map(\.title).filter { !$0.isEmpty }
            return titles.isEmpty ? ReportBuilder.loc("关联待办未关闭") : titles.joined(separator: ReportBuilder.loc("、"))
        }

        var issueLocations: String {
            joined(openTodos.map(\.drawingIssueLocation))
        }

        var layerOrPages: String {
            joined(openTodos.map(\.drawingIssueLayerOrPage))
        }

        var measurements: String {
            joined(openTodos.map(\.drawingIssueMeasurement))
        }

        var closeEvidence: String {
            joined(openTodos.map(\.drawingIssueCloseEvidence))
        }

        var screenshotFileNames: String {
            joined(openTodos.compactMap(\.rectificationBeforePhotoFileName))
        }

        var closingEvidenceFileNames: String {
            joined(openTodos.compactMap(\.rectificationAfterPhotoFileName))
        }

        private func joined(_ values: [String]) -> String {
            var seen: Set<String> = []
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { seen.insert($0).inserted }
                .joined(separator: "；")
        }
    }

    static func projectPackageArchiveFileName(projectName: String) -> String {
        "\(safeZipName(projectName, fallback: "untitled_project"))_project_delivery_package.zip"
    }

    static func safeZipName(_ raw: String, fallback: String = "untitled") -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
        let compact = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? fallback : compact
    }

    static func tsv(_ values: [String]) -> String {
        values.map(tsvField).joined(separator: "\t")
    }

    private static func tsvField(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    static func quickNoteAttachmentSummaryColumns(
        _ attachments: [QuickNoteAttachment]
    ) -> (raw: String, display: String) {
        let grouped = Dictionary(grouping: attachments, by: \.attachmentKind)
        let raw = QuickNoteAttachmentKind
            .allCases
            .compactMap { kind -> String? in
                let count = grouped[kind]?.count ?? 0
                guard count > 0 else { return nil }
                return "\(kind.rawValue):\(count)"
            }
            .joined(separator: ",")
        return (raw, QuickNoteText.attachmentSummary(attachments))
    }

    static func projectDocumentChecklistTSVText(_ checklist: DocumentArchiveChecklistSnapshot) -> String {
        let header = tsv([
            "category_key",
            "category_display",
            "status_raw",
            "status_display",
            "document_count",
            "action_count",
            "returned_count",
            "archived_count"
        ])
        let rows = checklist.items.map { item in
            tsv([
                item.category.exportKey,
                item.category.displayName,
                item.statusExportKey,
                item.statusText,
                "\(item.documentCount)",
                "\(item.actionCount)",
                "\(item.returnedCount)",
                "\(item.archivedCount)"
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func projectPreDeliveryInspectionTSVText(
        project: Project,
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        todos: [SiteTodo],
        logs: [DailyLog],
        quickNotes: [QuickNote],
        backupState: ProjectDeliveryPackageBackupState = .current()
    ) -> String {
        let header = tsv([
            "check_key",
            "check_display",
            "status_raw",
            "status_display",
            "severity",
            "object_type",
            "object_id",
            "object_name",
            "owner",
            "due_date",
            "file_name",
            "detail",
            "recommended_action"
        ])
        let rows = projectPreDeliveryInspectionRows(
            project: project,
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes,
            backupState: backupState
        )
        return ([header] + rows.map { tsv($0.fields) }).joined(separator: "\n")
    }

    static func projectPreDeliveryInspectionRows(
        project: Project,
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        todos: [SiteTodo],
        logs: [DailyLog],
        quickNotes: [QuickNote],
        backupState: ProjectDeliveryPackageBackupState = .current()
    ) -> [ProjectPreDeliveryInspectionRow] {
        var rows: [ProjectPreDeliveryInspectionRow] = []

        func pass(
            _ key: String,
            _ display: String,
            detail: String,
            action: String = ""
        ) {
            rows.append(ProjectPreDeliveryInspectionRow(
                checkKey: key,
                checkDisplay: display,
                statusRaw: "passed",
                statusDisplay: loc("通过"),
                severity: "ok",
                objectType: "project",
                objectId: project.id.uuidString,
                objectName: project.name,
                owner: "",
                dueDate: "",
                fileName: "",
                detail: detail,
                recommendedAction: action
            ))
        }

        let missingDrawingOriginals = projectPackageSortedDrawings(drawings)
            .filter { !DrawingStorage.exists(fileName: $0.fileName) }
        if missingDrawingOriginals.isEmpty {
            pass(
                "missing_drawing_original",
                loc("缺图纸原件"),
                detail: loc("图纸台账引用的本机原件均可找到。")
            )
        } else {
            rows += missingDrawingOriginals.map { drawing in
                ProjectPreDeliveryInspectionRow(
                    checkKey: "missing_drawing_original",
                    checkDisplay: loc("缺图纸原件"),
                    statusRaw: "failed",
                    statusDisplay: loc("未通过"),
                    severity: "blocker",
                    objectType: "drawing",
                    objectId: drawing.id.uuidString,
                    objectName: drawingDisplayName(drawing),
                    owner: drawing.receiver,
                    dueDate: drawing.issuedAt,
                    fileName: drawing.fileName,
                    detail: locFormat("图纸原件不存在，文件状态 %@。", drawing.fileAvailabilityStatus.displayName),
                    recommendedAction: loc("恢复原件文件，或重新导入该图纸当前版后再导出交付包。")
                )
            }
        }

        let openTodos = todos
            .filter { !$0.isDone }
            .sorted { lhs, rhs in
                if lhs.dueDate == rhs.dueDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.dueDate < rhs.dueDate
            }
        if openTodos.isEmpty {
            pass("open_todo", loc("未结待办"), detail: loc("没有未完成现场待办。"))
        } else {
            rows += openTodos.map { todo in
                ProjectPreDeliveryInspectionRow(
                    checkKey: "open_todo",
                    checkDisplay: loc("未结待办"),
                    statusRaw: "failed",
                    statusDisplay: loc("未通过"),
                    severity: todo.priority == .high ? "blocker" : "warning",
                    objectType: "todo",
                    objectId: todo.id.uuidString,
                    objectName: todo.title,
                    owner: todo.owner,
                    dueDate: todo.dueDate,
                    fileName: "",
                    detail: locFormat("%@待办，类型 %@。%@", todo.priority.displayName, todo.issueType.displayName, todo.note),
                    recommendedAction: loc("交付前关闭待办，或在交付说明中明确遗留责任和完成时间。")
                )
            }
        }

        let missingReceipts = projectPackageMissingReceiptRecords(
            financialRecords: financialRecords,
            documents: documents
        )
        if missingReceipts.isEmpty {
            pass("missing_receipt", loc("缺票据"), detail: loc("需要留票的账目均已关联票据或资料。"))
        } else {
            rows += missingReceipts.map { record in
                let name = [
                    record.date,
                    record.direction.displayName,
                    record.category.displayName,
                    money(number(record.amount)),
                    record.counterparty
                ].filter { !$0.isEmpty }.joined(separator: " ")
                return ProjectPreDeliveryInspectionRow(
                    checkKey: "missing_receipt",
                    checkDisplay: loc("缺票据"),
                    statusRaw: "failed",
                    statusDisplay: loc("未通过"),
                    severity: "warning",
                    objectType: "financial_record",
                    objectId: record.id.uuidString,
                    objectName: name,
                    owner: record.counterparty,
                    dueDate: record.dueDate,
                    fileName: "",
                    detail: locFormat("%@账目需要票据，但未关联票据/资料。", record.category.displayName),
                    recommendedAction: loc("补拍或导入票据原件，并关联到该账目。")
                )
            }
        }

        if backupState.isFresh {
            pass(
                "backup_freshness",
                loc("未备份"),
                detail: backupState.detail
            )
        } else {
            rows.append(ProjectPreDeliveryInspectionRow(
                checkKey: "backup_freshness",
                checkDisplay: loc("未备份"),
                statusRaw: "failed",
                statusDisplay: loc("未通过"),
                severity: "warning",
                objectType: "project",
                objectId: project.id.uuidString,
                objectName: project.name,
                owner: "",
                dueDate: "",
                fileName: "",
                detail: backupState.detail,
                recommendedAction: loc("导出最终交付包前先完成一次本地或 iCloud 备份。")
            ))
        }

        let drawingGroupsWithoutCurrent = projectPackageDrawingGroupsWithoutCurrentVersion(drawings)
        if drawingGroupsWithoutCurrent.isEmpty {
            pass(
                "missing_current_drawing_version",
                loc("当前版缺失"),
                detail: drawings.isEmpty ? loc("项目暂无图纸，已由缺图纸检查覆盖。") : loc("所有图纸组均已标记当前版。")
            )
        } else {
            rows += drawingGroupsWithoutCurrent.map { groupName in
                ProjectPreDeliveryInspectionRow(
                    checkKey: "missing_current_drawing_version",
                    checkDisplay: loc("当前版缺失"),
                    statusRaw: "failed",
                    statusDisplay: loc("未通过"),
                    severity: "warning",
                    objectType: "drawing_group",
                    objectId: "",
                    objectName: groupName,
                    owner: "",
                    dueDate: "",
                    fileName: "",
                    detail: loc("该图纸组存在版本记录，但没有任何一版标记为当前版。"),
                    recommendedAction: loc("在图纸台账中确认最终版本，并标记为当前版。")
                )
            }
        }

        return rows
    }

    static func projectCurrentDrawingRegisterTSVText(_ drawings: [ProjectDrawing]) -> String {
        let header = tsv([
            "drawing_id",
            "drawing_number",
            "name",
            "discipline",
            "floor_area",
            "version",
            "issued_at",
            "receiver",
            "file_type",
            "file_name",
            "file_exists",
            "file_availability_status",
            "file_availability_checked_at",
            "external_open_failure_reason",
            "external_open_failed_at",
            "issue_status_raw",
            "issue_status_display",
            "linked_todo_count",
            "linked_log_count",
            "linked_document_count",
            "imported_at",
            "note"
        ])
        let rows = currentProjectPackageDrawings(drawings).map { drawing in
            tsv([
                drawing.id.uuidString,
                drawing.drawingNumber,
                drawingDisplayName(drawing),
                drawing.discipline,
                drawing.floorArea,
                drawing.version,
                drawing.issuedAt,
                drawing.receiver,
                drawing.fileType,
                drawing.fileName,
                DrawingStorage.exists(fileName: drawing.fileName) ? "true" : "false",
                drawing.fileAvailabilityStatus.rawValue,
                drawing.fileAvailabilityCheckedAt,
                drawing.externalOpenFailureReason,
                drawing.externalOpenFailedAt,
                drawingIssueStatusKey(drawing.issueStatus),
                drawing.issueStatus.displayName,
                "\(drawing.linkedTodoIDs.count)",
                "\(drawing.linkedLogIDs.count)",
                "\(drawing.linkedDocumentIDs.count)",
                drawing.importedAt,
                drawing.note
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func projectDrawingMissingCheckTSVText(_ drawings: [ProjectDrawing]) -> String {
        let header = tsv([
            "drawing_id",
            "drawing_number",
            "name",
            "discipline",
            "floor_area",
            "version",
            "is_current",
            "file_type",
            "file_name",
            "file_exists",
            "file_availability_status",
            "file_availability_checked_at",
            "external_open_failure_reason",
            "external_open_failed_at",
            "status_raw",
            "status_display",
            "imported_at"
        ])
        let rows = projectPackageSortedDrawings(drawings).map { drawing in
            let exists = DrawingStorage.exists(fileName: drawing.fileName)
            return tsv([
                drawing.id.uuidString,
                drawing.drawingNumber,
                drawingDisplayName(drawing),
                drawing.discipline,
                drawing.floorArea,
                drawing.version,
                drawing.isCurrentVersion ? "true" : "false",
                drawing.fileType,
                drawing.fileName,
                exists ? "true" : "false",
                drawing.fileAvailabilityStatus.rawValue,
                drawing.fileAvailabilityCheckedAt,
                drawing.externalOpenFailureReason,
                drawing.externalOpenFailedAt,
                exists ? "present" : "missing",
                exists ? loc("原件存在") : loc("原件缺失"),
                drawing.importedAt
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func projectOpenDrawingIssuesTSVText(drawings: [ProjectDrawing], todos: [SiteTodo]) -> String {
        let header = tsv([
            "drawing_id",
            "drawing_number",
            "name",
            "discipline",
            "floor_area",
            "version",
            "issue_status_raw",
            "issue_status_display",
            "issue_note",
            "issue_location",
            "layer_or_page",
            "measurement_result",
            "close_evidence",
            "screenshot_file_names",
            "closing_evidence_file_names",
            "open_todo_count",
            "open_todo_titles",
            "owners",
            "due_dates",
            "linked_todo_ids",
            "file_name"
        ])
        let rows = projectPackageOpenDrawingIssueRows(drawings: drawings, todos: todos).map { issue in
            tsv([
                issue.drawing.id.uuidString,
                issue.drawing.drawingNumber,
                drawingDisplayName(issue.drawing),
                issue.drawing.discipline,
                issue.drawing.floorArea,
                issue.drawing.version,
                drawingIssueStatusKey(issue.drawing.issueStatus),
                issue.drawing.issueStatus == .none ? loc("关联待办未关闭") : issue.drawing.issueStatus.displayName,
                issue.drawing.issueNote,
                issue.issueLocations,
                issue.layerOrPages,
                issue.measurements,
                issue.closeEvidence,
                issue.screenshotFileNames,
                issue.closingEvidenceFileNames,
                "\(issue.openTodos.count)",
                issue.openTodos.map(\.title).joined(separator: "；"),
                issue.openTodos.map(\.owner).filter { !$0.isEmpty }.joined(separator: "；"),
                issue.openTodos.map(\.dueDate).filter { !$0.isEmpty }.joined(separator: "；"),
                issue.openTodos.map { $0.id.uuidString }.joined(separator: ";"),
                issue.drawing.fileName
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func projectPackageMissingReceiptRecords(
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument]
    ) -> [ProjectFinancialRecord] {
        financialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = documents.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }
    }

    static func projectPackageMissingOriginalEntries(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) -> [String] {
        var entries: [String] = []
        entries += documents.compactMap { document in
            ProjectDocumentStorage.exists(fileName: document.fileName) ? nil : locFormat("资料 %@", document.title)
        }
        entries += drawings.compactMap { drawing in
            DrawingStorage.exists(fileName: drawing.fileName) ? nil : locFormat("图纸 %@", drawing.name)
        }
        for log in logs {
            for photo in log.photoAttachments where !PhotoStorage.exists(fileName: photo.fileName) {
                entries.append(locFormat("照片 %@ %@", log.date, photo.tag.displayName))
            }
        }
        for note in quickNotes {
            for attachment in note.attachments where !QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
                entries.append(locFormat("随手记附件 %@", note.title.isEmpty ? note.createdAt : note.title))
            }
        }
        return entries
    }

    static func projectPackageDrawingGroupsWithoutCurrentVersion(_ drawings: [ProjectDrawing]) -> [String] {
        guard !drawings.isEmpty else { return [] }
        let grouped = Dictionary(grouping: drawings) { drawing in
            let key = normalizedProjectDrawingFamilyKey(drawing.name)
            return key.isEmpty ? drawing.fileName : key
        }
        return grouped.values.compactMap { group in
            guard !group.contains(where: \.isCurrentVersion) else { return nil }
            let sorted = group.sorted { lhs, rhs in
                if lhs.importedAt == rhs.importedAt {
                    return lhs.fileName < rhs.fileName
                }
                return lhs.importedAt > rhs.importedAt
            }
            guard let drawing = sorted.first else { return nil }
            let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? drawing.fileName : name
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func estimatedProjectPackageStepCount(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote],
        contacts: [ProjectContact]
    ) -> Int {
        var total = 8 // PDF + README + delivery checklist + pre-delivery inspection + document/drawing TSV files
        total += documents.count
        total += drawings.count
        total += logs.reduce(0) { $0 + $1.photoAttachments.count }
        if !quickNotes.isEmpty {
            total += 1 // quick note summary
            total += quickNotes.reduce(0) { $0 + $1.attachments.count }
        }
        if !contacts.isEmpty {
            total += 1
        }
        return max(total, 1)
    }
}
