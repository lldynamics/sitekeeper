import SwiftUI

struct MaterialSelectionControls: View {
    let hasSelection: Bool
    let onSelectAll: () -> Void
    let onClear: () -> Void

    var body: some View {
        Section {
            HStack {
                Button(AppLocalization.string("全选当前结果"), action: onSelectAll)
                Spacer()
                Button(AppLocalization.string("清除选择"), action: onClear)
                    .disabled(!hasSelection)
            }
            .font(.callout)
        }
    }
}
