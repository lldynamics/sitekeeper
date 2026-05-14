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
        Section(String(localized: "联系人 (\(filteredContacts.count))")) {
            if !filteredContacts.isEmpty {
                Button(action: onAdd) {
                    Label("添加联系人", systemImage: "person.crop.circle.badge.plus")
                }
            }
            TextField("搜索姓名、电话、公司、备注", text: $searchText)
            Picker("角色筛选", selection: $roleFilter) {
                Text("全部").tag(ProjectContactRole?.none)
                ForEach(roleOptions, id: \.self) { item in
                    Text(item.displayName).tag(Optional(item))
                }
            }
            ContactPickerView(
                contacts: filteredContacts,
                projectName: { _ in "" },
                showsProjectName: false,
                showsPhoneActions: true,
                emptyTitle: "暂无联系人",
                emptySystemImage: "person.crop.circle",
                emptyDescription: Text("记录客户、监理、供应商和施工班组等联系人。"),
                onSelect: onEdit,
                onDelete: onDelete
            )
            if filteredContacts.isEmpty {
                Button(action: onAdd) {
                    Label("添加联系人", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.appProminent())
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
