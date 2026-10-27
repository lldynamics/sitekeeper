import SwiftUI

extension ProjectDetailContainer {
    var projectAddMenu: some View {
        Menu {
            Button {
                routeState.presentation = .quickAdd(.log)
            } label: {
                Label(AppLocalization.string("写施工日志"), systemImage: "book.pages.fill")
            }
            Button {
                routeState.presentation = .addFinancial
            } label: {
                Label(AppLocalization.string("新增账目"), systemImage: "receipt.fill")
            }
            Button {
                routeState.presentation = .quickAdd(.material)
            } label: {
                Label(AppLocalization.string("新增材料"), systemImage: "shippingbox.fill")
            }
            Button {
                routeState.presentation = .quickAdd(.quote)
            } label: {
                Label(AppLocalization.string("新增报价"), systemImage: "doc.text.fill")
            }
            Button {
                routeState.presentation = .quickAdd(.labor)
            } label: {
                Label(AppLocalization.string("新增人工记录"), systemImage: "person.2.fill")
            }
            Button {
                routeState.presentation = .addContact
            } label: {
                Label(AppLocalization.string("新增联系人"), systemImage: "person.crop.circle.badge.plus")
            }
        } label: {
            Label(AppLocalization.string("新增记录"), systemImage: "plus.circle.fill")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel(AppLocalization.string("新增记录"))
        .accessibilityIdentifier("project-detail-add-menu")
    }

    func projectMoreMenu(project: Project, snapshot: ProjectDetailSnapshot) -> some View {
        Menu {
            Button {
                openTodoFilterFromMetric()
            } label: {
                Label(AppLocalization.string("处理待办"), systemImage: "checklist.checked")
            }
            Button {
                routeState.presentation = .editProject
            } label: {
                Label(AppLocalization.string("编辑项目资料"), systemImage: "square.and.pencil")
            }

            Divider()

            Button {
                routeState.documentScanCategory = nil
                routeState.presentation = .documentScanSetup
            } label: {
                Label(AppLocalization.string("扫描项目资料"), systemImage: "doc.viewfinder.fill")
            }
            Button {
                assetState.showDrawingImporter = true
            } label: {
                Label(AppLocalization.string("导入图纸原件"), systemImage: "square.on.square.squareshape.controlhandles")
            }

            Divider()

            Button {
                routeState.presentation = .deliveryGuide
            } label: {
                Label(AppLocalization.string("打开交付向导"), systemImage: "checklist.checked")
            }
            Button {
                requestExportProjectPackage(project, snapshot: snapshot)
            } label: {
                Label(AppLocalization.string("导出交付包"), systemImage: "archivebox.fill")
            }
        } label: {
            Label(AppLocalization.string("更多操作"), systemImage: "ellipsis.circle")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel(AppLocalization.string("更多操作"))
        .accessibilityIdentifier("project-detail-more-menu")
    }
}
