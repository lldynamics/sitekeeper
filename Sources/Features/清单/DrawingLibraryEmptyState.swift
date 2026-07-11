import SwiftUI

struct DrawingLibraryEmptyState: View {
    let isFiltered: Bool
    let onClearFilters: () -> Void
    let onImport: () -> Void

    var body: some View {
        if isFiltered {
            AppActionableEmptyState(
                title: String(localized: "未找到图纸"),
                systemImage: "line.3.horizontal.decrease.circle",
                message: String(localized: "调整搜索词或状态筛选后再试。")
            ) {
                Button(String(localized: "清空筛选"), action: onClearFilters)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("drawing-empty-clear-filters")
            }
        } else {
            AppActionableEmptyState(
                title: String(localized: "暂无图纸"),
                systemImage: "doc.viewfinder",
                message: String(localized: "先导入 DWG / DXF / PDF 图纸原件，App 负责台账、版本、当前版和交付导出；DWG/DXF 通过外部专业看图软件打开。")
            ) {
                Button(action: onImport) {
                    Label(String(localized: "导入图纸"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("drawing-empty-import")
            }
        }
    }
}
