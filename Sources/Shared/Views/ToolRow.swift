import SwiftUI

/// 统一列表行组件，替代 CalculatorTabView / ChecklistTabView / ProjectsTabView 中的重复 ToolRow
struct ToolRow: View {
    let icon: String
    let title: String
    let desc: String
    var color: Color = .appPrimaryAction
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.12))
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if showsChevron {
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(desc)
        .accessibilityHint(AppLocalization.string("双击打开"))
    }
}
