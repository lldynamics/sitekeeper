import SwiftUI

/// Project-local entry points keep the existing detail layout and navigation intact.
struct ProjectFieldWorkflowView: View {
    @Environment(DataStore.self) private var store
    private let projectID: UUID

    init(project: Project) { projectID = project.id }

    var body: some View {
        Group {
            if let project = store.projects.first(where: { $0.id == projectID }) {
                List {
                    Section(project.name) {
                        NavigationLink { ProjectFieldReportView(project: project) } label: {
                            Label(AppLocalization.string("施工日报与周报"), systemImage: "doc.text.image")
                        }
                        .accessibilityIdentifier("project.field-report")
                        NavigationLink { ProjectStatementView(project: project) } label: {
                            Label(AppLocalization.string("客户收款对账"), systemImage: "list.bullet.rectangle")
                        }
                        .accessibilityIdentifier("project.customer-statement")
                        NavigationLink { MaterialFollowUpView(project: project) } label: {
                            Label(AppLocalization.string("采购与催货清单"), systemImage: "shippingbox")
                        }
                        .accessibilityIdentifier("project.material-follow-up")
                        NavigationLink { ProjectChangeOrdersView(project: project) } label: {
                            Label(AppLocalization.string("工程变更与增项"), systemImage: "doc.badge.plus")
                        }
                        .accessibilityIdentifier("project.change-orders")
                    }
                    Section {
                        Text(AppLocalization.string("导出前先预览项目、日期和内容；由你选择是否分享。增项确认单单独记录，不自动修改合同或账目。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(AppLocalization.string("项目不存在"), systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(AppLocalization.string("现场汇报与核对"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
