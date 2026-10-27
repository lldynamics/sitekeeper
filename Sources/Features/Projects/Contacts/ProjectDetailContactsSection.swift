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
        Section(String(format: AppLocalization.string("联系人 (%lld)"), Int64(filteredContacts.count))) {
            if !filteredContacts.isEmpty {
                Button(action: onAdd) {
                    Label(AppLocalization.string("添加联系人"), systemImage: "person.crop.circle.badge.plus")
                }
            }
            TextField(AppLocalization.string("搜索姓名、电话、公司、备注"), text: $searchText)
            Picker(AppLocalization.string("角色筛选"), selection: $roleFilter) {
                Text(AppLocalization.string("全部")).tag(ProjectContactRole?.none)
                ForEach(roleOptions, id: \.self) { item in
                    Text(item.displayName).tag(Optional(item))
                }
            }
            if filteredContacts.isEmpty {
                AppActionableEmptyState(
                    title: contacts.isEmpty ? AppLocalization.string("暂无联系人") : AppLocalization.string("没有匹配联系人"),
                    systemImage: "person.crop.circle",
                    message: contacts.isEmpty
                        ? AppLocalization.string("记录客户、监理、供应商和施工班组等联系人。")
                        : AppLocalization.string("调整搜索或角色筛选后再看。")
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
                            contacts.isEmpty ? AppLocalization.string("添加联系人") : AppLocalization.string("清除筛选"),
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
                    emptyTitle: AppLocalization.string("暂无联系人"),
                    emptySystemImage: "person.crop.circle",
                    emptyDescription: Text(AppLocalization.string("记录客户、监理、供应商和施工班组等联系人。")),
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
