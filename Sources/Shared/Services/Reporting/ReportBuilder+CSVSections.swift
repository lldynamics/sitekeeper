import Foundation

extension ReportBuilder {
    static func materialCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeMaterials else { return [] }
        var rows: [String] = []
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
        return rows
    }

    static func quoteCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeQuotes else { return [] }
        var rows: [String] = []
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
        return rows
    }

    static func laborCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeLabor else { return [] }
        var rows: [String] = []
        rows.append(csvMachineSection("labor_records"))
        rows.append(csv(["date", "workers", "hours", "workload_unit", "unit_rate", "work_type", "team_name", "is_settled", "amount_raw", "amount_display", "note", "project_id"]))
        rows += snapshot.laborRecords.map { record in
            let lineTotal = laborAmountColumns(record, currencyDisplayMode: options.currencyDisplayMode)
            return csv([
                record.date,
                record.workers,
                record.hours,
                record.workloadUnit.rawValue,
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
        return rows
    }

    static func projectFinanceCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeProjectFinance else { return [] }
        var rows: [String] = []
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
        return rows
    }

    static func projectDocumentCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeProjectDocuments else { return [] }
        var rows: [String] = []
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
        return rows
    }

    static func projectContactCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeProjectContacts else { return [] }
        var rows: [String] = []
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
        return rows
    }

    static func projectDrawingCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeProjectDrawings else { return [] }
        var rows: [String] = []
        rows.append(csvMachineSection("project_drawings"))
        rows.append(csv([
            "name",
            "drawing_number",
            "discipline",
            "floor_area",
            "file_type",
            "version",
            "is_current_version",
            "issued_at",
            "receiver",
            "file_name",
            "file_availability_status_key",
            "file_availability_status_display",
            "file_availability_checked_at",
            "external_open_failure_reason",
            "external_open_failed_at",
            "issue_status_key",
            "issue_status_display",
            "issue_note",
            "linked_todo_ids",
            "linked_log_ids",
            "linked_document_ids",
            "imported_at",
            "related_log_date",
            "note",
            "project_id"
        ]))
        rows += snapshot.projectDrawings.map { drawing in
            csv([
                drawing.name,
                drawing.drawingNumber,
                drawing.discipline,
                drawing.floorArea,
                drawing.fileType,
                drawing.version,
                drawing.isCurrentVersion ? "true" : "false",
                drawing.issuedAt,
                drawing.receiver,
                drawing.fileName,
                drawing.fileAvailabilityStatus.exportKey,
                drawing.fileAvailabilityStatus.displayName,
                drawing.fileAvailabilityCheckedAt,
                drawing.externalOpenFailureReason,
                drawing.externalOpenFailedAt,
                drawing.issueStatus.exportKey,
                drawing.issueStatus.displayName,
                drawing.issueNote,
                drawing.linkedTodoIDs.map(\.uuidString).joined(separator: ";"),
                drawing.linkedLogIDs.map(\.uuidString).joined(separator: ";"),
                drawing.linkedDocumentIDs.map(\.uuidString).joined(separator: ";"),
                drawing.importedAt,
                drawing.relatedLogDate,
                drawing.note,
                drawing.projectId.uuidString
            ])
        }
        rows.append("")
        return rows
    }

    static func warehouseMovementCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeWarehouseMovements else { return [] }
        var rows: [String] = []
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
        return rows
    }

    private static func machineBool(_ value: Bool) -> String {
        value ? "true" : "false"
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
        _ value: MoneyValue,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> (raw: String, display: String) {
        let raw = Formatters.money(decimal: value.decimal)
        return (raw, currencyDisplayMode.format(decimal: value.decimal))
    }

    private static func parsedAmountColumns(
        _ value: MoneyValue,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> (raw: String, display: String) {
        guard let decimal = value.optionalDecimal else {
            return ("", "")
        }
        return (Formatters.money(decimal: decimal), currencyDisplayMode.format(decimal: decimal))
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
