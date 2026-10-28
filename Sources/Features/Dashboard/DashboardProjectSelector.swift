import SwiftUI

struct DashboardProjectSelector: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let activeProjectCount: Int
    let displayLimit: Int
    let rows: [DashboardProjectRow]
    let hiddenProjectCount: Int
    let selectedProjectID: UUID?
    @Binding var selectedProjectIdRaw: String
    let onShowPicker: () -> Void

    @ViewBuilder
    var body: some View {
        if activeProjectCount == 0 {
            emptyCurrentProjectSelector
        } else {
            focusedProjectScrollerShell
        }
    }

    private var emptyCurrentProjectSelector: some View {
        NavigationLink { ProjectListView() } label: {
            emptyCurrentProjectSelectorLabel
        }
        .buttonStyle(.plain)
        .padding(AppSpacing.normal)
        .background {
            AppSurface(
                tone: .grouped,
                cornerRadius: 16,
                shadow: .card,
                stroke: Color(uiColor: .separator).opacity(0.18)
            ) {
                Color.clear
            }
        }
        .accessibilityIdentifier("dashboard-empty-active-projects")
    }

    @ViewBuilder
    private var emptyCurrentProjectSelectorLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Label(AppLocalization.string("暂无进行中工程"), systemImage: "building.2")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(AppLocalization.string("去添加"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
            }
        } else {
            HStack(spacing: AppSpacing.tight) {
                Label(AppLocalization.string("暂无进行中工程"), systemImage: "building.2")
                Spacer()
                Text(AppLocalization.string("去添加"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
            }
        }
    }

    private var focusedProjectScrollerShell: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(spacing: AppSpacing.tight) {
                Label(AppLocalization.string("进行中的工程"), systemImage: "scope")
                    .font(.headline)
                Spacer()
                if activeProjectCount > displayLimit {
                    Text(String(format: AppLocalization.string("共 %lld 个"), Int64(activeProjectCount)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(rows) { row in
                        dashboardProjectButton(row)
                    }

                    if hiddenProjectCount > 0 {
                        Button {
                            onShowPicker()
                        } label: {
                            DashboardProjectChip(
                                title: String(format: AppLocalization.string("更多 %lld"), Int64(hiddenProjectCount)),
                                subtitle: AppLocalization.string("查看全部"),
                                isSelected: false,
                                color: .appDoc
                            )
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.normal)
        .background {
            AppSurface(
                tone: .grouped,
                cornerRadius: 16,
                shadow: .card,
                stroke: Color(uiColor: .separator).opacity(0.18)
            ) {
                Color.clear
            }
        }
    }

    private func dashboardProjectButton(_ row: DashboardProjectRow) -> some View {
        let project = row.project
        return NavigationLink {
            ProjectDetailView(projectId: project.id)
        } label: {
            DashboardProjectChip(
                title: project.name,
                subtitle: row.subtitle,
                isSelected: selectedProjectID == project.id,
                color: row.color
            )
        }
        .simultaneousGesture(TapGesture().onEnded {
            selectedProjectIdRaw = project.id.uuidString
        })
        .contextMenu {
            Button {
                selectedProjectIdRaw = project.id.uuidString
            } label: {
                Label(AppLocalization.string("设为当前工程"), systemImage: "pin.fill")
            }
            NavigationLink {
                DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
            } label: {
                Label(AppLocalization.string("写日志"), systemImage: "book.pages.fill")
            }
            NavigationLink {
                SiteTodoView(initialProjectId: project.id, autoOpenComposer: true)
            } label: {
                Label(AppLocalization.string("加待办"), systemImage: "checklist")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
            } label: {
                Label(AppLocalization.string("记账"), systemImage: "receipt.fill")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
            } label: {
                Label(AppLocalization.string("加资料"), systemImage: "doc.badge.plus")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, initialMode: .assets)
            } label: {
                Label(AppLocalization.string("联系人/资料"), systemImage: "person.crop.rectangle.stack")
            }
        }
    }
}
