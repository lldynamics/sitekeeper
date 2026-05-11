import SwiftUI

struct ProjectModeHubSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section(title) {
            content()
        }
    }
}

struct ProjectModeHubRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: AppSpacing.normal) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
