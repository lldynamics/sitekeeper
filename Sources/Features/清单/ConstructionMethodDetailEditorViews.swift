import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

private let constructionMethodDeleteUndoHint = String(localized: "删除后可在提示中撤销，附件会延迟清理。")

private func constructionMethodShareText(_ method: ConstructionMethod) -> String {
    let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未命名工艺") : method.title
    let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未分类") : method.trade
    let steps = method.procedureSteps.isEmpty ? String(localized: "暂无") : method.procedureSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let quality = method.qualityChecklist.isEmpty ? String(localized: "暂无") : method.qualityChecklist.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let safety = method.safetyChecklist.isEmpty ? String(localized: "暂无") : method.safetyChecklist.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let tutorial = method.tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "暂无") : method.tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
    return """
    \(title)
    \(String(format: String(localized: "专业：%@"), trade))
    \(String(format: String(localized: "版本：%@"), method.versionName.isEmpty ? "V1" : method.versionName))
    \(String(format: String(localized: "状态：%@"), method.publishStatus.displayName))
    \(String(format: String(localized: "更新：%@"), method.updatedAt))

    \(String(localized: "施工步骤："))
    \(steps)

    \(String(localized: "质量检查项："))
    \(quality)

    \(String(localized: "安全注意项："))
    \(safety)

    \(String(localized: "完整教程："))
    \(tutorial)
    """
}

struct ConstructionMethodDetailInlineView: View {
    @Environment(DataStore.self) private var store
    let methodID: UUID
    let onDelete: (ConstructionMethod) -> Void
    let onSave: (ConstructionMethod) -> Void
    @State private var editingMethod: ConstructionMethod?
    @State private var previewAttachment: QuickNoteAttachment?
    @State private var showDeleteConfirm = false

    private var method: ConstructionMethod? {
        store.constructionMethods.first(where: { $0.id == methodID })
    }

    var body: some View {
        Group {
            if let method {
                ConstructionMethodDetailContent(
                    method: method,
                    onPreviewAttachment: { previewAttachment = $0 }
                )
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ShareLink(item: constructionMethodShareText(method)) {
                                Label(String(localized: "分享"), systemImage: "square.and.arrow.up")
                            }
                            Button(String(localized: "编辑")) { editingMethod = method }
                            Button(String(localized: "删除"), role: .destructive) { showDeleteConfirm = true }
                        }
                    }
            } else {
                ContentUnavailableView(String(localized: "工艺不存在"), systemImage: "exclamationmark.triangle")
            }
        }
        .sheet(item: $editingMethod) { method in
            ConstructionMethodEditSheet(method: method) { updated in
                onSave(updated)
                editingMethod = nil
            } onDelete: { target in
                onDelete(target)
                editingMethod = nil
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            QuickNoteAttachmentPreview(attachment: attachment)
        }
        .alert(String(localized: "删除这条施工工艺？"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive) {
                if let method {
                    onDelete(method)
                }
            }
        } message: {
            Text(constructionMethodDeleteUndoHint)
        }
    }
}

struct ConstructionMethodDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let methodID: UUID
    let onEdit: (ConstructionMethod) -> Void
    let onDelete: (ConstructionMethod) -> Void
    let onSave: (ConstructionMethod) -> Void

    @State private var previewAttachment: QuickNoteAttachment?
    @State private var editingMethod: ConstructionMethod?
    @State private var showDeleteConfirm = false

    private var method: ConstructionMethod? {
        store.constructionMethods.first(where: { $0.id == methodID })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let method {
                    ConstructionMethodDetailContent(method: method, onPreviewAttachment: { previewAttachment = $0 })
                } else {
                        ContentUnavailableView(String(localized: "工艺不存在"), systemImage: "exclamationmark.triangle")
                        .task(id: method?.id) {
                            guard method == nil else { return }
                            guard await DebouncedTask.wait(for: .milliseconds(200)) else { return }
                            dismiss()
                        }
                }
            }
            .navigationTitle(String(localized: "施工工艺"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
                if let method {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: constructionMethodShareText(method)) {
                            Label(String(localized: "分享"), systemImage: "square.and.arrow.up")
                        }
                        Button(String(localized: "编辑")) {
                            onEdit(method)
                            editingMethod = method
                        }
                        Button(String(localized: "删除"), role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .sheet(item: $editingMethod) { method in
                ConstructionMethodEditSheet(method: method) { updated in
                    onSave(updated)
                    editingMethod = nil
                } onDelete: { target in
                    onDelete(target)
                    editingMethod = nil
                    dismiss()
                }
            }
            .sheet(item: $previewAttachment) { attachment in
                QuickNoteAttachmentPreview(attachment: attachment)
            }
            .alert(String(localized: "删除这条施工工艺？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    if let method {
                        onDelete(method)
                        dismiss()
                    }
                }
            } message: {
                Text(constructionMethodDeleteUndoHint)
            }
        }
    }
}

private struct ConstructionMethodDetailContent: View {
    @Environment(DataStore.self) private var store
    let method: ConstructionMethod
    var onPreviewAttachment: ((QuickNoteAttachment) -> Void)? = nil
    @State private var showOnlyPendingItems = false
    @State private var referenceAction: ConstructionMethodReferenceAction?
    @State private var operationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(method.title.isEmpty ? String(localized: "未命名工艺") : method.title)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 10) {
                        Label(method.trade.isEmpty ? String(localized: "未分类") : method.trade, systemImage: "tag")
                        Label(method.versionName.isEmpty ? "V1" : method.versionName, systemImage: "number")
                        Label(method.publishStatus.displayName, systemImage: method.publishStatus == .published ? "checkmark.seal.fill" : "doc.badge.clock")
                        Label(String(format: String(localized: "更新于 %@"), method.updatedAt), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Toggle(String(localized: "仅看未完成"), isOn: $showOnlyPendingItems)
                        .toggleStyle(.switch)
                        .font(.callout)
                }
                ConstructionMethodReferenceBlock { action in
                    referenceAction = action
                }
                ConstructionMethodDetailBlock(
                    title: String(localized: "施工步骤"),
                    systemImage: "list.number",
                    lines: method.procedureSteps,
                    isCheckable: true,
                    showOnlyPendingItems: showOnlyPendingItems
                )
                ConstructionMethodDetailBlock(
                    title: String(localized: "质量标准"),
                    systemImage: "checkmark.seal",
                    lines: method.qualityChecklist,
                    isCheckable: true,
                    showOnlyPendingItems: showOnlyPendingItems
                )
                ConstructionMethodDetailBlock(
                    title: String(localized: "安全注意"),
                    systemImage: "shield.lefthalf.filled",
                    lines: method.safetyChecklist,
                    isCheckable: true,
                    showOnlyPendingItems: showOnlyPendingItems
                )
                ConstructionMethodTutorialBlock(
                    tutorialBody: method.tutorialBody,
                    attachments: method.tutorialAttachments,
                    onPreviewAttachment: onPreviewAttachment
                )
            }
            .padding(16)
        }
        .sheet(item: $referenceAction) { action in
            ConstructionMethodReferenceSheet(
                method: method,
                action: action,
                projects: store.projects,
                onSave: createReference(_:projectId:)
            )
        }
        .operationToast(message: $operationMessage)
    }

    @MainActor
    private func createReference(_ action: ConstructionMethodReferenceAction, projectId: UUID?) {
        switch action {
        case .todo:
            store.insertSiteTodoAtTop(
                SiteTodo(
                    title: String(format: String(localized: "按工艺检查：%@"), methodDisplayTitle(method)),
                    dueDate: Formatters.date.string(from: Date()),
                    priority: .medium,
                    issueType: .quality,
                    note: constructionMethodReferenceText(method),
                    linkedConstructionMethodIDs: [method.id],
                    projectId: projectId
                )
            )
            operationMessage = String(localized: "已生成现场待办")
        case .dailyLog:
            store.insertDailyLogAtTop(
                DailyLog(
                    date: Formatters.date.string(from: Date()),
                    weather: autoWeatherNow(),
                    content: String(format: String(localized: "引用施工工艺：%@\n\n%@"), methodDisplayTitle(method), constructionMethodReferenceText(method)),
                    workers: "0",
                    safety: method.safetyChecklist.joined(separator: "\n"),
                    tomorrowPlan: String(format: String(localized: "按《%@》复核现场执行情况"), methodDisplayTitle(method)),
                    qualityIssue: "",
                    rectification: "",
                    linkedConstructionMethodIDs: [method.id],
                    projectId: projectId
                )
            )
            operationMessage = String(localized: "已生成施工日志")
        case .rectification:
            store.insertSiteTodoAtTop(
                SiteTodo(
                    title: String(format: String(localized: "整改复核：%@"), methodDisplayTitle(method)),
                    dueDate: Formatters.date.string(from: Date()),
                    priority: .high,
                    issueType: .quality,
                    note: String(format: String(localized: "整改依据：\n%@"), constructionMethodReferenceText(method)),
                    linkedConstructionMethodIDs: [method.id],
                    projectId: projectId
                )
            )
            operationMessage = String(localized: "已生成整改待办")
        }
        store.scheduleSave()
        AppHaptics.success()
    }
}

private enum ConstructionMethodReferenceAction: String, CaseIterable, Identifiable {
    case todo
    case dailyLog
    case rectification

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo:
            return String(localized: "生成待办")
        case .dailyLog:
            return String(localized: "写入日志")
        case .rectification:
            return String(localized: "生成整改")
        }
    }

    var detail: String {
        switch self {
        case .todo:
            return String(localized: "用于现场检查、复核或安排执行")
        case .dailyLog:
            return String(localized: "把工艺依据写入今天的施工日志")
        case .rectification:
            return String(localized: "生成质量整改待办并关联该工艺")
        }
    }

    var systemImage: String {
        switch self {
        case .todo:
            return "checklist.checked"
        case .dailyLog:
            return "book.pages.fill"
        case .rectification:
            return "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .todo:
            return .appDoc
        case .dailyLog:
            return .appSuccess
        case .rectification:
            return .appRisk
        }
    }
}

private struct ConstructionMethodReferenceBlock: View {
    let onSelect: (ConstructionMethodReferenceAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(String(localized: "引用到现场"), systemImage: "link.badge.plus")
                .font(.headline)
            Text(String(localized: "把这条工艺直接变成待办、日志或整改依据。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: AppSpacing.tight) {
                ForEach(ConstructionMethodReferenceAction.allCases) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: action.systemImage)
                                .font(.headline)
                            Text(action.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .tint(action.tint)
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.detail)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ConstructionMethodReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let method: ConstructionMethod
    let action: ConstructionMethodReferenceAction
    let projects: [Project]
    let onSave: (ConstructionMethodReferenceAction, UUID?) -> Void

    @State private var selectedProjectId: UUID?

    private var sortedProjects: [Project] {
        projects.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "工艺")) {
                    LabeledContent(String(localized: "名称"), value: methodDisplayTitle(method))
                    LabeledContent(String(localized: "专业"), value: method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未分类") : method.trade)
                    LabeledContent(String(localized: "动作"), value: action.title)
                }
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "项目"), selection: $selectedProjectId) {
                        Text(String(localized: "不关联项目")).tag(nil as UUID?)
                        ForEach(sortedProjects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section(String(localized: "将写入")) {
                    Text(action.detail)
                        .font(.callout)
                    Text(constructionMethodReferenceText(method))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "生成")) {
                        onSave(action, selectedProjectId)
                        dismiss()
                    }
                }
            }
        }
    }
}

private func methodDisplayTitle(_ method: ConstructionMethod) -> String {
    let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? String(localized: "未命名工艺") : title
}

private func constructionMethodReferenceText(_ method: ConstructionMethod) -> String {
    var sections: [String] = []
    let title = methodDisplayTitle(method)
    let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
    sections.append(String(format: String(localized: "工艺：%@"), title))
    if !trade.isEmpty {
        sections.append(String(format: String(localized: "专业：%@"), trade))
    }
    if !method.versionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        sections.append(String(format: String(localized: "版本：%@"), method.versionName))
    }
    if !method.procedureSteps.isEmpty {
        sections.append(String(format: String(localized: "施工步骤：\n%@"), numberedLines(method.procedureSteps)))
    }
    if !method.qualityChecklist.isEmpty {
        sections.append(String(format: String(localized: "质量要点：\n%@"), numberedLines(method.qualityChecklist)))
    }
    if !method.safetyChecklist.isEmpty {
        sections.append(String(format: String(localized: "安全注意：\n%@"), numberedLines(method.safetyChecklist)))
    }
    return sections.joined(separator: "\n\n")
}

private func numberedLines(_ lines: [String]) -> String {
    lines
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .enumerated()
        .map { "\($0.offset + 1). \($0.element)" }
        .joined(separator: "\n")
}

private struct ConstructionMethodTutorialBlock: View {
    let tutorialBody: String
    let attachments: [QuickNoteAttachment]
    var onPreviewAttachment: ((QuickNoteAttachment) -> Void)? = nil

    private var normalizedBody: String {
        tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var renderedBody: AttributedString {
        if let markdown = try? AttributedString(markdown: normalizedBody) {
            return markdown
        }
        return AttributedString(normalizedBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "完整教程"), systemImage: "doc.text")
                .font(.headline)
            if normalizedBody.isEmpty {
                Text(String(localized: "未填写完整教程。可在编辑页补充从准备到验收的全流程说明。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(renderedBody)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if !attachments.isEmpty {
                ConstructionMethodAttachmentCarousel(
                    attachments: attachments,
                    onPreview: { attachment in
                        onPreviewAttachment?(attachment)
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ConstructionMethodAttachmentCarousel: View {
    let attachments: [QuickNoteAttachment]
    let onPreview: (QuickNoteAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachments) { attachment in
                    Button {
                        onPreview(attachment)
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                            if let image = previewImage(for: attachment) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: attachment.attachmentKind.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            if attachment.attachmentKind == .video {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.45))
                                    .padding(8)
                            }
                        }
                        .frame(width: 220, height: 144)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func previewImage(for attachment: QuickNoteAttachment) -> UIImage? {
        switch attachment.attachmentKind {
        case .photo, .drawing:
            guard let data = QuickNoteAttachmentStorage.data(for: attachment.fileName) else { return nil }
            return UIImage(data: data)
        case .video:
            return QuickNoteAttachmentStorage.videoThumbnail(for: attachment.fileName)
        case .audio, .file:
            return nil
        }
    }
}

private struct ConstructionMethodDetailBlock: View {
    let title: String
    let systemImage: String
    let lines: [String]
    var isCheckable = false
    var showOnlyPendingItems = false

    @State private var checkedIndexes: Set<Int> = []
    @State private var showCompletedItems = false

    private var sanitizedLines: [String] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var completedCount: Int {
        checkedIndexes.intersection(Set(sanitizedLines.indices)).count
    }

    private var pendingIndexes: [Int] {
        sanitizedLines.indices.filter { !checkedIndexes.contains($0) }
    }

    private var completedIndexes: [Int] {
        sanitizedLines.indices.filter { checkedIndexes.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if isCheckable, !sanitizedLines.isEmpty {
                    Text("\(completedCount)/\(sanitizedLines.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button(String(localized: "重置")) { checkedIndexes.removeAll() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                }
            }
            if sanitizedLines.isEmpty {
                Text(String(localized: "未填写"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if isCheckable {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pendingIndexes, id: \.self) { index in
                            checkableLineRow(index: index, line: sanitizedLines[index], isChecked: false)
                        }
                        if showOnlyPendingItems {
                            if !completedIndexes.isEmpty {
                                Text(String(format: String(localized: "已隐藏 %lld 项已完成内容"), Int64(completedIndexes.count)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if !completedIndexes.isEmpty {
                                DisclosureGroup(String(format: String(localized: "已完成 %lld 项"), Int64(completedIndexes.count)), isExpanded: $showCompletedItems) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(completedIndexes, id: \.self) { index in
                                            checkableLineRow(index: index, line: sanitizedLines[index], isChecked: true)
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                                .font(.caption)
                                .tint(.secondary)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(sanitizedLines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                Text(line)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
        .onChange(of: sanitizedLines) { _, _ in
            checkedIndexes.removeAll()
            showCompletedItems = false
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggleChecked(_ index: Int) {
        if checkedIndexes.contains(index) {
            checkedIndexes.remove(index)
        } else {
            checkedIndexes.insert(index)
        }
    }

    @ViewBuilder
    private func checkableLineRow(index: Int, line: String, isChecked: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                toggleChecked(index)
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            Text(line)
                .frame(maxWidth: .infinity, alignment: .leading)
                .strikethrough(isChecked, color: .secondary)
                .foregroundStyle(isChecked ? .secondary : .primary)
        }
        .font(.callout)
    }
}

struct ConstructionMethodAttachmentMiniStrip: View {
    let attachments: [QuickNoteAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments.prefix(3)) { attachment in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                        if let image = previewImage(for: attachment) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: attachment.attachmentKind.systemImage)
                                .foregroundStyle(.secondary)
                        }
                        if attachment.attachmentKind == .video {
                            Image(systemName: "play.circle.fill")
                                .font(.caption)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if attachments.count > 3 {
                    Text("+\(attachments.count - 3)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.top, 2)
        }
    }

    private func previewImage(for attachment: QuickNoteAttachment) -> UIImage? {
        switch attachment.attachmentKind {
        case .photo, .drawing:
            guard let data = QuickNoteAttachmentStorage.data(for: attachment.fileName) else { return nil }
            return UIImage(data: data)
        case .video:
            return QuickNoteAttachmentStorage.videoThumbnail(for: attachment.fileName)
        case .audio, .file:
            return nil
        }
    }
}

struct ConstructionMethodEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let method: ConstructionMethod?
    private let draftScopeID: UUID
    let onSave: (ConstructionMethod) -> Void
    var onDelete: ((ConstructionMethod) -> Void)?

    @State private var title: String
    @State private var trade: String
    @State private var versionName: String
    @State private var publishStatus: ConstructionMethod.PublishStatus
    @State private var tutorialBody: String
    @State private var tutorialAttachments: [QuickNoteAttachment]
    @State private var procedureSteps: [String]
    @State private var qualityChecklist: [String]
    @State private var safetyChecklist: [String]
    @State private var newProcedureStep = ""
    @State private var newQualityItem = ""
    @State private var newSafetyItem = ""
    @State private var attachments: [QuickNoteAttachment]
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var selectedTutorialMediaItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showTutorialCamera = false
    @State private var previewAttachment: QuickNoteAttachment?
    @State private var isImportingMedia = false
    @State private var mediaImportMessage = ""
    @State private var isImportingTutorialMedia = false
    @State private var tutorialMediaImportMessage = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showDeleteConfirm = false
    @State private var sessionAddedFileNames: Set<String> = []
    @State private var didSave = false
    @State private var didRestoreDraft = false
    @State private var draftSaveTask: Task<Void, Never>?

    init(method: ConstructionMethod?, onSave: @escaping (ConstructionMethod) -> Void, onDelete: ((ConstructionMethod) -> Void)? = nil) {
        self.method = method
        self.draftScopeID = method?.id ?? UUID()
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: method?.title ?? "")
        _trade = State(initialValue: method?.trade ?? "")
        _versionName = State(initialValue: method?.versionName ?? "V1")
        _publishStatus = State(initialValue: method?.publishStatus ?? .draft)
        _tutorialBody = State(initialValue: method?.tutorialBody ?? "")
        _tutorialAttachments = State(initialValue: method?.tutorialAttachments ?? [])
        _procedureSteps = State(initialValue: method?.procedureSteps ?? [])
        _qualityChecklist = State(initialValue: method?.qualityChecklist ?? [])
        _safetyChecklist = State(initialValue: method?.safetyChecklist ?? [])
        _attachments = State(initialValue: method?.attachments ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                processSections
                tutorialSections
                qualitySections
            }
            .navigationTitle(method == nil ? String(localized: "新增施工工艺") : String(localized: "编辑施工工艺"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                restoreDraftIfNeeded()
            }
            .onDisappear {
                draftSaveTask?.cancel()
                if didSave {
                    ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                    return
                }
                if hasDraftContent {
                    persistDraftImmediately()
                } else {
                    ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                    DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                        Array(sessionAddedFileNames),
                        summary: "constructionMethodEditor.sessionAddedFiles"
                    )?.perform()
                }
            }
            .onChange(of: draftAutosaveFingerprint) { _, _ in
                scheduleDraftSave()
            }
            .onChange(of: scenePhase) { _, phase in
                guard !didSave else { return }
                if phase == .inactive || phase == .background {
                    draftSaveTask?.cancel()
                    persistDraftImmediately()
                }
            }
            .onChange(of: selectedMediaItems) { _, newItems in
                Task { await importMediaItems(newItems, target: .general) }
            }
            .onChange(of: selectedTutorialMediaItems) { _, newItems in
                Task { await importMediaItems(newItems, target: .tutorial) }
            }
            .sheet(isPresented: $showCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    appendImageAttachment(image)
                }
            }
            .sheet(isPresented: $showTutorialCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    appendTutorialImageAttachment(image)
                }
            }
            .sheet(item: $previewAttachment) { attachment in
                QuickNoteAttachmentPreview(attachment: attachment)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        draftSaveTask?.cancel()
                        if hasDraftContent {
                            persistDraftImmediately()
                        } else {
                            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                        }
                        dismiss()
                    }
                }
                if method != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        draftSaveTask?.cancel()
                        didSave = true
                        onSave(updatedMethod)
                        ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(String(localized: "删除这条施工工艺？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    draftSaveTask?.cancel()
                    ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                    if let target = method { onDelete?(target) }
                    dismiss()
                }
            } message: {
                Text(constructionMethodDeleteUndoHint)
            }
            .alert(String(localized: "无法添加媒体"), isPresented: $showAlert) {
                Button(String(localized: "知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var stepTemplates: [String] {
        [
            String(localized: "现场交底"),
            String(localized: "材料进场验收"),
            String(localized: "放线定位"),
            String(localized: "分步施工"),
            String(localized: "隐蔽验收"),
            String(localized: "成品保护")
        ]
    }

    private var basicInfoSection: some View {
        Section(String(localized: "工艺信息")) {
            TextField(String(localized: "标题"), text: $title)
            TextField(String(localized: "专业/工种"), text: $trade)
            TextField(String(localized: "版本号"), text: $versionName)
            Picker(String(localized: "发布状态"), selection: $publishStatus) {
                ForEach(ConstructionMethod.PublishStatus.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
    }

    private var processSections: some View {
        Group {
            Section(String(localized: "施工步骤")) {
                if procedureSteps.isEmpty {
                    Text(String(localized: "暂无步骤，先新增一条。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(procedureSteps.indices, id: \.self) { index in
                    procedureStepRow(index)
                }
                addItemRow(
                    placeholder: String(localized: "新增步骤"),
                    text: $newProcedureStep,
                    onAdd: appendProcedureStep
                )
            }
            Section(String(localized: "常用步骤模板")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stepTemplates, id: \.self) { template in
                            Button(template) { applyStepTemplate(template) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var tutorialSections: some View {
        ConstructionMethodTutorialEditorSections(
            didRestoreDraft: didRestoreDraft,
            tutorialBody: $tutorialBody,
            selectedTutorialMediaItems: $selectedTutorialMediaItems,
            isImportingTutorialMedia: isImportingTutorialMedia,
            tutorialMediaImportMessage: tutorialMediaImportMessage,
            tutorialAttachments: tutorialAttachments,
            onInsertBlock: appendTutorialBlock,
            onOpenCamera: openTutorialCamera,
            onPreviewAttachment: { previewAttachment = $0 },
            onRemoveAttachment: removeTutorialAttachment
        )
    }

    private var qualitySections: some View {
        Group {
            Section(String(localized: "质量检查项")) {
                if qualityChecklist.isEmpty {
                    Text(String(localized: "暂无质量检查项。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(qualityChecklist.indices, id: \.self) { index in
                    qualityItemRow(index)
                }
                addItemRow(
                    placeholder: String(localized: "新增质量检查项"),
                    text: $newQualityItem,
                    onAdd: appendQualityItem
                )
            }
            Section(String(localized: "安全注意项")) {
                if safetyChecklist.isEmpty {
                    Text(String(localized: "暂无安全注意项。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(safetyChecklist.indices, id: \.self) { index in
                    safetyItemRow(index)
                }
                addItemRow(
                    placeholder: String(localized: "新增安全注意项"),
                    text: $newSafetyItem,
                    onAdd: appendSafetyItem
                )
            }
        }
    }

    private var hasDraftContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !procedureSteps.isEmpty
            || !qualityChecklist.isEmpty
            || !safetyChecklist.isEmpty
            || !attachments.isEmpty
            || !tutorialAttachments.isEmpty
    }

    private var draftAutosaveFingerprint: String {
        [
            title,
            trade,
            versionName,
            publishStatus.rawValue,
            tutorialBody,
            procedureSteps.joined(separator: "\n"),
            qualityChecklist.joined(separator: "\n"),
            safetyChecklist.joined(separator: "\n"),
            attachments.map(\.fileName).joined(separator: "|"),
            tutorialAttachments.map(\.fileName).joined(separator: "|")
        ].joined(separator: "||")
    }

    private var currentDraftSnapshot: ConstructionMethodEditDraft {
        ConstructionMethodEditDraft(
            title: title,
            trade: trade,
            versionName: versionName,
            publishStatus: publishStatus,
            tutorialBody: tutorialBody,
            tutorialAttachments: tutorialAttachments,
            procedureSteps: procedureSteps,
            qualityChecklist: qualityChecklist,
            safetyChecklist: safetyChecklist,
            attachments: attachments,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private var updatedMethod: ConstructionMethod {
        var value = method ?? ConstructionMethod()
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.trade = trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVersion = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.versionName = normalizedVersion.isEmpty ? "V1" : normalizedVersion
        value.publishStatus = publishStatus
        value.tutorialBody = tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        value.tutorialTextSize = .normal
        value.tutorialAttachments = tutorialAttachments
        value.procedureSteps = normalizeList(procedureSteps)
        value.qualityChecklist = normalizeList(qualityChecklist)
        value.safetyChecklist = normalizeList(safetyChecklist)
        value.attachments = attachments
        value.updatedAt = Formatters.now()
        return value
    }

    private func applyStepTemplate(_ template: String) {
        let normalized = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !procedureSteps.contains(normalized) else { return }
        procedureSteps.append(normalized)
    }

    private func appendTutorialBlock(_ block: String) {
        let content = tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            tutorialBody = block
        } else if tutorialBody.hasSuffix("\n") {
            tutorialBody += block
        } else {
            tutorialBody += "\n\(block)"
        }
    }

    private func binding(for items: Binding<[String]>, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard items.wrappedValue.indices.contains(index) else { return "" }
                return items.wrappedValue[index]
            },
            set: { newValue in
                guard items.wrappedValue.indices.contains(index) else { return }
                items.wrappedValue[index] = newValue
            }
        )
    }

    @ViewBuilder
    private func procedureStepRow(_ index: Int) -> some View {
        let canMoveUp = index > 0
        let canMoveDown = index < procedureSteps.count - 1
        checklistRow(
            title: String(format: String(localized: "步骤 %lld"), Int64(index + 1)),
            text: binding(for: $procedureSteps, index: index),
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: { moveProcedureStepUp(index) },
            onMoveDown: { moveProcedureStepDown(index) },
            onDelete: { removeProcedureStep(index) }
        )
    }

    @ViewBuilder
    private func qualityItemRow(_ index: Int) -> some View {
        let canMoveUp = index > 0
        let canMoveDown = index < qualityChecklist.count - 1
        checklistRow(
            title: String(format: String(localized: "检查项 %lld"), Int64(index + 1)),
            text: binding(for: $qualityChecklist, index: index),
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: { moveQualityItemUp(index) },
            onMoveDown: { moveQualityItemDown(index) },
            onDelete: { removeQualityItem(index) }
        )
    }

    @ViewBuilder
    private func safetyItemRow(_ index: Int) -> some View {
        let canMoveUp = index > 0
        let canMoveDown = index < safetyChecklist.count - 1
        checklistRow(
            title: String(format: String(localized: "注意项 %lld"), Int64(index + 1)),
            text: binding(for: $safetyChecklist, index: index),
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: { moveSafetyItemUp(index) },
            onMoveDown: { moveSafetyItemDown(index) },
            onDelete: { removeSafetyItem(index) }
        )
    }

    private func checklistRow(
        title: String,
        text: Binding<String>,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(String(localized: "输入内容"), text: text, axis: .vertical)
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addItemRow(
        placeholder: String,
        text: Binding<String>,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
            }
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func appendProcedureStep() {
        let value = newProcedureStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        procedureSteps.append(value)
        newProcedureStep = ""
    }

    private func appendQualityItem() {
        let value = newQualityItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        qualityChecklist.append(value)
        newQualityItem = ""
    }

    private func appendSafetyItem() {
        let value = newSafetyItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        safetyChecklist.append(value)
        newSafetyItem = ""
    }

    private func moveProcedureStepUp(_ index: Int) {
        guard procedureSteps.indices.contains(index), index > 0 else { return }
        procedureSteps.swapAt(index, index - 1)
    }

    private func moveProcedureStepDown(_ index: Int) {
        guard procedureSteps.indices.contains(index), index < procedureSteps.count - 1 else { return }
        procedureSteps.swapAt(index, index + 1)
    }

    private func removeProcedureStep(_ index: Int) {
        guard procedureSteps.indices.contains(index) else { return }
        procedureSteps.remove(at: index)
    }

    private func moveQualityItemUp(_ index: Int) {
        guard qualityChecklist.indices.contains(index), index > 0 else { return }
        qualityChecklist.swapAt(index, index - 1)
    }

    private func moveQualityItemDown(_ index: Int) {
        guard qualityChecklist.indices.contains(index), index < qualityChecklist.count - 1 else { return }
        qualityChecklist.swapAt(index, index + 1)
    }

    private func removeQualityItem(_ index: Int) {
        guard qualityChecklist.indices.contains(index) else { return }
        qualityChecklist.remove(at: index)
    }

    private func moveSafetyItemUp(_ index: Int) {
        guard safetyChecklist.indices.contains(index), index > 0 else { return }
        safetyChecklist.swapAt(index, index - 1)
    }

    private func moveSafetyItemDown(_ index: Int) {
        guard safetyChecklist.indices.contains(index), index < safetyChecklist.count - 1 else { return }
        safetyChecklist.swapAt(index, index + 1)
    }

    private func removeSafetyItem(_ index: Int) {
        guard safetyChecklist.indices.contains(index) else { return }
        safetyChecklist.remove(at: index)
    }

    private func normalizeList(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showError(String(localized: "当前设备不可用相机。"))
            return
        }
        Task { @MainActor in
            guard await requestCameraAccessIfNeeded() else {
                showError(String(localized: "未获得相机权限，无法拍摄。"))
                return
            }
            showCamera = true
        }
    }

    private func openTutorialCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showError(String(localized: "当前设备不可用相机。"))
            return
        }
        Task { @MainActor in
            guard await requestCameraAccessIfNeeded() else {
                showError(String(localized: "未获得相机权限，无法拍摄。"))
                return
            }
            showTutorialCamera = true
        }
    }

    private func requestCameraAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func appendImageAttachment(_ image: UIImage) {
        do {
            let fileName = try QuickNoteAttachmentStorage.saveImageOrThrow(image)
            attachments.append(QuickNoteAttachment(kind: .photo, fileName: fileName))
            sessionAddedFileNames.insert(fileName)
        } catch {
            showError(String(format: String(localized: "图片保存失败：%@"), error.localizedDescription))
        }
    }

    private func appendTutorialImageAttachment(_ image: UIImage) {
        do {
            let fileName = try QuickNoteAttachmentStorage.saveImageOrThrow(image)
            tutorialAttachments.append(QuickNoteAttachment(kind: .photo, fileName: fileName))
            sessionAddedFileNames.insert(fileName)
        } catch {
            showError(String(format: String(localized: "教程图片保存失败：%@"), error.localizedDescription))
        }
    }

    private func removeAttachment(_ attachment: QuickNoteAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        if sessionAddedFileNames.contains(attachment.fileName) {
            DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                [attachment.fileName],
                summary: "constructionMethodEditor.removeAttachment"
            )?.perform()
            sessionAddedFileNames.remove(attachment.fileName)
        }
    }

    private func removeTutorialAttachment(_ attachment: QuickNoteAttachment) {
        tutorialAttachments.removeAll { $0.id == attachment.id }
        if sessionAddedFileNames.contains(attachment.fileName) {
            DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                [attachment.fileName],
                summary: "constructionMethodEditor.removeTutorialAttachment"
            )?.perform()
            sessionAddedFileNames.remove(attachment.fileName)
        }
    }

    private enum MediaImportTarget {
        case general
        case tutorial
    }

    private func restoreDraftIfNeeded() {
        guard let draft = ConstructionMethodEditDraftStore.load(methodID: method?.id, scopeID: draftScopeID) else { return }
        title = draft.title
        trade = draft.trade
        versionName = draft.versionName
        publishStatus = draft.publishStatus
        tutorialBody = draft.tutorialBody
        tutorialAttachments = draft.tutorialAttachments
        procedureSteps = draft.procedureSteps
        qualityChecklist = draft.qualityChecklist
        safetyChecklist = draft.safetyChecklist
        attachments = draft.attachments
        didRestoreDraft = true
    }

    private func scheduleDraftSave() {
        guard hasDraftContent else {
            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
            return
        }
        let snapshot = currentDraftSnapshot
        let methodID = method?.id
        let scopeID = draftScopeID
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            guard await DebouncedTask.wait(for: .milliseconds(350)) else { return }
            ConstructionMethodEditDraftStore.save(snapshot, methodID: methodID, scopeID: scopeID)
        }
    }

    private func persistDraftImmediately() {
        guard hasDraftContent else {
            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
            return
        }
        let snapshot = currentDraftSnapshot
        ConstructionMethodEditDraftStore.save(snapshot, methodID: method?.id, scopeID: draftScopeID)
    }

    private func importMediaItems(_ items: [PhotosPickerItem], target: MediaImportTarget) async {
        guard !items.isEmpty else { return }
        await MainActor.run {
            switch target {
            case .general:
                isImportingMedia = true
                mediaImportMessage = String(localized: "正在导入媒体...")
            case .tutorial:
                isImportingTutorialMedia = true
                tutorialMediaImportMessage = String(localized: "正在导入教程媒体...")
            }
        }
        defer {
            Task { @MainActor in
                switch target {
                case .general:
                    isImportingMedia = false
                    mediaImportMessage = ""
                    selectedMediaItems = []
                case .tutorial:
                    isImportingTutorialMedia = false
                    tutorialMediaImportMessage = ""
                    selectedTutorialMediaItems = []
                }
            }
        }

        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                await MainActor.run {
                    switch target {
                    case .general:
                        mediaImportMessage = String(localized: "检查视频大小和时长...")
                    case .tutorial:
                        tutorialMediaImportMessage = String(localized: "检查视频大小和时长...")
                    }
                }
                do {
                    guard let transfer = try await item.loadTransferable(type: QuickNoteVideoTransfer.self) else {
                        await MainActor.run { showError(String(localized: "视频导入失败。")) }
                        continue
                    }
                    await MainActor.run {
                        _ = QuickNoteAttachmentStorage.videoThumbnail(for: transfer.fileName)
                        let attachment = QuickNoteAttachment(
                            kind: .video,
                            fileName: transfer.fileName,
                            originalName: transfer.originalName,
                            durationSeconds: transfer.durationSeconds
                        )
                        switch target {
                        case .general:
                            attachments.append(attachment)
                        case .tutorial:
                            tutorialAttachments.append(attachment)
                        }
                        sessionAddedFileNames.insert(transfer.fileName)
                    }
                } catch let error as QuickNoteVideoTransferError {
                    await MainActor.run { showError(error.userMessage) }
                } catch {
                    await MainActor.run { showError(String(localized: "视频导入失败。")) }
                }
                continue
            }

            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { showError(String(localized: "有一项图片导入失败。")) }
                continue
            }
            await MainActor.run {
                switch target {
                case .general:
                    appendImageAttachment(image)
                case .tutorial:
                    appendTutorialImageAttachment(image)
                }
            }
        }
    }

    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}
