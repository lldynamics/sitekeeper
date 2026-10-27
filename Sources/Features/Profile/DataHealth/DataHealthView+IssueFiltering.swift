import SwiftUI

extension DataHealthView {
    var issueSections: [DataHealthIssueSection] {
        [
            DataHealthIssueSection(id: "missingPhotoFiles", title: l("缺失照片文件"), items: missingPhotoFileIssues),
            DataHealthIssueSection(id: "missingDocumentFiles", title: l("缺失票据文件"), items: missingDocumentFileIssues),
            DataHealthIssueSection(id: "missingQuickNoteAttachmentFiles", title: l("缺失随手记附件"), items: missingQuickNoteAttachmentIssues),
            DataHealthIssueSection(id: "orphanPhotoFiles", title: l("孤立照片文件"), items: orphanPhotoFileIssues),
            DataHealthIssueSection(id: "orphanDrawingFiles", title: l("孤立图纸文件"), items: orphanDrawingFileIssues),
            DataHealthIssueSection(id: "orphanDocumentFiles", title: l("孤立票据文件"), items: orphanDocumentFileIssues),
            DataHealthIssueSection(id: "orphanQuickNoteAttachmentFiles", title: l("孤立随手记附件"), items: orphanQuickNoteAttachmentIssues),
            DataHealthIssueSection(id: "orphanAttachmentMappings", title: l("孤立附件映射"), items: orphanAttachmentMappingIssues),
            DataHealthIssueSection(id: "orphanWarehouseAttachmentMappings", title: l("仓库悬空附件映射"), items: orphanWarehouseAttachmentMappingIssues),
            DataHealthIssueSection(id: "danglingDocumentLinks", title: l("资料悬空关联"), items: danglingDocumentLinkIssues),
            DataHealthIssueSection(id: "autoFixableInvalidProjectRefs", title: l("无效项目关联（可自动修复）"), items: autoFixableInvalidProjectRefIssues),
            DataHealthIssueSection(id: "manualInvalidProjectRefs", title: l("无效项目关联（需手动处理）"), items: manualInvalidProjectRefIssues),
            DataHealthIssueSection(id: "storageIssueRows", title: l("存储错误记录"), items: storageIssueRows)
        ]
    }

    var displayedIssueSections: [DataHealthIssueSection] {
        switch selectedIssueSort {
        case .severityDescending:
            return issueSections.sorted { lhs, rhs in
                sectionSeverityScore(lhs) > sectionSeverityScore(rhs)
            }
        case .severityAscending:
            return issueSections.sorted { lhs, rhs in
                sectionSeverityScore(lhs) < sectionSeverityScore(rhs)
            }
        case .titleAscending, .titleDescending:
            return issueSections
        }
    }

    var filteredIssueCount: Int {
        allFilteredIssues.count
    }

    var allFilteredIssues: [DataHealthIssue] {
        issueSections.flatMap { filteredIssueItems($0.items) }
    }

    var hasActiveIssueFilters: Bool {
        selectedIssueProjectFilter != DataHealthIssueProjectFilter.all
            || showsOnlyAutoFixableIssues
            || !issueSearchKeyword.isEmpty
    }

    var issueSearchKeyword: String {
        issueSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func filteredIssueItems(_ items: [DataHealthIssue]) -> [DataHealthIssue] {
        let filtered = items.filter { issue in
            matchesAutoFixableFilter(issue)
                && matchesProjectFilter(issue)
                && matchesSearchFilter(issue)
        }
        return sortIssueItems(filtered)
    }

    func matchesAutoFixableFilter(_ issue: DataHealthIssue) -> Bool {
        !showsOnlyAutoFixableIssues || issue.isAutoFixable
    }

    func matchesSearchFilter(_ issue: DataHealthIssue) -> Bool {
        guard !issueSearchKeyword.isEmpty else { return true }
        return issue.searchableText.localizedCaseInsensitiveContains(issueSearchKeyword)
    }

    func matchesProjectFilter(_ issue: DataHealthIssue) -> Bool {
        switch selectedIssueProjectFilter {
        case DataHealthIssueProjectFilter.all:
            return true
        case DataHealthIssueProjectFilter.noProject:
            return issue.effectiveProjectId == nil
        case DataHealthIssueProjectFilter.invalidProject:
            guard let projectId = issue.effectiveProjectId else { return false }
            return !projectIdSet.contains(projectId)
        default:
            guard let projectId = issue.effectiveProjectId else { return false }
            return selectedIssueProjectFilter == DataHealthIssueProjectFilter.project(projectId)
        }
    }

    func sortIssueItems(_ items: [DataHealthIssue]) -> [DataHealthIssue] {
        items.sorted(by: compareIssue(_:_:))
    }

    func compareIssue(_ lhs: DataHealthIssue, _ rhs: DataHealthIssue) -> Bool {
        switch selectedIssueSort {
        case .severityDescending:
            if lhs.severity != rhs.severity {
                return lhs.severity.rawValue > rhs.severity.rawValue
            }
        case .severityAscending:
            if lhs.severity != rhs.severity {
                return lhs.severity.rawValue < rhs.severity.rawValue
            }
        case .titleAscending:
            let compare = lhs.title.localizedStandardCompare(rhs.title)
            if compare != .orderedSame {
                return compare == .orderedAscending
            }
        case .titleDescending:
            let compare = lhs.title.localizedStandardCompare(rhs.title)
            if compare != .orderedSame {
                return compare == .orderedDescending
            }
        }

        let detailCompare = lhs.detail.localizedStandardCompare(rhs.detail)
        if detailCompare != .orderedSame {
            return detailCompare == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    func sectionSeverityScore(_ section: DataHealthIssueSection) -> Int {
        filteredIssueItems(section.items).map(\.severity.rawValue).max() ?? Int.min
    }

    var autoFixableFilteredIssueCount: Int {
        allFilteredIssues.filter(\.isAutoFixable).count
    }

    var manualFilteredIssueCount: Int {
        max(allFilteredIssues.count - autoFixableFilteredIssueCount, 0)
    }

    var filteredRepairActionCount: Int {
        allFilteredIssues.reduce(0) { count, issue in
            count + issue.actions.reduce(0) { partial, action in
                if case .repair = action.kind { return partial + 1 }
                return partial
            }
        }
    }

    var filteredTrashActionCount: Int {
        allFilteredIssues.reduce(0) { count, issue in
            count + issue.actions.reduce(0) { partial, action in
                if case .moveOrphanFileToTrash = action.kind { return partial + 1 }
                return partial
            }
        }
    }

    func issueSectionTitle(_ title: String, filteredCount: Int, totalCount: Int) -> String {
        if filteredCount == totalCount {
            return "\(title) (\(totalCount))"
        }
        return "\(title) (\(filteredCount)/\(totalCount))"
    }

    func toggleIssueSectionExpansion(_ sectionID: String) {
        withAnimation(.snappy(duration: 0.18)) {
            if expandedIssueSectionIDs.contains(sectionID) {
                expandedIssueSectionIDs.remove(sectionID)
            } else {
                expandedIssueSectionIDs.insert(sectionID)
            }
        }
    }

    func resetIssueFilters() {
        selectedIssueProjectFilter = DataHealthIssueProjectFilter.all
        showsOnlyAutoFixableIssues = false
        issueSearchText = ""
        selectedIssueSort = .severityDescending
        expandedIssueSectionIDs.removeAll()
    }
}
