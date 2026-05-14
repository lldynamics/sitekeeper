import SwiftUI

struct CADTextOptionsPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    var textOptionsSheet: some View {
        NavigationStack {
            Form {
                Section("当前文字方案") {
                    LabeledContent(String(localized: "方案")) {
                        Text(currentTextSchemeTitle)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                    }
                    ForEach(textSchemeDiagnosticRows, id: \.0) { row in
                        LabeledContent(row.0) {
                            Text(row.1)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("常用修复") {
                    Button {
                        Task {
                            await autoDetectTextOptions()
                        }
                    } label: {
                        Label(
                            isAutoDetectingText ? "正在自动识别…" : "文字自动识别",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isAutoDetectingText || !shouldUseLibreDWGRenderer)
                    Text("优先先跑自动识别，确认评分和字体信息后再手动切换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        reloadCurrentCADPreview()
                        showTextEncodingDialog = false
                    } label: {
                        Label("按当前方案重载图纸", systemImage: "arrow.clockwise")
                    }
                    .disabled(!shouldUseLibreDWGRenderer)
                }

                Section("一键切换") {
                    Button {
                        applyTextPreset(encoding: .auto, bigFont: .auto, resetAutoDetectScore: true)
                        showTextEncodingDialog = false
                    } label: {
                        Label("自动", systemImage: "wand.and.stars")
                    }
                    Button {
                        applyTextPreset(encoding: .gbk936, bigFont: .auto, resetAutoDetectScore: true)
                        showTextEncodingDialog = false
                    } label: {
                        Label("GBK", systemImage: "character.book.closed")
                    }
                    Button {
                        applyTextPreset(encoding: .gb18030, bigFont: .auto, resetAutoDetectScore: true)
                        showTextEncodingDialog = false
                    } label: {
                        Label("GB18030", systemImage: "character.book.closed")
                    }
                    Button {
                        applyTextPreset(encoding: .big5950, bigFont: .big5, resetAutoDetectScore: true)
                        showTextEncodingDialog = false
                    } label: {
                        Label("Big5", systemImage: "textformat.alt")
                    }
                    Button {
                        applyTextPreset(encoding: .utf8, bigFont: .auto, resetAutoDetectScore: true)
                        showTextEncodingDialog = false
                    } label: {
                        Label("UTF-8", systemImage: "curlybraces")
                    }
                    Text("如果仍有乱码，导出诊断日志并带上样式/字体信息。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("文字编码") {
                    Picker("编码", selection: $selectedTextEncoding) {
                        ForEach(CADDrawingTextEncoding.allCases, id: \.self) { encoding in
                            Text(encoding.displayName).tag(encoding)
                        }
                    }
                    Text("用于解决整张图纸的中文解码问题，设置会保存到当前图纸。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("SHX / 大字体") {
                    Picker("字体映射", selection: $selectedTextBigFont) {
                        ForEach(CADDrawingTextBigFont.allCases, id: \.self) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    Text("当 SHX 字体或大字体导致中文、符号显示异常时，切换这里会立即重载当前预览，并跟随这张图纸记忆。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("文字编码与字体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showTextEncodingDialog = false
                    }
                }
            }
            .onChange(of: selectedTextEncoding) { _, encoding in
                applyTextEncoding(encoding)
            }
            .onChange(of: selectedTextBigFont) { _, profile in
                applyTextBigFont(profile)
            }
        }
    }

    func applyTextEncoding(_ encoding: CADDrawingTextEncoding) {
        if activeRequest.textEncoding != encoding {
            activeRequest.onTextEncodingChange(activeRequest.drawingID, encoding)
            activeRequest = updatingActiveRequest(textEncoding: encoding)
        }
        updateTextSchemeSnapshot { snapshot in
            snapshot.codePage = encoding.codePageOverride
        }
        reloadCurrentCADPreview()
    }

    func applyTextBigFont(_ profile: CADDrawingTextBigFont) {
        if activeRequest.textBigFont != profile {
            activeRequest.onTextBigFontChange(activeRequest.drawingID, profile)
            activeRequest = updatingActiveRequest(textBigFont: profile)
        }
        updateTextSchemeSnapshot { snapshot in
            snapshot.bigFont = profile.bridgeCode
        }
        reloadCurrentCADPreview()
    }

    func applyTextPreset(
        encoding: CADDrawingTextEncoding,
        bigFont: CADDrawingTextBigFont,
        resetAutoDetectScore: Bool = false
    ) {
        selectedTextEncoding = encoding
        selectedTextBigFont = bigFont
        applyTextEncoding(encoding)
        applyTextBigFont(bigFont)
        if resetAutoDetectScore {
            updateTextSchemeSnapshot { snapshot in
                snapshot.styleName = nil
                snapshot.fontFile = nil
                snapshot.bigFontFile = nil
                snapshot.autoDetectScore = nil
                snapshot.styleSummary = nil
                snapshot.rawTextBytesHexSample = nil
                snapshot.detectionSummary = nil
            }
        }
    }

    func updateTextSchemeSnapshot(
        _ mutation: (inout CADDrawingTextSchemeSnapshot) -> Void
    ) {
        var next = textSchemeSnapshot
        mutation(&next)
        guard next != textSchemeSnapshot else { return }
        textSchemeSnapshot = next
        activeRequest.onTextSchemeSnapshotChange(activeRequest.drawingID, next)
        activeRequest = updatingActiveRequest(textSchemeSnapshot: next)
    }

    @MainActor
    func autoDetectTextOptions() async {
        guard !isAutoDetectingText else { return }
        isAutoDetectingText = true
        defer { isAutoDetectingText = false }

        do {
            guard let result = try await CADRendererProvider.detectLibreDWGTextOptions(for: activeRequest.fileURL) else {
                alertMessage = String(localized: "当前构建没有可用的 LibreDWG 文字自动识别器。")
                showAlert = true
                return
            }
            let encoding = textEncoding(forCodePage: result.codePage) ?? .auto
            let bigFont = textBigFont(forBridgeCode: result.bigFont) ?? .auto
            let snapshot = CADDrawingTextSchemeSnapshot(
                codePage: result.codePage,
                bigFont: result.bigFont,
                styleName: result.styleName,
                fontFile: result.fontFile,
                bigFontFile: result.bigFontFile,
                autoDetectScore: result.autoDetectScore,
                styleSummary: result.styleSummary,
                rawTextBytesHexSample: result.rawTextBytesHexSample,
                detectionSummary: result.detectionSummary ?? result.summary
            )
            applyDetectedTextOptions(encoding: encoding, bigFont: bigFont, snapshot: snapshot)
            alertMessage = "\(String(localized: "已应用自动识别结果"))：\(encoding.displayName) / \(bigFont.displayName)\n\(result.summary)"
            showAlert = true
            showTextEncodingDialog = false
        } catch {
            alertMessage = "\(String(localized: "文字自动识别失败"))：\(error.localizedDescription)"
            showAlert = true
        }
    }

    @MainActor
    func applyDetectedTextOptions(
        encoding: CADDrawingTextEncoding,
        bigFont: CADDrawingTextBigFont,
        snapshot: CADDrawingTextSchemeSnapshot
    ) {
        selectedTextEncoding = encoding
        selectedTextBigFont = bigFont
        textSchemeSnapshot = snapshot
        activeRequest = updatingActiveRequest(
            textEncoding: encoding,
            textBigFont: bigFont,
            textSchemeSnapshot: snapshot
        )
        persistDetectedTextOptionsToDrawing(
            encoding: encoding,
            bigFont: bigFont,
            snapshot: snapshot
        )
        reloadCurrentCADPreview()
    }

    @MainActor
    func applyPreviewAutoDetectedTextOptions(snapshot: CADDrawingTextSchemeSnapshot) {
        let encoding = textEncoding(forCodePage: snapshot.codePage) ?? .auto
        let bigFont = textBigFont(forBridgeCode: snapshot.bigFont) ?? .auto
        let didChangeEncoding = activeRequest.textEncoding != encoding
        let didChangeBigFont = activeRequest.textBigFont != bigFont
        let didChangeSnapshot = activeRequest.textSchemeSnapshot != snapshot
        guard didChangeEncoding || didChangeBigFont || didChangeSnapshot else { return }

        selectedTextEncoding = encoding
        selectedTextBigFont = bigFont
        textSchemeSnapshot = snapshot
        activeRequest = updatingActiveRequest(
            textEncoding: encoding,
            textBigFont: bigFont,
            textSchemeSnapshot: snapshot
        )
        persistDetectedTextOptionsToDrawing(
            encoding: encoding,
            bigFont: bigFont,
            snapshot: snapshot
        )
        if didChangeEncoding || didChangeBigFont {
            reloadCurrentCADPreview()
        }
    }

    @MainActor
    func persistDetectedTextOptionsToDrawing(
        encoding: CADDrawingTextEncoding,
        bigFont: CADDrawingTextBigFont,
        snapshot: CADDrawingTextSchemeSnapshot
    ) {
        if let index = store.projectDrawings.firstIndex(where: { $0.id == activeRequest.drawingID }) {
            store.projectDrawings[index].textEncoding = encoding
            store.projectDrawings[index].textBigFont = bigFont
            store.projectDrawings[index].textSchemeSnapshot = snapshot
            store.scheduleSave()
        } else {
            activeRequest.onTextEncodingChange(activeRequest.drawingID, encoding)
            activeRequest.onTextBigFontChange(activeRequest.drawingID, bigFont)
            activeRequest.onTextSchemeSnapshotChange(activeRequest.drawingID, snapshot)
        }
    }

    func textEncoding(forCodePage codePage: Int32?) -> CADDrawingTextEncoding? {
        guard let codePage else { return nil }
        return CADDrawingTextEncoding.allCases.first { $0.codePageOverride == codePage }
    }

    func codePageDisplayName(_ codePage: Int32) -> String {
        switch codePage {
        case 936:
            return "GBK 936"
        case 54936:
            return "GB18030 54936"
        case 950:
            return "Big5 950"
        case 932:
            return "Shift-JIS 932"
        case 949:
            return "Korean 949"
        case 65001:
            return "UTF-8"
        default:
            return "CP\(Int(codePage))"
        }
    }

    func textBigFont(forBridgeCode bridgeCode: Int32?) -> CADDrawingTextBigFont? {
        guard let bridgeCode else { return nil }
        return CADDrawingTextBigFont.allCases.first { $0.bridgeCode == bridgeCode }
    }

    func updatingActiveRequest(
        textEncoding: CADDrawingTextEncoding? = nil,
        textBigFont: CADDrawingTextBigFont? = nil,
        textSchemeSnapshot: CADDrawingTextSchemeSnapshot? = nil
    ) -> ProjectCADPreviewRequest {
        ProjectCADPreviewRequest(
            projectId: activeRequest.projectId,
            drawingID: activeRequest.drawingID,
            fileURL: activeRequest.fileURL,
            displayName: activeRequest.displayName,
            fileType: activeRequest.fileType,
            textEncoding: textEncoding ?? activeRequest.textEncoding,
            textBigFont: textBigFont ?? activeRequest.textBigFont,
            textSchemeSnapshot: textSchemeSnapshot ?? activeRequest.textSchemeSnapshot,
            overlaySnapshotData: activeRequest.overlaySnapshotData,
            onOverlaySnapshotChange: activeRequest.onOverlaySnapshotChange,
            onTextEncodingChange: activeRequest.onTextEncodingChange,
            onTextBigFontChange: activeRequest.onTextBigFontChange,
            onTextSchemeSnapshotChange: activeRequest.onTextSchemeSnapshotChange
        )
    }

    func reloadCurrentCADPreview() {
        clearInProgress()
        if tool.requiresDrawingCoordinateCapture {
            tool = .browse
        }
        nativeCanvasTransform = nil
        nativeSnapPoints.removeAll()
        nativeEndpointSnapPoints.removeAll()
        nativeMidpointSnapPoints.removeAll()
        nativeCenterSnapPoints.removeAll()
        nativeSnapSourcePoints.removeAll()
        cadPreviewReloadToken = UUID()
    }
}
