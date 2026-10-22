import SwiftUI

struct FileSearchExecutionKey: Equatable {
    let keyword: String
    let signature: Int
}

struct ProjectFileProjectRow: View {
    let project: Project
    let summary: ProjectFileSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.normal) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? Color.appPrimaryAction : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(project.name)
                        .font(.body.weight(.semibold))
                        .appListPrimaryTextLayout()
                    Spacer()
                    Text(String(format: String(localized: "%lld 个文件"), Int64(summary.totalCount)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.totalCount > 0 ? Color.appPrimaryAction : .secondary)
                }
                HStack(spacing: AppSpacing.tight) {
                    ProjectFileCountChip(title: String(localized: "图片"), value: summary.imageCount, color: .appDoc)
                    ProjectFileCountChip(title: String(localized: "图纸"), value: summary.drawingCount, color: .appPrimaryAction)
                    ProjectFileCountChip(title: String(localized: "资料"), value: summary.documentCount, color: .appPrimaryAction)
                    ProjectFileCountChip(title: String(localized: "附件"), value: summary.quickNoteAttachmentCount, color: .appPrimaryAction)
                }
                if !project.location.isEmpty {
                    Text(project.location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .appListSecondaryTextLayout()
                }
            }
        }
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.appPrimarySurface : Color.clear)
        )
    }
}

struct ProjectFileDeliveryInspectionRow<IssueContent: View>: View {
    let inspection: ProjectDocumentDeliveryInspection
    let issueContent: (ProjectDocumentDeliveryInspectionIssue) -> IssueContent

    init(
        inspection: ProjectDocumentDeliveryInspection,
        @ViewBuilder issueContent: @escaping (ProjectDocumentDeliveryInspectionIssue) -> IssueContent
    ) {
        self.inspection = inspection
        self.issueContent = issueContent
    }

    private var visibleIssues: ArraySlice<ProjectDocumentDeliveryInspectionIssue> {
        inspection.issues.prefix(3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appWarning)
                    .frame(width: 18)
                Text(inspection.project.name)
                    .font(.subheadline.weight(.semibold))
                    .appListPrimaryTextLayout()
                Spacer(minLength: 8)
                Text(
                    String(
                        format: String(localized: "%lld 条"),
                        Int64(inspection.issueDetailCount)
                    )
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appRisk)
            }

            ForEach(visibleIssues) { issue in
                issueContent(issue)
            }

            if inspection.issues.count > visibleIssues.count {
                Text(
                    String(
                        format: String(localized: "另有 %lld 类问题"),
                        Int64(inspection.issues.count - visibleIssues.count)
                    )
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, 8)
        .background {
            AppSurface(
                tone: .tinted(Color.appWarning.opacity(0.08)),
                cornerRadius: 10,
                stroke: Color.appWarning.opacity(0.18)
            ) {
                Color.clear
            }
        }
    }
}

struct ProjectFileDeliveryIssueLine: View {
    let issue: ProjectDocumentDeliveryInspectionIssue
    var showsAction = false

    private var sampleText: String {
        let text = issue.samples.prefix(3).joined(separator: "、")
        if issue.samples.count > 3 {
            return String(
                format: String(localized: "%@ 等"),
                text
            )
        }
        return text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: issue.kind.systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(issue.kind.tint)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(
                        String(
                            format: String(localized: "%@ %lld"),
                            issue.kind.title,
                            Int64(issue.count)
                        )
                    )
                    .font(.caption.weight(.semibold))

                    if showsAction {
                        Text(issue.kind.actionTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(issue.kind.tint)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(issue.kind.tint)
                    }
                }

                if !sampleText.isEmpty {
                    Text(sampleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct ProjectFileSplitItemRow: View {
    let item: ProjectFileItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.normal) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.exists ? item.category.tint : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .appListSecondaryTextLayout()
                HStack(spacing: AppSpacing.tight) {
                    Text(item.fileType.uppercased())
                    Text(item.formattedSize)
                    if let status = item.documentStatus {
                        Text(status.displayName)
                            .foregroundStyle(status.requiresArchiveAttention ? Color.appWarning : Color.secondary)
                    }
                    if item.hasDocumentLedgerIssues {
                        Text(String(localized: "台账缺项"))
                            .foregroundStyle(.appWarning)
                    }
                    if item.isLargeFile {
                        Text(String(localized: "大文件"))
                            .foregroundStyle(.appRisk)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.exists ? Color.secondary : Color.appRisk)
            }
            Spacer(minLength: 6)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appPrimaryAction)
            }
        }
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.appPrimarySurfaceSubtle : Color.clear))
    }
}

struct ProjectFileSearchResult: Identifiable, Sendable {
    let project: Project
    let item: ProjectFileItem

    var id: String {
        "\(project.id.uuidString)-\(item.id)"
    }
}
