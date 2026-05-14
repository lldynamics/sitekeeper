import SwiftUI

struct ProjectDetailPrimaryActionList<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            Section("快捷操作") {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                }
                .buttonStyle(.appProminent(tint: tint))
            }

            content()
        }
    }
}
