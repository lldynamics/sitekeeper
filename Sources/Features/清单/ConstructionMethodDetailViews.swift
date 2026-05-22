import SwiftUI

let constructionMethodDeleteUndoHint = String(localized: "删除后可在提示中撤销，附件会延迟清理。")

func constructionMethodShareText(_ method: ConstructionMethod) -> String {
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

struct ConstructionMethodDetailContent: View {
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
