import SwiftUI

struct DashboardRiskStrip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var isExpanded: Bool
    @ScaledMetric(relativeTo: .caption) private var expandedContentHeight: CGFloat = 220

    let hasDashboardRisk: Bool
    let pins: [DashboardRiskPin]

    private let previewLimit = 2

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: AppSpacing.tight, alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 150), spacing: AppSpacing.tight, alignment: .top)]
    }

    var body: some View {
        Group {
            if hasDashboardRisk {
                VStack(alignment: .leading, spacing: AppSpacing.tight * 0.5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.tight) {
                            reminderSummary
                                .fixedSize(horizontal: true, vertical: true)
                            Spacer(minLength: AppSpacing.tight)
                            expansionButton
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            reminderSummary
                            expansionButton
                        }
                    }

                    if isExpanded && pins.count > previewLimit {
                        // Keep the control visible in the bottom strip of wide dashboards.
                        // Short lists use their natural height; longer lists can scroll.
                        ViewThatFits(in: .vertical) {
                            riskGrid(pins)
                                .fixedSize(horizontal: false, vertical: true)
                            ScrollView(.vertical) {
                                riskGrid(pins)
                            }
                            .scrollIndicators(.visible)
                        }
                        .frame(maxHeight: min(expandedContentHeight, 300), alignment: .top)
                    } else {
                        riskGrid(Array(pins.prefix(previewLimit)))
                    }
                }
            } else {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSuccess)
                    Text(AppLocalization.string("今日无风险"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSuccess)
                    Spacer()
                    Text(AppLocalization.string("继续保持"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, AppSpacing.tight + 1)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.normal - 2)
                        .fill(Color.appWillowSurfaceSubtle)
                )
            }
        }
        .onChange(of: hasDashboardRisk) { _, hasRisk in
            if !hasRisk { isExpanded = false }
        }
    }

    private var reminderSummary: some View {
        Text(String(format: AppLocalization.string("%d 类提醒"), pins.count))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var expansionButton: some View {
        if pins.count > previewLimit {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: AppSpacing.tight * 0.5) {
                    Text(AppLocalization.string(isExpanded ? "收起" : "查看全部"))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appPrimaryAction)
            .accessibilityLabel(AppLocalization.string(isExpanded ? "收起提醒" : "查看全部提醒"))
            .accessibilityValue(AppLocalization.string(isExpanded ? "已展开" : "已收起"))
            .accessibilityIdentifier("dashboard-risk-expansion-toggle")
        }
    }

    private func riskGrid(_ displayedPins: [DashboardRiskPin]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.tight) {
            ForEach(displayedPins) { pin in
                DashboardRiskPill(
                    title: pin.title,
                    value: pin.value,
                    color: pin.color,
                    hasRisk: pin.hasRisk,
                    destination: pin.destination,
                    quickActions: pin.quickActions
                )
                .accessibilityIdentifier("dashboard-risk-\(pin.id)")
            }
        }
        .padding(.vertical, AppSpacing.tight * 0.25)
    }
}
