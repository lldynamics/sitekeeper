import SwiftUI
import UniformTypeIdentifiers

struct ProjectContactDatabaseView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    let focusedContactId: UUID?
    @State var searchText = ""
    @State var selectedProjectId: UUID?
    @State var roleFilter: ProjectContactRole?
    @State var showAdd = false
    @State var editingContact: ProjectContact?
    @State var didOpenFocusedContact = false
    @State var exportPayload: ExportPayload?
    @State var showExporter = false
    @State var showSystemContactPicker = false
    @State var importFeedbackMessage = ""
    @State var showImportFeedbackAlert = false
    @State var mergeConfirmPhone: String?
    @State var showMergeConfirm = false
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()

    init(focusedContactId: UUID? = nil) {
        self.focusedContactId = focusedContactId
    }

    var projects: [Project] {
        projectStore.projects
    }

    var projectContacts: [ProjectContact] {
        projectStore.projectContacts
    }

    private var scopedContacts: [ProjectContact] {
        projectContacts.filter { contact in
            guard let selectedProjectId else { return true }
            return contact.isLinked(to: selectedProjectId)
        }
        .filter {
            guard let roleFilter else { return true }
            return $0.role == roleFilter
        }
    }

    var filteredContacts: [ProjectContact] {
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
            projects: projects,
            contacts: scopedContacts,
            limit: 6
        )
    }

    private var duplicatePhoneGroups: [(phone: String, contacts: [ProjectContact])] {
        let grouped = Dictionary(grouping: projectContacts) { normalizedPhone($0.phone) }
        return grouped
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { (phone: $0.key, contacts: $0.value.sorted { projectName($0.projectId) < projectName($1.projectId) }) }
            .sorted { $0.phone < $1.phone }
    }

    var body: some View {
        SearchableDatabaseView(
            title: AppLocalization.string("联系人"),
            searchText: $searchText,
            searchPrompt: AppLocalization.string("搜索姓名、电话、公司、项目"),
            items: filteredContacts,
            emptyTitle: AppLocalization.string("暂无联系人"),
            emptySystemImage: "person.crop.rectangle.stack",
            emptyDescription: Text(AppLocalization.string("项目联系人会统一显示在这里，可按项目筛选。")),
            emptyActionTitle: projectContacts.isEmpty ? AppLocalization.string("添加联系人") : AppLocalization.string("清除筛选"),
            emptyActionSystemImage: projectContacts.isEmpty ? "person.crop.circle.badge.plus" : "line.3.horizontal.decrease.circle",
            onEmptyAction: {
                if projectContacts.isEmpty {
                    showAdd = true
                } else {
                    searchText = ""
                    selectedProjectId = nil
                    roleFilter = nil
                }
            },
            searchSuggestions: searchSuggestions,
            searchEmptyStateText: AppLocalization.string("未找到匹配的联系人、电话、公司或项目"),
            onSelect: { contact in
                editingContact = contact
            },
            onSelectSuggestion: { suggestion in
                guard suggestion.category == .contact else { return }
                guard let contact = projectContacts.first(where: { $0.id == suggestion.entityId }) else { return }
                selectedProjectId = contact.projectId
                editingContact = contact
            },
            deleteConfig: SearchableDatabaseDeleteConfig(
                title: AppLocalization.string("删除联系人？"),
                itemNoun: AppLocalization.string("联系人"),
                singularMessage: AppLocalization.string("删除后可在提示中撤销。"),
                pluralMessage: { count, noun in
                    String(format: AppLocalization.string("将删除 %lld 条%@，可在提示中撤销。"), Int64(count), noun)
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
                    ProjectContactFilterBars(projects: projects, selectedProjectId: $selectedProjectId, roleFilter: $roleFilter)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if selectedProjectId == nil && !duplicatePhoneGroups.isEmpty {
                    Section(AppLocalization.string("疑似重复联系人")) {
                        ForEach(duplicatePhoneGroups, id: \.phone) { group in
                            DisclosureGroup(String(format: AppLocalization.string("%@ · %lld 条"), group.phone, Int64(group.contacts.count))) {
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
                                    Label(AppLocalization.string("合并为同一联系人"), systemImage: "arrow.triangle.merge")
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
                        Label(AppLocalization.string("导入本机联系人"), systemImage: "person.badge.plus")
                    }
                    Button {
                        exportContactsVCard()
                    } label: {
                        Label(AppLocalization.string("导出联系人 vCard"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Label(AppLocalization.string("新增联系人"), systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(AppLocalization.string("更多操作"))
            }
        )
        .onAppear(perform: openFocusedContactIfNeeded)
        .sheet(isPresented: $showAdd) {
            ProjectContactDatabaseEditSheet(contact: nil, projects: projects, initialProjectId: selectedProjectId) { contact in
                store.upsertProjectContact(contact, insertAtTopWhenNew: true)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingContact) { contact in
            ProjectContactDatabaseEditSheet(contact: contact, projects: projects, initialProjectId: contact.projectId) { updated in
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
            defaultFilename: exportPayload?.defaultFilename ?? AppLocalization.string("项目联系人.vcf")
        ) { result in
            handleContactExportCompletion(result)
        }
        .sheet(isPresented: $showSystemContactPicker) {
            SystemContactPicker(
                onSelect: { imported in
                    importSystemContact(imported)
                },
                onCancel: {}
            )
        }
        .alert(AppLocalization.string("联系人导入"), isPresented: $showImportFeedbackAlert) {
            Button(AppLocalization.string("确定"), role: .cancel) {}
        } message: {
            Text(importFeedbackMessage)
        }
        .confirmationDialog(AppLocalization.string("合并联系人？"), isPresented: $showMergeConfirm, titleVisibility: .visible) {
            Button(AppLocalization.string("合并，保留第一个项目的联系人"), role: .destructive) {
                if let phone = mergeConfirmPhone {
                    mergeDuplicateContacts(phone: phone)
                }
            }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        } message: {
            if let phone = mergeConfirmPhone,
               let group = duplicatePhoneGroups.first(where: { $0.phone == phone }) {
                Text(String(format: AppLocalization.string("将删除 %lld 个重复联系人，仅保留每个项目中身份信息最完整的记录。"), Int64(group.contacts.count - 1)))
            }
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }
}
