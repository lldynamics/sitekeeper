import SwiftUI

struct RecordPageControls: View {
    let index: Int
    let count: Int
    @Binding var selection: Int

    var body: some View {
        if count > 1 {
            HStack {
                Button(AppLocalization.string("上一页")) { selection = max(0, index - 1) }.disabled(index == 0)
                Spacer()
                Text(String(format: AppLocalization.string("第 %lld / %lld 页"), Int64(index + 1), Int64(count)))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(AppLocalization.string("下一页")) { selection = min(count - 1, index + 1) }.disabled(index + 1 >= count)
            }
            .buttonStyle(.borderless)
        }
    }
}
