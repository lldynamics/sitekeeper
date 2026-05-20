import SwiftUI

extension CADPreviewContainer {
    private var diagnosticExporterPresented: Binding<Bool> {
        Binding(
            get: { diagnosticExportPayload != nil },
            set: { isPresented in
                if !isPresented {
                    diagnosticExportPayload = nil
                }
            }
        )
    }

    private var annotationExporterPresented: Binding<Bool> {
        Binding(
            get: { annotationExportPayload != nil },
            set: { isPresented in
                if !isPresented {
                    annotationExportPayload = nil
                }
            }
        )
    }

    private var fallbackScreenshotExporterPresented: Binding<Bool> {
        Binding(
            get: { fallbackScreenshotPayload != nil },
            set: { isPresented in
                if !isPresented {
                    fallbackScreenshotPayload = nil
                }
            }
        )
    }

    func applyPresentationModifiers<Content: View>(to content: Content) -> some View {
        content
            .confirmationDialog(String(localized: "清空批注和测量？"), isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(String(localized: "清空全部"), role: .destructive) {
                    recordUndoSnapshot()
                    var cleared = CADOverlaySnapshot()
                    cleared.metersPerDrawingUnit = snapshot.metersPerDrawingUnit
                    copyOverlayDisplayPreferences(from: snapshot, to: &cleared)
                    snapshot = cleared
                    quantityHighlightTarget = nil
                    clearInProgress()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "将删除本图纸的批注、测量和算量数据。"))
            }
            .confirmationDialog(String(localized: "导出批注测量"), isPresented: $showAnnotationExportFormatDialog, titleVisibility: .visible) {
                Button(CADAnnotationExportFormat.csv.title) {
                    exportAnnotationSummary(format: .csv)
                }
                Button(CADAnnotationExportFormat.pdf.title) {
                    exportAnnotationSummary(format: .pdf)
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "可导出为 CSV 表格或 PDF 报表。"))
            }
            .alert(String(localized: "CAD 提示"), isPresented: $showAlert) {
                Button(String(localized: "知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showTextEncodingDialog) {
                CADTextOptionsPanel {
                    textOptionsSheet
                }
            }
            .sheet(isPresented: $showScaleSheet) {
                CADMeasurementPanel {
                    scaleEditor
                }
            }
            .sheet(isPresented: $showOverlayLayerSheet) {
                overlayLayerEditor
            }
            .sheet(isPresented: $showQuantitySheet) {
                CADMeasurementPanel {
                    quantitySheet
                }
            }
            .sheet(isPresented: $showNoteSheet) {
                noteEditorSheet
            }
            .sheet(isPresented: $showIssuePhotoCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    appendIssueMarker(photo: image)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityShareSheet(activityItems: [activeRequest.fileURL])
            }
            .fileExporter(
                isPresented: diagnosticExporterPresented,
                document: ExportDocument(
                    data: diagnosticExportPayload?.data ?? Data(),
                    sourceFileURL: diagnosticExportPayload?.sourceFileURL
                ),
                contentType: diagnosticExportPayload?.contentType ?? .zipArchive,
                defaultFilename: diagnosticExportPayload?.defaultFilename ?? "CAD诊断包.zip"
            ) { result in
                handleDiagnosticExportResult(result)
            }
            .fileExporter(
                isPresented: annotationExporterPresented,
                document: ExportDocument(data: annotationExportPayload?.data ?? Data()),
                contentType: annotationExportPayload?.contentType ?? .commaSeparatedText,
                defaultFilename: annotationExportPayload?.defaultFilename ?? "CAD批注测量.csv"
            ) { result in
                handleAnnotationExportResult(result)
            }
            .fileExporter(
                isPresented: fallbackScreenshotExporterPresented,
                document: ExportDocument(data: fallbackScreenshotPayload?.data ?? Data()),
                contentType: fallbackScreenshotPayload?.contentType ?? .png,
                defaultFilename: fallbackScreenshotPayload?.defaultFilename ?? "CAD兼容预览反馈.png"
            ) { result in
                handleFallbackScreenshotExportResult(result)
            }
    }

    private func handleDiagnosticExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            alertMessage = String(localized: "CAD 诊断包已导出。")
            showAlert = true
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                alertMessage = localizedErrorMessage(
                    prefix: String(localized: "CAD 诊断包导出失败"),
                    error: error
                )
                showAlert = true
            }
        }
        diagnosticExportPayload = nil
    }

    private func handleAnnotationExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            alertMessage = String(localized: "CAD 批注测量已导出。")
            showAlert = true
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                alertMessage = localizedErrorMessage(
                    prefix: String(localized: "CAD 批注测量导出失败"),
                    error: error
                )
                showAlert = true
            }
        }
        annotationExportPayload = nil
    }

    private func handleFallbackScreenshotExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            alertMessage = String(localized: "CAD 兼容预览截图已导出。")
            showAlert = true
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                alertMessage = localizedErrorMessage(
                    prefix: String(localized: "CAD 兼容预览截图导出失败"),
                    error: error
                )
                showAlert = true
            }
        }
        fallbackScreenshotPayload = nil
    }

    @MainActor
    func exportDiagnosticLog() async {
        guard !isExportingDiagnosticLog else { return }
        isExportingDiagnosticLog = true
        defer { isExportingDiagnosticLog = false }

        var rendererReport: String?
        var reporterErrorMessage: String?
        do {
            rendererReport = try await CADRendererProvider.makeDiagnosticReport(
                for: activeRequest.fileURL,
                preferredTextCodePage: selectedTextEncoding.codePageOverride,
                preferredTextBigFont: selectedTextBigFont.bridgeCode
            )
        } catch {
            reporterErrorMessage = localizedErrorMessage(
                prefix: String(localized: "CAD 内核诊断生成失败"),
                error: error
            )
            StorageIssueLog.record("CAD 诊断日志生成失败：\(activeRequest.displayName)，\(error.localizedDescription)")
        }

        do {
            let report = fallbackDiagnosticLog(
                extraMessage: reporterErrorMessage,
                rendererReport: rendererReport
            )
            diagnosticExportPayload = try diagnosticPackagePayload(humanReport: report)
        } catch {
            let report = fallbackDiagnosticLog(
                extraMessage: localizedErrorMessage(
                    prefix: String(localized: "CAD 诊断包生成失败"),
                    error: error
                ),
                rendererReport: rendererReport
            )
            StorageIssueLog.record("CAD 诊断包生成失败：\(activeRequest.displayName)，\(error.localizedDescription)")
            diagnosticExportPayload = ExportPayload(
                data: Data(report.utf8),
                contentType: .plainText,
                defaultFilename: diagnosticLogFileName()
            )
        }
    }

    private func diagnosticBaseName() -> String {
        let baseName = activeRequest.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return baseName.isEmpty ? activeRequest.fileURL.deletingPathExtension().lastPathComponent : baseName
    }

    private func diagnosticPackageFileName() -> String {
        "\(diagnosticBaseName())_CAD诊断包.zip"
    }

    private func diagnosticLogFileName() -> String {
        "\(diagnosticBaseName())_CAD诊断日志.txt"
    }

    private func diagnosticReportFileName() -> String {
        "diagnostic_report.txt"
    }

    private func diagnosticMachineTraceFileName() -> String {
        "pipeline_trace.json"
    }

    private func diagnosticPackagePayload(humanReport: String) throws -> ExportPayload {
        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: diagnosticReportFileName(), data: Data(humanReport.utf8))
        zip.addFile(path: diagnosticMachineTraceFileName(), data: try diagnosticMachineTraceData())
        return ExportPayload(
            data: zip.build(),
            contentType: .zipArchive,
            defaultFilename: diagnosticPackageFileName()
        )
    }

    private func fallbackScreenshotFileName() -> String {
        let baseName = activeRequest.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = baseName.isEmpty ? activeRequest.fileURL.deletingPathExtension().lastPathComponent : baseName
        return "\(name)_兼容预览反馈.png"
    }

    private func fallbackDiagnosticLog(extraMessage: String? = nil, rendererReport: String? = nil) -> String {
        var lines: [String] = []
        lines.append(String(localized: "CAD 技术排查报告"))
        lines.append("\(String(localized: "生成时间"))：\(Formatters.dateTime.string(from: Date()))")
        lines.append("")
        lines.append("## \(String(localized: "文件"))")
        lines.append("\(String(localized: "文件名"))：\(activeRequest.fileURL.lastPathComponent)")
        lines.append("\(String(localized: "路径"))：\(activeRequest.fileURL.path)")
        lines.append("\(String(localized: "类型"))：\(activeRequest.fileType.uppercased())")
        lines.append("\(String(localized: "大小"))：\(fallbackFileSizeText())")
        lines.append("\(String(localized: "文件头 Hex"))：\(fallbackHeaderHex())")
        lines.append("\(String(localized: "源文件写入"))：\(String(localized: "否（批注、测量、文字编码和字体设置只保存在应用项目数据中）"))")
        lines.append("\(String(localized: "机器 trace"))：\(diagnosticMachineTraceFileName())")
        lines.append("")
        lines.append("## \(String(localized: "预览环境"))")
        lines.append("\(String(localized: "CAD 看图内核可用"))：\(CADDrawingCapability.isCADEngineInstalled() ? String(localized: "是") : String(localized: "否"))")
        lines.append("\(String(localized: "Renderer 已绑定"))：\(CADRendererProvider.isRendererBound ? String(localized: "是") : String(localized: "否"))")
        lines.append("\(String(localized: "看图模式"))：\(selectedCADViewerMode.title)")
        let pipeline = diagnosticPipeline()
        lines.append("\(String(localized: "结论"))：\(pipeline.conclusion)")
        lines.append("failureLayer：\(pipeline.failureLayer)")
        lines.append("failureStage：\(pipeline.failureStage)")
        if forceFallbackForPerformance {
            lines.append("\(String(localized: "性能降级"))：\(String(localized: "是"))")
            lines.append("\(String(localized: "降级原因"))：\(forceFallbackReason ?? "-")")
        }
        if let performance = lastRendererPerformance {
            lines.append("\(String(localized: "性能采样"))：visible=\(performance.visibleEntityCount), commands=\(performance.renderCommandCount), textCommands=\(performance.textCommandCount), textOverlays=\(performance.textOverlayCount), textSkipped=\(performance.textOverlaySkippedCount), renderMs=\(Int(performance.renderMs))ms, firstFrameMs=\(Int(performance.firstFrameMs))ms, skipped=\(performance.skippedEntityCount), layers=\(performance.visibleLayerCount)")
            lines.append("\(String(localized: "渲染闭环"))：layer=\(performance.rendererFailureLayer), reason=\(performance.rendererFailureReason)")
            lines.append("\(String(localized: "闭环计数"))：import=\(performance.totalEntityCount), indexed=\(performance.indexedEntityCount), viewportBeforeLayer=\(performance.viewportEntityCountBeforeLayerFilter), viewportVisible=\(performance.visibleEntityCount), commands=\(performance.renderCommandCount), vertices=\(performance.vertexCount), text=\(performance.textOverlayCount)/\(performance.textCommandCount), textSkipped=\(performance.textOverlaySkippedCount), layers=\(performance.visibleLayerCount)/\(performance.totalLayerCount)")
            lines.append("\(String(localized: "文字闭环"))：importText=\(performance.totalTextEntityCount), indexedText=\(performance.indexedTextEntityCount), viewportTextBeforeLayer=\(performance.viewportTextEntityCountBeforeLayerFilter), visibleText=\(performance.visibleTextEntityCount), renderInputText=\(performance.renderInputTextEntityCount), textCommands=\(performance.textCommandCount), textAtlas=\(performance.textOverlayCount), textSkipped=\(performance.textOverlaySkippedCount)")
            lines.append("\(String(localized: "闭环状态"))：modelBoundsValid=\(performance.modelBoundsValid), viewportBoundsValid=\(performance.viewportBoundsValid), viewportIntersectsModel=\(performance.viewportIntersectsModel), layerFilterActive=\(performance.layerFilterActive)")
            if performance.textCommandCount > 0 && performance.textOverlayCount == 0 {
                lines.append("\(String(localized: "文字渲染诊断"))：CAD 已生成文字命令，但当前帧没有可见文字贴图；优先检查 viewport、文字坐标、图层和字体栅格化。")
            }
        }
        if shouldUseFallbackViewer {
            let outputs = CADFallbackOutputResolver.resolve(fileURL: activeRequest.fileURL)
            lines.append("\(String(localized: "兼容预览输出"))：\(outputs.summary)")
        }
        lines.append("\(String(localized: "当前文字编码"))：\(selectedTextEncoding.displayName)")
        lines.append("\(String(localized: "当前 SHX/大字体"))：\(selectedTextBigFont.displayName)")
        if !activeRequest.projectFontMappings.isEmpty {
            lines.append("\(String(localized: "本项目字体映射"))：")
            for mapping in projectFontMappingRows.prefix(12) {
                lines.append("- \(mapping.source.displayName)：\(mapping.pattern) -> \(mapping.bigFont.displayName)")
            }
        }
        if let codePage = textSchemeSnapshot.codePage {
            lines.append("\(String(localized: "当前命中编码"))：\(codePageDisplayName(codePage))")
        }
        if let styleName = textSchemeSnapshot.styleName {
            lines.append("\(String(localized: "当前样式"))：\(styleName)")
        }
        if let fontFile = textSchemeSnapshot.fontFile {
            lines.append("\(String(localized: "当前字体"))：\(fontFile)")
        }
        if let bigFontFile = textSchemeSnapshot.bigFontFile {
            lines.append("\(String(localized: "当前大字体文件"))：\(bigFontFile)")
        }
        if let score = textSchemeSnapshot.autoDetectScore {
            lines.append("\(String(localized: "自动识别评分"))：\(score)")
        }
        if let styleSummary = textSchemeSnapshot.styleSummary, !styleSummary.isEmpty {
            lines.append("\(String(localized: "STYLE 表"))：\(styleSummary)")
        }
        if let matchedFontSummary = textSchemeSnapshot.matchedFontSummary, !matchedFontSummary.isEmpty {
            lines.append("\(String(localized: "已匹配字体"))：\(matchedFontSummary)")
        }
        if let unresolvedFontSummary = textSchemeSnapshot.unresolvedFontSummary, !unresolvedFontSummary.isEmpty {
            lines.append("\(String(localized: "未匹配字体"))：\(unresolvedFontSummary)")
        }
        if let fontResolutionSummary = textSchemeSnapshot.fontResolutionSummary, !fontResolutionSummary.isEmpty {
            lines.append("\(String(localized: "字体解析"))：\(fontResolutionSummary)")
        }
        if let rawSample = textSchemeSnapshot.rawTextBytesHexSample, !rawSample.isEmpty {
            lines.append("raw text bytes：\(rawSample)")
        }
        if let summary = textSchemeSnapshot.detectionSummary, !summary.isEmpty {
            lines.append("\(String(localized: "识别摘要"))：\(summary)")
        }
        if let engineStatusHint {
            lines.append("\(String(localized: "提示"))：\(engineStatusHint)")
        }
        if let rendererReport, !rendererReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("## \(String(localized: "内核报告"))")
            lines.append(rendererReport)
        }
        let runtimeLog = NativeCAD.CADDiagnosticLog.recentEntries(limit: 24)
        if !runtimeLog.isEmpty {
            lines.append("")
            lines.append("## CAD runtime log")
            for entry in runtimeLog {
                lines.append("- [\(entry.timestamp)] \(entry.category): \(entry.message)")
                if let payload = entry.payloadJSON, !payload.isEmpty {
                    lines.append("  payload: \(payload)")
                }
            }
        }
        if let extraMessage {
            lines.append("")
            lines.append("## \(String(localized: "诊断生成错误"))")
            lines.append(extraMessage)
        }
        return lines.joined(separator: "\n")
    }

    private func localizedErrorMessage(prefix: String, error: Error) -> String {
        let suffix = error.localizedDescription
        return prefix + "：" + suffix
    }

    private func diagnosticMachineTraceData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(diagnosticMachineTrace())
    }

    private func diagnosticMachineTrace() -> CADDiagnosticMachineTrace {
        let kernelTrace = cadOpenTechnicalDetails?.pipelineTrace
        let nativeTrace = lastCADOpenTrace
        let pipeline = diagnosticPipeline(kernelTrace: kernelTrace, nativeTrace: nativeTrace)
        let counts = diagnosticCounts(kernelTrace: kernelTrace, nativeTrace: nativeTrace)
        let diagnostics = cadOpenTechnicalDetails?.diagnostics ?? []
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

        return CADDiagnosticMachineTrace(
            schemaVersion: 1,
            traceKind: "sitekeeper.cad.open",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            humanReportFile: diagnosticReportFileName(),
            machineTraceFile: diagnosticMachineTraceFileName(),
            file: CADDiagnosticMachineTrace.FileInfo(
                displayName: activeRequest.displayName,
                path: activeRequest.fileURL.path,
                fileType: activeRequest.fileType.uppercased(),
                fileByteCount: diagnosticFileByteCount(),
                headerHex: fallbackHeaderHex(),
                importedAt: activeRequest.importedAt
            ),
            environment: CADDiagnosticMachineTrace.Environment(
                appVersion: appVersion,
                buildNumber: buildNumber,
                cadEngineInstalled: CADDrawingCapability.isCADEngineInstalled(),
                rendererBound: CADRendererProvider.isRendererBound,
                viewerMode: selectedCADViewerMode.rawValue,
                fallbackViewerActive: shouldUseFallbackViewer,
                performanceFallbackActive: forceFallbackForPerformance,
                performanceFallbackReason: forceFallbackReason
            ),
            pipeline: pipeline,
            counts: counts,
            text: CADDiagnosticMachineTrace.TextState(
                selectedEncoding: selectedTextEncoding.rawValue,
                selectedBigFont: selectedTextBigFont.rawValue,
                codePageOverride: selectedTextEncoding.codePageOverride,
                bigFontCode: selectedTextBigFont.bridgeCode,
                detectedCodePage: textSchemeSnapshot.codePage.map(codePageDisplayName),
                detectedStyleName: textSchemeSnapshot.styleName,
                detectedFontFile: textSchemeSnapshot.fontFile,
                detectedBigFontFile: textSchemeSnapshot.bigFontFile,
                autoDetectScore: textSchemeSnapshot.autoDetectScore,
                unresolvedFontSummary: textSchemeSnapshot.unresolvedFontSummary,
                fontResolutionSummary: textSchemeSnapshot.fontResolutionSummary,
                rawTextBytesHexSample: textSchemeSnapshot.rawTextBytesHexSample
            ),
            performance: lastRendererPerformance.map { performance in
                CADDiagnosticMachineTrace.Performance(
                    entityCountInViewport: performance.entityCountInViewport,
                    drawCallCount: performance.drawCallCount,
                    frameTimeMilliseconds: performance.frameTimeMilliseconds,
                    skippedEntityCount: performance.skippedEntityCount,
                    visibleLayerCount: performance.visibleLayerCount,
                    totalLayerCount: performance.totalLayerCount,
                    simplifiedMode: performance.simplifiedMode,
                    renderCommandCount: performance.renderCommandCount,
                    textCommandCount: performance.textCommandCount,
                    textOverlayCount: performance.textOverlayCount,
                    renderMilliseconds: performance.renderMs,
                    firstFrameMilliseconds: performance.firstFrameMs,
                    totalEntityCount: performance.totalEntityCount,
                    indexedEntityCount: performance.indexedEntityCount,
                    viewportEntityCountBeforeLayerFilter: performance.viewportEntityCountBeforeLayerFilter,
                    layerFilterActive: performance.layerFilterActive,
                    modelBounds: CADDiagnosticMachineTrace.Bounds(performance.modelBounds),
                    viewportBounds: CADDiagnosticMachineTrace.Bounds(performance.viewportBounds),
                    modelBoundsValid: performance.modelBoundsValid,
                    viewportBoundsValid: performance.viewportBoundsValid,
                    viewportIntersectsModel: performance.viewportIntersectsModel,
                    vertexCount: performance.vertexCount,
                    totalTextEntityCount: performance.totalTextEntityCount,
                    indexedTextEntityCount: performance.indexedTextEntityCount,
                    viewportTextEntityCountBeforeLayerFilter: performance.viewportTextEntityCountBeforeLayerFilter,
                    visibleTextEntityCount: performance.visibleTextEntityCount,
                    renderInputTextEntityCount: performance.renderInputTextEntityCount,
                    rendererFailureLayer: performance.rendererFailureLayer,
                    rendererFailureReason: performance.rendererFailureReason
                )
            },
            openQuality: cadOpenQuality.map { quality in
                CADDiagnosticMachineTrace.OpenQuality(
                    level: quality.level,
                    title: quality.title,
                    summary: quality.summary,
                    allowsMarkup: quality.allowsMarkup,
                    supportsSearch: quality.supportsSearch,
                    detailLines: quality.detailLines
                )
            },
            kernelTrace: kernelTrace.map(CADDiagnosticMachineTrace.KernelTrace.init),
            nativeTrace: nativeTrace.map(CADDiagnosticMachineTrace.NativeTrace.init),
            diagnostics: diagnostics,
            runtimeLog: NativeCAD.CADDiagnosticLog.recentEntries(limit: 50),
            notes: diagnosticNotes(pipeline: pipeline, diagnostics: diagnostics)
        )
    }

    private func diagnosticPipeline(
        kernelTrace: SiteKeeperCADKernel.DWGOpenPipelineTrace? = nil,
        nativeTrace: NativeCAD.CADOpenTrace? = nil
    ) -> CADDiagnosticMachineTrace.Pipeline {
        if let kernelTrace {
            let failureLayer = diagnosticFailureLayer(kernelTrace)
            if failureLayer == "none", let rendererFailureLayer = diagnosticFailureLayer(lastRendererPerformance) {
                return CADDiagnosticMachineTrace.Pipeline(
                    failureLayer: rendererFailureLayer,
                    failureStage: "renderer_\(rendererFailureLayer)",
                    openState: currentOpenStateRawValue(),
                    importSource: cadOpenTechnicalDetails?.importEngine,
                    conclusion: diagnosticConclusion(for: rendererFailureLayer),
                    traceSource: "renderer_frame_trace"
                )
            }
            return CADDiagnosticMachineTrace.Pipeline(
                failureLayer: failureLayer,
                failureStage: kernelTrace.failureStage,
                openState: kernelTrace.openState.rawValue,
                importSource: cadOpenTechnicalDetails?.importEngine,
                conclusion: diagnosticConclusion(for: failureLayer),
                traceSource: "kernel_pipeline_trace"
            )
        }

        if let nativeTrace {
            let failureLayer = diagnosticFailureLayer(nativeTrace)
            if failureLayer == "none", let rendererFailureLayer = diagnosticFailureLayer(lastRendererPerformance) {
                return CADDiagnosticMachineTrace.Pipeline(
                    failureLayer: rendererFailureLayer,
                    failureStage: "renderer_\(rendererFailureLayer)",
                    openState: nativeTrace.openedForRender ? "rendered" : "unsupported",
                    importSource: nativeTrace.importSource,
                    conclusion: diagnosticConclusion(for: rendererFailureLayer),
                    traceSource: "renderer_frame_trace"
                )
            }
            return CADDiagnosticMachineTrace.Pipeline(
                failureLayer: failureLayer,
                failureStage: nativeTrace.openedForRender ? "rendered" : failureLayer,
                openState: nativeTrace.openedForRender ? "rendered" : "unsupported",
                importSource: nativeTrace.importSource,
                conclusion: diagnosticConclusion(for: failureLayer),
                traceSource: "native_canvas_trace"
            )
        }

        if let rendererFailureLayer = diagnosticFailureLayer(lastRendererPerformance) {
            return CADDiagnosticMachineTrace.Pipeline(
                failureLayer: rendererFailureLayer,
                failureStage: "renderer_\(rendererFailureLayer)",
                openState: currentOpenStateRawValue(),
                importSource: cadOpenTechnicalDetails?.importEngine,
                conclusion: diagnosticConclusion(for: rendererFailureLayer),
                traceSource: "renderer_frame_trace"
            )
        }

        let failureLayer = CADRendererProvider.isRendererBound ? "unknown" : "render"
        return CADDiagnosticMachineTrace.Pipeline(
            failureLayer: failureLayer,
            failureStage: CADRendererProvider.isRendererBound ? "missing_trace" : "renderer_unbound",
            openState: currentOpenStateRawValue(),
            importSource: cadOpenTechnicalDetails?.importEngine,
            conclusion: diagnosticConclusion(for: failureLayer),
            traceSource: "fallback_context"
        )
    }

    private func diagnosticCounts(
        kernelTrace: SiteKeeperCADKernel.DWGOpenPipelineTrace?,
        nativeTrace: NativeCAD.CADOpenTrace?
    ) -> CADDiagnosticMachineTrace.Counts {
        if let kernelTrace {
            return CADDiagnosticMachineTrace.Counts(
                rawEntityCount: max(kernelTrace.jsonRawEntityCount, kernelTrace.dxfRawEntityCount),
                adapterEntityCount: kernelTrace.adapterEntityCount,
                databaseEntityCount: kernelTrace.databaseEntityCount,
                drawableEntityCount: kernelTrace.drawableEntityCount,
                renderCommandCount: kernelTrace.renderCommandCount,
                visibleLayerCount: kernelTrace.visibleLayerCount
            )
        }

        if let nativeTrace {
            let rawCount = CADDiagnosticMachineTrace.NativeTrace(nativeTrace).rawEntityCounts.total
            return CADDiagnosticMachineTrace.Counts(
                rawEntityCount: rawCount,
                adapterEntityCount: nativeTrace.entityCount,
                databaseEntityCount: nativeTrace.entityCount,
                drawableEntityCount: nativeTrace.drawableEntityCount,
                renderCommandCount: nativeTrace.renderCommandCount,
                visibleLayerCount: nativeCADVisibleLayerIDs?.count ?? nativeCADLayers.filter(\.isVisible).count
            )
        }

        return CADDiagnosticMachineTrace.Counts(
            rawEntityCount: 0,
            adapterEntityCount: 0,
            databaseEntityCount: cadOpenTechnicalDetails?.pipelineTrace?.databaseEntityCount ?? 0,
            drawableEntityCount: cadOpenTechnicalDetails?.drawableEntityCount ?? 0,
            renderCommandCount: lastRendererPerformance?.renderCommandCount ?? 0,
            visibleLayerCount: lastRendererPerformance?.visibleLayerCount ?? nativeCADVisibleLayerIDs?.count ?? nativeCADLayers.count
        )
    }

    private func diagnosticFailureLayer(_ trace: SiteKeeperCADKernel.DWGOpenPipelineTrace) -> String {
        if trace.openState == .rendered || trace.failureStage == "rendered" {
            return "none"
        }
        if trace.jsonRawEntityCount == 0,
           trace.dxfRawEntityCount == 0,
           trace.adapterEntityCount == 0,
           trace.databaseEntityCount == 0 {
            return "libredwg"
        }
        if trace.adapterEntityCount == 0 { return "adapter" }
        if trace.drawableEntityCount == 0 { return "database" }
        if trace.renderCommandCount == 0 { return "render" }

        let stage = trace.failureStage.lowercased()
        if stage.contains("libredwg") || stage.contains("geometry_source") || stage.contains("import") {
            return "libredwg"
        }
        if stage.contains("adapter") { return "adapter" }
        if stage.contains("database") || stage.contains("drawable") { return "database" }
        if stage.contains("render") { return "render" }
        return "unknown"
    }

    private func diagnosticFailureLayer(_ trace: NativeCAD.CADOpenTrace) -> String {
        if trace.openedForRender {
            return "none"
        }
        let rawCount = CADDiagnosticMachineTrace.NativeTrace(trace).rawEntityCounts.total
        if rawCount == 0 { return "libredwg" }
        if trace.entityCount == 0 { return "adapter" }
        if trace.drawableEntityCount == 0 { return "database" }
        if trace.renderCommandCount == 0 { return "render" }
        return "unknown"
    }

    private func diagnosticFailureLayer(_ performance: CADRendererPerformanceSnapshot?) -> String? {
        guard let performance, performance.rendererFailureLayer != "none" else {
            return nil
        }
        return performance.rendererFailureLayer
    }

    private func diagnosticConclusion(for failureLayer: String) -> String {
        switch failureLayer {
        case "none":
            return "CAD pipeline reached renderable output."
        case "libredwg":
            return "LibreDWG did not provide drawable geometry."
        case "adapter":
            return "Raw geometry exists but adapter produced no database entities."
        case "database":
            return "Database entities exist but no drawable entities are available."
        case "render":
            return "Drawable entities exist but render commands are unavailable."
        case "import":
            return "Renderer received no imported entities."
        case "bounds":
            return "Entities exist but bounds/indexing are invalid."
        case "layer":
            return "Entities exist but current layer visibility hides them."
        case "viewport":
            return "Entities exist but the current viewport does not hit drawable bounds."
        case "renderCommand":
            return "Visible entities exist but render commands are not produced."
        case "textOverlay":
            return "Text commands exist but text overlays are missing or incomplete."
        case "textBounds":
            return "Text entities exist but their bounds did not enter the spatial index."
        case "textLayer":
            return "Text entities exist in the viewport but current layer visibility hides them."
        case "textRenderCommand":
            return "Text entities exist in the viewport but text render commands are not produced."
        case "metal":
            return "Render commands exist but Metal output has no drawable vertices."
        default:
            return "CAD pipeline failure layer is unknown."
        }
    }

    private func currentOpenStateRawValue() -> String {
        switch cadOpenRoute {
        case .rendered(let result), .unsupported(let result):
            switch result.openState {
            case .rendered:
                return "rendered"
            case .unsupported:
                return "unsupported"
            case .failed:
                return "failed"
            }
        }
    }

    private func diagnosticNotes(pipeline: CADDiagnosticMachineTrace.Pipeline, diagnostics: [String]) -> [String] {
        var notes: [String] = []
        if pipeline.failureLayer == "libredwg" {
            notes.append("Stop at LibreDWG until raw drawable geometry is available.")
        }
        if pipeline.failureLayer == "layer" {
            notes.append("Check layer visibility and layer names before changing import/render code.")
        }
        if pipeline.failureLayer == "viewport" {
            notes.append("Check fit-to-extents, viewport transform, and model bounds intersection.")
        }
        if pipeline.failureLayer == "bounds" {
            notes.append("Check entity bounds and spatial index insertion.")
        }
        if pipeline.failureLayer == "renderCommand" {
            notes.append("Check entity-to-render-command mapping for visible entity types.")
        }
        if pipeline.failureLayer == "textOverlay" {
            notes.append("Check text position, scale, rotation, font rasterization, and overlay visibility.")
        }
        if diagnostics.isEmpty {
            notes.append("No kernel diagnostics were attached to this export.")
        }
        return notes
    }

    private func fallbackFileSizeText() -> String {
        let bytes = diagnosticFileByteCount()
        guard bytes > 0 else { return "-" }
        return QuickNoteAttachmentStorage.formattedFileSize(bytes)
    }

    private func diagnosticFileByteCount() -> Int {
        do {
            let values = try activeRequest.fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? activeRequest.fileSizeBytes
        } catch {
            return activeRequest.fileSizeBytes
        }
    }

    private func fallbackHeaderHex() -> String {
        guard let handle = try? FileHandle(forReadingFrom: activeRequest.fileURL) else {
            return "-"
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 32) else {
            return "-"
        }
        return data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
