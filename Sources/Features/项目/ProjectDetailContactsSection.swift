import SwiftUI

struct ProjectContactsView: View {
    let contacts: [ProjectContact]
    let onAdd: () -> Void
    let onEdit: (ProjectContact) -> Void
    let onDelete: (Set<UUID>) -> Void
    @State private var roleFilter: ProjectContactRole?
    @State private var searchText = ""

    private var roleOptions: [ProjectContactRole] {
        Array(Set(contacts.map(\.role)))
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        Section(String(format: String(localized: "联系人 (%lld)"), Int64(filteredContacts.count))) {
            if !filteredContacts.isEmpty {
                Button(action: onAdd) {
                    Label(String(localized: "添加联系人"), systemImage: "person.crop.circle.badge.plus")
                }
            }
            TextField(String(localized: "搜索姓名、电话、公司、备注"), text: $searchText)
            Picker(String(localized: "角色筛选"), selection: $roleFilter) {
                Text(String(localized: "全部")).tag(ProjectContactRole?.none)
                ForEach(roleOptions, id: \.self) { item in
                    Text(item.displayName).tag(Optional(item))
                }
            }
            if filteredContacts.isEmpty {
                AppActionableEmptyState(
                    title: contacts.isEmpty ? String(localized: "暂无联系人") : String(localized: "没有匹配联系人"),
                    systemImage: "person.crop.circle",
                    message: contacts.isEmpty
                        ? String(localized: "记录客户、监理、供应商和施工班组等联系人。")
                        : String(localized: "调整搜索或角色筛选后再看。")
                ) {
                    Button {
                        if contacts.isEmpty {
                            onAdd()
                        } else {
                            searchText = ""
                            roleFilter = nil
                        }
                    } label: {
                        Label(
                            contacts.isEmpty ? String(localized: "添加联系人") : String(localized: "清除筛选"),
                            systemImage: contacts.isEmpty ? "person.crop.circle.badge.plus" : "line.3.horizontal.decrease.circle"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appProminent())
                }
            } else {
                ContactPickerView(
                    contacts: filteredContacts,
                    projectName: { _ in "" },
                    showsProjectName: false,
                    showsPhoneActions: true,
                    emptyTitle: String(localized: "暂无联系人"),
                    emptySystemImage: "person.crop.circle",
                    emptyDescription: Text(String(localized: "记录客户、监理、供应商和施工班组等联系人。")),
                    onSelect: onEdit,
                    onDelete: onDelete
                )
            }
        }
    }

    private var filteredContacts: [ProjectContact] {
        let roleScoped = contacts.filter { contact in
            guard let roleFilter else { return true }
            return contact.role == roleFilter
        }
        return SearchMatcher.filter(roleScoped, keyword: searchText)
    }
}
