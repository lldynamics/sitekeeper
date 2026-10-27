import SwiftUI

struct ProjectDrawingSectionView: View {
    @Binding var drawingFilter: DrawingListFilter
    let relatedDrawings: [ProjectDrawing]
    let filteredDrawings: [ProjectDrawing]
    let icon: (String) -> String
    let onImportDrawing: () -> Void
    let onEdit: (ProjectDrawing) -> Void
    let onTimeline: (ProjectDrawing) -> Void
    let onPreview: (ProjectDrawing) -> Void
    let onDelete: (ProjectDrawing) -> Void
    @State private var showHistoricalDrawings = false

    private var currentVersionDrawings: [ProjectDrawing] {
        filteredDrawings.filter(\.isCurrentVersion)
    }

    private var historicalDrawings: [ProjectDrawing] {
        filteredDrawings.filter { !$0.isCurrentVersion }
    }

    var body: some View {
        ProjectDetailAnchoredSection(String(format: AppLocalization.string("图纸 (%lld)"), Int64(relatedDrawings.count)), anchor: .assets) {
            Picker(AppLocalization.string("筛选"), selection: $drawingFilter) {
                ForEach(DrawingListFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            if relatedDrawings.isEmpty {
                ProjectInlineEmptyState(
                    AppLocalization.string("还没有图纸"),
                    systemImage: "doc.viewfinder",
                    detail: AppLocalization.string("可上传 DWG、DXF、PDF；PDF 可系统预览，DWG/DXF 原件需通过外部专业看图软件打开。")
                )
                Button(action: onImportDrawing) {
                    Label(AppLocalization.string("导图纸"), systemImage: "doc.viewfinder.fill")
                }
                .buttonStyle(.appProminent())
            } else if filteredDrawings.isEmpty {
                Button(action: onImportDrawing) {
                    Label(AppLocalization.string("导图纸"), systemImage: "doc.viewfinder.fill")
                }
                ProjectInlineEmptyState(AppLocalization.string("没有匹配图纸"), systemImage: "line.3.horizontal.decrease.circle")
            } else {
                Button(action: onImportDrawing) {
                    Label(AppLocalization.string("导图纸"), systemImage: "doc.viewfinder.fill")
                }
                if drawingFilter == .all {
                    if !currentVersionDrawings.isEmpty {
                        ForEach(currentVersionDrawings) { drawing in
                            drawingRow(drawing)
                        }
                    }
                    if !historicalDrawings.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHistoricalDrawings.toggle()
                            }
                        } label: {
                            HStack {
                                Label(String(format: AppLocalization.string("历史版本 (%lld)"), Int64(historicalDrawings.count)), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                Spacer()
                                Image(systemName: showHistoricalDrawings ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if showHistoricalDrawings {
                            ForEach(historicalDrawings) { drawing in
                                drawingRow(drawing)
                            }
                        }
                    }
                } else {
                    ForEach(filteredDrawings) { drawing in
                        drawingRow(drawing)
                    }
                }
            }
        }
    }

    private func drawingRow(_ drawing: ProjectDrawing) -> some View {
        Button {
            onEdit(drawing)
        } label: {
            HStack(spacing: AppSpacing.normal) {
                Image(systemName: icon(drawing.fileType))
                    .foregroundStyle(Color.appDoc)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(drawingDisplayName(for: drawing))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(drawing.version)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                        if drawing.isCurrentVersion {
                            Text(AppLocalization.string("当前版"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appSuccess)
                        } else {
                            Text(AppLocalization.string("历史版"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(drawing.fileType.uppercased()) · \(Formatters.displayDateText(drawing.importedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    FlowTagLine(tags: drawingLedgerTags(for: drawing))
                    if let linkSummary = drawingLinkSummary(for: drawing) {
                        Text(linkSummary)
                            .font(.caption2)
                            .foregroundStyle(Color.appPrimaryAction)
                            .lineLimit(1)
                    }
                    let status = openStatus(for: drawing)
                    if let statusText = status.text {
                        Text(statusText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(status.isReady ? Color.appSuccess : Color.appWarning)
                    }
                    if let failureText = ProjectDetailDrawingHelper.externalOpenFailureLine(for: drawing) {
                        Text(failureText)
                            .font(.caption2)
                            .foregroundStyle(Color.appWarning)
                            .lineLimit(2)
                    }
                    if !drawing.relatedLogDate.isEmpty {
                        Text(String(format: AppLocalization.string("关联日志: %@"), drawing.relatedLogDate.storageText))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if drawing.issueStatus != .none {
                        Text(String(format: AppLocalization.string("状态: %@"), drawing.issueStatus.displayName))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appWarning)
                    }
                    if !drawing.issueNote.isEmpty {
                        Text(String(format: AppLocalization.string("问题: %@"), drawing.issueNote))
                            .font(.caption2)
                            .foregroundStyle(Color.appRisk)
                            .lineLimit(1)
                    }
                    if !drawing.note.isEmpty {
                        Text(drawing.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTimeline(drawing)
            } label: {
                Label(AppLocalization.string("查看版本时间线"), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
            Button {
                onPreview(drawing)
            } label: {
                Label(openActionTitle(for: drawing), systemImage: "square.and.arrow.up")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete(drawing)
            } label: {
                Label(AppLocalization.string("删除"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onPreview(drawing)
            } label: {
                Label(openSwipeTitle(for: drawing), systemImage: "square.and.arrow.up")
            }
            .tint(Color.appDoc)
        }
    }

    private func drawingDisplayName(for drawing: ProjectDrawing) -> String {
        let trimmed = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return drawing.fileName
    }

    private func drawingLedgerTags(for drawing: ProjectDrawing) -> [String] {
        [
            drawing.drawingNumber.isEmpty ? "" : String(format: AppLocalization.string("图号: %@"), drawing.drawingNumber),
            drawing.discipline.isEmpty ? "" : String(format: AppLocalization.string("专业: %@"), drawing.discipline),
            drawing.floorArea.isEmpty ? "" : String(format: AppLocalization.string("楼层/区域: %@"), drawing.floorArea),
            drawing.issuedAt.isEmpty ? "" : String(format: AppLocalization.string("出图: %@"), drawing.issuedAt.storageText),
            drawing.receiver.isEmpty ? "" : String(format: AppLocalization.string("接收: %@"), drawing.receiver)
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func drawingLinkSummary(for drawing: ProjectDrawing) -> String? {
        let parts = [
            drawing.linkedTodoIDs.isEmpty ? "" : String(format: AppLocalization.string("待办 %lld"), Int64(drawing.linkedTodoIDs.count)),
            drawing.linkedLogIDs.isEmpty ? "" : String(format: AppLocalization.string("日志 %lld"), Int64(drawing.linkedLogIDs.count)),
            drawing.linkedDocumentIDs.isEmpty ? "" : String(format: AppLocalization.string("资料 %lld"), Int64(drawing.linkedDocumentIDs.count))
        ]
        .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return String(format: AppLocalization.string("关联: %@"), parts.joined(separator: " · "))
    }

    private func openStatus(for drawing: ProjectDrawing) -> (text: String?, isReady: Bool) {
        let status = ProjectDetailDrawingHelper.fileAvailabilityLine(for: drawing)
        return (status.text, status.isReady)
    }

    private func openActionTitle(for drawing: ProjectDrawing) -> String {
        ProjectDetailDrawingHelper.requiresExternalViewer(drawing.fileType)
            ? AppLocalization.string("用外部专业看图软件打开")
            : AppLocalization.string("打开原件")
    }

    private func openSwipeTitle(for drawing: ProjectDrawing) -> String {
        ProjectDetailDrawingHelper.requiresExternalViewer(drawing.fileType)
            ? AppLocalization.string("外部专业看图")
            : AppLocalization.string("打开")
    }
}
