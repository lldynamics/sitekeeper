import SwiftUI

extension View {
    /// 提升纯图标按钮在浅色/深色背景下的可见性。
    func visibleIconStyle() -> some View {
        self
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 20, height: 20)
    }
}
