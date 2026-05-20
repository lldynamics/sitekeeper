extension SiteKeeperCADKernel {
    struct CADTextEngine {
        var decoder = CADTextDecoder()
        var normalizer = CADTextNormalizer()
        var mtextParser = CADMTextParser()
        var fontResolver = CADFontResolver()

        func makeTextRun(
            rawText: String,
            insertionPoint: CADPoint,
            style: CADTextStyle,
            height: Double? = nil,
            rotationRadians: Double = 0,
            widthFactor: Double? = nil,
            boxWidth: Double? = nil,
            boxHeight: Double? = nil,
            horizontalAlignmentCode: Int? = nil,
            verticalAlignmentCode: Int? = nil,
            warnings existingWarnings: [String] = []
        ) -> CADTextRun {
            let decoded = decoder.decode(rawText: rawText, textStyle: style)
            let normalized = normalizer.normalizeText(decoded.decodedText)
            let parsed = mtextParser.parse(normalized.normalizedText)
            let font = fontResolver.resolve(style: style, displayText: parsed.plainText)
            let warnings = existingWarnings
                + decoded.warnings
                + normalized.warnings
                + parsed.warnings
                + font.warnings

            return CADTextRun(
                rawText: rawText,
                decodedText: decoded.decodedText,
                normalizedText: normalized.normalizedText,
                displayText: parsed.plainText,
                styleName: font.styleName,
                fontFile: font.fontFile,
                bigFontFile: font.bigFontFile,
                selectedFontName: font.selectedFontName,
                fontWasAvailable: font.fontWasAvailable,
                fallbackReason: font.fallbackReason,
                decodeMethod: decoded.decodeMethod,
                warnings: warnings,
                insertionPoint: insertionPoint,
                textStyleId: style.id,
                height: height ?? style.fixedHeight ?? 2.5,
                rotationRadians: rotationRadians,
                widthFactor: widthFactor ?? style.widthFactor,
                boxWidth: boxWidth,
                boxHeight: boxHeight,
                horizontalAlignmentCode: horizontalAlignmentCode,
                verticalAlignmentCode: verticalAlignmentCode
            )
        }
    }
}
