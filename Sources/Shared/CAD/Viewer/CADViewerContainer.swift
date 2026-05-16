import SwiftUI

struct CADViewerContainer: View {
    let fileURL: URL
    let displayName: String
    let onReportIssue: () -> Void

    var body: some View {
        CADMetalLibreDWGPoCEntry(
            fileURL: fileURL,
            displayName: displayName,
            onReportIssue: onReportIssue
        )
    }
}

struct CADMetalLibreDWGPoCEntry: View {
    let fileURL: URL
    let displayName: String
    let onReportIssue: () -> Void

    var body: some View {
        ZStack {
            CADCanvasView(fileURL: fileURL)

            VStack(spacing: 0) {
                CADViewerToolbar(
                    fileURL: fileURL,
                    displayName: displayName,
                    onReportIssue: onReportIssue
                )

                Spacer()
            }
        }
    }
}
