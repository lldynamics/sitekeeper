import SwiftUI

struct ProjectFileGuideHintStrip: View {
    let title: String
    let subtitle: String
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.min")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appWarning)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "questionmark.circle.fill" : "questionmark.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isExpanded
                    ? String(localized: "project.files.guide.collapse.accessibility")
                    : String(localized: "project.files.guide.expand.accessibility")
            )

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "project.files.guide.close.accessibility"))
        }
        .padding(.vertical, 2)
    }
}

struct ProjectFileGuidePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectFileGuideIllustration()

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "project.files.guide.title"))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "project.files.guide.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProjectFileGuideStep(
                icon: "magnifyingglass",
                title: String(localized: "project.files.guide.search.title"),
                detail: String(localized: "project.files.guide.search.detail")
            )
            ProjectFileGuideStep(
                icon: "clock.fill",
                title: String(localized: "project.files.guide.recent.title"),
                detail: String(localized: "project.files.guide.recent.detail")
            )
            ProjectFileGuideStep(
                icon: "square.and.arrow.up",
                title: String(localized: "project.files.guide.share.title"),
                detail: String(localized: "project.files.guide.share.detail")
            )
        }
        .padding(.vertical, 2)
    }
}

struct ProjectFileCategoryGuidePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectFileCategoryIllustration()
            ProjectFileGuideStep(
                icon: "doc.on.doc.fill",
                title: String(localized: "project.files.categoryGuide.categories.title"),
                detail: String(localized: "project.files.categoryGuide.categories.detail")
            )
            ProjectFileGuideStep(
                icon: "eye.fill",
                title: String(localized: "project.files.categoryGuide.preview.title"),
                detail: String(localized: "project.files.categoryGuide.preview.detail")
            )
        }
        .padding(.vertical, 1)
    }
}

struct ProjectFileGuideIllustration: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.appDocSurfaceSubtle, Color.appPrimarySurfaceSubtle, Color.appSuccessSurfaceSubtle],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.32))
                .frame(width: 68, height: 68)
                .offset(x: 230, y: -34)

            HStack(alignment: .bottom, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.7))
                        .frame(width: 48, height: 48)
                    Image(systemName: "folder.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.appDoc)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.appDoc.opacity(0.8))

                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.7))
                        .frame(width: 48, height: 48)
                    Image(systemName: "doc.richtext.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryAction)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    Label(String(localized: "project.files.action.search"), systemImage: "magnifyingglass")
                    Label(String(localized: "project.files.action.preview"), systemImage: "eye.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appDoc)
            }
            .padding(12)
        }
        .frame(height: 96)
    }
}

struct ProjectFileCategoryIllustration: View {
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.appDocSurfaceSubtle, Color.appPrimarySurfaceSubtle],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            HStack(spacing: 18) {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(Color.appDoc)
                Image(systemName: "doc.viewfinder")
                    .foregroundStyle(Color.appPrimaryAction)
                Image(systemName: "doc.richtext")
                    .foregroundStyle(Color.appWarning)
                Image(systemName: "paperclip")
                    .foregroundStyle(Color.appSuccess)
            }
            .font(.headline.weight(.semibold))
        }
        .frame(height: 54)
    }
}
