import Foundation

extension DataHealthView {
    var referenceRepairPreviewIssues: [DataHealthIssue] {
        issueSections
            .flatMap(\.items)
            .filter(issueHasRepairAction(_:))
            .sorted(by: impactPreviewIssueSort(_:_:))
    }

    var orphanCleanupPreviewFiles: [(kind: DataHealthOrphanFileKind, fileName: String)] {
        var rows: [(kind: DataHealthOrphanFileKind, fileName: String)] = []
        rows.append(contentsOf: orphanPhotoFiles.map { (.photo, $0) })
        rows.append(contentsOf: orphanDrawingFiles.map { (.drawing, $0) })
        rows.append(contentsOf: orphanDocumentFiles.map { (.projectDocument, $0) })
        rows.append(contentsOf: orphanQuickNoteAttachmentFiles.map { (.quickNoteAttachment, $0) })
        return rows.sorted { lhs, rhs in
            let lhsKind = orphanFileKindTitle(lhs.kind)
            let rhsKind = orphanFileKindTitle(rhs.kind)
            let kindCompare = lhsKind.localizedStandardCompare(rhsKind)
            if kindCompare != .orderedSame {
                return kindCompare == .orderedAscending
            }
            return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
        }
    }

    var referenceRepairConfirmMessage: String {
        var lines = [
            l("将修复缺失引用、财务/仓库悬空附件映射、资料悬空关联和可置空的无效项目关联，不会删除任何照片、图纸、票据或随手记原文件。无法自动修复的项目关联会保留在“需手动处理项目关联”列表。")
        ]
        let previews = Array(referenceRepairPreviewIssues.prefix(5))
        if !previews.isEmpty {
            lines.append("")
            lines.append(l("影响记录预览："))
            lines.append(contentsOf: previews.map { "- \($0.exportText)" })
            let remaining = max(referenceRepairPreviewIssues.count - previews.count, 0)
            if remaining > 0 {
                lines.append(lf("- 其余 %lld 条可在异常列表中查看", Int64(remaining)))
            }
        }
        return lines.joined(separator: "\n")
    }

    var orphanCleanupConfirmMessage: String {
        var lines = [
            l("将删除未被任何记录引用的照片、图纸、票据和随手记附件。请先确认这些原件无需保留。")
        ]
        let previews = Array(orphanCleanupPreviewFiles.prefix(5))
        if !previews.isEmpty {
            lines.append("")
            lines.append(l("影响文件预览："))
            lines.append(contentsOf: previews.map { "- \(orphanFileKindTitle($0.kind)) · \($0.fileName)" })
            let remaining = max(orphanCleanupPreviewFiles.count - previews.count, 0)
            if remaining > 0 {
                lines.append(lf("- 其余 %lld 个孤立文件可在异常列表中查看", Int64(remaining)))
            }
        }
        return lines.joined(separator: "\n")
    }

    func issueHasRepairAction(_ issue: DataHealthIssue) -> Bool {
        issue.actions.contains { action in
            if case .repair = action.kind { return true }
            return false
        }
    }

    func impactPreviewIssueSort(_ lhs: DataHealthIssue, _ rhs: DataHealthIssue) -> Bool {
        if lhs.severity != rhs.severity {
            return lhs.severity.rawValue > rhs.severity.rawValue
        }
        let titleCompare = lhs.title.localizedStandardCompare(rhs.title)
        if titleCompare != .orderedSame {
            return titleCompare == .orderedAscending
        }
        let detailCompare = lhs.detail.localizedStandardCompare(rhs.detail)
        if detailCompare != .orderedSame {
            return detailCompare == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    var repairImpactRows: [(title: String, count: Int)] {
        var counts: [String: Int] = [:]
        for issue in allFilteredIssues {
            for action in issue.actions {
                switch action.kind {
                case .repair(let repair):
                    counts[repairImpactTitle(repair), default: 0] += 1
                case .moveOrphanFileToTrash(let file):
                    counts[trashImpactTitle(file.kind), default: 0] += 1
                case .navigate, .createTodo:
                    continue
                }
            }
        }
        return counts
            .map { (title: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    func repairImpactTitle(_ repair: DataHealthIssueRepair) -> String {
        switch repair {
        case .clearDailyLogLegacyPhoto, .removeDailyLogPhoto:
            return l("日志缺失照片引用将被清理")
        case .clearSiteTodoBeforePhoto, .clearSiteTodoAfterPhoto:
            return l("待办缺失照片引用将被清理")
        case .removeProjectDocument:
            return l("缺失资料记录将被移除并回收关联")
        case .removeQuickNoteAttachment:
            return l("缺失随手记附件引用将被清理")
        case .unlinkFinancialDocument:
            return l("财务悬空附件映射将被解除")
        case .unlinkWarehouseDocument:
            return l("仓库悬空附件映射将被解除")
        case .clearDocumentLinkedFinancialRecord:
            return l("资料悬空账目关联将被清空")
        case .clearMaterialProject, .clearQuoteProject, .clearLaborProject, .clearDailyLogProject, .clearSiteTodoProject, .clearQuickNoteProject:
            return l("无效项目关联将被清空")
        }
    }

    func trashImpactTitle(_ kind: DataHealthOrphanFileKind) -> String {
        switch kind {
        case .photo:
            return l("孤立照片将移入回收站")
        case .drawing:
            return l("孤立图纸将移入回收站")
        case .projectDocument:
            return l("孤立票据文件将移入回收站")
        case .quickNoteAttachment:
            return l("孤立随手记附件将移入回收站")
        }
    }

    func orphanFileKindTitle(_ kind: DataHealthOrphanFileKind) -> String {
        switch kind {
        case .photo:
            return l("照片")
        case .drawing:
            return l("图纸")
        case .projectDocument:
            return l("票据文件")
        case .quickNoteAttachment:
            return l("随手记附件")
        }
    }

    func orphanFileKindSymbol(_ kind: DataHealthOrphanFileKind) -> String {
        switch kind {
        case .photo:
            return "photo"
        case .drawing:
            return "doc.viewfinder"
        case .projectDocument:
            return "doc.richtext"
        case .quickNoteAttachment:
            return "paperclip"
        }
    }
}
