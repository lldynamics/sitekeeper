import SwiftUI

struct DrawingLibrarySharePresenter: ViewModifier {
    @Binding var shareURL: URL?
    @Binding var shareDrawingID: UUID?
    let store: DataStore

    private var isPresented: Binding<Bool> {
        Binding(
            get: { shareURL != nil },
            set: { isPresented in
                if !isPresented {
                    shareURL = nil
                    shareDrawingID = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            if let shareURL {
                ActivityShareSheet(activityItems: [shareURL], onComplete: { completed in
                    ProjectDetailAssetActions.recordDrawingExternalOpenResult(
                        completed: completed,
                        drawingID: shareDrawingID,
                        store: store
                    )
                    self.shareURL = nil
                    self.shareDrawingID = nil
                })
            }
        }
    }
}

extension View {
    func drawingLibrarySharePresenter(
        shareURL: Binding<URL?>,
        shareDrawingID: Binding<UUID?>,
        store: DataStore
    ) -> some View {
        modifier(
            DrawingLibrarySharePresenter(
                shareURL: shareURL,
                shareDrawingID: shareDrawingID,
                store: store
            )
        )
    }
}
