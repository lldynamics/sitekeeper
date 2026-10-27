import SwiftUI

let constructionMethodDeleteUndoHint = AppLocalization.string("删除后可在提示中撤销，附件会延迟清理。")

func constructionMethodShareText(_ method: ConstructionMethod) -> String {
    let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLocalization.string("未命名工艺") : method.title
    let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLocalization.string("未分类") : method.trade
    let steps = method.procedureSteps.isEmpty ? AppLocalization.string("暂无") : method.procedureSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let quality = method.qualityChecklist.isEmpty ? AppLocalization.string("暂无") : method.qualityChecklist.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let safety = method.safetyChecklist.isEmpty ? AppLocalization.string("暂无") : method.safetyChecklist.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let tutorial = method.tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLocalization.string("暂无") : method.tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
    return """
    \(title)
    \(String(format: AppLocalization.string("专业：%@"), trade))
    \(String(format: AppLocalization.string("版本：%@"), method.versionName.isEmpty ? "V1" : method.versionName))
    \(String(format: AppLocalization.string("状态：%@"), method.publishStatus.displayName))
    \(String(format: AppLocalization.string("更新：%@"), Formatters.displayDateText(method.updatedAt)))

    \(AppLocalization.string("施工步骤："))
    \(steps)

    \(AppLocalization.string("质量检查项："))
    \(quality)

    \(AppLocalization.string("安全注意项："))
    \(safety)

    \(AppLocalization.string("完整教程："))
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
                                Label(AppLocalization.string("分享"), systemImage: "square.and.arrow.up")
                            }
                            Button(AppLocalization.string("编辑")) { editingMethod = method }
                            Button(AppLocalization.string("删除"), role: .destructive) { showDeleteConfirm = true }
                        }
                    }
            } else {
                ContentUnavailableView(AppLocalization.string("工艺不存在"), systemImage: "exclamationmark.triangle")
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
        .alert(AppLocalization.string("删除这条施工工艺？"), isPresented: $showDeleteConfirm) {
            Button(AppLocalization.string("取消"), role: .cancel) {}
            Button(AppLocalization.string("删除"), role: .destructive) {
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
                    ContentUnavailableView(AppLocalization.string("工艺不存在"), systemImage: "exclamationmark.triangle")
                        .task(id: method?.id) {
                            guard method == nil else { return }
                            guard await DebouncedTask.wait(for: .milliseconds(200)) else { return }
                            dismiss()
                        }
                }
            }
            .navigationTitle(AppLocalization.string("施工工艺"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("关闭")) { dismiss() }
                }
                if let method {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: constructionMethodShareText(method)) {
                            Label(AppLocalization.string("分享"), systemImage: "square.and.arrow.up")
                        }
                        Button(AppLocalization.string("编辑")) {
                            onEdit(method)
                            editingMethod = method
                        }
                        Button(AppLocalization.string("删除"), role: .destructive) {
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
            .alert(AppLocalization.string("删除这条施工工艺？"), isPresented: $showDeleteConfirm) {
                Button(AppLocalization.string("取消"), role: .cancel) {}
                Button(AppLocalization.string("删除"), role: .destructive) {
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
                    Text(method.title.isEmpty ? AppLocalization.string("未命名工艺") : method.title)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 10) {
                        Label(method.trade.isEmpty ? AppLocalization.string("未分类") : method.trade, systemImage: "tag")
                        Label(method.versionName.isEmpty ? "V1" : method.versionName, systemImage: "number")
                        Label(method.publishStatus.displayName, systemImage: method.publishStatus == .published ? "checkmark.seal.fill" : "doc.badge.clock")
                        Label(String(format: AppLocalization.string("更新于 %@"), Formatters.displayDateText(method.updatedAt)), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let sourceURL = URL(string: method.sourceURL), !method.sourceID.isEmpty {
                        Link(destination: sourceURL) {
                            Label(AppLocalization.string("查看工程知识网站原文"), systemImage: "globe.asia.australia")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    Toggle(AppLocalization.string("仅看未完成"), isOn: $showOnlyPendingItems)
                        .toggleStyle(.switch)
                        .font(.callout)
                }
                ConstructionMethodKnowledgeReferencesBlock(method: method)
                ConstructionMethodReferenceBlock { action in
                    referenceAction = action
                }
                ConstructionMethodDetailBlock(
                    title: AppLocalization.string("施工步骤"),
                    systemImage: "list.number",
                    lines: method.procedureSteps,
                    isCheckable: true,
                    showOnlyPendingItems: showOnlyPendingItems
                )
                ConstructionMethodDetailBlock(
                    title: AppLocalization.string("质量标准"),
                    systemImage: "checkmark.seal",
                    lines: method.qualityChecklist,
                    isCheckable: true,
                    showOnlyPendingItems: showOnlyPendingItems
                )
                ConstructionMethodDetailBlock(
                    title: AppLocalization.string("安全注意"),
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
                    title: String(format: AppLocalization.string("按工艺检查：%@"), methodDisplayTitle(method)),
                    dueDate: .day(CalendarDay(date: Date())),
                    priority: .medium,
                    issueType: .quality,
                    note: constructionMethodReferenceText(method),
                    linkedConstructionMethodIDs: [method.id],
                    projectId: projectId
                )
            )
            operationMessage = AppLocalization.string("已生成现场待办")
        case .dailyLog:
            store.insertDailyLogAtTop(
                DailyLog(
                    date: .day(CalendarDay(date: Date())),
                    weather: "",
                    content: String(format: AppLocalization.string("引用施工工艺：%@\n\n%@"), methodDisplayTitle(method), constructionMethodReferenceText(method)),
                    workers: NumericInputSupport.quantity("0"),
                    safety: method.safetyChecklist.joined(separator: "\n"),
                    tomorrowPlan: String(format: AppLocalization.string("按《%@》复核现场执行情况"), methodDisplayTitle(method)),
                    qualityIssue: "",
                    rectification: "",
                    linkedConstructionMethodIDs: [method.id],
                    projectId: projectId
                )
            )
            operationMessage = AppLocalization.string("已生成施工日志，请补充现场天气。")
        case .rectification:
            store.insertSiteTodoAtTop(
                SiteTodo(
                    title: String(format: AppLocalization.string("整改复核：%@"), methodDisplayTitle(method)),
                    dueDate: .day(CalendarDay(date: Date())),
                    priority: .high,
                    issueType: .quality,
                    note: String(format: AppLocalization.string("整改依据：\n%@"), constructionMethodReferenceText(method)),
                    linkedConstructionMethodIDs: [method.id],
                    projectId: projectId
                )
            )
            operationMessage = AppLocalization.string("已生成整改待办")
        }
        store.scheduleSave()
        AppHaptics.success()
    }
}

private struct ConstructionMethodKnowledgeReferencesBlock: View {
    let method: ConstructionMethod

    private var hasContent: Bool {
        let sourceURL = method.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !sourceURL.isEmpty
            || !method.sourceVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !method.sourceUpdatedAt.isEmpty
            || !method.relatedStandards.isEmpty
            || !method.relatedTemplates.isEmpty
            || !method.relatedArticles.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 8) {
                Label(AppLocalization.string("来源与关联资料"), systemImage: "link")
                    .font(.headline)

                if let sourceURL = normalizedURL(method.sourceURL) {
                    Link(destination: sourceURL) {
                        Label(AppLocalization.string("来源网站原文"), systemImage: "globe.asia.australia")
                            .font(.callout.weight(.semibold))
                    }
                }

                let sourceVersion = method.sourceVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sourceVersion.isEmpty {
                    Text(String(format: AppLocalization.string("来源版本：%@"), sourceVersion))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let sourceUpdatedAt = method.sourceUpdatedAt
                if !sourceUpdatedAt.isEmpty {
                    Text(String(format: AppLocalization.string("网站更新时间：%@"), Formatters.displayDateText(sourceUpdatedAt)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let standards = normalizedStandards(method.relatedStandards)
                if !standards.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string("相关规范"))
                            .font(.subheadline.weight(.semibold))
                        ForEach(standards, id: \.self) { value in
                            if let url = normalizedURL(value) {
                                Link(destination: url) {
                                    Label(value, systemImage: "doc.text")
                                        .font(.callout)
                                }
                            } else {
                                Label(value, systemImage: "doc.text")
                                    .font(.callout)
                            }
                        }
                    }
                }

                relatedLinksSection(
                    title: AppLocalization.string("相关模板"),
                    links: method.relatedTemplates,
                    icon: "doc.on.doc"
                )

                relatedLinksSection(
                    title: AppLocalization.string("相关文章"),
                    links: method.relatedArticles,
                    icon: "newspaper"
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func relatedLinksSection(
        title: String,
        links: [ConstructionMethodKnowledgeLink],
        icon: String
    ) -> some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                ForEach(links) { link in
                    let fallbackTitle = link.href.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayTitle = link.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? fallbackTitle
                        : link.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = normalizedURL(link.href) {
                        Link(destination: url) {
                            Label(displayTitle, systemImage: icon)
                                .font(.callout)
                        }
                    } else {
                        Label(displayTitle, systemImage: icon)
                            .font(.callout)
                    }
                }
            }
        }
    }

    private func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private func normalizedStandards(_ standards: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for standard in standards {
            let value = standard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard seen.insert(value).inserted else { continue }
            result.append(value)
        }
        return result
    }
}
