import SwiftUI

struct ProjectModeHubEntry: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let destination: AnyView
}

struct ProjectModeHubSection: View {
    let title: String
    let entries: [ProjectModeHubEntry]

    var body: some View {
        Section(title) {
            ForEach(entries) { entry in
                NavigationLink {
                    entry.destination
                        .navigationTitle(entry.title)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: entry.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(entry.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(entry.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
