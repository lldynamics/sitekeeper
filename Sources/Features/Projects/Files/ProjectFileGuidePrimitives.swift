import SwiftUI

struct ProjectFileMicroGuideRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}

struct ProjectFileHealthFilterSection: View {
    @Binding var selection: ProjectFileHealthFilter

    var body: some View {
        Section(AppLocalization.string("project.files.healthFilter.section")) {
            Picker(AppLocalization.string("project.files.healthFilter.section"), selection: $selection) {
                ForEach(ProjectFileHealthFilter.allCases, id: \.self) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            if selection != .all {
                ProjectFileMicroGuideRow(
                    icon: selection.systemImage,
                    color: selection.tint,
                    title: selection.title,
                    detail: AppLocalization.string("project.files.healthFilter.active.detail")
                )
            }
        }
    }
}

struct ProjectFileCountChip: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        Text("\(title) \(value)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(value > 0 ? color : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill((value > 0 ? color : Color.secondary).opacity(0.12)))
    }
}
