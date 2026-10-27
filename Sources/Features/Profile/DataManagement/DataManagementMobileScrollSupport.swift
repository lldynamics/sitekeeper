import SwiftUI

private struct DataManagementMobileScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DataManagementMobileScrollProbeRow: View {
    let onOffsetChange: ((CGFloat) -> Void)?
    @State private var baselineMinY: CGFloat?
    @State private var lastReportedOffset: CGFloat = .greatestFiniteMagnitude

    var body: some View {
        Color.clear
            .frame(height: 0)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DataManagementMobileScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .global).minY
                    )
                }
            }
            .onPreferenceChange(DataManagementMobileScrollOffsetPreferenceKey.self) { minY in
                guard let onOffsetChange else { return }
                if let baselineMinY {
                    let offset = minY - baselineMinY
                    guard lastReportedOffset.isInfinite || abs(offset - lastReportedOffset) > 1 else { return }
                    lastReportedOffset = offset
                    onOffsetChange(offset)
                } else {
                    baselineMinY = minY
                    lastReportedOffset = 0
                    onOffsetChange(0)
                }
            }
    }
}
