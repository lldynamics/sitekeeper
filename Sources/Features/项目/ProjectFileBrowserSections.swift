import SwiftUI

struct ProjectFileDeliveryInspectionSection<Destination: View>: View {
    let inspections: [ProjectDocumentDeliveryInspection]
    let isSplitNavigation: Bool
    let onSelectIssue: (ProjectDocumentDeliveryInspection, ProjectDocumentDeliveryInspectionIssue) -> Void
    let onExport: (ProjectDocumentDeliveryInspectionExportFormat) -> Void
    let destination: (ProjectDocumentDeliveryInspection, ProjectDocumentDeliveryInspectionIssue) -> Destination

    private var issueInspections: [ProjectDocumentDeliveryInspection] {
        inspections.filter { !$0.isReadyForDelivery }
    }

    private var issueCount: Int {
        issueInspections.reduce(0) { $0 + $1.issueDetailCount }
    }

    @ViewBuilder
    var body: some View {
        if !inspections.isEmpty {
            Section(String(localized: "交付体检")) {
                if issueInspections.isEmpty {
                    ProjectFileMicroGuideRow(
                        icon: "checkmark.seal.fill",
                        color: .appSuccess,
                        title: String(localized: "一键体检通过"),
                        detail: String(localized: "资料类别、原件、归档状态、责任人和形成日期暂未发现交付风险。")
                    )
                } else {
                    ProjectFileMicroGuideRow(
                        icon: "checklist.unchecked",
                        color: .appWarning,
                        title: String(
                            format: String(localized: "%lld 个项目需处理"),
                            Int64(issueInspections.count)
                        ),
                        detail: String(
                            format: String(localized: "共 %lld 条交付前检查项，优先处理缺件、退回和未归档资料。"),
                            Int64(issueCount)
                        )
                    )

                    ForEach(issueInspections.prefix(4)) { inspection in
                        if isSplitNavigation {
                            ProjectFileDeliveryInspectionRow(inspection: inspection) { issue in
                                Button {
                                    onSelectIssue(inspection, issue)
                                } label: {
                                    ProjectFileDeliveryIssueLine(issue: issue, showsAction: true)
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.clear)
                        } else {
                            ProjectFileDeliveryInspectionRow(inspection: inspection) { issue in
                                NavigationLink {
                                    destination(inspection, issue)
                                } label: {
                                    ProjectFileDeliveryIssueLine(issue: issue, showsAction: true)
                                }
                            }
                        }
                    }

                    if issueInspections.count > 4 {
                        Text(
                            String(
                                format: String(localized: "还有 %lld 个项目待体检处理，可用搜索缩小范围。"),
                                Int64(issueInspections.count - 4)
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Menu {
                    Button {
                        onExport(.pdf)
                    } label: {
                        Label(String(localized: "导出 PDF"), systemImage: "doc.richtext")
                    }
                    Button {
                        onExport(.csv)
                    } label: {
                        Label(String(localized: "导出 CSV"), systemImage: "tablecells")
                    }
                } label: {
                    Label(String(localized: "导出体检清单"), systemImage: "square.and.arrow.up")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
    }
}

struct ProjectFileBrowserDetailPanel: View {
    let item: ProjectFileItem?
    let onPreview: (URL) -> Void

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.normal) {
                        HStack(spacing: AppSpacing.normal) {
                            Image(systemName: item.systemImage)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(item.category.tint)
                                .frame(width: 36, height: 36)
                                .background(item.category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        fileDetailStatusSummary(for: item)

                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(String(localized: "类型"), value: item.fileType.uppercased())
                            LabeledContent(String(localized: "大小"), value: item.formattedSize)
                            LabeledContent(String(localized: "状态"), value: item.exists ? String(localized: "可用") : String(localized: "文件缺失"))
                            if let documentStatus = item.documentStatus {
                                LabeledContent(String(localized: "报验状态"), value: documentStatus.displayName)
                            }
                            if item.isLargeFile {
                                LabeledContent(String(localized: "体积提示"), value: String(localized: "大文件"))
                            }
                        }
                        .font(.subheadline)

                        if item.exists {
                            if ProjectDetailDrawingHelper.requiresExternalViewer(item.fileType) {
                                InlineNotice(
                                    title: String(localized: "图纸台账 + 外部打开"),
                                    message: String(localized: "DWG/DXF 原件不在 App 内完整预览，请通过外部专业看图软件打开；App 负责台账、版本、当前版和交付导出。"),
                                    tone: .info
                                )
                            } else {
                                Button {
                                    onPreview(item.url)
                                } label: {
                                    Label(String(localized: "预览文件"), systemImage: "eye")
                                }
                                .buttonStyle(.appProminent())
                            }
                            ShareLink(item: item.url) {
                                Label(
                                    item.category == .drawings
                                        ? String(localized: "用外部专业看图软件打开")
                                        : String(localized: "分享/打开"),
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                        } else {
                            InlineNotice(
                                title: String(localized: "文件缺失"),
                                message: String(localized: "该文件在本地已缺失，请回到项目详情重新导入。"),
                                tone: .error
                            )
                        }
                    }
                    .padding(AppSpacing.relaxed)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "请选择文件"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(String(localized: "在中栏点击文件后，右侧显示详情并支持 QuickLook 预览。"))
                )
            }
        }
    }

    @ViewBuilder
    private func fileDetailStatusSummary(for item: ProjectFileItem) -> some View {
        HStack(spacing: AppSpacing.tight) {
            StatusChip(
                text: item.exists ? String(localized: "可用") : String(localized: "文件缺失"),
                tone: item.exists ? .success : .risk,
                compact: true
            )
            if let documentStatus = item.documentStatus {
                StatusChip(
                    text: documentStatus.displayName,
                    tone: documentStatus.requiresArchiveAttention ? .warning : .doc,
                    compact: true
                )
            }
            if item.hasDocumentLedgerIssues {
                StatusChip(text: String(localized: "台账缺项"), tone: .warning, compact: true)
            }
            if item.isLargeFile {
                StatusChip(text: String(localized: "大文件"), tone: .risk, compact: true)
            }
        }
    }
}
