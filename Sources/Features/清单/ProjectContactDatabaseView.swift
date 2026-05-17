import SwiftUI
import UniformTypeIdentifiers

struct ProjectContactDatabaseView: View {
    @Environment(DataStore.self) private var store
    @Environment(ProjectStore.self) private var projectStore
    let focusedContactId: UUID?
    @State private var searchText = ""
    @State private var selectedProjectId: UUID?
    @State private var roleFilter: ProjectContactRole?
    @State private var showAdd = false
    @State private var editingContact: ProjectContact?
    @State private var didOpenFocusedContact = false
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var showSystemContactPicker = false
    @State private var importFeedbackMessage = ""
    @State private var showImportFeedbackAlert = false
    @State private var mergeConfirmPhone: String?
    @State private var showMergeConfirm = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    init(focusedContactId: UUID? = nil) {
        self.focusedContactId = focusedContactId
    }

    private var scopedContacts: [ProjectContact] {
        store.projectContacts.filter { contact in
            guard let selectedProjectId else { return true }
            return contact.isLinked(to: selectedProjectId)
        }
        .filter {
            guard let roleFilter else { return true }
            return $0.role == roleFilter
        }
    }

    private var filteredContacts: [ProjectContact] {
        return SearchMatcher.filter(
            scopedContacts,
            keyword: searchText,
            sort: { lhs, rhs in
                let leftProject = projectName(lhs.projectId)
                let rightProject = projectName(rhs.projectId)
                if leftProject != rightProject { return leftProject < rightProject }
                return lhs.name < rhs.name
            },
            extraFields: { contact in
                [projectName(contact.projectId)] + projectNames(for: contact.relatedProjectIds)
            }
        )
    }

    private var searchSuggestions: [RealtimeSearchSuggestion] {
        RealtimeSearchSuggestionBuilder.suggestions(
            keyword: searchText,
            categories: [.contact],
            projects: store.projects,
            contacts: scopedContacts,
            limit: 6
        )
    }

    private var duplicatePhoneGroups: [(phone: String, contacts: [ProjectContact])] {
        let grouped = Dictionary(grouping: store.projectContacts) { normalizedPhone($0.phone) }
        return grouped
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { (phone: $0.key, contacts: $0.value.sorted { projectName($0.projectId) < projectName($1.projectId) }) }
            .sorted { $0.phone < $1.phone }
    }

    var body: some View {
        SearchableDatabaseView(
            title: "联系人",
            searchText: $searchText,
            searchPrompt: "搜索姓名、电话、公司、项目",
            items: filteredContacts,
            emptyTitle: "暂无联系人",
            emptySystemImage: "person.crop.rectangle.stack",
            emptyDescription: Text("项目联系人会统一显示在这里，可按项目筛选。"),
            searchSuggestions: searchSuggestions,
            onSelect: { contact in
                editingContact = contact
            },
            onSelectSuggestion: { suggestion in
                guard suggestion.category == .contact else { return }
                guard let contact = store.projectContacts.first(where: { $0.id == suggestion.entityId }) else { return }
                selectedProjectId = contact.projectId
                editingContact = contact
            },
            deleteConfig: SearchableDatabaseDeleteConfig(
                title: "删除联系人？",
                itemNoun: "联系人",
                singularMessage: "删除后可在提示中撤销。",
                pluralMessage: { count, noun in
                    "将删除 \(count) 条\(noun)，可在提示中撤销。"
                }
            ),
            onDeleteConfirmed: deleteContacts,
            rowContent: { contact in
                ContactPickerRowView(
                    contact: contact,
                    projectName: projectName(contact.projectId),
                    showsProjectName: true,
                    showsPhoneActions: true,
                    crmSummary: contactCRMSummary(for: contact),
                    linkedProjectNames: linkedProjectNames(for: contact)
                )
            },
            headerContent: {
                Section {
                    filterBars
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if selectedProjectId == nil && !duplicatePhoneGroups.isEmpty {
                    Section("疑似重复联系人") {
                        ForEach(duplicatePhoneGroups, id: \.phone) { group in
                            DisclosureGroup("\(group.phone) · \(group.contacts.count) 条") {
                                ForEach(group.contacts) { contact in
                                    ContactPickerRowView(
                                        contact: contact,
                                        projectName: projectName(contact.projectId),
                                        showsProjectName: true,
                                        showsPhoneActions: true,
                                        linkedProjectNames: linkedProjectNames(for: contact)
                                    )
                                }
                                Button {
                                    mergeConfirmPhone = group.phone
                                    showMergeConfirm = true
                                } label: {
                                    Label("合并为同一联系人", systemImage: "arrow.triangle.merge")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.appWarning)
                                }
                            }
                        }
                    }
                }
            },
            footerContent: {
                EmptyView()
            },
            toolbarContent: {
                Menu {
                    Button {
                        beginSystemContactImport()
                    } label: {
                        Label("导入本机联系人", systemImage: "person.badge.plus")
                    }
                    Button {
                        exportContactsVCard()
                    } label: {
                        Label("导出联系人 vCard", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Label("新增联系人", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel("更多操作")
            }
        )
        .onAppear(perform: openFocusedContactIfNeeded)
        .sheet(isPresented: $showAdd) {
            ProjectContactDatabaseEditSheet(contact: nil, projects: store.projects, initialProjectId: selectedProjectId) { contact in
                store.upsertProjectContact(contact, insertAtTopWhenNew: true)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingContact) { contact in
            ProjectContactDatabaseEditSheet(contact: contact, projects: store.projects, initialProjectId: contact.projectId) { updated in
                store.upsertProjectContact(updated)
                store.scheduleSave()
                editingContact = nil
            } onDelete: { target in
                deleteContact(target)
                editingContact = nil
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .vCard,
            defaultFilename: exportPayload?.defaultFilename ?? "项目联系人.vcf"
        ) { _ in }
        .sheet(isPresented: $showSystemContactPicker) {
            SystemContactPicker(
                onSelect: { imported in
                    importSystemContact(imported)
                },
                onCancel: {}
            )
        }
        .alert("联系人导入", isPresented: $showImportFeedbackAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importFeedbackMessage)
        }
        .confirmationDialog("合并联系人？", isPresented: $showMergeConfirm, titleVisibility: .visible) {
            Button("合并，保留第一个项目的联系人", role: .destructive) {
                if let phone = mergeConfirmPhone {
                    mergeDuplicateContacts(phone: phone)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let phone = mergeConfirmPhone,
               let group = duplicatePhoneGroups.first(where: { $0.phone == phone }) {
                Text("将删除 \(group.contacts.count - 1) 个重复联系人，仅保留每个项目中身份信息最完整的记录。")
            }
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }

    private var filterBars: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            // 项目筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    contactFilterChip(title: "全部项目", isSelected: selectedProjectId == nil && roleFilter == nil, isColored: false) {
                        selectedProjectId = nil
                        roleFilter = nil
                    }
                    ForEach(store.projects.sorted { $0.name < $1.name }) { project in
                        contactFilterChip(title: project.name, isSelected: selectedProjectId == project.id, isColored: true) {
                            selectedProjectId = project.id
                            roleFilter = nil
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            // 角色筛选
            if selectedProjectId == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        contactFilterChip(title: "全部", isSelected: roleFilter == nil, isColored: false) {
                            roleFilter = nil
                        }
                        ForEach(ProjectContactRole.allCases, id: \.rawValue) { role in
                            contactFilterChip(title: role.displayName, isSelected: roleFilter == role, isColored: true) {
                                roleFilter = role
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func contactFilterChip(title: String, isSelected: Bool, isColored: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.appPrimaryAction : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func openFocusedContactIfNeeded() {
        guard let focusedContactId, !didOpenFocusedContact,
              let contact = store.projectContacts.first(where: { $0.id == focusedContactId }) else { return }
        didOpenFocusedContact = true
        searchText = ""
        selectedProjectId = contact.projectId
        Task { @MainActor in
            editingContact = contact
        }
    }

    private func deleteContact(_ contact: ProjectContact) {
        deleteContacts(Set([contact.id]), source: "ProjectContactDatabaseView")
    }

    private func deleteContacts(_ ids: Set<UUID>, source: String = "ProjectContactDatabaseView") {
        guard !ids.isEmpty else { return }
        let targets = store.projectContacts.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let deletion = store.removeProjectContacts(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除联系人 %lld 位"), Int64(targets.count)),
                detail: contactAuditDetail(targets),
                source: source
            )
        )
        queueContactDeletion(
            deletion,
            message: String(format: String(localized: "已删除 %lld 位联系人"), Int64(deletion.deletedCount))
        )
    }

    private func deleteContacts(_ items: [ProjectContact]) {
        deleteContacts(Set(items.map(\.id)))
    }

    private func queueContactDeletion(
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

    private func contactAuditDetail(_ contacts: [ProjectContact]) -> String {
        ListFormatter.localizedString(
            byJoining: contacts.map { contact in
                [contact.name, contact.phone, projectName(contact.projectId)]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            }
        )
    }

    /// 同一手机号关联的项目名列表
    private func linkedProjectNames(for contact: ProjectContact) -> [String] {
        let phoneKey = normalizedPhone(contact.phone)
        var projectIDs = Set(contact.relatedProjectIds)
        if !phoneKey.isEmpty {
            let all = store.projectContacts.filter { normalizedPhone($0.phone) == phoneKey && $0.id != contact.id }
            projectIDs.formUnion(all.map(\.projectId))
            projectIDs.formUnion(all.flatMap(\.relatedProjectIds))
        }
        projectIDs.remove(contact.projectId)
        return projectNames(for: Array(projectIDs))
    }

    /// 合并同一手机号的重复联系人（每个项目仅保留一条最完整的记录）
    private func mergeDuplicateContacts(phone: String) {
        let phoneKey = normalizedPhone(phone)
        let all = store.projectContacts.filter { normalizedPhone($0.phone) == phoneKey }
        guard all.count > 1 else { return }
        // 按项目分组，每个项目只保留一条
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
        let targets = store.projectContacts.filter { idsToDelete.contains($0.id) }
        guard !targets.isEmpty else { return }

        let deletion = store.removeProjectContacts(
            ids: idsToDelete,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "合并重复联系人，删除 %lld 位"), Int64(targets.count)),
                detail: "\(phoneKey) · \(contactAuditDetail(targets))",
                source: "ProjectContactDatabaseView"
            )
        )
        queueContactDeletion(
            deletion,
            message: String(format: String(localized: "已合并联系人，删除 %lld 个重复项"), Int64(deletion.deletedCount))
        )
    }

    /// 导出 vCard
    private func exportContactsVCard() {
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
            defaultFilename: "项目联系人.vcf"
        )
        showExporter = true
    }

    private func projectName(_ id: UUID) -> String {
        store.projects.first(where: { $0.id == id })?.name ?? "未知项目"
    }

    private func projectNames(for ids: [UUID]) -> [String] {
        ids.compactMap { id in
            store.projects.first(where: { $0.id == id })?.name
        }
    }

    private func normalizedPhone(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    private func contactCRMSummary(for contact: ProjectContact) -> String? {
        let cluster = contactCluster(for: contact)
        let projectIds = Array(Set(cluster.map(\.projectId)))
        guard !projectIds.isEmpty else { return nil }

        let sortedProjects = projectIds.sorted { lhs, rhs in
            recentActivityDate(for: lhs) > recentActivityDate(for: rhs)
        }
        let projectNames = sortedProjects
            .prefix(2)
            .map { projectName($0) }
            .filter { !$0.isEmpty && $0 != "未知项目" }
        let projectPreview = projectNames.isEmpty ? "暂无项目" : projectNames.joined(separator: "、")
        let unpaid = sortedProjects.reduce(0.0) { total, projectId in
            total + unpaidAmount(for: projectId)
        }

        if unpaid > 0 {
            return "最近合作：\(projectPreview) · 待收 \(ReportBuilder.money(unpaid))"
        }
        return "最近合作：\(projectPreview)"
    }

    private func contactCluster(for contact: ProjectContact) -> [ProjectContact] {
        let phoneKey = normalizedPhone(contact.phone)
        if !phoneKey.isEmpty {
            return store.projectContacts.filter { normalizedPhone($0.phone) == phoneKey }
        }
        let nameKey = contact.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !nameKey.isEmpty else { return [contact] }
        return store.projectContacts.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameKey
        }
    }

    private func recentActivityDate(for projectId: UUID) -> Date {
        let summaryDate = projectStore.projectActivitySummary(for: projectId).latestActivityDate
        let startDate = store.projects.first(where: { $0.id == projectId })
            .flatMap { Formatters.parseDateOrDateTime($0.startDate) }
            ?? .distantPast
        return max(summaryDate ?? .distantPast, startDate)
    }

    private func unpaidAmount(for projectId: UUID) -> Double {
        guard let project = store.projects.first(where: { $0.id == projectId }) else { return 0 }
        let contract = project.contractAmountValue.doubleValue
        let paidFromSummary = projectStore.projectActivitySummary(for: projectId).collectedIncomeAmount
        let paid = max(paidFromSummary, project.paidAmountValue.doubleValue)
        return max(contract - paid, 0)
    }

    private func beginSystemContactImport() {
        guard !store.projects.isEmpty else {
            showImportFeedback("请先创建项目，再导入联系人。")
            return
        }
        guard targetProjectIdForImport() != nil else {
            showImportFeedback("请先在顶部筛选中选择一个项目，再导入联系人。")
            return
        }
        showSystemContactPicker = true
    }

    private func targetProjectIdForImport() -> UUID? {
        if let selectedProjectId {
            return selectedProjectId
        }
        if store.projects.count == 1 {
            return store.projects[0].id
        }
        return nil
    }

    private func importSystemContact(_ imported: ImportedSystemContact) {
        showSystemContactPicker = false
        guard let projectId = targetProjectIdForImport() else {
            showImportFeedback("请先选择项目，再导入联系人。")
            return
        }

        let resolvedName = imported.fullName.isEmpty
            ? (imported.organizationName.isEmpty ? "未命名联系人" : imported.organizationName)
            : imported.fullName

        let normalizedPrimary = normalizedPhone(imported.primaryPhone)
        if !normalizedPrimary.isEmpty,
           let existing = store.projectContacts.first(where: {
               normalizedPhone($0.phone) == normalizedPrimary && $0.isLinked(to: projectId)
           }) {
            selectedProjectId = projectId
            editingContact = existing
            showImportFeedback("该号码已存在，已定位到现有联系人。")
            return
        }

        var noteLines: [String] = []
        if imported.phoneNumbers.count > 1 {
            noteLines.append("备用号码：\(imported.phoneNumbers.dropFirst().joined(separator: "、"))")
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
        showImportFeedback("已导入联系人：\(resolvedName)")
    }

    private func showImportFeedback(_ message: String) {
        importFeedbackMessage = message
        showImportFeedbackAlert = true
    }
}

private struct ProjectContactDatabaseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contact: ProjectContact?
    let projects: [Project]
    let initialProjectId: UUID?
    let onSave: (ProjectContact) -> Void
    var onDelete: ((ProjectContact) -> Void)?

    @State private var projectId: UUID?
    @State private var relatedProjectIDs: Set<UUID>
    @State private var name: String
    @State private var role: ProjectContactRole
    @State private var company: String
    @State private var phone: String
    @State private var note: String
    @State private var showDeleteConfirm = false
    @State private var showSystemContactPicker = false

    init(
        contact: ProjectContact?,
        projects: [Project],
        initialProjectId: UUID?,
        onSave: @escaping (ProjectContact) -> Void,
        onDelete: ((ProjectContact) -> Void)? = nil
    ) {
        self.contact = contact
        self.projects = projects
        self.initialProjectId = initialProjectId
        self.onSave = onSave
        self.onDelete = onDelete
        _projectId = State(initialValue: contact?.projectId ?? initialProjectId ?? projects.first?.id)
        _relatedProjectIDs = State(initialValue: Set(contact?.relatedProjectIds ?? []))
        _name = State(initialValue: contact?.name ?? "")
        _role = State(initialValue: contact?.role ?? .owner)
        _company = State(initialValue: contact?.company ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _note = State(initialValue: contact?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("归属项目") {
                    Picker("项目", selection: $projectId) {
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    ProjectTagMultiSelectView(
                        projects: projects,
                        primaryProjectId: projectId,
                        selectedProjectIDs: $relatedProjectIDs
                    )
                }
                Section("联系人") {
                    Button {
                        showSystemContactPicker = true
                    } label: {
                        Label("从通讯录导入", systemImage: "person.badge.plus")
                    }
                    TextField("姓名/单位", text: $name)
                    ProjectContactRoleField(role: $role)
                    TextField("公司/班组", text: $company)
                    TextField("电话", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                if contact != nil {
                    Section {
                        Button("删除联系人", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(contact == nil ? "新增联系人" : "编辑联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedContact)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("删除这个联系人？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let contact { onDelete?(contact) }
                    dismiss()
                }
            }
            .sheet(isPresented: $showSystemContactPicker) {
                SystemContactPicker(
                    onSelect: { imported in
                        applyImportedContact(imported)
                    },
                    onCancel: {}
                )
            }
        }
    }

    private var canSave: Bool {
        projectId != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var updatedContact: ProjectContact {
        let targetProjectId = projectId ?? initialProjectId ?? projects.first?.id ?? UUID()
        var value = contact ?? ProjectContact(projectId: targetProjectId, name: "")
        value.projectId = targetProjectId
        value.relatedProjectIds = Array(relatedProjectIDs.filter { $0 != targetProjectId })
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.role = role
        value.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        value.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private func applyImportedContact(_ imported: ImportedSystemContact) {
        showSystemContactPicker = false
        if !imported.fullName.isEmpty { name = imported.fullName }
        if !imported.organizationName.isEmpty { company = imported.organizationName }
        if !imported.primaryPhone.isEmpty { phone = imported.primaryPhone }
        appendSparePhones(imported)
    }

    private func appendSparePhones(_ imported: ImportedSystemContact) {
        guard imported.phoneNumbers.count > 1 else { return }
        let spareText = imported.phoneNumbers.dropFirst().joined(separator: "、")
        guard !spareText.isEmpty else { return }
        let marker = "备用号码：\(spareText)"
        if note.contains(marker) { return }
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        note = note.isEmpty ? marker : "\(note)\n\(marker)"
    }
}
