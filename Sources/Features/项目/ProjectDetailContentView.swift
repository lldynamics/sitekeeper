import SwiftUI

struct ProjectDetailContentView<JumpBar: View, Header: View, QuickActions: View, ModePicker: View, Content: View>: View {
    let isWide: Bool
    let scrollRequest: ProjectDetailAnchorRequest?
    @ViewBuilder let jumpBar: () -> JumpBar
    @ViewBuilder let header: () -> Header
    @ViewBuilder let quickActions: () -> QuickActions
    @ViewBuilder let modePicker: () -> ModePicker
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            List {
                jumpBar()
                header()
                quickActions()
                modePicker()
                content()
            }
            .onChange(of: scrollRequest?.id) { _, _ in
                guard let request = scrollRequest else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(request.anchor.scrollID, anchor: .top)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
        .frame(maxWidth: isWide ? 980 : .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: isWide ? .topLeading : .center)
    }
}
