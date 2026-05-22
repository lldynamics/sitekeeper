import SwiftUI

struct ProjectDetailContentView<JumpBar: View, Header: View, ModePicker: View, Content: View>: View {
    let isWide: Bool
    let scrollRequest: ProjectDetailAnchorRequest?
    let onVisibleAnchorChange: (ProjectDetailAnchor) -> Void
    @ViewBuilder let jumpBar: () -> JumpBar
    @ViewBuilder let header: () -> Header
    @ViewBuilder let modePicker: () -> ModePicker
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if isWide {
                modePicker()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                Divider()
            }

            ScrollViewReader { proxy in
                List {
                    jumpBar()
                    header()
                    if !isWide {
                        modePicker()
                    }
                    content()
                }
                .coordinateSpace(name: ProjectDetailScrollTracking.coordinateSpaceName)
                .onChange(of: scrollRequest?.id) { _, _ in
                    guard let request = scrollRequest else { return }
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(request.anchor.scrollID, anchor: .top)
                    }
                }
                .onPreferenceChange(ProjectDetailAnchorOffsetPreferenceKey.self) { offsets in
                    guard isWide,
                          let anchor = ProjectDetailScrollTracking.currentAnchor(from: offsets) else { return }
                    onVisibleAnchorChange(anchor)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
        }
        .frame(maxWidth: isWide ? 980 : .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: isWide ? .topLeading : .center)
    }
}
