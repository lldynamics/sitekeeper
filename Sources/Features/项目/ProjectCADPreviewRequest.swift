import Foundation

struct ProjectCADPreviewRequest: Identifiable {
    let id = UUID()
    let projectId: UUID
    let drawingID: UUID
    let fileURL: URL
    let displayName: String
    let fileType: String
    let importedAt: String
    let fileSizeBytes: Int
    let textEncoding: CADDrawingTextEncoding
    let textBigFont: CADDrawingTextBigFont
    let textSchemeSnapshot: CADDrawingTextSchemeSnapshot
    let cadViewState: CADDrawingViewState
    let projectFontMappings: [CADProjectFontMapping]
    let overlaySnapshotData: String
    let onOverlaySnapshotChange: (UUID, String) -> Void
    let onViewStateChange: (UUID, CADDrawingViewState) -> Void
    let onTextEncodingChange: (UUID, CADDrawingTextEncoding) -> Void
    let onTextBigFontChange: (UUID, CADDrawingTextBigFont) -> Void
    let onTextSchemeSnapshotChange: (UUID, CADDrawingTextSchemeSnapshot) -> Void
    let onProjectFontMappingsChange: (UUID, [CADProjectFontMapping]) -> Void

    var preferredTextCodePage: Int32? {
        textEncoding.codePageOverride
    }

    var preferredTextBigFontCode: Int32? {
        textBigFont.bridgeCode
    }

    var cadFile: CADFile {
        CADFile(
            id: id,
            projectId: projectId,
            drawingId: drawingID,
            fileURL: fileURL,
            displayName: displayName,
            fileType: fileType,
            importedAt: importedAt,
            fileSizeBytes: fileSizeBytes
        )
    }

    var rendererFontMappings: [CADRendererFontMapping] {
        projectFontMappings.compactMap { mapping in
            guard !mapping.normalizedPattern.isEmpty,
                  mapping.bigFont != .auto,
                  let bridgeCode = mapping.bigFont.bridgeCode else { return nil }
            return CADRendererFontMapping(
                sourceKind: mapping.source.rawValue,
                pattern: mapping.normalizedPattern,
                bigFont: bridgeCode
            )
        }
    }
}
