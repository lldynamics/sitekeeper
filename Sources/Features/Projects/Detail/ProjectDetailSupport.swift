import SwiftUI

struct ProjectDrawingTimelineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drawingName: String
    let drawings: [ProjectDrawing]
    let onSetCurrent: (ProjectDrawing) -> Void
    let onPreview: (ProjectDrawing) -> Void
    let onEdit: (ProjectDrawing) -> Void

    var body: some View {
        NavigationStack {
            List {
                if drawings.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.string("暂无版本记录"),
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text(AppLocalization.string("同名图纸导入新版本后，可在这里查看版本时间线。"))
                    )
                } else {
                    ForEach(drawings) { drawing in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(drawing.version).font(.callout.weight(.semibold))
                        if drawing.isCurrentVersion {
                            Text(AppLocalization.string("当前版"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appSuccess)
                        }
                        Spacer()
                        Text(Formatters.displayDateText(drawing.importedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    FlowTagLine(tags: drawingTimelineTags(for: drawing))
                    if !drawing.relatedLogDate.isEmpty {
                        Text(String(format: AppLocalization.string("关联日志: %@"), drawing.relatedLogDate.storageText))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                            if drawing.issueStatus != .none {
                                Text(String(format: AppLocalization.string("状态: %@"), drawing.issueStatus.displayName))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryAction)
                            }
                            if !drawing.issueNote.isEmpty {
                                Text(String(format: AppLocalization.string("问题: %@"), drawing.issueNote))
                                    .font(.caption2)
                                    .foregroundStyle(.appRisk)
                            }
                            HStack(spacing: 16) {
                                Button(AppLocalization.string("打开")) {
                                    onPreview(drawing)
                                }
                                .font(.caption)
                                Button(AppLocalization.string("编辑")) {
                                    onEdit(drawing)
                                    dismiss()
                                }
                                .font(.caption)
                                if !drawing.isCurrentVersion {
                                    Button(AppLocalization.string("设为当前版")) {
                                        onSetCurrent(drawing)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(String(format: AppLocalization.string("%@ 时间线"), drawingName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("关闭")) { dismiss() }
                }
            }
        }
    }

    private func drawingTimelineTags(for drawing: ProjectDrawing) -> [String] {
        [
            drawing.drawingNumber.isEmpty ? "" : String(format: AppLocalization.string("图号: %@"), drawing.drawingNumber),
            drawing.discipline,
            drawing.floorArea,
            drawing.issuedAt.isEmpty ? "" : String(format: AppLocalization.string("出图: %@"), drawing.issuedAt.storageText),
            drawing.receiver.isEmpty ? "" : String(format: AppLocalization.string("接收: %@"), drawing.receiver)
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
