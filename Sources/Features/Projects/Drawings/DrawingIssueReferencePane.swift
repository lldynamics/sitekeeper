import SwiftUI

struct DrawingIssueReferencePane: View {
    let drawing: ProjectDrawing
    let onReferencePage: (Int) -> Void
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            if drawing.fileType.lowercased() == "pdf", drawing.fileAvailabilityStatus == .available {
                AppPDFDocumentView(url: DrawingStorage.fileURL(for: drawing.fileName), onPageChange: { currentPage = $0 })
                Button {
                    onReferencePage(currentPage)
                } label: {
                    Label(AppLocalization.string("引用当前页"), systemImage: "link")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(currentPage == 0)
                .accessibilityIdentifier("drawing-reference-page")
            } else {
                ContentUnavailableView(
                    AppLocalization.string("图纸原件"), systemImage: "doc.viewfinder",
                    description: Text(ProjectDetailDrawingHelper.fileAvailabilityLine(for: drawing).text)
                )
            }
        }
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawing-reference-pane")
    }
}
