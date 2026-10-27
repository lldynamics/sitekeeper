import SwiftUI

struct ProjectInlineEmptyState: View {
    let title: String
    let systemImage: String
    let detail: String?

    init(_ title: String, systemImage: String, detail: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct FlowTagLine: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    tagViews
                }
                VStack(alignment: .leading, spacing: 4) {
                    tagViews
                }
            }
        }
    }

    @ViewBuilder
    private var tagViews: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
