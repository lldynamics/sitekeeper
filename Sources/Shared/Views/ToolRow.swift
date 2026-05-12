import SwiftUI

/// 统一列表行组件，替代 CalculatorTabView / ChecklistTabView / ProjectsTabView 中的重复 ToolRow
struct ToolRow: View {
    let icon: String
    let title: String
    let desc: String
    var color: Color = .appPrimaryAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(desc)
        .accessibilityHint("双击打开")
    }
}
