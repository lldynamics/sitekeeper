import SwiftUI

struct DashboardRiskStrip: View {
    let hasDashboardRisk: Bool
    let pins: [DashboardRiskPin]

    var body: some View {
        Group {
            if hasDashboardRisk {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.tight) {
                        ForEach(pins) { pin in
                            DashboardRiskPill(
                                title: pin.title,
                                value: pin.value,
                                color: pin.color,
                                hasRisk: pin.hasRisk,
                                destination: pin.destination,
                                quickActions: pin.quickActions
                            )
                        }
                    }
                    .padding(.vertical, AppSpacing.tight * 0.25)
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
    }
}
