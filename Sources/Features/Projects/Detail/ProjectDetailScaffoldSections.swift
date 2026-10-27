import SwiftUI

struct ProjectDetailHeaderSection: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let project: Project
    @Binding var status: ProjectStatus
    let todayValue: String
    let todayColor: Color
    let riskValue: String
    let riskColor: Color
    let pendingValue: String
    let pendingColor: Color
    let deliveryValue: String
    let deliveryColor: Color
    let showsStatus: Bool
    let onOpenToday: () -> Void
    let onOpenRisk: () -> Void
    let onOpenPending: () -> Void
    let onOpenDelivery: () -> Void

    private var usesPadOverviewCards: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.normal) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.title3.weight(.bold))
                        Text(project.location.isEmpty ? AppLocalization.string("未填写地址") : project.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if showsStatus {
                        Picker(AppLocalization.string("状态"), selection: $status) {
                            ForEach(ProjectStatus.allCases, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                overviewMetrics
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
                    title: AppLocalization.string("今日"),
                    value: todayValue,
                    color: todayColor,
                    systemImage: "calendar.badge.clock",
                    action: onOpenToday
                )
                metricCard(
                    title: AppLocalization.string("风险"),
                    value: riskValue,
                    color: riskColor,
                    systemImage: "exclamationmark.triangle.fill",
                    action: onOpenRisk
                )
                metricCard(
                    title: AppLocalization.string("待处理"),
                    value: pendingValue,
                    color: pendingColor,
                    systemImage: "checklist",
                    action: onOpenPending
                )
                metricCard(
                    title: AppLocalization.string("交付"),
                    value: deliveryValue,
                    color: deliveryColor,
                    systemImage: "checkmark.seal.fill",
                    action: onOpenDelivery
                )
            }
        } else {
            HStack {
                metric(AppLocalization.string("今日"), todayValue, todayColor, action: onOpenToday)
                metric(AppLocalization.string("风险"), riskValue, riskColor, action: onOpenRisk)
                metric(AppLocalization.string("待处理"), pendingValue, pendingColor, action: onOpenPending)
                metric(AppLocalization.string("交付"), deliveryValue, deliveryColor, action: onOpenDelivery)
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
                    .appListPrimaryTextLayout()
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
                    .appListPrimaryTextLayout()
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .appListPrimaryTextLayout()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(.horizontal, AppSpacing.normal)
            .padding(.vertical, AppSpacing.tight)
            .background(Color.appPrimarySurfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
