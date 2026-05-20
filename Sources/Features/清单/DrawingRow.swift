import SwiftUI

struct DrawingRow: View {
    let drawing: ProjectDrawing
    let projectName: String?
    let onOpen: () -> Void

    private var title: String {
        drawing.name.isEmpty ? drawing.fileName : drawing.name
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: AppSpacing.normal) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.appDoc)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if drawing.isCurrentVersion {
                            Text(String(localized: "当前版"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appSuccess)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appSuccess.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(openStatus.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(openStatus.isReady ? Color.appSuccess : Color.appWarning)
                    if let failureText = ProjectDetailDrawingHelper.externalOpenFailureLine(for: drawing) {
                        Text(failureText)
                            .font(.caption2)
                            .foregroundStyle(Color.appWarning)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: AppSpacing.tight)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var detailText: String {
        var parts = [String]()
        if let projectName {
            parts.append(projectName)
        }
        if !drawing.drawingNumber.isEmpty {
            parts.append(String(format: String(localized: "图号 %@"), drawing.drawingNumber))
        }
        if !drawing.discipline.isEmpty {
            parts.append(drawing.discipline)
        }
        if !drawing.floorArea.isEmpty {
            parts.append(drawing.floorArea)
        }
        parts.append(drawing.version)
        if !drawing.issuedAt.isEmpty {
            parts.append(String(format: String(localized: "出图 %@"), drawing.issuedAt))
        }
        if !drawing.receiver.isEmpty {
            parts.append(String(format: String(localized: "接收 %@"), drawing.receiver))
        }
        parts.append(drawing.fileType.uppercased())
        if !drawing.importedAt.isEmpty {
            parts.append(String(format: String(localized: "导入 %@"), drawing.importedAt))
        }
        let linkCount = drawing.linkedTodoIDs.count + drawing.linkedLogIDs.count + drawing.linkedDocumentIDs.count
        if linkCount > 0 {
            parts.append(String(format: String(localized: "关联 %lld"), Int64(linkCount)))
        }
        return parts.joined(separator: " · ")
    }

    private var icon: String {
        switch drawing.fileType.lowercased() {
        case "pdf":
            return "doc.richtext.fill"
        case "dwg", "dxf":
            return "compass.drawing"
        default:
            return "doc.viewfinder"
        }
    }

    private var openStatus: (text: String, isReady: Bool) {
        ProjectDetailDrawingHelper.fileAvailabilityLine(for: drawing)
    }

    private var accessibilityLabel: String {
        if ProjectDetailDrawingHelper.requiresExternalViewer(drawing.fileType) {
            return String(format: String(localized: "用外部专业看图软件打开 %@"), title)
        }
        return String(format: String(localized: "打开图纸原件 %@"), title)
    }
}
