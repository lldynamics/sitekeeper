import SwiftUI

struct CADDiagnosticPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    var shouldShowCADDiagnosticCommand: Bool {
        guard isCADFile else { return false }
        if engineStatusHint != nil {
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
                        title: String(localized: "DWG Lite"),
                        value: CADDrawingCapability.isLibreDWGRendererAvailable() ? String(localized: "可用") : String(localized: "不可用")
                    )
                    diagnosticRow(
                        title: String(localized: "看图入口"),
                        value: CADRendererProvider.isLibreDWGRendererBound ? String(localized: "已绑定") : String(localized: "未绑定")
                    )
                    diagnosticRow(
                        title: String(localized: "源文件写入"),
                        value: String(localized: "否")
                    )
                    if let engineStatusHint {
                        diagnosticRow(title: String(localized: "提示"), value: engineStatusHint)
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
}
