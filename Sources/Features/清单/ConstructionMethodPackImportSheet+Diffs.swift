import Foundation

extension ConstructionMethodPackImportSheet {
    var availablePackCount: Int {
        if let payload {
            return payload.packs.count
        }
        return cachedSnapshot?.payload.packs.count ?? 0
    }

    var websiteGeneratedAtDisplayText: String {
        if let payload {
            return generatedAtDisplayText(payload.generatedAt)
        }
        if let cached = cachedSnapshot {
            return generatedAtDisplayText(cached.payload.generatedAt)
        }
        return String(localized: "暂无")
    }

    var localVersionDisplayText: String {
        let importedMethods = existingMethods.filter { !$0.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !importedMethods.isEmpty else {
            return String(localized: "未导入")
        }
        let versions = Set(
            importedMethods
                .map { $0.sourceVersion.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        if versions.count == 1, let version = versions.first {
            return String(format: String(localized: "%@ · %lld 条"), version, Int64(importedMethods.count))
        }
        if versions.count > 1 {
            return String(format: String(localized: "多版本（%1$lld）· %2$lld 条"), Int64(versions.count), Int64(importedMethods.count))
        }
        return String(format: String(localized: "已导入 %lld 条"), Int64(importedMethods.count))
    }

    var offlineCacheDisplayText: String {
        guard let cachedSnapshot else {
            return String(localized: "未缓存")
        }
        let timeText: String
        if let date = cachedSnapshot.cachedDate {
            timeText = Formatters.dateTime.string(from: date)
        } else {
            timeText = String(localized: "未知时间")
        }
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(cachedSnapshot.rawBytes), countStyle: .file)
        return "\(cachedSnapshot.payload.packs.count) 条 · \(sizeText) · \(timeText)"
    }

    var shouldShowRetryButton: Bool {
        errorMessage != nil || lastImportStatus?.outcome == .failed
    }

    var sourceDisplayText: String {
        let endpoint = (loadedEndpoint ?? ConstructionMethodPackImportService.configuredPrimaryEndpoint).absoluteString
        let source = ConstructionMethodPackImportConfiguration.configuredEndpointSource
        return "\(source)\n\(endpoint)"
    }

    var selectedImportDiffs: [ImportDiffPreview] {
        guard let payload else { return [] }
        return payload.packs
            .filter { selectedPackIDs.contains($0.id) }
            .map(importDiff(for:))
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return diffSortWeight(lhs.kind) < diffSortWeight(rhs.kind)
                }
                if lhs.changes.count != rhs.changes.count {
                    return lhs.changes.count > rhs.changes.count
                }
                return lhs.pack.title.localizedCompare(rhs.pack.title) == .orderedAscending
            }
    }

    var selectedDiffSummaryText: String {
        guard !selectedImportDiffs.isEmpty else {
            return String(localized: "暂无")
        }
        let newCount = selectedImportDiffs.filter { $0.kind == .new }.count
        let updateCount = selectedImportDiffs.filter { $0.kind == .updated }.count
        let unchangedCount = selectedImportDiffs.filter { $0.kind == .unchanged }.count
        return String(
            format: String(localized: "新增 %1$lld · 更新 %2$lld · 无变化 %3$lld"),
            Int64(newCount),
            Int64(updateCount),
            Int64(unchangedCount)
        )
    }

    func diffSortWeight(_ kind: ImportDiffPreview.Kind) -> Int {
        switch kind {
        case .updated:
            return 0
        case .new:
            return 1
        case .unchanged:
            return 2
        }
    }

    func importDiff(for pack: RemoteConstructionMethodPack) -> ImportDiffPreview {
        guard let existing = existingMethod(for: pack) else {
            return ImportDiffPreview(pack: pack, kind: .new, changes: [])
        }

        let mapped = pack.constructionMethod(existing: existing)
        var changes: [ImportFieldChange] = []

        appendStringChange(
            changes: &changes,
            key: "title",
            label: String(localized: "标题"),
            before: existing.title,
            after: mapped.title
        )
        appendStringChange(
            changes: &changes,
            key: "trade",
            label: String(localized: "专业"),
            before: existing.trade,
            after: mapped.trade
        )
        appendStringChange(
            changes: &changes,
            key: "versionName",
            label: String(localized: "版本号"),
            before: existing.versionName,
            after: mapped.versionName
        )
        appendStringChange(
            changes: &changes,
            key: "publishStatus",
            label: String(localized: "发布状态"),
            before: existing.publishStatus.rawValue,
            after: mapped.publishStatus.rawValue
        )
        appendBodyChange(
            changes: &changes,
            key: "tutorialBody",
            label: String(localized: "正文"),
            before: existing.tutorialBody,
            after: mapped.tutorialBody
        )
        appendListChange(
            changes: &changes,
            key: "procedureSteps",
            label: String(localized: "步骤清单"),
            before: existing.procedureSteps,
            after: mapped.procedureSteps
        )
        appendListChange(
            changes: &changes,
            key: "qualityChecklist",
            label: String(localized: "质检清单"),
            before: existing.qualityChecklist,
            after: mapped.qualityChecklist
        )
        appendListChange(
            changes: &changes,
            key: "safetyChecklist",
            label: String(localized: "安全清单"),
            before: existing.safetyChecklist,
            after: mapped.safetyChecklist
        )
        appendStringChange(
            changes: &changes,
            key: "sourceURL",
            label: String(localized: "来源链接"),
            before: existing.sourceURL,
            after: mapped.sourceURL
        )
        appendStringChange(
            changes: &changes,
            key: "sourceVersion",
            label: String(localized: "来源版本"),
            before: existing.sourceVersion,
            after: mapped.sourceVersion
        )
        appendStringChange(
            changes: &changes,
            key: "sourceUpdatedAt",
            label: String(localized: "网站更新时间"),
            before: existing.sourceUpdatedAt,
            after: mapped.sourceUpdatedAt
        )
        appendListChange(
            changes: &changes,
            key: "relatedStandards",
            label: String(localized: "相关规范"),
            before: existing.relatedStandards,
            after: mapped.relatedStandards
        )
        appendLinksChange(
            changes: &changes,
            key: "relatedTemplates",
            label: String(localized: "相关模板"),
            before: existing.relatedTemplates,
            after: mapped.relatedTemplates
        )
        appendLinksChange(
            changes: &changes,
            key: "relatedArticles",
            label: String(localized: "相关文章"),
            before: existing.relatedArticles,
            after: mapped.relatedArticles
        )

        let kind: ImportDiffPreview.Kind = changes.isEmpty ? .unchanged : .updated
        return ImportDiffPreview(pack: pack, kind: kind, changes: changes)
    }

    func appendStringChange(
        changes: inout [ImportFieldChange],
        key: String,
        label: String,
        before: String,
        after: String
    ) {
        let normalizedBefore = normalizedText(before)
        let normalizedAfter = normalizedText(after)
        guard normalizedBefore != normalizedAfter else { return }
        changes.append(
            ImportFieldChange(
                key: key,
                label: label,
                before: summarizedText(normalizedBefore),
                after: summarizedText(normalizedAfter)
            )
        )
    }

    func appendBodyChange(
        changes: inout [ImportFieldChange],
        key: String,
        label: String,
        before: String,
        after: String
    ) {
        let normalizedBefore = normalizedText(before)
        let normalizedAfter = normalizedText(after)
        guard normalizedBefore != normalizedAfter else { return }
        changes.append(
            ImportFieldChange(
                key: key,
                label: label,
                before: summarizedBody(normalizedBefore),
                after: summarizedBody(normalizedAfter)
            )
        )
    }

    func appendListChange(
        changes: inout [ImportFieldChange],
        key: String,
        label: String,
        before: [String],
        after: [String]
    ) {
        let normalizedBefore = normalizedList(before)
        let normalizedAfter = normalizedList(after)
        guard normalizedBefore != normalizedAfter else { return }
        changes.append(
            ImportFieldChange(
                key: key,
                label: label,
                before: summarizedList(normalizedBefore),
                after: summarizedList(normalizedAfter)
            )
        )
    }

    func appendLinksChange(
        changes: inout [ImportFieldChange],
        key: String,
        label: String,
        before: [ConstructionMethodKnowledgeLink],
        after: [ConstructionMethodKnowledgeLink]
    ) {
        let normalizedBefore = normalizedLinks(before)
        let normalizedAfter = normalizedLinks(after)
        guard normalizedBefore != normalizedAfter else { return }
        changes.append(
            ImportFieldChange(
                key: key,
                label: label,
                before: summarizedLinks(normalizedBefore),
                after: summarizedLinks(normalizedAfter)
            )
        )
    }

    func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedList(_ values: [String]) -> [String] {
        values.map(normalizedText).filter { !$0.isEmpty }
    }

    func normalizedLinks(_ links: [ConstructionMethodKnowledgeLink]) -> [ConstructionMethodKnowledgeLink] {
        links.compactMap { link in
            let title = normalizedText(link.title)
            let href = normalizedText(link.href)
            guard !href.isEmpty else { return nil }
            return ConstructionMethodKnowledgeLink(title: title.isEmpty ? href : title, href: href)
        }
    }

    func summarizedText(_ value: String, limit: Int = 40) -> String {
        guard !value.isEmpty else { return String(localized: "空") }
        if value.count <= limit {
            return value
        }
        return "\(value.prefix(limit))…"
    }

    func summarizedBody(_ value: String) -> String {
        guard !value.isEmpty else { return String(localized: "空") }
        let lineCount = value.split(whereSeparator: \.isNewline).count
        let snippet = summarizedText(value.replacingOccurrences(of: "\n", with: " "), limit: 26)
        return String(format: String(localized: "%1$lld 行 · %@"), Int64(lineCount), snippet)
    }

    func summarizedList(_ values: [String]) -> String {
        guard !values.isEmpty else { return String(localized: "空") }
        let head = values.prefix(3).joined(separator: "；")
        if values.count <= 3 {
            return head
        }
        return String(format: String(localized: "%1$@（共 %2$lld 项）"), head, Int64(values.count))
    }

    func summarizedLinks(_ links: [ConstructionMethodKnowledgeLink]) -> String {
        guard !links.isEmpty else { return String(localized: "空") }
        let head = links.prefix(2).map { link in
            let title = normalizedText(link.title)
            return title.isEmpty ? normalizedText(link.href) : title
        }.joined(separator: "；")
        if links.count <= 2 {
            return head
        }
        return String(format: String(localized: "%1$@（共 %2$lld 条）"), head, Int64(links.count))
    }

    func generatedAtDisplayText(_ raw: String) -> String {
        guard let date = Formatters.parseDateOrDateTime(raw) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "暂无")
                : raw
        }
        return Formatters.dateTime.string(from: date)
    }

    var lastImportStatusDisplayText: String {
        guard let status = lastImportStatus else {
            return String(localized: "暂无")
        }
        switch status.outcome {
        case .success:
            return String(localized: "成功")
        case .failed:
            return String(localized: "失败")
        }
    }

    var lastImportStatusDetailText: String? {
        guard let status = lastImportStatus else { return nil }
        let timeText: String
        if let date = status.happenedAt {
            timeText = Formatters.dateTime.string(from: date)
        } else {
            timeText = String(localized: "未知时间")
        }
        let endpointText = status.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let core = status.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpointText.isEmpty {
            return "\(timeText) · \(core)"
        }
        return "\(timeText) · \(core) · \(endpointText)"
    }
}
