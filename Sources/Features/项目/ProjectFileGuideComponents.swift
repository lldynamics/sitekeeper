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
            .accessibilityLabel(isExpanded ? "收起使用提示" : "展开使用提示")

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭使用提示")
        }
        .padding(.vertical, 2)
    }
}

struct ProjectFileGuidePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectFileGuideIllustration()

            VStack(alignment: .leading, spacing: 3) {
                Text("如何快速找文件")
                    .font(.subheadline.weight(.semibold))
                Text("先按项目筛选，再看最近文件，最后进入分类页批量预览与分享。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProjectFileGuideStep(icon: "magnifyingglass", title: "先搜索项目", detail: "顶部搜索支持项目名和地点。")
            ProjectFileGuideStep(icon: "clock.fill", title: "看最近文件", detail: "最近文件按时间倒序，适合快速回看。")
            ProjectFileGuideStep(icon: "square.and.arrow.up", title: "点开后可分享", detail: "进入分类后支持预览、分享和打开。")
        }
        .padding(.vertical, 2)
    }
}

struct ProjectFileCategoryGuidePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectFileCategoryIllustration()
            ProjectFileGuideStep(icon: "doc.on.doc.fill", title: "分类查看", detail: "图片、CAD、票据、附件分开管理。")
            ProjectFileGuideStep(icon: "eye.fill", title: "轻点预览", detail: "点行内菜单可预览文件并快速分享。")
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
                    Label("搜索", systemImage: "magnifyingglass")
                    Label("预览", systemImage: "eye.fill")
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
        Section("健康筛选") {
            Picker("健康筛选", selection: $selection) {
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
                    detail: "仅显示命中该状态的项目或文件。"
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
                        Text("大文件")
                            .foregroundStyle(.appRisk)
                    }
                    if item.hasDocumentLedgerIssues {
                        Text("台账缺项")
                            .foregroundStyle(.appWarning)
                    }
                    if !item.exists {
                        Text("文件缺失")
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
                        Label("预览", systemImage: "eye")
                    }
                    ShareLink(item: item.url) {
                        Label(
                            item.category == .drawings
                                ? String(localized: "用专业看图软件打开")
                                : String(localized: "分享/打开"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel("预览与分享")
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
