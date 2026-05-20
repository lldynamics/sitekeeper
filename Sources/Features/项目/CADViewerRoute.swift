import SwiftUI

struct CADViewerRoute: View {
    let request: ProjectCADPreviewRequest
    var showsToolbar = true
    var initialViewState: CADRendererViewState? = nil
    var callbacks = CADRendererCallbacks()
    var selectedLayoutID: String? = nil
    var visibleLayerIDs: Set<String>? = nil
    var onLayoutsChanged: ([NativeCAD.CADLayout]) -> Void = { _ in }
    var onSelectedLayoutIDChanged: (String?) -> Void = { _ in }
    var onLayersChanged: ([NativeCAD.CADLayer]) -> Void = { _ in }
    var onVisibleLayerIDsChanged: (Set<String>?) -> Void = { _ in }
    let onClose: () -> Void
    let onReportIssue: () -> Void

    var body: some View {
        NativeCADViewerEntry(
            fileURL: request.fileURL,
            displayName: request.displayName,
            textImportOptions: CADCanvasTextImportOptions(
                preferredTextCodePage: request.preferredTextCodePage,
                preferredTextBigFont: request.preferredTextBigFontCode,
                fontMappings: request.rendererFontMappings
            ),
            showsToolbar: showsToolbar,
            initialViewState: initialViewState,
            callbacks: callbacks,
            externalCurrentLayoutID: selectedLayoutID,
            externalVisibleLayerIDs: visibleLayerIDs,
            onLayoutsChangedExternal: onLayoutsChanged,
            onCurrentLayoutIDChangedExternal: onSelectedLayoutIDChanged,
            onLayersChangedExternal: onLayersChanged,
            onVisibleLayerIDsChangedExternal: onVisibleLayerIDsChanged,
            onClose: onClose,
            onReportIssue: onReportIssue
        )
    }
}
