import Foundation

enum BackupImportStage: String {
    case copyingSourceFile = "copying_source_file"
    case readingPreview = "reading_preview"
    case readingMetadata = "reading_metadata"
    case stagingFiles = "staging_files"
    case applyingMetadata = "applying_metadata"
    case committingFiles = "committing_files"
    case persistingMetadata = "persisting_metadata"
    case cleaningOverwrittenFiles = "cleaning_overwritten_files"

    var displayName: String {
        switch self {
        case .copyingSourceFile:
            return AppLocalization.string("复制备份文件")
        case .readingPreview:
            return AppLocalization.string("读取备份预览")
        case .readingMetadata:
            return AppLocalization.string("读取数据索引")
        case .stagingFiles:
            return AppLocalization.string("暂存原文件")
        case .applyingMetadata:
            return AppLocalization.string("应用数据索引")
        case .committingFiles:
            return AppLocalization.string("提交原文件")
        case .persistingMetadata:
            return AppLocalization.string("写入本地数据")
        case .cleaningOverwrittenFiles:
            return AppLocalization.string("清理旧文件")
        }
    }

    func failureSummary(error: Error) -> String {
        String(
            format: AppLocalization.string("导入失败（%@）：%@"),
            displayName,
            error.localizedDescription
        )
    }

    func auditDetail(fileName: String? = nil, extra: String? = nil) -> String {
        var parts = ["stage=\(rawValue)", "stageName=\(displayName)"]
        if let fileName, !fileName.isEmpty {
            parts.append("file=\(fileName)")
        }
        if let extra, !extra.isEmpty {
            parts.append(extra)
        }
        return parts.joined(separator: ", ")
    }
}
