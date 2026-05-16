import SwiftUI

struct CADViewerRoute: View {
    let request: ProjectCADPreviewRequest
    var showsToolbar = true
    var initialViewState: CADRendererViewState? = nil
    var callbacks = CADRendererCallbacks()
    var visibleLayerIDs: Set<String>? = nil
    var onLayersChanged: ([CADPoC.CADLayer]) -> Void = { _ in }
    var onVisibleLayerIDsChanged: (Set<String>?) -> Void = { _ in }
    let onClose: () -> Void
    let onReportIssue: () -> Void

    var body: some View {
        CADMetalLibreDWGPoCEntry(
            fileURL: request.fileURL,
            displayName: request.displayName,
            showsToolbar: showsToolbar,
            initialViewState: initialViewState,
            callbacks: callbacks,
            externalVisibleLayerIDs: visibleLayerIDs,
            onLayersChangedExternal: onLayersChanged,
            onVisibleLayerIDsChangedExternal: onVisibleLayerIDsChanged,
            onClose: onClose,
            onReportIssue: onReportIssue
        )
    }
}
