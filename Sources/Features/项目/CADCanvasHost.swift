import SwiftUI

struct CADCanvasHost<Renderer: View, Overlay: View, ImmersiveOverlay: View, ImmersiveTop: View>: View {
    let isImmersivePreview: Bool
    let allowsOverlayEditing: Bool
    let overlayHitTestingEnabled: Bool
    let immersiveTopSafePadding: CGFloat
    let immersiveBottomSafePadding: CGFloat
    @ViewBuilder let renderer: () -> Renderer
    @ViewBuilder let overlayLayer: (CGSize) -> Overlay
    @ViewBuilder let immersiveOverlayControls: () -> ImmersiveOverlay
    @ViewBuilder let immersiveTopControls: () -> ImmersiveTop

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                renderer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if allowsOverlayEditing {
                    overlayLayer(geo.size)
                        .allowsHitTesting(overlayHitTestingEnabled)
                        .zIndex(1)
                }
                if allowsOverlayEditing && isImmersivePreview {
                    immersiveOverlayControls()
                        .padding(.horizontal, 12)
                        .padding(.bottom, immersiveBottomSafePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .zIndex(2)
                }
                if isImmersivePreview {
                    immersiveTopControls()
                        .padding(.horizontal, 12)
                        .padding(.top, immersiveTopSafePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(3)
                }
            }
            .background(Color.black.opacity(0.02))
        }
    }
}
