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
}
