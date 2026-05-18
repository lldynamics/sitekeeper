import SwiftUI
import UniformTypeIdentifiers

struct CADTextOptionsPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    var hasFontResolutionFeedback: Bool {
        let matched = textSchemeSnapshot.matchedFontSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let unresolved = textSchemeSnapshot.unresolvedFontSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !matched.isEmpty || !unresolved.isEmpty
    }

    var hasUnresolvedFontDiagnosticIssue: Bool {
        !(textSchemeSnapshot.unresolvedFontSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSuspiciousTextDiagnosticIssue: Bool {
        let searchable = [
            textSchemeSnapshot.detectionSummary,
            textSchemeSnapshot.fontResolutionSummary
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
        guard !searchable.isEmpty else { return false }
        return searchable.localizedStandardContains("疑似") ||
            searchable.localizedStandardContains("乱码") ||
            searchable.localizedStandardContains("未匹配")
    }

    var projectFontMappingRows: [CADProjectFontMapping] {
        activeRequest.projectFontMappings.sorted { lhs, rhs in
            if lhs.source.rawValue == rhs.source.rawValue {
                return lhs.pattern.localizedStandardCompare(rhs.pattern) == .orderedAscending
            }
            return lhs.source.rawValue < rhs.source.rawValue
        }
    }

    var projectFontMappingTargetOptions: [CADDrawingTextBigFont] {
        [.gbcbig, .hztxt, .hzfs, .big5]
    }

    var shouldShowProjectFontMappingSection: Bool {
        currentProjectFontMappingCandidate != nil || !projectFontMappingRows.isEmpty
    }

    var currentProjectFontMappingCandidate: (source: CADProjectFontMappingSource, pattern: String)? {
        let candidates: [(CADProjectFontMappingSource, String?)] = [
            (.bigFontFile, textSchemeSnapshot.bigFontFile),
            (.fontFile, textSchemeSnapshot.fontFile),
            (.styleName, textSchemeSnapshot.styleName),
        ]
        for candidate in candidates {
            let pattern = candidate.1?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !pattern.isEmpty {
                return (candidate.0, pattern)
            }
        }
        return nil
    }

    var textRepairStatusTitle: String {
        if hasUnresolvedFontDiagnosticIssue {
            return String(localized: "发现未匹配字体")
        }
        if hasSuspiciousTextDiagnosticIssue {
            return String(localized: "发现疑似乱码")
        }
        if textSchemeSnapshot.autoDetectScore != nil {
            return String(localized: "已应用自动识别")
        }
        return String(localized: "未发现明显文字问题")
    }

    var textRepairStatusIcon: String {
        if hasUnresolvedFontDiagnosticIssue || hasSuspiciousTextDiagnosticIssue {
            return "exclamationmark.triangle"
        }
        if textSchemeSnapshot.autoDetectScore != nil {
            return "checkmark.seal"
        }
        return "text.viewfinder"
    }

    var textRepairStatusTint: Color {
        if hasUnresolvedFontDiagnosticIssue || hasSuspiciousTextDiagnosticIssue {
            return Color.appWarning
        }
        if textSchemeSnapshot.autoDetectScore != nil {
            return Color.appSuccess
        }
        return .secondary
    }

    var textRepairGuidance: String {
        if hasUnresolvedFontDiagnosticIssue {
            return String(localized: "检测到未匹配的 SHX/大字体。先自动修复；仍乱码时，把当前缺失字体保存为本项目替代表。")
        }
        if hasSuspiciousTextDiagnosticIssue {
            return String(localized: "优先使用自动修复中文；如果仍乱码，再切换为中文通用方案。")
        }
        return String(localized: "优先修复 DWG 编码和 SHX/大字体；显示字体可切换为仿宋、宋体或导入 TTF/OTF/TTC。")
    }

    var recommendedChineseTextRepairTitle: String {
        let preset = recommendedChineseTextRepairPreset()
        return "\(preset.encoding.displayName) / \(preset.bigFont.displayName)"
    }

    var selectedCADDisplayFont: CADDrawingTextDisplayFont {
        CADDrawingTextDisplayFont(rawValue: cadTextDisplayFontRaw) ?? .auto
    }

    var currentCADDisplayFontStatus: String {
        let choice = selectedCADDisplayFont
        if choice == .auto {
            return "自动"
        }
        if choice == .system {
            return "系统默认"
        }
        let resolved = CADImportedFontRegistry.resolvedDisplayFontName(
            for: choice,
            importedFontName: cadImportedTextFontName,
            importedFontPath: cadImportedTextFontPath
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !resolved.isEmpty {
            return resolved
        }
        if choice == .imported {
            return "未导入字体"
        }
        return "未找到可用的\(choice.displayName)，会回到自动字体"
    }

    var cadDisplayFontImportTypes: [UTType] {
        [
            UTType(filenameExtension: "ttf"),
            UTType(filenameExtension: "otf"),
            UTType(filenameExtension: "ttc")
        ].compactMap { $0 }
    }

    var textOptionsSheet: some View {
        NavigationStack {
            Form {
                Section("文字修复") {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(textRepairStatusTitle)
                                .font(.subheadline.weight(.semibold))
                            Text("当前：\(currentTextSchemeTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: textRepairStatusIcon)
                            .foregroundStyle(textRepairStatusTint)
                    }

                    Text(textRepairGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("推荐操作") {
                    Button {
                        Task {
                            await autoDetectTextOptions()
                        }
                    } label: {
                        Label(
                            isAutoDetectingText ? "正在自动修复…" : "自动修复中文",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isAutoDetectingText || !canUseCADTextRepair)

                    Button {
                        applyRecommendedChineseTextRepair()
                        showTextEncodingDialog = false
                    } label: {
                        Label("推荐中文组合", systemImage: "character.book.closed")
                    }
                    .disabled(!canUseCADTextRepair)

                    Text("推荐：\(recommendedChineseTextRepairTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        applyTextPreset(encoding: .auto, bigFont: .auto, resetAutoDetectScore: true)
                        showTextEncodingDialog = false
                    } label: {
                        Label("恢复自动识别", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!canUseCADTextRepair)
                }

                Section("文字显示字体") {
                    Picker("显示字体", selection: $cadTextDisplayFontRaw) {
                        ForEach(CADDrawingTextDisplayFont.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .disabled(!canUseCADTextRepair)
                    .onChange(of: cadTextDisplayFontRaw) { _, _ in
                        reloadCurrentCADPreview()
                    }

                    LabeledContent("当前字体") {
                        Text(currentCADDisplayFontStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Button {
                            applyCADDisplayFont(.fangSong)
                        } label: {
                            Label("试用仿宋", systemImage: "textformat")
                        }
                        .disabled(!canUseCADTextRepair)

                        Spacer()

                        Button {
                            showCADDisplayFontImporter = true
                        } label: {
                            Label("导入字体", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!canUseCADTextRepair)
                    }

                    Text("这里控制已解码文字的显示字体；SHX/BigFont 解码仍由上方编码和大字体方案决定。SHX 文件不能当作系统字体直接导入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if hasFontResolutionFeedback {
                    Section("字体状态") {
                        fontResolutionFeedbackView
                    }
                }

                if shouldShowProjectFontMappingSection {
                    Section("字体替代表") {
                        if let candidate = currentProjectFontMappingCandidate {
                            LabeledContent("图纸字体") {
                                Text(candidate.pattern)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            Picker("替代表", selection: $projectFontMappingBigFont) {
                                ForEach(projectFontMappingTargetOptions, id: \.self) { profile in
                                    Text(profile.displayName).tag(profile)
                                }
                            }
                            Button {
                                saveProjectFontMappingCandidate(candidate)
                            } label: {
                                Label("保存当前字体替代", systemImage: "tray.and.arrow.down")
                            }
                            .disabled(!canUseCADTextRepair)
                        } else {
                            Text("检测到未匹配 SHX/大字体时，这里会出现可保存的项目替代表。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(projectFontMappingRows) { mapping in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mapping.pattern)
                                    .font(.subheadline.weight(.semibold))
                                    .textSelection(.enabled)
                                Text(projectFontMappingDescription(mapping))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: deleteProjectFontMappings)

                        Text("替代表只保存到项目数据，用来辅助 DWG 文字解析，不会修改 CAD 原文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("文字修复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showTextEncodingDialog = false
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showCADDisplayFontImporter,
            allowedContentTypes: cadDisplayFontImportTypes,
            allowsMultipleSelection: false
        ) { result in
            handleCADDisplayFontImport(result)
        }
    }

    @ViewBuilder
    var fontResolutionFeedbackView: some View {
        if let matchedFontSummary = textSchemeSnapshot.matchedFontSummary, !matchedFontSummary.isEmpty {
            Label {
                Text(matchedFontSummary)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(Color.appSuccess)
            }
        }
        if let unresolvedFontSummary = textSchemeSnapshot.unresolvedFontSummary, !unresolvedFontSummary.isEmpty {
            Label {
                Text(unresolvedFontSummary)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.appWarning)
            }
            Text("如果自动修复后仍乱码，可在“字体替代表”保存当前缺失字体到项目数据。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func applyRecommendedChineseTextRepair() {
        let preset = recommendedChineseTextRepairPreset()
        applyTextPreset(
            encoding: preset.encoding,
            bigFont: preset.bigFont,
            resetAutoDetectScore: true
        )
        alertMessage = String(
            format: String(localized: "已切换为 %@ / %@。%@"),
            preset.encoding.displayName,
            preset.bigFont.displayName,
            preset.reason
        )
        showAlert = true
    }

    func applyCADDisplayFont(_ font: CADDrawingTextDisplayFont) {
        let didChange = cadTextDisplayFontRaw != font.rawValue
        cadTextDisplayFontRaw = font.rawValue
        if font == .fangSong,
           CADImportedFontRegistry.resolvedDisplayFontName(
            for: .fangSong,
            importedFontName: cadImportedTextFontName,
            importedFontPath: cadImportedTextFontPath
           ) == nil {
            alertMessage = String(localized: "当前系统没有可用仿宋字体。可导入 TTF/OTF/TTC 字体后再切换为“导入字体”。")
            showAlert = true
        }
        if !didChange {
            reloadCurrentCADPreview()
        }
    }

    func handleCADDisplayFontImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            do {
                guard let url = urls.first else {
                    return
                }
                let font = try CADImportedFontRegistry.importFont(from: url)
                cadImportedTextFontName = font.fontName
                cadImportedTextFontPath = font.filePath
                cadTextDisplayFontRaw = CADDrawingTextDisplayFont.imported.rawValue
                reloadCurrentCADPreview()
                alertMessage = String(localized: "字体已导入并应用：\(font.fontName)")
                showAlert = true
            } catch {
                alertMessage = cadFontImportErrorMessage(
                    prefix: String(localized: "字体导入失败"),
                    error: error
                )
                showAlert = true
            }
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                alertMessage = cadFontImportErrorMessage(
                    prefix: String(localized: "字体导入失败"),
                    error: error
                )
                showAlert = true
            }
        }
    }

    func cadFontImportErrorMessage(prefix: String, error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? prefix : "\(prefix)：\(message)"
    }

    func recommendedChineseTextRepairPreset(
        codePage: Int32? = nil,
        bigFont bridgeCode: Int32? = nil,
        styleName: String? = nil,
        fontFile: String? = nil,
        bigFontFile: String? = nil,
        unresolvedSummary: String? = nil
    ) -> (encoding: CADDrawingTextEncoding, bigFont: CADDrawingTextBigFont, reason: String) {
        let encoding = preferredChineseRepairEncoding(codePage: codePage)
        if let detectedBigFont = nonAutoTextBigFont(forBridgeCode: bridgeCode) {
            return (encoding, detectedBigFont, String(localized: "使用识别到的大字体方案。"))
        }

        let hints = [
            bigFontFile,
            fontFile,
            styleName,
            unresolvedSummary,
            textSchemeSnapshot.bigFontFile,
            textSchemeSnapshot.fontFile,
            textSchemeSnapshot.styleName,
            textSchemeSnapshot.unresolvedFontSummary,
            textSchemeSnapshot.fontResolutionSummary
        ]
        if let inferred = inferredTextBigFont(from: hints) {
            return (encoding, inferred, String(localized: "已根据图纸字体名推断大字体。"))
        }

        if encoding == .big5950 {
            return (encoding, .big5, String(localized: "按繁体中文 DWG 常见方案处理。"))
        }
        return (encoding, .gbcbig, String(localized: "按简体中文 DWG 常见方案处理。"))
    }

    func preferredChineseRepairEncoding(codePage: Int32?) -> CADDrawingTextEncoding {
        if let codePage,
           let encoding = textEncoding(forCodePage: codePage),
           encoding != .auto {
            return encoding
        }
        switch selectedTextEncoding {
        case .gbk936, .gb18030, .big5950:
            return selectedTextEncoding
        case .auto:
            return .gb18030
        }
    }

    func nonAutoTextBigFont(forBridgeCode bridgeCode: Int32?) -> CADDrawingTextBigFont? {
        guard let profile = textBigFont(forBridgeCode: bridgeCode), profile != .auto else {
            return nil
        }
        return profile
    }

    func inferredTextBigFont(from hints: [String?]) -> CADDrawingTextBigFont? {
        for hint in hints {
            let value = hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { continue }
            let inferred = CADDrawingTextBigFont.inferredFromFontName(value)
            if inferred != .auto {
                return inferred
            }
        }
        return nil
    }

    func saveProjectFontMappingCandidate(_ candidate: (source: CADProjectFontMappingSource, pattern: String)) {
        let pattern = candidate.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, projectFontMappingBigFont.bridgeCode != nil else { return }
        let mapping = CADProjectFontMapping(
            source: candidate.source,
            pattern: pattern,
            bigFont: projectFontMappingBigFont
        )
        var mappings = activeRequest.projectFontMappings
        if let index = mappings.firstIndex(where: { $0.deduplicationKey == mapping.deduplicationKey }) {
            mappings[index].pattern = mapping.pattern
            mappings[index].bigFont = mapping.bigFont
        } else {
            mappings.append(mapping)
        }
        persistProjectFontMappings(mappings, reloadPreview: true)
        alertMessage = String(localized: "已保存到本项目字体替代表，并按新映射重载图纸。")
        showAlert = true
    }

    func projectFontMappingDescription(_ mapping: CADProjectFontMapping) -> String {
        "\(mapping.source.displayName) -> \(mapping.bigFont.displayName)"
    }

    func deleteProjectFontMappings(at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            projectFontMappingRows.indices.contains(index) ? projectFontMappingRows[index].id : nil
        }
        guard !ids.isEmpty else { return }
        let next = activeRequest.projectFontMappings.filter { !ids.contains($0.id) }
        persistProjectFontMappings(next, reloadPreview: true)
    }

    func persistProjectFontMappings(
        _ mappings: [CADProjectFontMapping],
        reloadPreview: Bool
    ) {
        activeRequest.onProjectFontMappingsChange(activeRequest.projectId, mappings)
        activeRequest = updatingActiveRequest(projectFontMappings: mappings)
        if reloadPreview {
            reloadCurrentCADPreview()
        }
    }

    func applyTextPreset(
        encoding: CADDrawingTextEncoding,
        bigFont: CADDrawingTextBigFont,
        resetAutoDetectScore: Bool = false
    ) {
        isApplyingTextPreset = true
        defer {
            DispatchQueue.main.async {
                isApplyingTextPreset = false
            }
        }
        selectedTextEncoding = encoding
        selectedTextBigFont = bigFont
        var nextSnapshot = textSchemeSnapshot
        nextSnapshot.codePage = encoding.codePageOverride
        nextSnapshot.bigFont = bigFont.bridgeCode
        if resetAutoDetectScore {
            nextSnapshot.styleName = nil
            nextSnapshot.fontFile = nil
            nextSnapshot.bigFontFile = nil
            nextSnapshot.autoDetectScore = nil
            nextSnapshot.styleSummary = nil
            nextSnapshot.matchedFontSummary = nil
            nextSnapshot.unresolvedFontSummary = nil
            nextSnapshot.fontResolutionSummary = nil
            nextSnapshot.rawTextBytesHexSample = nil
            nextSnapshot.detectionSummary = nil
        }
        activeRequest = updatingActiveRequest(
            textEncoding: encoding,
            textBigFont: bigFont,
            textSchemeSnapshot: nextSnapshot
        )
        selectedTextEncoding = encoding
        selectedTextBigFont = bigFont
        textSchemeSnapshot = nextSnapshot
        persistDetectedTextOptionsToDrawing(
            encoding: encoding,
            bigFont: bigFont,
            snapshot: nextSnapshot
        )
        reloadCurrentCADPreview()
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
            guard let result = try await CADRendererProvider.detectTextOptions(
                for: activeRequest.fileURL,
                fontMappings: activeRequest.rendererFontMappings
            ) else {
                alertMessage = String(localized: "当前自有 CAD 内核还没有接入文字自动识别引擎。")
                showAlert = true
                return
            }
            let fallback = recommendedChineseTextRepairPreset(
                codePage: result.codePage,
                bigFont: result.bigFont,
                styleName: result.styleName,
                fontFile: result.fontFile,
                bigFontFile: result.bigFontFile,
                unresolvedSummary: result.unresolvedFontSummary
            )
            let encoding = textEncoding(forCodePage: result.codePage) ?? fallback.encoding
            let bigFont = nonAutoTextBigFont(forBridgeCode: result.bigFont) ?? fallback.bigFont
            let snapshot = CADDrawingTextSchemeSnapshot(
                codePage: encoding.codePageOverride ?? result.codePage,
                bigFont: bigFont.bridgeCode ?? result.bigFont,
                styleName: result.styleName,
                fontFile: result.fontFile,
                bigFontFile: result.bigFontFile,
                autoDetectScore: result.autoDetectScore,
                styleSummary: result.styleSummary,
                matchedFontSummary: result.matchedFontSummary,
                unresolvedFontSummary: result.unresolvedFontSummary,
                fontResolutionSummary: result.fontResolutionSummary,
                rawTextBytesHexSample: result.rawTextBytesHexSample,
                detectionSummary: result.detectionSummary ?? result.summary
            )
            applyDetectedTextOptions(encoding: encoding, bigFont: bigFont, snapshot: snapshot)
            alertMessage = "\(String(localized: "已应用自动修复结果"))：\(encoding.displayName) / \(bigFont.displayName)\n\(fallback.reason)\n\(result.summary)"
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
        let fallback = recommendedChineseTextRepairPreset(
            codePage: snapshot.codePage,
            bigFont: snapshot.bigFont,
            styleName: snapshot.styleName,
            fontFile: snapshot.fontFile,
            bigFontFile: snapshot.bigFontFile,
            unresolvedSummary: snapshot.unresolvedFontSummary
        )
        let encoding = textEncoding(forCodePage: snapshot.codePage) ?? fallback.encoding
        let bigFont = nonAutoTextBigFont(forBridgeCode: snapshot.bigFont) ?? fallback.bigFont
        var normalizedSnapshot = snapshot
        normalizedSnapshot.codePage = encoding.codePageOverride ?? snapshot.codePage
        normalizedSnapshot.bigFont = bigFont.bridgeCode ?? snapshot.bigFont
        let didChangeEncoding = activeRequest.textEncoding != encoding
        let didChangeBigFont = activeRequest.textBigFont != bigFont
        let didChangeSnapshot = activeRequest.textSchemeSnapshot != normalizedSnapshot
        guard didChangeEncoding || didChangeBigFont || didChangeSnapshot else { return }

        selectedTextEncoding = encoding
        selectedTextBigFont = bigFont
        textSchemeSnapshot = normalizedSnapshot
        activeRequest = updatingActiveRequest(
            textEncoding: encoding,
            textBigFont: bigFont,
            textSchemeSnapshot: normalizedSnapshot
        )
        persistDetectedTextOptionsToDrawing(
            encoding: encoding,
            bigFont: bigFont,
            snapshot: normalizedSnapshot
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
        activeRequest.onTextEncodingChange(activeRequest.drawingID, encoding)
        activeRequest.onTextBigFontChange(activeRequest.drawingID, bigFont)
        activeRequest.onTextSchemeSnapshotChange(activeRequest.drawingID, snapshot)
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
        textSchemeSnapshot: CADDrawingTextSchemeSnapshot? = nil,
        cadViewState: CADDrawingViewState? = nil,
        projectFontMappings: [CADProjectFontMapping]? = nil
    ) -> ProjectCADPreviewRequest {
        ProjectCADPreviewRequest(
            projectId: activeRequest.projectId,
            drawingID: activeRequest.drawingID,
            fileURL: activeRequest.fileURL,
            displayName: activeRequest.displayName,
            fileType: activeRequest.fileType,
            importedAt: activeRequest.importedAt,
            fileSizeBytes: activeRequest.fileSizeBytes,
            textEncoding: textEncoding ?? activeRequest.textEncoding,
            textBigFont: textBigFont ?? activeRequest.textBigFont,
            textSchemeSnapshot: textSchemeSnapshot ?? activeRequest.textSchemeSnapshot,
            cadViewState: cadViewState ?? activeRequest.cadViewState,
            projectFontMappings: projectFontMappings ?? activeRequest.projectFontMappings,
            overlaySnapshotData: activeRequest.overlaySnapshotData,
            onOverlaySnapshotChange: activeRequest.onOverlaySnapshotChange,
            onViewStateChange: activeRequest.onViewStateChange,
            onTextEncodingChange: activeRequest.onTextEncodingChange,
            onTextBigFontChange: activeRequest.onTextBigFontChange,
            onTextSchemeSnapshotChange: activeRequest.onTextSchemeSnapshotChange,
            onProjectFontMappingsChange: activeRequest.onProjectFontMappingsChange
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
        cadOpenQuality = nil
        cadPreviewReloadToken = UUID()
    }
}
