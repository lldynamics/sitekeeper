import SwiftUI

struct DashboardQuickActionItem {
    let title: String
    let systemImage: String
    let color: Color
    let destination: DashboardDestination
    let quickActions: [TodayPrimaryQuickAction]
}

struct DashboardQuickActions: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let items: [DashboardQuickActionItem]
    let onTrigger: (String) -> Void

    var body: some View {
        DashboardPanel(title: AppLocalization.string("快速录入"), systemImage: "bolt.fill") {
            DashboardQuickActionLayout(prefersSingleColumn: dynamicTypeSize.isAccessibilitySize) {
                DashboardQuickActionButtons(items: items, onTrigger: onTrigger)
            }
        }
    }
}

// A single layout keeps each NavigationLink's identity while the available width changes.
private struct DashboardQuickActionLayout: Layout {
    let prefersSingleColumn: Bool
    private let spacing = AppSpacing.tight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        metrics(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = metrics(width: bounds.width, subviews: subviews)
        var rowY = bounds.minY
        for row in layout.rowHeights.indices {
            let rowHeight = layout.rowHeights[row]
            for column in 0..<layout.columns {
                let index = row * layout.columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (layout.cellWidth + spacing), y: rowY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: layout.cellWidth, height: rowHeight)
                )
            }
            rowY += rowHeight + spacing
        }
    }

    private func metrics(width proposedWidth: CGFloat?, subviews: Subviews) -> Metrics {
        guard !subviews.isEmpty else { return Metrics(size: .zero, columns: 1, cellWidth: 0, rowHeights: []) }
        // Unspecified sizing measures the current, dynamically scaled labels rather than a device preset.
        let preferredCellWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let idealWidth = preferredCellWidth * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1)
        let width = max(0, proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth)
        let candidates = prefersSingleColumn ? [1] : [subviews.count, min(2, subviews.count), 1]
        let columns = candidates.first { count in
            preferredCellWidth * CGFloat(count) + spacing * CGFloat(count - 1) <= width
        } ?? 1
        let cellWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var rowHeights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let end = min(start + columns, subviews.count)
            let height = (start..<end).map { index in
                subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            }.max() ?? 0
            rowHeights.append(height)
        }
        let height = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return Metrics(size: CGSize(width: width, height: height), columns: columns, cellWidth: cellWidth, rowHeights: rowHeights)
    }

    private struct Metrics {
        let size: CGSize
        let columns: Int
        let cellWidth: CGFloat
        let rowHeights: [CGFloat]
    }
}

struct DashboardQuickActionButtons: View {
    let items: [DashboardQuickActionItem]
    let onTrigger: (String) -> Void

    var body: some View {
        ForEach(items.indices, id: \.self) { index in
            let item = items[index]
            TodayMiniAction(
                title: item.title,
                systemImage: item.systemImage,
                color: item.color,
                destination: item.destination,
                quickActions: item.quickActions,
                onTrigger: { onTrigger(item.title) }
            )
        }
    }
}
