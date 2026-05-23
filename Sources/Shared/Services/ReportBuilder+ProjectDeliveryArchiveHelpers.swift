import Foundation

extension ReportBuilder {
    static func projectDeliveryChecklistText(
        project: Project,
        logs: [DailyLog],
        drawings: [ProjectDrawing],
        contacts: [ProjectContact],
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        todos: [SiteTodo],
        quickNotes: [QuickNote]
    ) -> String {
        let logExpectation = projectDeliveryLogExpectation(project: project, logs: logs)
        let drawingsWithoutCurrent = projectPackageDrawingGroupsWithoutCurrentVersion(drawings)
        let currentDrawings = currentProjectPackageDrawings(drawings)
        let missingDrawingOriginalEntries = projectPackageMissingDrawingEntries(drawings)
        let openDrawingIssues = projectPackageOpenDrawingIssueRows(drawings: drawings, todos: todos)
        let missingReceipts = projectPackageMissingReceiptRecords(
            financialRecords: financialRecords,
            documents: documents
        )
        let documentChecklist = DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: project.requiredDocumentCategories
        )
        let unsettledRecords = financialRecords.filter { record in
            record.normalizedStatus == .active
                && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let unsettledAmount = unsettledRecords
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
            .doubleValue
        let deliveryHealth = projectDeliveryHealthReport(
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes
        )
        let advisoryWarningCount = [
            !logExpectation.missingDates.isEmpty,
            !drawingsWithoutCurrent.isEmpty,
            !openDrawingIssues.isEmpty,
            contacts.isEmpty,
            !unsettledRecords.isEmpty,
            documentChecklist.hasAttention
        ].filter { $0 }.count

        var lines: [String] = [
            loc("交付前检查清单"),
            locFormat("项目: %@", project.name),
            locFormat("生成时间: %@", Formatters.now()),
            locFormat("检查结论: %@", deliveryHealth.verdictDisplayName),
            locFormat("交付健康分: %lld/100", Int64(deliveryHealth.score)),
            locFormat("未通过项: %@", deliveryHealth.failedCheckDisplayText),
            advisoryWarningCount == 0 ? loc("建议检查: 无") : locFormat("建议检查: %lld 项", Int64(advisoryWarningCount)),
            "",
            loc("核心交付健康"),
            locFormat("   - 缺票据: %lld 笔", Int64(deliveryHealth.missingReceiptCount)),
            locFormat("   - 图纸: %lld 份", Int64(deliveryHealth.drawingCount)),
            locFormat("   - 当前版缺失: %lld 组", Int64(deliveryHealth.drawingGroupsWithoutCurrent.count)),
            locFormat("   - 未完成待办: %lld 项", Int64(deliveryHealth.openTodoCount)),
            locFormat("   - 备份状态: %@", deliveryHealth.backupState.detail),
            locFormat("   - 缺失原件: %lld 项", Int64(deliveryHealth.missingOriginalEntries.count)),
            "",
            loc("1. 施工日志"),
            locFormat("   - 已记录: %lld 条", Int64(logs.count))
        ]
        if !deliveryHealth.missingOriginalEntries.isEmpty {
            lines.append(locFormat("   - 缺失原件示例: %@", deliveryHealth.missingOriginalEntries.prefix(10).joined(separator: loc("、"))))
        }

        if logExpectation.expectedCount > 0 {
            lines.append(locFormat("   - 应覆盖施工日: %lld 天", Int64(logExpectation.expectedCount)))
            if logExpectation.missingDates.isEmpty {
                lines.append(loc("   - 结果: 已覆盖"))
            } else {
                lines.append(locFormat("   - 结果: 缺 %lld 天", Int64(logExpectation.missingDates.count)))
                lines.append(locFormat("   - 缺失日期: %@", logExpectation.missingDates.prefix(20).joined(separator: loc("、"))))
            }
        } else if logs.isEmpty {
            lines.append(loc("   - 结果: 未设置开工日期，且未记录施工日志"))
        } else {
            lines.append(loc("   - 结果: 未设置完整工期，按现有日志交付"))
        }

        lines += [
            "",
            loc("2. 图纸当前版"),
            locFormat("   - 图纸数量: %lld 份", Int64(drawings.count)),
            locFormat("   - 当前版图纸: %lld 份", Int64(currentDrawings.count)),
            locFormat("   - 图纸原件: %lld 份", Int64(drawings.count)),
            locFormat("   - 缺失图纸原件: %lld 项", Int64(missingDrawingOriginalEntries.count))
        ]
        if drawings.isEmpty {
            lines.append(loc("   - 结果: 未上传图纸"))
        } else if drawingsWithoutCurrent.isEmpty {
            lines.append(loc("   - 结果: 所有图纸组均有当前版"))
        } else {
            lines.append(locFormat("   - 结果: %lld 组图纸未标记当前版", Int64(drawingsWithoutCurrent.count)))
            lines.append(locFormat("   - 图纸组: %@", drawingsWithoutCurrent.prefix(20).joined(separator: loc("、"))))
        }
        if !missingDrawingOriginalEntries.isEmpty {
            lines.append(locFormat("   - 缺失图纸: %@", missingDrawingOriginalEntries.prefix(20).joined(separator: loc("、"))))
        }

        lines += [
            "",
            loc("3. 缺票检查"),
            locFormat("   - 需票据账目: %lld 笔", Int64(financialRecords.filter(\.requiresAttachment).count)),
            missingReceipts.isEmpty ? loc("   - 结果: 全部已关联票据/资料") : locFormat("   - 结果: 还有 %lld 笔缺票", Int64(missingReceipts.count))
        ]

        lines += [
            "",
            loc("4. 施工资料清单"),
            locFormat("   - 覆盖: %lld/%lld 类", Int64(documentChecklist.coveredCount), Int64(documentChecklist.requiredCount)),
            locFormat("   - 缺项: %lld 类", Int64(documentChecklist.missingCount)),
            locFormat("   - 待处理: %lld 份", Int64(documentChecklist.actionCount)),
            locFormat("   - 退回修改: %lld 份", Int64(documentChecklist.returnedDocumentCount)),
            locFormat("   - 已归档: %lld 份", Int64(documentChecklist.archivedDocumentCount))
        ]
        lines += documentChecklist.items.map {
            "   - \($0.category.displayName): \($0.statusText) · \($0.detailText)"
        }

        lines += [
            "",
            loc("5. 未关闭图纸问题"),
            locFormat("   - 未关闭问题: %lld 项", Int64(openDrawingIssues.count)),
            openDrawingIssues.isEmpty ? loc("   - 结果: 无未关闭图纸问题") : loc("   - 结果: 仍有图纸问题未关闭")
        ]
        lines += openDrawingIssues.prefix(20).map { issue in
            "   - \(drawingDisplayName(issue.drawing)) \(issue.drawing.version): \(issue.summary)"
        }

        lines += [
            "",
            loc("6. 联系人"),
            locFormat("   - 联系人数量: %lld 位", Int64(contacts.count)),
            contacts.isEmpty ? loc("   - 结果: 缺少项目联系人") : loc("   - 结果: 已维护联系人")
        ]

        lines += [
            "",
            loc("7. 未结清账目"),
            locFormat("   - 未结清笔数: %lld 笔", Int64(unsettledRecords.count)),
            locFormat("   - 未结清金额: %@", money(unsettledAmount)),
            unsettledRecords.isEmpty ? loc("   - 结果: 无未结清账目") : loc("   - 结果: 仍有未结清账目，建议交付前确认")
        ]

        lines += [
            "",
            loc("说明: 该清单由交付包导出时自动生成，供完工交付前核对使用。")
        ]
        return lines.joined(separator: "\n")
    }

    static func projectDeliveryHealthReport(
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        todos: [SiteTodo],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) -> ProjectDeliveryPackageHealthReport {
        ProjectDeliveryPackageHealthReport(
            missingReceiptCount: projectPackageMissingReceiptRecords(
                financialRecords: financialRecords,
                documents: documents
            ).count,
            drawingCount: drawings.count,
            openTodoCount: todos.filter { !$0.isDone }.count,
            backupState: .current(),
            missingOriginalEntries: projectPackageMissingOriginalEntries(
                documents: documents,
                drawings: drawings,
                logs: logs,
                quickNotes: quickNotes
            ),
            drawingGroupsWithoutCurrent: projectPackageDrawingGroupsWithoutCurrentVersion(drawings)
        )
    }

    private static func projectDeliveryLogExpectation(project: Project, logs: [DailyLog]) -> (expectedCount: Int, missingDates: [String]) {
        guard let start = Formatters.date.date(from: project.startDate) else {
            return (0, [])
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let configuredEnd = Formatters.date.date(from: project.expectedEndDate) ?? today
        let effectiveEnd = min(calendar.startOfDay(for: configuredEnd), today)
        var cursor = calendar.startOfDay(for: start)
        guard cursor <= effectiveEnd else {
            return (0, [])
        }

        let loggedDates = Set(logs.compactMap { normalizedReportDateKey($0.date) })
        var expectedDates: [String] = []
        while cursor <= effectiveEnd {
            expectedDates.append(Formatters.date.string(from: cursor))
            guard expectedDates.count < 370 else { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (expectedDates.count, expectedDates.filter { !loggedDates.contains($0) })
    }

    private static func normalizedReportDateKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = Formatters.parseDateOrDateTime(trimmed) {
            return Formatters.date.string(from: date)
        }
        return trimmed
    }

    static func currentProjectPackageDrawings(_ drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        projectPackageSortedDrawings(drawings.filter(\.isCurrentVersion))
    }

    static func projectPackageSortedDrawings(_ drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        drawings.sorted { lhs, rhs in
            let lhsKey = [
                lhs.discipline,
                lhs.floorArea,
                lhs.drawingNumber,
                drawingDisplayName(lhs),
                lhs.version,
                lhs.fileName
            ].joined(separator: "\u{1F}")
            let rhsKey = [
                rhs.discipline,
                rhs.floorArea,
                rhs.drawingNumber,
                drawingDisplayName(rhs),
                rhs.version,
                rhs.fileName
            ].joined(separator: "\u{1F}")
            return lhsKey.localizedStandardCompare(rhsKey) == .orderedAscending
        }
    }

    static func projectPackageMissingDrawingEntries(_ drawings: [ProjectDrawing]) -> [String] {
        projectPackageSortedDrawings(drawings).compactMap { drawing in
            DrawingStorage.exists(fileName: drawing.fileName) ? nil : drawingDisplayName(drawing)
        }
    }

    static func projectPackageOpenDrawingIssueRows(
        drawings: [ProjectDrawing],
        todos: [SiteTodo]
    ) -> [ProjectDrawingOpenIssueRow] {
        let todosByID = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        return projectPackageSortedDrawings(drawings).compactMap { drawing in
            let openTodos = drawing.linkedTodoIDs.compactMap { todosByID[$0] }.filter { !$0.isDone }
            let hasOpenDrawingStatus = drawing.issueStatus == .open
                || drawing.issueStatus == .inProgress
                || (drawing.issueStatus != .closed && !drawing.issueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            guard hasOpenDrawingStatus || !openTodos.isEmpty else { return nil }
            return ProjectDrawingOpenIssueRow(drawing: drawing, openTodos: openTodos)
        }
    }

    static func drawingDisplayName(_ drawing: ProjectDrawing) -> String {
        let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? drawing.fileName : name
    }

    static func drawingIssueStatusKey(_ status: DrawingIssueStatus) -> String {
        switch status {
        case .none: "none"
        case .open: "open"
        case .inProgress: "in_progress"
        case .closed: "closed"
        }
    }

    static func normalizedProjectDrawingFamilyKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[\\s_\\-]+", with: "", options: .regularExpression)
    }

    static func addGeneratedFileToProjectPackageZip(
        zip: inout StreamingZipArchiveWriter,
        data: Data,
        path: String,
        stagedRawBytes: inout Int
    ) throws {
        do {
            try zip.addFile(path: path, data: data)
        } catch {
            StorageIssueLog.recordEvent(
                "project_package.write_generated_file_failed",
                category: .zipArchive,
                details: [
                    "source": "ReportBuilder.addGeneratedFileToProjectPackageZip",
                    "path": path
                ],
                error: error
            )
            throw error
        }
        stagedRawBytes += data.count
    }

    static func addStoredFileToProjectPackageZip(
        zip: inout StreamingZipArchiveWriter,
        sourceFileURL: URL,
        fileBytes: Int,
        path: String,
        stagedRawBytes: inout Int
    ) throws {
        let resolvedFileBytes = max(fileBytes, QuickNoteAttachmentStorage.fileSize(at: sourceFileURL))
        do {
            try zip.addFile(path: path, sourceFileURL: sourceFileURL)
        } catch {
            StorageIssueLog.recordEvent(
                "project_package.write_stored_file_failed",
                category: .zipArchive,
                details: [
                    "source": "ReportBuilder.addStoredFileToProjectPackageZip",
                    "source_file": sourceFileURL.lastPathComponent,
                    "path": path
                ],
                error: error
            )
            throw error
        }
        stagedRawBytes += resolvedFileBytes
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
