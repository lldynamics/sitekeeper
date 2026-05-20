import SwiftUI
import UIKit

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
                        .font(.system(size: 22, weight: .semibold))
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
                        .font(.system(size: 20, weight: .semibold))
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
            .font(.system(size: 18, weight: .semibold))
        }
        .frame(height: 54)
    }
}

struct ProjectFileGuideStep: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appDoc)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

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
        Section(String(localized: "project.files.healthFilter.section")) {
            Picker(String(localized: "project.files.healthFilter.section"), selection: $selection) {
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
                    detail: String(localized: "project.files.healthFilter.active.detail")
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

struct ProjectFileItemRow: View {
    let item: ProjectFileItem
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProjectFileThumbnail(item: item)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(item.fileType.uppercased())
                    Text(item.formattedSize)
                    if let status = item.documentStatus {
                        Text(status.displayName)
                            .foregroundStyle(status.requiresArchiveAttention ? Color.appWarning : Color.secondary)
                    }
                    if item.isLargeFile {
                        Text(String(localized: "project.files.badge.large"))
                            .foregroundStyle(.appRisk)
                    }
                    if item.hasDocumentLedgerIssues {
                        Text(String(localized: "project.files.badge.ledgerIncomplete"))
                            .foregroundStyle(.appWarning)
                    }
                    if !item.exists {
                        Text(String(localized: "project.files.badge.missing"))
                            .foregroundStyle(.appRisk)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.exists ? Color.secondary : Color.appRisk)
            }
            Spacer(minLength: 8)
            if item.exists {
                Menu {
                    Button(action: onPreview) {
                        Label(String(localized: "project.files.action.preview"), systemImage: "eye")
                    }
                    ShareLink(item: item.url) {
                        Label(
                            item.category == .drawings
                                ? String(localized: "project.files.action.openExternalViewer")
                                : String(localized: "project.files.action.shareOpen"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "project.files.action.previewShare.accessibility"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.exists {
                onPreview()
            }
        }
    }
}

struct ProjectFileThumbnail: View {
    let item: ProjectFileItem

    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(item.category.tint.opacity(0.12))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(item.exists ? item.category.tint : .secondary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.exists ? Color.clear : Color.appStrokeError, lineWidth: 1)
        )
        .task(id: item.id) {
            await loadThumbnailIfNeeded()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard let token = item.thumbnailToken else {
            image = nil
            return
        }
        if let cached = ProjectFileThumbnailCache.image(for: token.cacheKey) {
            image = cached
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            let loaded = await token.loadImageAsync()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let loaded {
                    ProjectFileThumbnailCache.store(loaded, for: token.cacheKey)
                }
                image = loaded
            }
        }
        await loadTask?.value
    }
}
