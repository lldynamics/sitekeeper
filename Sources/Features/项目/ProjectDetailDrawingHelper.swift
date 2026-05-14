import Foundation

enum ProjectDrawingImportStrategy: String, CaseIterable, Identifiable {
    case mergeCurrentVersion
    case createNewVersion
    case replaceSameFormat

    var id: Self { self }

    var displayName: String {
        switch self {
        case .mergeCurrentVersion:
            return String(localized: "合并到当前版本")
        case .createNewVersion:
            return String(localized: "创建新版本")
        case .replaceSameFormat:
            return String(localized: "替换同格式文件")
        }
    }
}

enum ProjectDetailDrawingHelper {
    private static let zipEntryNotePrefix = "ZIP路径: "

    static func drawingIcon(_ fileType: String) -> String {
        switch fileType.lowercased() {
        case "pdf":
            return "doc.richtext.fill"
        case "dwg", "dxf":
            return "point.3.connected.trianglepath.dotted"
        default:
            return "doc.fill"
        }
    }

    static func isCADSource(_ fileType: String) -> Bool {
        let normalized = fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "dwg" || normalized == "dxf"
    }

    static func nextDrawingVersion(name: String, drawings: [ProjectDrawing]) -> String {
        let key = normalizedDrawingNameKey(name)
        let sameName = drawings.filter { candidate in
            normalizedDrawingNameKey(candidate.name) == key
        }
        let versions = sameName.map(\.version).compactMap(versionNumber)
        let next = (versions.max() ?? 0) + 1
        return "V\(next)"
    }

    static func normalizedVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = versionNumber(trimmed) {
            return "V\(n)"
        }
        if trimmed.isEmpty {
            return "V1"
        }
        return trimmed.uppercased()
    }

    static func versionNumber(_ version: String) -> Int? {
        let upper = version.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if upper.hasPrefix("V"), let value = Int(upper.dropFirst()) {
            return value
        }
        return Int(upper)
    }

    static func matchingPDFPreview(for drawing: ProjectDrawing, in drawings: [ProjectDrawing]) -> ProjectDrawing? {
        nil
    }

    static func matchingDXFPreview(for drawing: ProjectDrawing, in drawings: [ProjectDrawing]) -> ProjectDrawing? {
        nil
    }

    static func matchingRenderablePreview(for drawing: ProjectDrawing, in drawings: [ProjectDrawing]) -> ProjectDrawing? {
        nil
    }

    static func cadDrawingsWithoutRenderablePreview(in drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        []
    }

    static func conflictedDrawingNames(for urls: [URL], in drawings: [ProjectDrawing]) -> [String] {
        let existingKeys = Set(drawings.map { normalizedDrawingNameKey($0.name) }.filter { !$0.isEmpty })
        var names: [String] = []
        var seen: Set<String> = []
        for url in urls {
            let baseName = drawingDisplayName(from: url)
            let key = normalizedDrawingNameKey(baseName)
            guard !key.isEmpty, existingKeys.contains(key), !seen.contains(key) else { continue }
            names.append(baseName)
            seen.insert(key)
        }
        return names
    }

    static func drawingDisplayName(from sourceURL: URL) -> String {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? sourceURL.lastPathComponent : baseName
    }

    static func packageNote(for entryPath: String) -> String {
        let normalized = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        return "\(zipEntryNotePrefix)\(normalized)"
    }

    static func zipEntryPath(for drawing: ProjectDrawing) -> String? {
        let note = drawing.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.hasPrefix(zipEntryNotePrefix) else { return nil }
        let path = String(note.dropFirst(zipEntryNotePrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func zipFolderPath(for drawing: ProjectDrawing) -> String? {
        guard let path = zipEntryPath(for: drawing) else { return nil }
        let folder = (path as NSString).deletingLastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.isEmpty || folder == "." ? "根目录" : folder
    }

    static func replaceCandidate(for drawing: ProjectDrawing, in drawings: [ProjectDrawing]) -> ProjectDrawing? {
        let family = drawingFamily(for: drawing, in: drawings)
        let ext = drawing.fileType.lowercased()
        return family
            .filter { $0.fileType.lowercased() == ext }
            .sorted(by: preferredDrawingSort)
            .first
    }

    static func resolvedImportMetadata(
        for drawing: ProjectDrawing,
        in drawings: [ProjectDrawing],
        strategy: ProjectDrawingImportStrategy
    ) -> (version: String, isCurrentVersion: Bool, replacement: ProjectDrawing?) {
        let family = drawingFamily(for: drawing, in: drawings)
        switch strategy {
        case .createNewVersion:
            return (nextDrawingVersion(name: drawing.name, drawings: drawings), true, nil)
        case .mergeCurrentVersion:
            if let current = family.first(where: \.isCurrentVersion) {
                return (normalizedVersion(current.version), current.isCurrentVersion, nil)
            }
            if let latest = family.sorted(by: preferredDrawingSort).first {
                return (normalizedVersion(latest.version), latest.isCurrentVersion, nil)
            }
            return ("V1", true, nil)
        case .replaceSameFormat:
            if let target = replaceCandidate(for: drawing, in: drawings) {
                return (normalizedVersion(target.version), target.isCurrentVersion, target)
            }
            if let current = family.first(where: \.isCurrentVersion) {
                return (normalizedVersion(current.version), current.isCurrentVersion, nil)
            }
            if let latest = family.sorted(by: preferredDrawingSort).first {
                return (normalizedVersion(latest.version), latest.isCurrentVersion, nil)
            }
            return ("V1", true, nil)
        }
    }

    static func normalizedDrawingNameKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[\\s_\\-]+", with: "", options: .regularExpression)
    }

    private static func matchingPreview(
        for drawing: ProjectDrawing,
        in drawings: [ProjectDrawing],
        acceptedExtensions: Set<String>
    ) -> ProjectDrawing? {
        if let linkedID = drawing.linkedPreviewDrawingID,
           let linked = drawings.first(where: { $0.id == linkedID && $0.projectId == drawing.projectId }),
           acceptedExtensions.contains(linked.fileType.lowercased()) {
            return linked
        }

        let family = drawingFamily(for: drawing, in: drawings)
            .filter { acceptedExtensions.contains($0.fileType.lowercased()) }

        guard !family.isEmpty else { return nil }
        let versionKey = normalizedVersion(drawing.version)

        if let sameVersion = family
            .filter({ normalizedVersion($0.version) == versionKey })
            .sorted(by: preferredDrawingSort)
            .first {
            return sameVersion
        }

        return family
            .filter { candidate in
                candidate.isCurrentVersion
            }
            .sorted(by: preferredDrawingSort)
            .first
            ?? family.sorted(by: preferredDrawingSort).first
    }

    private static func drawingFamily(for drawing: ProjectDrawing, in drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        let key = normalizedDrawingNameKey(drawing.name)
        guard !key.isEmpty else { return [] }
        return drawings.filter { candidate in
            candidate.projectId == drawing.projectId &&
            normalizedDrawingNameKey(candidate.name) == key
        }
    }

    private static func preferredDrawingSort(_ lhs: ProjectDrawing, _ rhs: ProjectDrawing) -> Bool {
        if lhs.isCurrentVersion != rhs.isCurrentVersion {
            return lhs.isCurrentVersion && !rhs.isCurrentVersion
        }
        let left = Formatters.parseDateOrDateTime(lhs.importedAt) ?? .distantPast
        let right = Formatters.parseDateOrDateTime(rhs.importedAt) ?? .distantPast
        if left != right {
            return left > right
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
