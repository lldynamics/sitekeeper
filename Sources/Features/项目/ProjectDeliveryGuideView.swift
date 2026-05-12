import SwiftUI

struct ProjectDeliveryGuideData {
    let projectName: String
    let logCount: Int
    let drawingCount: Int
    let drawingWithoutCurrentCount: Int
    let documentCount: Int
    let contactCount: Int
    let missingReceiptCount: Int
    let unsettledFinancialCount: Int
    let missingOriginalEntries: [String]
    let estimatedPackageBytes: Int

    var hasBlockingMissingOriginals: Bool {
        !missingOriginalEntries.isEmpty
    }

    var hasDeliveryChecklistWarning: Bool {
        logCount == 0
            || drawingCount == 0
            || drawingWithoutCurrentCount > 0
            || contactCount == 0
            || missingReceiptCount > 0
            || unsettledFinancialCount > 0
    }
}

struct ProjectDeliveryGuideView: View {
    let data: ProjectDeliveryGuideData
    let onStartExport: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("交付检查") {
                    guideRow(
                        title: "缺日志检查",
                        detail: data.logCount > 0 ? "已记录 \(data.logCount) 条" : "未记录施工日志",
                        status: data.logCount > 0 ? .ok : .warning
                    ) {
                        onOpenMode(.records)
                    }
                    guideRow(
                        title: "缺票检查",
                        detail: data.missingReceiptCount == 0 ? "全部已关联" : "还有 \(data.missingReceiptCount) 条待关联",
                        status: data.missingReceiptCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.finance)
                    }
                    guideRow(
                        title: "图纸当前版检查",
                        detail: drawingCurrentVersionDetail,
                        status: drawingCurrentVersionStatus
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: "联系人缺失检查",
                        detail: data.contactCount > 0 ? "已维护 \(data.contactCount) 位" : "还没有联系人",
                        status: data.contactCount > 0 ? .ok : .warning
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: "未结清检查",
                        detail: data.unsettledFinancialCount == 0 ? "没有未结清账目" : "还有 \(data.unsettledFinancialCount) 笔未结清",
                        status: data.unsettledFinancialCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.finance)
                    }
                    guideRow(
                        title: "原件完整性",
                        detail: data.hasBlockingMissingOriginals ? "检测到 \(data.missingOriginalEntries.count) 个缺失原件" : "未发现缺失原件",
                        status: data.hasBlockingMissingOriginals ? .error : .ok
                    ) {
                        onOpenMode(.assets)
                    }
                }

                if data.hasDeliveryChecklistWarning {
                    Section {
                        Text("建议先补齐日志、票据、图纸当前版、联系人和未结清账目，再执行最终交付。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if data.hasBlockingMissingOriginals {
                    Section("缺失原件（导出前需处理）") {
                        ForEach(Array(data.missingOriginalEntries.prefix(20)), id: \.self) { item in
                            HStack(alignment: .top, spacing: AppSpacing.tight) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.appRisk)
                                    .font(.caption)
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if data.missingOriginalEntries.count > 20 {
                            Text("还有 \(data.missingOriginalEntries.count - 20) 项未显示")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("交付包预估") {
                    LabeledContent("工程名称") {
                        Text(data.projectName)
                            .lineLimit(1)
                    }
                    LabeledContent("预计原始附件体积") {
                        Text(ProjectDetailImportExportActions.formattedBytes(data.estimatedPackageBytes))
                            .foregroundStyle(.secondary)
                    }
                    Text("将导出包含日志、图纸、票据、联系人、财务摘要与原件的 ZIP 交付包。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        onStartExport()
                    } label: {
                        Label("一键导出交付包 ZIP", systemImage: "archivebox.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(data.hasBlockingMissingOriginals)
                } footer: {
                    if data.hasBlockingMissingOriginals {
                        Text("检测到缺失原件，需先补齐后才能导出。")
                    }
                }
            }
            .navigationTitle("完工交付向导")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func guideRow(title: String, detail: String, status: GuideStatus, fixAction: @escaping () -> Void) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status != .ok {
                Button("去处理") {
                    fixAction()
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var drawingCurrentVersionDetail: String {
        if data.drawingCount == 0 {
            return "还没有图纸"
        }
        if data.drawingWithoutCurrentCount > 0 {
            return "\(data.drawingWithoutCurrentCount) 组图纸未标记当前版"
        }
        return "已上传 \(data.drawingCount) 份，均有当前版"
    }

    private var drawingCurrentVersionStatus: GuideStatus {
        if data.drawingCount == 0 {
            return .warning
        }
        return data.drawingWithoutCurrentCount > 0 ? .warning : .ok
    }

    private enum GuideStatus {
        case ok
        case warning
        case error

        var icon: String {
            switch self {
            case .ok:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.circle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .ok:
                return .appSuccess
            case .warning:
                return .appPrimaryAction
            case .error:
                return .appRisk
            }
        }
    }
}
