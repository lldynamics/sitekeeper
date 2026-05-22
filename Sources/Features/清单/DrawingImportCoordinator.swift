import Foundation

struct DrawingImportFailure: Equatable {
    var fileName: String
    var reason: String

    var displayText: String {
        String(format: String(localized: "%@（%@）"), fileName, reason)
    }
}

struct DrawingImportResult: Equatable {
    var importedCount = 0
    var replacedCount = 0
    var failures: [DrawingImportFailure] = []

    var didImport: Bool { importedCount > 0 }
    var failedCount: Int { failures.count }

    var failureListText: String {
        failures.map(\.displayText).joined(separator: String(localized: "、"))
    }

    var operationMessage: String {
        if importedCount > 0, failures.isEmpty {
            if replacedCount > 0 {
                return String(
                    format: String(localized: "已导入 %lld 份图纸，替换 %lld 份同格式旧文件"),
                    Int64(importedCount),
                    Int64(replacedCount)
                )
            }
            return String(format: String(localized: "已导入 %lld 份图纸"), Int64(importedCount))
        }

        if importedCount > 0 {
            if replacedCount > 0 {
                return String(
                    format: String(localized: "已导入 %lld 份，%lld 份失败，已替换 %lld 份同格式旧文件"),
                    Int64(importedCount),
                    Int64(failedCount),
                    Int64(replacedCount)
                )
            }
            return String(
                format: String(localized: "已导入 %lld 份，%lld 份失败"),
                Int64(importedCount),
                Int64(failedCount)
            )
        }

        if !failures.isEmpty {
            return importErrorMessage ?? Self.noImportMessage
        }

        return Self.noImportMessage
    }

    var importErrorMessage: String? {
        if !failures.isEmpty {
            return String(format: String(localized: "以下文件导入失败：%@"), failureListText)
        }
        if importedCount == 0 {
            return Self.noImportMessage
        }
        return nil
    }

    static var noImportMessage: String {
        String(localized: "没有可导入的图纸文件，请选择 DWG / DXF / PDF / ZIP。")
    }
}

enum DrawingImportCoordinator {
    static func importStrategyMessage(for conflictNames: [String]) -> String {
        guard !conflictNames.isEmpty else {
            return String(localized: "检测到同名图纸，请选择导入策略。")
        }
        let preview = conflictNames.prefix(3).joined(separator: String(localized: "、"))
        if conflictNames.count > 3 {
            return String(
                format: String(localized: "检测到同名图纸：%@ 等 %lld 项，请选择导入策略。"),
                preview,
                Int64(conflictNames.count)
            )
        }
        return String(
            format: String(localized: "检测到同名图纸：%@，请选择导入策略。"),
            preview
        )
    }

    @MainActor
    static func conflictedDrawingNames(for urls: [URL], projectId: UUID, store: DataStore) -> [String] {
        let projectDrawings = store.projectDrawings.filter { $0.projectId == projectId }
        return ProjectDetailDrawingHelper.conflictedDrawingNames(for: urls, in: projectDrawings)
    }

    @MainActor
    static func importDrawings(
        _ urls: [URL],
        projectId: UUID,
        strategy: ProjectDrawingImportStrategy,
        store: DataStore,
        replacementCleanupSummary: String
    ) -> DrawingImportResult {
        var result = DrawingImportResult()
        var currentDrawings = store.projectDrawings.filter { $0.projectId == projectId }

        func importDrawing(_ drawing: ProjectDrawing) {
            var versioned = drawing
            let resolved = ProjectDetailDrawingHelper.resolvedImportMetadata(
                for: drawing,
                in: currentDrawings,
                strategy: strategy
            )
            versioned.version = resolved.version
            versioned.isCurrentVersion = resolved.isCurrentVersion

            if let replacement = resolved.replacement {
                store.removeProjectDrawings(
                    ids: Set([replacement.id]),
                    deferredFileCleanup: DataStoreDeferredFileCleanup.drawingFiles(
                        [replacement.fileName],
                        summary: replacementCleanupSummary
                    ),
                    recordsAuditImmediately: true
                )
                currentDrawings.removeAll { $0.id == replacement.id }
                result.replacedCount += 1
            }

            if strategy == .createNewVersion && versioned.isCurrentVersion {
                ProjectDetailAssetActions.updateCurrentVersionFlags(for: versioned, store: store)
                for index in currentDrawings.indices where currentDrawings[index].projectId == versioned.projectId {
                    if ProjectDetailDrawingHelper.normalizedDrawingNameKey(currentDrawings[index].name) ==
                        ProjectDetailDrawingHelper.normalizedDrawingNameKey(versioned.name),
                       currentDrawings[index].id != versioned.id {
                        currentDrawings[index].isCurrentVersion = false
                    }
                }
            }

            store.appendProjectDrawing(versioned)
            currentDrawings.append(versioned)
            result.importedCount += 1
        }

        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                importZipDrawings(
                    from: url,
                    projectId: projectId,
                    result: &result,
                    importDrawing: importDrawing
                )
                continue
            }

            do {
                let drawing = try DrawingStorage.saveImportedFileOrThrow(from: url, projectId: projectId)
                importDrawing(drawing)
            } catch {
                StorageIssueLog.recordEvent(
                    "drawing.import_file_failed",
                    category: .fileStorage,
                    details: [
                        "source": "DrawingImportCoordinator.importDrawings",
                        "file_name": url.lastPathComponent
                    ],
                    error: error
                )
                result.failures.append(DrawingImportFailure(fileName: url.lastPathComponent, reason: error.localizedDescription))
            }
        }

        return result
    }

    private static func importZipDrawings(
        from url: URL,
        projectId: UUID,
        result: inout DrawingImportResult,
        importDrawing: (ProjectDrawing) -> Void
    ) {
        do {
            var hasDrawingEntries = false
            try SimpleZipArchiveReader.scan(fileURL: url) { entry, readData, _ in
                let ext = (entry.path as NSString).pathExtension.lowercased()
                guard ProjectDrawing.allowedFileExtensions.contains(ext) else { return }
                hasDrawingEntries = true
                do {
                    let entryData = try readData()
                    var drawing = try DrawingStorage.saveImportedDataOrThrow(
                        data: entryData,
                        sourceFileName: entry.path,
                        projectId: projectId
                    )
                    drawing.note = ProjectDetailDrawingHelper.packageNote(for: entry.path)
                    importDrawing(drawing)
                } catch {
                    StorageIssueLog.recordEvent(
                        "drawing.import_zip_entry_failed",
                        category: .fileStorage,
                        details: [
                            "source": "DrawingImportCoordinator.importZipDrawings",
                            "entry_path": entry.path
                        ],
                        error: error
                    )
                    result.failures.append(DrawingImportFailure(fileName: entry.path, reason: error.localizedDescription))
                }
            }
            if !hasDrawingEntries {
                result.failures.append(
                    DrawingImportFailure(
                        fileName: url.lastPathComponent,
                        reason: String(localized: "ZIP 内没有可导入的图纸")
                    )
                )
            }
        } catch {
            StorageIssueLog.recordEvent(
                "drawing.import_zip_read_failed",
                category: .fileStorage,
                details: [
                    "source": "DrawingImportCoordinator.importZipDrawings",
                    "file_name": url.lastPathComponent
                ],
                error: error
            )
            result.failures.append(DrawingImportFailure(fileName: url.lastPathComponent, reason: error.localizedDescription))
        }
    }
}
