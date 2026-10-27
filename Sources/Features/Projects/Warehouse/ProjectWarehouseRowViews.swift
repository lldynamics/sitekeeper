import SwiftUI

struct ProjectWarehouseProjectRow: View {
    let project: Project
    let stockCount: Int
    let movementCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(project.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(String(format: AppLocalization.string("%lld 种"), Int64(stockCount)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stockCount == 0 ? Color.secondary : Color.appPrimaryAction)
            }
            Text(String(format: AppLocalization.string("出入库记录 %lld 条"), Int64(movementCount)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: AppLocalization.string("%@，库存材料 %lld 种，出入库记录 %lld 条"),
                project.name,
                Int64(stockCount),
                Int64(movementCount)
            )
        )
        .accessibilityHint(AppLocalization.string("双击查看项目仓库详情"))
    }
}

struct ProjectWarehouseAttachmentDraftRow: View {
    let attachment: ProjectWarehouseAttachmentDraft
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.systemImage)
                .foregroundStyle(Color.appDoc)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(attachment.displayType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(AppLocalization.string("移除"), role: .destructive, action: onRemove)
                .font(.caption.weight(.semibold))
                .accessibilityLabel(String(format: AppLocalization.string("移除附件 %@"), attachment.title))
        }
    }
}

struct ProjectWarehouseAttachmentDocumentRow: View {
    let document: ProjectDocument
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.appDoc)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(metaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: AppLocalization.string("%@，%@"), document.title, metaText))
        .accessibilityHint(AppLocalization.string("双击预览附件"))
    }

    private var metaText: String {
        let fileType = document.fileType.isEmpty ? AppLocalization.string("附件") : document.fileType.uppercased()
        return "\(document.category.displayName) · \(fileType) · \(Formatters.displayDateText(document.createdAt))"
    }

    private var icon: String {
        switch document.fileType.lowercased() {
        case "jpg", "jpeg", "png", "heic", "webp":
            return "photo"
        case "mov", "mp4", "m4v":
            return "video.fill"
        case "pdf":
            return "doc.richtext"
        case "dwg", "dxf":
            return "ruler"
        case "xls", "xlsx", "csv", "numbers":
            return "tablecells"
        case "doc", "docx", "pages":
            return "doc.text"
        default:
            return "paperclip"
        }
    }
}

struct WarehouseMovementRow: View {
    let movement: ProjectWarehouseMovement

    private var movementType: WarehouseMovementType {
        movement.normalizedMovementType
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: movementType.systemImage)
                .foregroundStyle(movementType == .inbound ? Color.appSuccess : Color.appWarning)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(movement.materialName)
                    .font(.callout.weight(.medium))
                Text([movement.specification, movement.counterparty, movement.handler].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !movement.linkedDocumentIds.isEmpty {
                    Label(
                        String(format: AppLocalization.string("%lld 个附件"), Int64(movement.linkedDocumentIds.count)),
                        systemImage: "paperclip"
                    )
                        .font(.caption2)
                        .foregroundStyle(Color.appDoc)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(movementType == .inbound ? "+" : "-")\(movement.quantity) \(movement.unit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(movementType == .inbound ? Color.appSuccess : Color.appWarning)
                Text(movement.date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: AppLocalization.string("%@，%@，%@%@，日期 %@"),
                movementType.displayName,
                movement.materialName,
                movement.quantity.wireText,
                movement.unit,
                movement.date.storageText
            )
        )
        .accessibilityHint(AppLocalization.string("双击查看出入库详情"))
    }
}
