import Foundation

extension ReportBuilder {
    static func makeCSV(snapshot: BackupSnapshot, options: ExportContentOptions) -> Data {
        var rows: [String] = []
        if options.includeMaterials {
            rows.append(csvMachineSection("material_items"))
            rows.append(csv(["name", "quantity", "unit", "unit_price", "specification", "brand", "supplier", "purchase_status_key", "purchase_status_display", "arrival_date", "amount_raw", "amount_display", "project_id"]))
            rows += snapshot.materialItems.map { item in
                let lineTotal = materialAmountColumns(item, currencyDisplayMode: options.currencyDisplayMode)
                return csv([
                    item.name,
                    item.quantity,
                    item.unit,
                    item.unitPrice,
                    item.specification,
                    item.brand,
                    item.supplier,
                    item.purchaseStatus.exportKey,
                    item.purchaseStatus.displayName,
                    item.arrivalDate,
                    lineTotal.raw,
                    lineTotal.display,
                    item.projectId?.uuidString ?? ""
                ])
            }
            rows.append("")
        }
        if options.includeQuotes {
            rows.append(csvMachineSection("quote_items"))
            rows.append(csv(["name", "unit_price", "quantity", "unit", "tax_rate", "discount_rate", "version", "status_key", "status_display", "customer_confirmed_date", "contract_amount_raw", "contract_amount_display", "notes", "project_id"]))
            rows += snapshot.quoteItems.map { item in
                let contractAmount = parsedAmountColumns(item.contractAmount, currencyDisplayMode: options.currencyDisplayMode)
                return csv([
                    item.name,
                    item.unitPrice,
                    item.quantity,
                    item.unit,
                    item.taxRate,
                    item.discountRate,
                    item.versionName,
                    item.status.exportKey,
                    item.status.displayName,
                    item.customerConfirmedDate,
                    contractAmount.raw,
                    contractAmount.display,
                    item.notes,
                    item.projectId?.uuidString ?? ""
                ])
            }
            rows.append("")
        }
        if options.includeLabor {
            rows.append(csvMachineSection("labor_records"))
            rows.append(csv(["date", "workers", "hours", "unit_rate", "work_type", "team_name", "is_settled", "amount_raw", "amount_display", "note", "project_id"]))
            rows += snapshot.laborRecords.map { record in
                let lineTotal = laborAmountColumns(record, currencyDisplayMode: options.currencyDisplayMode)
                return csv([
                    record.date,
                    record.workers,
                    record.hours,
                    record.unitRate,
                    record.workType,
                    record.teamName,
                    machineBool(record.isSettled),
                    lineTotal.raw,
                    lineTotal.display,
                    record.note,
                    record.projectId?.uuidString ?? ""
                ])
            }
            rows.append("")
        }
        if options.includeDailyLogs {
            rows.append(csvMachineSection("daily_logs"))
            rows.append(csv(["date", "weather", "workers", "content", "safety", "materials", "tomorrow_plan", "quality_issue", "rectification", "confirmer", "photo_count", "project_id"]))
            rows += snapshot.dailyLogs.map { log in
                csv([
                    log.date,
                    log.weather,
                    log.workers,
                    log.content,
                    log.safety,
                    log.materials,
                    log.tomorrowPlan,
                    log.qualityIssue,
                    log.rectification,
                    log.confirmer,
                    "\(log.photoAttachments.count)",
                    log.projectId?.uuidString ?? ""
                ])
            }
            rows.append("")
        }
        if options.includeProgress {
            rows.append(csvMachineSection("progress_tasks"))
            rows.append(csv(["title", "start_date", "due_date", "completion_percent", "note", "project_id"]))
            rows += snapshot.progressTasks.map { task in
                csv([
                    task.title,
                    task.startDate,
                    task.dueDate,
                    String(format: "%.0f", task.clampedCompletion * 100),
                    task.note,
                    task.projectId.uuidString
                ])
            }
            rows.append("")
        }
        if options.includeTodos {
            rows.append(csvMachineSection("site_todos"))
            rows.append(csv(["title", "owner", "due_date", "priority_key", "priority_display", "issue_type_key", "issue_type_display", "status_key", "status_display", "completed_at", "rectification_before_photo", "rectification_after_photo", "note", "project_id"]))
            rows += snapshot.siteTodos.map { todo in
                csv([
                    todo.title,
                    todo.owner,
                    todo.dueDate,
                    todo.priority.exportKey,
                    todo.priority.displayName,
                    todo.issueType.exportKey,
                    todo.issueType.displayName,
                    siteTodoStatusKey(todo),
                    siteTodoStatusDisplay(todo),
                    todo.completedAt ?? "",
                    todo.rectificationBeforePhotoFileName ?? "",
                    todo.rectificationAfterPhotoFileName ?? "",
                    todo.note,
                    todo.projectId?.uuidString ?? ""
                ])
            }
            rows.append("")
        }
        if options.includeProjectFinance {
            rows.append(csvMachineSection("project_financial_records"))
            rows.append(csv(["date", "direction_key", "direction_display", "category_key", "category_display", "status_key", "status_display", "due_date", "reminder_status_key", "reminder_status_display", "amount_raw", "amount_display", "counterparty", "invoice_number", "linked_document_count", "note", "project_id"]))
            rows += snapshot.projectFinancialRecords.map { record in
                let amount = parsedAmountColumns(record.amount, currencyDisplayMode: options.currencyDisplayMode)
                return csv([
                    record.date,
                    record.direction.exportKey,
                    record.direction.displayName,
                    record.category.exportKey,
                    record.category.displayName,
                    record.normalizedStatus.exportKey,
                    record.normalizedStatus.displayName,
                    record.dueDate,
                    record.normalizedReminderStatus.exportKey,
                    record.normalizedReminderStatus.displayName,
                    amount.raw,
                    amount.display,
                    record.counterparty,
                    record.invoiceNumber,
                    "\(record.linkedDocumentIds.count)",
                    record.note,
                    record.projectId.uuidString
                ])
            }
            rows.append("")
        }
        if options.includeProjectDocuments {
            let checklistRows = projectDocumentChecklistExportRows(snapshot: snapshot)
            rows.append(csvMachineSection("project_document_checklist"))
            rows.append(csv([
                "project_id",
                "project_name",
                "category_key",
                "category_display",
                "status_raw",
                "status_display",
                "document_count",
                "action_count",
                "returned_count",
                "archived_count"
            ]))
            rows += checklistRows.map { row in
                let item = row.item
                return csv([
                    row.projectID?.uuidString ?? "",
                    row.projectName,
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
            rows.append("")

            rows.append(csvMachineSection("project_documents"))
            rows.append(csv([
                "title",
                "category_key",
                "category_display",
                "version_number",
                "version_state",
                "replaces_document_id",
                "replaced_by_document_id",
                "submission_status_raw",
                "submission_status_display",
                "responsible_person",
                "formed_at",
                "archive_number",
                "work_section",
                "page_count",
                "amount_raw",
                "amount_display",
                "created_at",
                "linked_financial_record_id",
                "file_name",
                "note",
                "project_id"
            ]))
            rows += snapshot.projectDocuments.map { document in
                let amount = parsedAmountColumns(document.amount, currencyDisplayMode: options.currencyDisplayMode)
                return csv([
                    document.title,
                    document.category.exportKey,
                    document.category.displayName,
                    "\(document.normalizedVersionNumber)",
                    document.versionState.displayName,
                    document.replacesDocumentId?.uuidString ?? "",
                    document.replacedByDocumentId?.uuidString ?? "",
                    document.submissionStatus.exportKey,
                    document.submissionStatus.displayName,
                    document.responsiblePerson,
                    document.formedAt,
                    document.archiveNumber,
                    document.workSection,
                    "\(document.pageCount)",
                    amount.raw,
                    amount.display,
                    document.createdAt,
                    document.linkedFinancialRecordId?.uuidString ?? "",
                    document.fileName,
                    document.note,
                    document.projectId.uuidString
                ])
            }
            rows.append("")
        }
        if options.includeProjectContacts {
            rows.append(csvMachineSection("project_contacts"))
            rows.append(csv(["name", "role_key", "role_display", "phone", "company", "note", "project_id"]))
            rows += snapshot.projectContacts.map { contact in
                csv([
                    contact.name,
                    contact.normalizedRole.exportKey,
                    contact.roleDisplayName,
                    contact.phone,
                    contact.company,
                    contact.note,
                    contact.projectId.uuidString
                ])
            }
            rows.append("")
        }
        if options.includeProjectDrawings {
            rows.append(csvMachineSection("project_drawings"))
            rows.append(csv(["name", "file_type", "version", "file_name", "issue_status_key", "issue_status_display", "issue_note", "imported_at", "related_log_date", "note", "project_id"]))
            rows += snapshot.projectDrawings.map { drawing in
                csv([
                    drawing.name,
                    drawing.fileType,
                    drawing.version,
                    drawing.fileName,
                    drawing.issueStatus.exportKey,
                    drawing.issueStatus.displayName,
                    drawing.issueNote,
                    drawing.importedAt,
                    drawing.relatedLogDate,
                    drawing.note,
                    drawing.projectId.uuidString
                ])
            }
            rows.append("")
        }
        if options.includeWarehouseMovements {
            rows.append(csvMachineSection("warehouse_movements"))
            rows.append(csv(["date", "movement_type_key", "movement_type_display", "material_name", "specification", "unit", "quantity", "counterparty", "handler", "note", "linked_document_count", "project_id"]))
            rows += snapshot.projectWarehouseMovements.map { movement in
                csv([
                    movement.date,
                    movement.normalizedMovementType.exportKey,
                    movement.normalizedMovementType.displayName,
                    movement.materialName,
                    movement.specification,
                    movement.unit,
                    movement.quantity,
                    movement.counterparty,
                    movement.handler,
                    movement.note,
                    "\(movement.linkedDocumentIds.count)",
                    movement.projectId.uuidString
                ])
            }
            rows.append("")
        }
        if options.includeQuickNotes {
            rows.append(csvMachineSection("quick_notes"))
            rows.append(csv(["title", "content", "created_at", "updated_at", "attachment_count", "project_id"]))
            rows += snapshot.quickNotes.map { note in
                csv([
                    note.title,
                    note.content,
                    note.createdAt,
                    note.updatedAt,
                    "\(note.attachments.count)",
                    note.projectId?.uuidString ?? ""
                ])
            }
            rows.append("")
        }
        if options.includeOperationAuditLogs {
            rows.append(csvMachineSection("operation_audit_log"))
            rows.append(csv(["timestamp", "action_key", "action_display", "outcome_key", "outcome_display", "summary", "detail", "source", "id"]))
            rows += options.operationAuditEntries.map { entry in
                csv([
                    Formatters.dateTime.string(from: Date(timeIntervalSince1970: entry.timestamp)),
                    entry.action.rawValue,
                    operationAuditActionDisplayName(entry.action),
                    entry.outcome.rawValue,
                    operationAuditOutcomeDisplayName(entry.outcome),
                    entry.summary,
                    entry.detail,
                    entry.source,
                    entry.id.uuidString
                ])
            }
            rows.append("")
        }
        return Data(rows.joined(separator: "\n").utf8)
    }

    private static func machineBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func siteTodoStatusKey(_ todo: SiteTodo) -> String {
        if todo.isDone { return "done" }
        if todo.isOverdue { return "overdue" }
        return "pending"
    }

    private static func siteTodoStatusDisplay(_ todo: SiteTodo) -> String {
        if todo.isDone { return locDone }
        if todo.isOverdue { return locOverdue }
        return locPending
    }

    private static func materialAmountColumns(
        _ item: MaterialItem,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> (raw: String, display: String) {
        amountColumns(materialLineTotal(item), currencyDisplayMode: currencyDisplayMode)
    }

    private static func laborAmountColumns(
        _ record: LaborRecord,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> (raw: String, display: String) {
        amountColumns(laborLineTotal(record), currencyDisplayMode: currencyDisplayMode)
    }

    private static func amountColumns(
        _ value: Double,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> (raw: String, display: String) {
        let raw = amountRaw(value)
        return (raw, amountDisplay(value, currencyDisplayMode: currencyDisplayMode))
    }

    private static func parsedAmountColumns(
        _ rawText: String,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> (raw: String, display: String) {
        guard let decimal = DataValueParser.decimalValueIfPresent(from: rawText) else {
            return ("", "")
        }
        return amountColumns(
            NSDecimalNumber(decimal: decimal).doubleValue,
            currencyDisplayMode: currencyDisplayMode
        )
    }

    static func projectDocumentChecklistExportRows(snapshot: BackupSnapshot) -> [ProjectDocumentChecklistExportRow] {
        let documentsByProjectID = Dictionary(grouping: snapshot.projectDocuments, by: \.projectId)
        if !snapshot.projects.isEmpty {
            return snapshot.projects.flatMap { project in
                let checklist = DocumentArchiveChecklistSnapshot(
                    documents: documentsByProjectID[project.id] ?? [],
                    requiredCategories: project.requiredDocumentCategories
                )
                return checklist.items.map { item in
                    ProjectDocumentChecklistExportRow(
                        projectID: project.id,
                        projectName: project.name,
                        item: item
                    )
                }
            }
        }

        let checklist = DocumentArchiveChecklistSnapshot(documents: snapshot.projectDocuments)
        return checklist.items.map { item in
            ProjectDocumentChecklistExportRow(
                projectID: nil,
                projectName: "",
                item: item
            )
        }
    }
}

struct ProjectDocumentChecklistExportRow {
    let projectID: UUID?
    let projectName: String
    let item: DocumentArchiveChecklistItem
}

private extension MaterialPurchaseStatus {
    var exportKey: String {
        switch self {
        case .notPurchased: "not_purchased"
        case .purchased: "purchased"
        case .arrived: "arrived"
        case .used: "used"
        }
    }
}

private extension QuoteStatus {
    var exportKey: String {
        switch self {
        case .draft: "draft"
        case .sent: "sent"
        case .confirmed: "confirmed"
        }
    }
}

private extension ProjectFinancialDirection {
    var exportKey: String {
        switch self {
        case .income: "income"
        case .expense: "expense"
        }
    }
}

private extension ProjectFinancialCategory {
    var exportKey: String {
        switch self {
        case .collection: "collection"
        case .refund: "refund"
        case .reimbursement: "reimbursement"
        case .material: "material"
        case .labor: "labor"
        case .invoice: "invoice"
        case .receipt: "receipt"
        case .paymentRequest: "payment_request"
        case .other: "other"
        }
    }
}

private extension ProjectFinancialStatus {
    var exportKey: String {
        switch self {
        case .active: "active"
        case .draft: "draft"
        case .archived: "archived"
        }
    }
}

private extension ProjectFinancialReminderStatus {
    var exportKey: String {
        switch self {
        case .none: "none"
        case .pending: "pending"
        case .reminded: "reminded"
        case .done: "done"
        }
    }
}

extension ProjectDocumentCategory {
    var exportKey: String {
        switch self {
        case .paymentRequest: "payment_request"
        case .construction: "construction"
        case .constructionTechnical: "construction_technical"
        case .constructionMaterial: "construction_material"
        case .constructionSurvey: "construction_survey"
        case .constructionRecord: "construction_record"
        case .constructionTest: "construction_test"
        case .constructionManagement: "construction_management"
        case .processAcceptance: "process_acceptance"
        case .completionAcceptance: "completion_acceptance"
        case .invoice: "invoice"
        case .receipt: "receipt"
        case .contract: "contract"
        case .acceptance: "acceptance"
        case .other: "other"
        }
    }
}

extension ProjectContactRole {
    var exportKey: String {
        switch self {
        case .owner: "owner"
        case .customer: "customer"
        case .supervisor: "supervisor"
        case .supplier: "supplier"
        case .team: "team"
        case .other: "other"
        }
    }
}

private extension DrawingIssueStatus {
    var exportKey: String {
        switch self {
        case .none: "none"
        case .open: "open"
        case .inProgress: "in_progress"
        case .closed: "closed"
        }
    }
}

private extension TodoPriority {
    var exportKey: String {
        switch self {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        }
    }
}

private extension TodoIssueType {
    var exportKey: String {
        switch self {
        case .safety: "safety"
        case .quality: "quality"
        case .material: "material"
        case .schedule: "schedule"
        case .general: "general"
        }
    }
}

private extension WarehouseMovementType {
    var exportKey: String {
        switch self {
        case .inbound: "inbound"
        case .outbound: "outbound"
        }
    }
}

extension ProjectDocumentSubmissionStatus {
    var exportKey: String {
        switch self {
        case .notSubmitted: "not_submitted"
        case .pending: "pending"
        case .submitted: "submitted"
        case .returned: "returned"
        case .confirmed: "confirmed"
        case .archived: "archived"
        }
    }
}

extension DocumentArchiveChecklistItem {
    var statusExportKey: String {
        if isMissing { return "missing" }
        if returnedCount > 0 { return "returned" }
        if actionCount > 0 { return "pending" }
        if archivedCount == documentCount { return "archived" }
        return "covered"
    }
}
