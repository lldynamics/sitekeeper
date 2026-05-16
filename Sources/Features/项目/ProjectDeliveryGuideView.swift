import SwiftUI

struct ProjectDeliveryGuideData {
    let projectName: String
    let logCount: Int
    let expectedLogDateCount: Int
    let missingLogDateCount: Int
    let missingLogDateSamples: [String]
    let drawingCount: Int
    let drawingGroupsWithoutCurrent: [String]
    let documentCount: Int
    let contactCount: Int
    let missingReceiptCount: Int
    let unsettledFinancialCount: Int
    let unsettledFinancialAmount: Double
    let missingOriginalEntries: [String]
    let estimatedPackageBytes: Int

    var drawingWithoutCurrentCount: Int {
        drawingGroupsWithoutCurrent.count
    }

    var hasBlockingMissingOriginals: Bool {
        !missingOriginalEntries.isEmpty
    }

    var hasDeliveryChecklistWarning: Bool {
        missingLogDateCount > 0
            || drawingCount == 0
            || drawingWithoutCurrentCount > 0
            || contactCount == 0
            || missingReceiptCount > 0
            || unsettledFinancialCount > 0
    }

    var deliveryWarningCount: Int {
        [
            missingLogDateCount > 0,
            drawingCount == 0 || drawingWithoutCurrentCount > 0,
            contactCount == 0,
            missingReceiptCount > 0,
            unsettledFinancialCount > 0
        ].filter { $0 }.count
    }

    var isReadyForDelivery: Bool {
        !hasDeliveryChecklistWarning && !hasBlockingMissingOriginals
    }
}

struct ProjectDeliveryGuideView: View {
    let data: ProjectDeliveryGuideData
    let onStartExport: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    readinessCard
                }

                Section(String(localized: "交付检查")) {
                    guideRow(
                        title: String(localized: "缺日志检查"),
                        detail: logCoverageDetail,
                        status: data.missingLogDateCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.records)
                    }
                    guideRow(
                        title: String(localized: "缺票检查"),
                        detail: data.missingReceiptCount == 0
                            ? String(localized: "全部已关联")
                            : String(format: String(localized: "还有 %lld 条待关联"), Int64(data.missingReceiptCount)),
                        status: data.missingReceiptCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.finance)
                    }
                    guideRow(
                        title: String(localized: "图纸当前版检查"),
                        detail: drawingCurrentVersionDetail,
                        status: drawingCurrentVersionStatus
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: String(localized: "联系人缺失检查"),
                        detail: data.contactCount > 0
                            ? String(format: String(localized: "已维护 %lld 位"), Int64(data.contactCount))
                            : String(localized: "还没有联系人"),
                        status: data.contactCount > 0 ? .ok : .warning
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: String(localized: "未结清检查"),
                        detail: unsettledFinancialDetail,
                        status: data.unsettledFinancialCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.finance)
                    }
                    guideRow(
                        title: String(localized: "原件完整性"),
                        detail: data.hasBlockingMissingOriginals
                            ? String(format: String(localized: "检测到 %lld 个缺失原件"), Int64(data.missingOriginalEntries.count))
                            : String(localized: "未发现缺失原件"),
                        status: data.hasBlockingMissingOriginals ? .error : .ok
                    ) {
                        onOpenMode(.assets)
                    }
                }

                if data.hasDeliveryChecklistWarning {
                    Section {
                        Text(String(localized: "仍可先预览交付包，但建议先补齐日志、票据、图纸当前版、联系人和未结清账目，再执行最终交付。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if data.hasBlockingMissingOriginals {
                    Section(String(localized: "缺失原件（导出前需处理）")) {
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
                            Text(
                                String(
                                    format: String(localized: "还有 %lld 项未显示"),
                                    Int64(data.missingOriginalEntries.count - 20)
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(String(localized: "交付包预估")) {
                    LabeledContent(String(localized: "工程名称")) {
                        Text(data.projectName)
                            .lineLimit(1)
                    }
                    LabeledContent(String(localized: "预计原始附件体积")) {
                        Text(ProjectDetailImportExportActions.formattedBytes(data.estimatedPackageBytes))
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "将导出包含日志、图纸、票据、联系人、财务摘要与原件的 ZIP 交付包。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        onStartExport()
                    } label: {
                        Label(exportButtonTitle, systemImage: "archivebox.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appProminent())
                    .disabled(data.hasBlockingMissingOriginals)
                } footer: {
                    if data.hasBlockingMissingOriginals {
                        Text(String(localized: "检测到缺失原件，需先补齐后才能导出。"))
                    }
                }
            }
            .navigationTitle(String(localized: "完工交付向导"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            Image(systemName: data.isReadyForDelivery ? "checkmark.seal.fill" : "checklist.unchecked")
                .font(.title2.weight(.semibold))
                .foregroundStyle(data.isReadyForDelivery ? Color.appSuccess : Color.appPrimaryAction)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    data.isReadyForDelivery
                        ? String(localized: "交付准备完成")
                        : String(format: String(localized: "完工前还有 %lld 项需要处理"), Int64(data.deliveryWarningCount))
                )
                    .font(.headline)
                Text(readinessDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var readinessDetail: String {
        if data.isReadyForDelivery {
            return String(localized: "日志、票据、图纸当前版、联系人和未结清账目检查均已通过。")
        }
        if data.hasBlockingMissingOriginals {
            return String(localized: "检测到缺失原件，需补齐后才能导出最终 ZIP。")
        }
        return String(localized: "下方每项都可以直接跳转处理，处理完成后再回来导出交付包。")
    }

    private var logCoverageDetail: String {
        if data.missingLogDateCount == 0 {
            if data.expectedLogDateCount > 0 {
                return String(
                    format: String(localized: "已覆盖 %lld 个施工日，共 %lld 条日志"),
                    Int64(data.expectedLogDateCount),
                    Int64(data.logCount)
                )
            }
            return data.logCount > 0
                ? String(format: String(localized: "已记录 %lld 条"), Int64(data.logCount))
                : String(localized: "未设置工期，暂无缺日志日期")
        }
        if data.expectedLogDateCount == 0 {
            return String(localized: "未记录施工日志")
        }
        let sample = data.missingLogDateSamples.joined(separator: "、")
        if sample.isEmpty {
            return String(format: String(localized: "缺 %lld 个施工日"), Int64(data.missingLogDateCount))
        }
        return String(
            format: String(localized: "缺 %lld 个施工日：%@"),
            Int64(data.missingLogDateCount),
            sample
        )
    }

    private var unsettledFinancialDetail: String {
        guard data.unsettledFinancialCount > 0 else {
            return String(localized: "没有未结清账目")
        }
        if data.unsettledFinancialAmount > 0 {
            return String(
                format: String(localized: "还有 %lld 笔，合计 %@"),
                Int64(data.unsettledFinancialCount),
                ReportBuilder.money(data.unsettledFinancialAmount)
            )
        }
        return String(
            format: String(localized: "还有 %lld 笔未结清"),
            Int64(data.unsettledFinancialCount)
        )
    }

    private var exportButtonTitle: String {
        data.hasDeliveryChecklistWarning
            ? String(localized: "检查后导出交付包 ZIP")
            : String(localized: "一键导出交付包 ZIP")
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
                Button(String(localized: "去处理")) {
                    fixAction()
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var drawingCurrentVersionDetail: String {
        if data.drawingCount == 0 {
            return String(localized: "还没有图纸")
        }
        if data.drawingWithoutCurrentCount > 0 {
            let sample = data.drawingGroupsWithoutCurrent.prefix(3).joined(separator: "、")
            if sample.isEmpty {
                return String(
                    format: String(localized: "%lld 组图纸未标记当前版"),
                    Int64(data.drawingWithoutCurrentCount)
                )
            }
            return String(
                format: String(localized: "%lld 组图纸未标记当前版：%@"),
                Int64(data.drawingWithoutCurrentCount),
                sample
            )
        }
        return String(format: String(localized: "已上传 %lld 份，均有当前版"), Int64(data.drawingCount))
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
