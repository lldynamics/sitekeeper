import Foundation

extension SiteKeeperCADKernel.CADExternalSDKDrawing {
    init(database: SiteKeeperCADKernel.CADDatabase) {
        let entities = database.entities.map { SiteKeeperCADKernel.CADExternalSDKEntity(entity: $0) }
        self.init(
            units: database.units,
            extents: database.extents,
            layers: database.layers,
            layouts: database.layouts,
            entities: entities,
            blocks: database.blocks.map { SiteKeeperCADKernel.CADExternalSDKBlock(block: $0) },
            textStyles: database.textStyles,
            xrefs: database.xrefs,
            diagnostics: database.diagnostics,
            performanceTrace: database.performanceTrace,
            textTrace: database.textTrace
        )
    }
}

extension SiteKeeperCADKernel.CADExternalSDKBlock {
    init(block: SiteKeeperCADKernel.CADBlock) {
        self.init(
            id: block.id,
            name: block.name,
            basePoint: block.basePoint,
            entities: block.entities.map { SiteKeeperCADKernel.CADExternalSDKEntity(entity: $0) },
            bounds: block.bounds,
            sourceHandle: block.sourceHandle
        )
    }
}

extension SiteKeeperCADKernel.CADExternalSDKEntity {
    init(entity: SiteKeeperCADKernel.CADEntity) {
        self.init(
            type: entity.kind,
            layerId: entity.layerID,
            layoutId: entity.layoutID,
            color: entity.color,
            lineType: entity.lineType,
            lineWeight: entity.lineWeight,
            geometry: SiteKeeperCADKernel.CADExternalSDKGeometry(entity: entity),
            text: entity.text.map { SiteKeeperCADKernel.CADExternalSDKText(text: $0) },
            blockName: entity.blockName,
            visibility: entity.visibility,
            sourceHandle: entity.sourceHandle,
            diagnostics: entity.diagnostics,
            unsupportedReason: entity.unsupportedReason
        )
    }
}

extension SiteKeeperCADKernel.CADExternalSDKGeometry {
    init?(entity: SiteKeeperCADKernel.CADEntity) {
        if let path = entity.path {
            self = .path(path)
            return
        }
        guard !entity.bounds.isEmpty else { return nil }
        self = .bounds(entity.bounds)
    }
}

extension SiteKeeperCADKernel.CADExternalSDKText {
    init(text: SiteKeeperCADKernel.CADTextRun) {
        self.init(
            rawText: text.rawText,
            decodedText: text.decodedText,
            normalizedText: text.normalizedText,
            displayText: text.displayText,
            styleName: text.styleName,
            fontFile: text.fontFile,
            bigFontFile: text.bigFontFile,
            selectedFontName: text.selectedFontName,
            decodeMethod: text.decodeMethod,
            warnings: text.warnings,
            insertionPoint: text.insertionPoint,
            textStyleId: text.textStyleId,
            height: text.height,
            rotationRadians: text.rotationRadians
        )
    }
}
