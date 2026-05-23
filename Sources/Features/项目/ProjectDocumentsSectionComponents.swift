import SwiftUI

struct ProjectDocumentMatchSuggestionsView: View {
    let matches: [DocumentFinancialMatch]
    let onLink: (UUID, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(String(localized: "缺票自动匹配建议"), systemImage: "wand.and.stars")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appWarning)
            ForEach(matches) { match in
                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.document.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(match.record.date) · \(match.record.counterparty.isEmpty ? String(localized: "未填写单位") : match.record.counterparty)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "建议关联 %@"), ReportBuilder.money(match.record.amountValue.doubleValue)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "关联")) {
                        onLink(match.document.id, match.record.id)
                    }
                    .buttonStyle(.appProminent())
                    .font(.caption2.weight(.semibold))
                }
            }
        }
        .padding(AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                .fill(Color.appPeachSurfaceSubtle)
        )
    }
}

struct ProjectDocumentChecklistRowView: View {
    let item: DocumentArchiveChecklistItem

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            Image(systemName: item.systemImage)
                .font(.callout)
                .foregroundStyle(item.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.category.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                Text(item.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.tint)
        }
    }
}

struct ProjectDocumentStageRecommendationCard: View {
    let stageDisplayName: String
    let missingCategories: [ProjectDocumentCategory]
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(
                String(format: String(localized: "%@建议补开 %lld 类"), stageDisplayName, Int64(missingCategories.count)),
                systemImage: "wand.and.stars"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appPrimaryAction)

            Text(missingCategories.map(\.displayName).joined(separator: "、"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                onApply()
            } label: {
                Label(String(localized: "启用阶段推荐"), systemImage: "checklist.checked")
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
        }
        .padding(AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                .fill(Color.appPeachSurfaceSubtle)
        )
    }
}
