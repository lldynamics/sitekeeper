import SwiftUI

struct ProjectDetailHeaderSection<RiskStrip: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let project: Project
    @Binding var status: ProjectStatus
    let progressValue: String
    let quoteValue: String
    let todoValue: String
    let unpaidAmount: Double
    let riskStrip: RiskStrip
    let customerLine: String?
    let periodLine: String?
    let showsStatus: Bool
    let onOpenRecords: () -> Void
    let onOpenFinanceFromQuote: () -> Void
    let onOpenTodoFilter: () -> Void
    let onOpenFinanceFromUnpaid: () -> Void
    let onEditProject: () -> Void
    let canExportDeliveryPackage: Bool
    let onExportDeliveryPackage: () -> Void

    private var usesPadOverviewCards: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.normal) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.title3.weight(.bold))
                        Text(project.location.isEmpty ? String(localized: "未填写地址") : project.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if showsStatus {
                        Picker(String(localized: "状态"), selection: $status) {
                            ForEach(ProjectStatus.allCases, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                overviewMetrics
                riskStrip
                if let customerLine {
                    Text(customerLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let periodLine {
                    Text(periodLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onEditProject()
                } label: {
                    Label(String(localized: "编辑项目资料"), systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                }
                if canExportDeliveryPackage {
                    Button {
                        onExportDeliveryPackage()
                    } label: {
                        Label(String(localized: "一键导出交付包"), systemImage: "archivebox.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appPrimaryAction)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var overviewMetrics: some View {
        if usesPadOverviewCards {
            let columns: [GridItem] = [
                GridItem(.flexible(), spacing: AppSpacing.normal),
                GridItem(.flexible(), spacing: AppSpacing.normal)
            ]
            LazyVGrid(columns: columns, spacing: AppSpacing.normal) {
                metricCard(
                    title: String(localized: "进度"),
                    value: progressValue,
                    color: .appWarning,
                    systemImage: "gauge.with.dots.needle.50percent",
                    action: onOpenRecords
                )
                metricCard(
                    title: String(localized: "报价"),
                    value: quoteValue,
                    color: .appDoc,
                    systemImage: "doc.text.fill",
                    action: onOpenFinanceFromQuote
                )
                metricCard(
                    title: String(localized: "待办"),
                    value: todoValue,
                    color: .appWarning,
                    systemImage: "checklist",
                    action: onOpenTodoFilter
                )
                metricCard(
                    title: String(localized: "未收款"),
                    value: unpaidAmount > 0 ? ReportBuilder.money(unpaidAmount) : String(localized: "已收清"),
                    color: unpaidAmount > 0 ? .appPrimaryAction : .appSuccess,
                    systemImage: "yensign.circle.fill",
                    action: onOpenFinanceFromUnpaid
                )
            }
        } else {
            HStack {
                metric(String(localized: "进度"), progressValue, .appWarning, action: onOpenRecords)
                metric(String(localized: "报价"), quoteValue, .appDoc, action: onOpenFinanceFromQuote)
                metric(String(localized: "待办"), todoValue, .appWarning, action: onOpenTodoFilter)
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func metricCard(title: String, value: String, color: Color, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, AppSpacing.normal)
            .padding(.vertical, AppSpacing.tight)
            .background(Color.appPrimarySurfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}

struct ProjectDetailQuickActionSection: View {
    let onAddLog: () -> Void
    let onAddFinance: () -> Void
    let onAddContact: () -> Void
    let onImportDrawing: () -> Void
    let onAddMaterial: () -> Void
    let onAddQuote: () -> Void
    let onAddLabor: () -> Void

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    actionChip(String(localized: "写日志"), systemImage: "book.pages.fill", color: .appSuccess, action: onAddLog)
                    actionChip(String(localized: "记账"), systemImage: "receipt.fill", color: .appFinance, action: onAddFinance)
                    actionChip(String(localized: "导资料"), systemImage: "doc.viewfinder.fill", color: .appDoc, action: onImportDrawing)
                    moreActionsMenu
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))
        }
    }

    private func actionChip(_ title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, 7)
                .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var moreActionsMenu: some View {
        Menu {
            Button(action: onAddContact) {
                Label(String(localized: "联系人"), systemImage: "person.crop.circle.badge.plus")
            }
            Button(action: onAddMaterial) {
                Label(String(localized: "材料"), systemImage: "shippingbox.fill")
            }
            Button(action: onAddQuote) {
                Label(String(localized: "报价"), systemImage: "doc.text.fill")
            }
            Button(action: onAddLabor) {
                Label(String(localized: "人工"), systemImage: "person.2.fill")
            }
        } label: {
            Label(String(localized: "更多"), systemImage: "ellipsis.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appPrimaryAction)
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, 7)
                .background(Color.appPrimaryAction.opacity(0.12), in: Capsule())
        }
    }
}
