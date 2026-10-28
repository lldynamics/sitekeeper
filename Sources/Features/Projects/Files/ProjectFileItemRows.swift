import SwiftUI
import UIKit

struct ProjectFileItemRow: View {
    let item: ProjectFileItem
    let onPreview: () -> Void

    private var requiresExternalDrawingViewer: Bool {
        item.category == .drawings && ProjectDetailDrawingHelper.requiresExternalViewer(item.fileType)
    }

    var body: some View {
        HStack(spacing: 12) {
            ProjectFileThumbnail(item: item)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .accessibilityIdentifier("project-file-row-\(item.id)")
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
                        Text(AppLocalization.string("project.files.badge.large"))
                            .foregroundStyle(.appRisk)
                    }
                    if item.hasDocumentLedgerIssues {
                        Text(AppLocalization.string("project.files.badge.ledgerIncomplete"))
                            .foregroundStyle(.appWarning)
                    }
                    if !item.exists {
                        Text(AppLocalization.string("project.files.badge.missing"))
                            .foregroundStyle(.appRisk)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.exists ? Color.secondary : Color.appRisk)
            }
            Spacer(minLength: 8)
            if item.exists {
                Menu {
                    if !requiresExternalDrawingViewer {
                        Button(action: onPreview) {
                            Label(AppLocalization.string("project.files.action.preview"), systemImage: "eye")
                        }
                        .accessibilityIdentifier("project-file-preview-\(item.id)")
                    }
                    ShareLink(item: item.url) {
                        Label(
                            item.category == .drawings
                                ? AppLocalization.string("project.files.action.openExternalViewer")
                                : AppLocalization.string("project.files.action.shareOpen"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(AppLocalization.string("project.files.action.previewShare.accessibility"))
                .accessibilityIdentifier("project-file-actions-\(item.id)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.exists && !requiresExternalDrawingViewer {
                onPreview()
            }
        }
    }
}

struct ProjectFileThumbnail: View {
    let item: ProjectFileItem

    @State private var image: UIImage?
    @State private var reloadRevision: UInt64 = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(item.category.tint.opacity(0.12))
            if let image, item.exists {
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
        .reloadThumbnail(onInvalidationOf: item.url) { reloadRevision &+= 1 }
        .task(id: Request(token: item.thumbnailToken, exists: item.exists, revision: reloadRevision)) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        image = nil
        guard item.exists, let token = item.thumbnailToken else {
            image = nil
            return
        }
        let loaded = await ProjectFileThumbnailCache.image(for: token)
        guard !Task.isCancelled else { return }
        image = loaded
    }

    private struct Request: Hashable {
        let token: ProjectFileThumbnailToken?
        let exists: Bool
        let revision: UInt64
    }
}
