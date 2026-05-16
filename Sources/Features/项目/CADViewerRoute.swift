import SwiftUI

struct CADViewerRoute: View {
    let request: ProjectCADPreviewRequest
    let onReportIssue: () -> Void

    var body: some View {
        CADMetalLibreDWGPoCEntry(
            fileURL: request.fileURL,
            displayName: request.displayName,
            onReportIssue: onReportIssue
        )
    }
}
