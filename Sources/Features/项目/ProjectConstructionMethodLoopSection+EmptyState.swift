import SwiftUI

struct ProjectConstructionMethodLoopEmptyStateView: View {
    var body: some View {
        ProjectInlineEmptyState(
            String(localized: "当前筛选没有匹配工艺"),
            systemImage: "square.stack.3d.down.right.slash",
            detail: String(localized: "可先去施工工艺库导入/新建，再回来一键生成闭环。")
        )
    }
}
