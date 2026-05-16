import SwiftUI

struct CADDiagnosticPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    var shouldShowCADDiagnosticCommand: Bool {
        guard CADTechnicalDiagnosticsVisibility.isEnabled else { return false }
        guard isCADFile, shouldUseCADKernelRenderer else { return false }
        if engineStatusHint != nil {
            return true
        }
        if let cadOpenQuality, !cadOpenQuality.isReady {
            return true
        }
        if hasUnresolvedFontDiagnosticIssue {
            return true
        }
        if hasSuspiciousTextDiagnosticIssue {
            return true
        }
        return false
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

    var cadDiagnosticSheet: some View {
        NavigationStack {
            List {
                Section(String(localized: "预览状态")) {
                    diagnosticRow(
                        title: String(localized: "看图内核"),
                        value: CADDrawingCapability.isCADEngineInstalled() ? String(localized: "已接入") : String(localized: "未接入")
                    )
                    diagnosticRow(
                        title: String(localized: "看图入口"),
                        value: CADRendererProvider.isRendererBound ? String(localized: "已绑定") : String(localized: "未绑定")
                    )
                    diagnosticRow(
                        title: String(localized: "源文件写入"),
                        value: String(localized: "否")
                    )
                    diagnosticRow(
                        title: String(localized: "看图模式"),
                        value: selectedCADViewerMode.title
                    )
                    if let engineStatusHint {
                        diagnosticRow(title: String(localized: "提示"), value: engineStatusHint)
                    }
                }

                Section(String(localized: "打开质量")) {
                    if let cadOpenQuality = cadOpenQualityForDisplay {
                        diagnosticRow(title: String(localized: "状态"), value: cadOpenQuality.title)
                        diagnosticRow(title: String(localized: "处理"), value: cadOpenQuality.summary)
                        diagnosticRow(title: String(localized: "批注定位"), value: cadOpenQuality.allowsMarkup ? String(localized: "可用") : String(localized: "不可用"))
                        diagnosticRow(title: String(localized: "文字搜索"), value: cadOpenQuality.supportsSearch ? String(localized: "可用") : String(localized: "不可用"))
                        ForEach(Array(cadOpenQuality.detailLines.enumerated()), id: \.offset) { _, detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section(String(localized: "文字与字体")) {
                    diagnosticRow(title: String(localized: "当前方案"), value: currentTextSchemeTitle)
                    if let codePage = textSchemeSnapshot.codePage {
                        diagnosticRow(title: String(localized: "命中编码"), value: codePageDisplayName(codePage))
                    }
                    if let score = textSchemeSnapshot.autoDetectScore {
                        diagnosticRow(title: String(localized: "识别评分"), value: "\(score)")
                    }
                    if let matched = textSchemeSnapshot.matchedFontSummary, !matched.isEmpty {
                        diagnosticRow(title: String(localized: "已匹配字体"), value: matched)
                    }
                    if let unresolved = textSchemeSnapshot.unresolvedFontSummary, !unresolved.isEmpty {
                        diagnosticRow(title: String(localized: "未匹配字体"), value: unresolved)
                    }
                    if let summary = textSchemeSnapshot.detectionSummary, !summary.isEmpty {
                        diagnosticRow(title: String(localized: "识别摘要"), value: summary)
                    }
                }

                Section(String(localized: "操作")) {
                    Button {
                        Task {
                            await exportDiagnosticLog()
                        }
                    } label: {
                        Label(
                            isExportingDiagnosticLog ? String(localized: "正在生成诊断日志") : String(localized: "导出诊断日志"),
                            systemImage: isExportingDiagnosticLog ? "hourglass" : "doc.text.magnifyingglass"
                        )
                    }
                    .disabled(isExportingDiagnosticLog)
                }
            }
            .navigationTitle(String(localized: "诊断"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) {
                        showCADDiagnosticSheet = false
                    }
                }
            }
        }
    }

    func diagnosticRow(title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    var cadOpenQualityForDisplay: CADOpenQualitySnapshot? {
        if let cadOpenQuality {
            return cadOpenQuality
        }
        guard isCADFile else { return nil }

        if !CADRendererProvider.isRendererBound {
            return CADOpenQualitySnapshot(
                level: "kernelUnavailable",
                title: String(localized: "CAD 看图内核未绑定"),
                summary: CADViewerMessages.engineMissingMessage,
                primaryAction: String(localized: "下载原图"),
                detailLines: [CADViewerMessages.engineMissingMessage],
                allowsMarkup: false,
                supportsSearch: false
            )
        }

        switch cadOpenRoute {
        case .online:
            return CADOpenQualitySnapshot(
                level: "ready",
                title: String(localized: "在线预览可用"),
                summary: String(localized: "图纸已进入可交互预览。"),
                primaryAction: String(localized: "查看图纸"),
                detailLines: [String(localized: "打开质量回调尚未返回，当前显示入口状态。")],
                allowsMarkup: true,
                supportsSearch: true
            )
        case .unsupported(let result):
            return CADOpenQualitySnapshot(
                level: "kernelBootstrap",
                title: String(localized: "在线预览不可用"),
                summary: result.message,
                primaryAction: String(localized: "下载原图"),
                detailLines: result.technicalDetails?.diagnostics ?? [result.message],
                allowsMarkup: false,
                supportsSearch: false
            )
        }
    }
}
