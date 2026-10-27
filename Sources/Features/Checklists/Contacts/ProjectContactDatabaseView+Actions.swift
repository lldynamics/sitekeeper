import SwiftUI

extension ProjectContactDatabaseView {
    func handleContactExportCompletion(_ result: Result<URL, Error>) {
        let outcome = ExportCompletionHandler.evaluate(result, source: "ProjectContactDatabaseView")
        operationNotice = ExportCompletionHandler.notice(for: outcome) {
            guard exportPayload != nil else { return }
            showExporter = true
        }
    }

    func openFocusedContactIfNeeded() {
        guard let focusedContactId, !didOpenFocusedContact,
              let contact = projectContacts.first(where: { $0.id == focusedContactId }) else { return }
        didOpenFocusedContact = true
        searchText = ""
        selectedProjectId = contact.projectId
        Task { @MainActor in
            editingContact = contact
        }
    }

    func deleteContact(_ contact: ProjectContact) {
        deleteContacts(Set([contact.id]), source: "ProjectContactDatabaseView")
    }

    func deleteContacts(_ ids: Set<UUID>, source: String = "ProjectContactDatabaseView") {
        guard !ids.isEmpty else { return }
        let targets = projectContacts.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let deletion = store.removeProjectContacts(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("删除联系人 %lld 位"), Int64(targets.count)),
                detail: contactAuditDetail(targets),
                source: source
            )
        )
        queueContactDeletion(
            deletion,
            message: String(format: AppLocalization.string("已删除 %lld 位联系人"), Int64(deletion.deletedCount))
        )
    }

    func deleteContacts(_ items: [ProjectContact]) {
        deleteContacts(Set(items.map(\.id)))
    }

    func queueContactDeletion(
        _ deletion: DataStoreRemovalResult<ProjectContact>,
        message: String
    ) {
        guard !deletion.isEmpty else { return }
        undoableDeletion.queue(
            notice: $operationNotice,
            message: message,
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreProjectContacts(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    func contactAuditDetail(_ contacts: [ProjectContact]) -> String {
        ListFormatter.localizedString(
            byJoining: contacts.map { contact in
                [contact.name, contact.phone, projectName(contact.projectId)]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            }
        )
    }

    func linkedProjectNames(for contact: ProjectContact) -> [String] {
        let phoneKey = normalizedPhone(contact.phone)
        var projectIDs = Set(contact.relatedProjectIds)
        if !phoneKey.isEmpty {
            let all = projectContacts.filter { normalizedPhone($0.phone) == phoneKey && $0.id != contact.id }
            projectIDs.formUnion(all.map(\.projectId))
            projectIDs.formUnion(all.flatMap(\.relatedProjectIds))
        }
        projectIDs.remove(contact.projectId)
        return projectNames(for: Array(projectIDs))
    }

    func mergeDuplicateContacts(phone: String) {
        let phoneKey = normalizedPhone(phone)
        let all = projectContacts.filter { normalizedPhone($0.phone) == phoneKey }
        guard all.count > 1 else { return }

        var toKeep = Set<UUID>()
        let grouped = Dictionary(grouping: all, by: \.projectId)
        for (_, contacts) in grouped {
            let best = contacts.max { a, b in
                let scoreA = [a.name, a.company, a.phone, a.note].filter { !$0.isEmpty }.count
                let scoreB = [b.name, b.company, b.phone, b.note].filter { !$0.isEmpty }.count
                return scoreA < scoreB
            }
            if let best {
                toKeep.insert(best.id)
            }
        }
        let idsToDelete = Set(all.map(\.id)).subtracting(toKeep)
        let targets = projectContacts.filter { idsToDelete.contains($0.id) }
        guard !targets.isEmpty else { return }

        let deletion = store.removeProjectContacts(
            ids: idsToDelete,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("合并重复联系人，删除 %lld 位"), Int64(targets.count)),
                detail: "\(phoneKey) · \(contactAuditDetail(targets))",
                source: "ProjectContactDatabaseView"
            )
        )
        queueContactDeletion(
            deletion,
            message: String(format: AppLocalization.string("已合并联系人，删除 %lld 个重复项"), Int64(deletion.deletedCount))
        )
    }

    func exportContactsVCard() {
        var lines: [String] = []
        for contact in filteredContacts {
            lines.append("BEGIN:VCARD")
            lines.append("VERSION:3.0")
            lines.append("FN:\(contact.name)")
            let cleaned = normalizedPhone(contact.phone)
            if !cleaned.isEmpty {
                lines.append("TEL;TYPE=CELL:\(cleaned)")
            }
            if !contact.company.isEmpty {
                lines.append("ORG:\(contact.company)")
            }
            if !contact.note.isEmpty {
                lines.append("NOTE:\(contact.note)")
            }
            let projectRef = projectName(contact.projectId)
            if !projectRef.isEmpty {
                lines.append("NOTE:项目:\(projectRef)")
            }
            let relatedNames = projectNames(for: contact.relatedProjectIds)
            if !relatedNames.isEmpty {
                lines.append("NOTE:历史项目:\(relatedNames.joined(separator: "、"))")
            }
            lines.append("END:VCARD")
        }
        let data = lines.joined(separator: "\r\n").data(using: .utf8) ?? Data()
        exportPayload = ExportPayload(
            data: data,
            contentType: .vCard,
            defaultFilename: AppLocalization.string("项目联系人.vcf")
        )
        showExporter = true
    }

    func projectName(_ id: UUID) -> String {
        projects.first(where: { $0.id == id })?.name ?? AppLocalization.string("未知项目")
    }

    func projectNames(for ids: [UUID]) -> [String] {
        ids.compactMap { id in
            projects.first(where: { $0.id == id })?.name
        }
    }

    func normalizedPhone(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    func contactCRMSummary(for contact: ProjectContact) -> String? {
        let cluster = contactCluster(for: contact)
        let projectIds = Array(Set(cluster.map(\.projectId)))
        guard !projectIds.isEmpty else { return nil }

        let sortedProjects = projectIds.sorted { lhs, rhs in
            recentActivityDate(for: lhs) > recentActivityDate(for: rhs)
        }
        let projectNames = sortedProjects
            .prefix(2)
            .map { projectName($0) }
            .filter { !$0.isEmpty && $0 != AppLocalization.string("未知项目") }
        let projectPreview = projectNames.isEmpty ? AppLocalization.string("暂无项目") : projectNames.joined(separator: "、")
        let unpaid = sortedProjects.reduce(MoneyValue.zero) { total, projectId in
            total + unpaidAmount(for: projectId)
        }

        if unpaid > 0 {
            return String(format: AppLocalization.string("最近合作：%@ · 待收 %@"), projectPreview, ReportBuilder.money(unpaid))
        }
        return String(format: AppLocalization.string("最近合作：%@"), projectPreview)
    }

    func contactCluster(for contact: ProjectContact) -> [ProjectContact] {
        let phoneKey = normalizedPhone(contact.phone)
        if !phoneKey.isEmpty {
            return projectContacts.filter { normalizedPhone($0.phone) == phoneKey }
        }
        let nameKey = contact.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !nameKey.isEmpty else { return [contact] }
        return projectContacts.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameKey
        }
    }

    func recentActivityDate(for projectId: UUID) -> Date {
        let summaryDate = projectStore.projectActivitySummary(for: projectId).latestActivityDate
        let startDate = projects.first(where: { $0.id == projectId })
            .flatMap { Formatters.parseDateOrDateTime($0.startDate) }
            ?? .distantPast
        return max(summaryDate ?? .distantPast, startDate)
    }

    func unpaidAmount(for projectId: UUID) -> MoneyValue {
        guard let project = projects.first(where: { $0.id == projectId }) else { return 0 }
        let contract = project.contractAmount
        let paidFromSummary = projectStore.projectActivitySummary(for: projectId).collectedIncomeAmount
        let paid = ProjectFinancialMetrics.effectivePaidAmount(
            recordedCollectionAmount: paidFromSummary,
            manualPaidAmount: project.paidAmount
        )
        return ProjectFinancialMetrics.unpaidAmount(contractAmount: contract, paidAmount: paid)
    }

    func beginSystemContactImport() {
        guard !projects.isEmpty else {
            showImportFeedback(AppLocalization.string("请先创建项目，再导入联系人。"))
            return
        }
        guard targetProjectIdForImport() != nil else {
            showImportFeedback(AppLocalization.string("请先在顶部筛选中选择一个项目，再导入联系人。"))
            return
        }
        showSystemContactPicker = true
    }

    func targetProjectIdForImport() -> UUID? {
        if let selectedProjectId {
            return selectedProjectId
        }
        if projects.count == 1 {
            return projects[0].id
        }
        return nil
    }

    func importSystemContact(_ imported: ImportedSystemContact) {
        showSystemContactPicker = false
        guard let projectId = targetProjectIdForImport() else {
            showImportFeedback(AppLocalization.string("请先选择项目，再导入联系人。"))
            return
        }

        let resolvedName = imported.fullName.isEmpty
            ? (imported.organizationName.isEmpty ? AppLocalization.string("未命名联系人") : imported.organizationName)
            : imported.fullName

        let normalizedPrimary = normalizedPhone(imported.primaryPhone)
        if !normalizedPrimary.isEmpty,
           let existing = projectContacts.first(where: {
               normalizedPhone($0.phone) == normalizedPrimary && $0.isLinked(to: projectId)
           }) {
            selectedProjectId = projectId
            editingContact = existing
            showImportFeedback(AppLocalization.string("该号码已存在，已定位到现有联系人。"))
            return
        }

        var noteLines: [String] = []
        if imported.phoneNumbers.count > 1 {
            noteLines.append(
                String(
                    format: AppLocalization.string("备用号码：%@"),
                    imported.phoneNumbers.dropFirst().joined(separator: "、")
                )
            )
        }

        let contact = ProjectContact(
            projectId: projectId,
            relatedProjectIds: [],
            name: resolvedName,
            role: .other,
            company: imported.organizationName,
            phone: imported.primaryPhone,
            note: noteLines.joined(separator: "\n")
        )
        store.upsertProjectContact(contact, insertAtTopWhenNew: true)
        store.scheduleSave()
        selectedProjectId = projectId
        AppHaptics.success()
        showImportFeedback(String(format: AppLocalization.string("已导入联系人：%@"), resolvedName))
    }

    func showImportFeedback(_ message: String) {
        importFeedbackMessage = message
        showImportFeedbackAlert = true
    }
}
