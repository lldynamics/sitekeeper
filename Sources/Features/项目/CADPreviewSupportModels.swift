import SwiftUI

enum CADViewerMode: String, CaseIterable, Identifiable {
    case auto
    case vector
    case fallback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return String(localized: "自动")
        case .vector: return String(localized: "图元")
        case .fallback: return String(localized: "兼容预览")
        }
    }

    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .vector: return "point.3.connected.trianglepath.dotted"
        case .fallback: return "photo.on.rectangle"
        }
    }
}

struct CADFallbackViewportTransform: Codable, Equatable {
    var zoomScale: Double
    var panOffsetX: Double
    var panOffsetY: Double
    var boundsX: Double
    var boundsY: Double
    var boundsWidth: Double
    var boundsHeight: Double
    var viewportCenterX: Double?
    var viewportCenterY: Double?

    init(
        zoomScale: Double,
        panOffsetX: Double,
        panOffsetY: Double,
        boundsX: Double,
        boundsY: Double,
        boundsWidth: Double,
        boundsHeight: Double,
        viewportCenterX: Double?,
        viewportCenterY: Double?
    ) {
        self.zoomScale = zoomScale
        self.panOffsetX = panOffsetX
        self.panOffsetY = panOffsetY
        self.boundsX = boundsX
        self.boundsY = boundsY
        self.boundsWidth = boundsWidth
        self.boundsHeight = boundsHeight
        self.viewportCenterX = viewportCenterX
        self.viewportCenterY = viewportCenterY
    }

    init(transform: CADNativeCanvasTransform, viewState: CADDrawingViewState) {
        self.init(
            zoomScale: viewState.zoomScale,
            panOffsetX: viewState.panOffsetX,
            panOffsetY: viewState.panOffsetY,
            boundsX: Double(transform.bounds.minX),
            boundsY: Double(transform.bounds.minY),
            boundsWidth: Double(transform.bounds.width),
            boundsHeight: Double(transform.bounds.height),
            viewportCenterX: viewState.viewportCenterX,
            viewportCenterY: viewState.viewportCenterY
        )
    }
}

struct CADArrowAnnotation: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: CADPoint
    var end: CADPoint
    var lineWidth: Double
    var colorHex: String?
    var layerName: String?
    var createdAt: String
}

struct CADFallbackIssueMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    var point: CADPoint
    var normalizedPoint: CADPoint
    var drawingId: UUID?
    var layoutId: String?
    var worldPoint: CADPoint?
    var viewportTransform: CADFallbackViewportTransform?
    var title: String
    var note: String
    var photoFileName: String?
    var layerName: String?
    var measurementSummary: String?
    var colorHex: String?
    var createdAt: String
}

struct CADFallbackPreviewOutputs: Equatable {
    var thumbnailURL: URL?
    var previewSVGURL: URL?
    var previewPDFURL: URL?
    var previewImageURL: URL?
    var previewPageURLs: [URL]
    var previewTileURLs: [URL]
    var searchedDirectories: [URL]

    static let empty = CADFallbackPreviewOutputs(
        thumbnailURL: nil,
        previewSVGURL: nil,
        previewPDFURL: nil,
        previewImageURL: nil,
        previewPageURLs: [],
        previewTileURLs: [],
        searchedDirectories: []
    )

    var hasRenderablePreview: Bool {
        previewSVGURL != nil ||
            previewPDFURL != nil ||
            previewImageURL != nil ||
            thumbnailURL != nil ||
            !previewPageURLs.isEmpty ||
            !previewTileURLs.isEmpty
    }

    var firstImageURL: URL? {
        previewImageURL ?? previewPageURLs.first ?? previewTileURLs.first ?? thumbnailURL
    }

    var summary: String {
        var parts: [String] = []
        if thumbnailURL != nil { parts.append("thumbnail.png") }
        if previewSVGURL != nil { parts.append("preview.svg") }
        if previewPDFURL != nil { parts.append("preview.pdf") }
        if previewImageURL != nil { parts.append("preview image") }
        if !previewPageURLs.isEmpty { parts.append("preview_pages \(previewPageURLs.count)") }
        if !previewTileURLs.isEmpty { parts.append("preview_tiles \(previewTileURLs.count)") }
        return parts.isEmpty ? String(localized: "未找到兼容预览输出") : parts.joined(separator: " · ")
    }
}

enum CADFallbackOutputResolver {
    static func resolve(fileURL: URL) -> CADFallbackPreviewOutputs {
        let directories = candidateDirectories(for: fileURL)
        let previewPDFURL: URL?
        if fileURL.pathExtension.lowercased() == "pdf" {
            previewPDFURL = fileURL
        } else {
            previewPDFURL = firstExistingFile(named: ["preview.pdf"], in: directories)
        }

        return CADFallbackPreviewOutputs(
            thumbnailURL: firstExistingFile(named: ["thumbnail.png"], in: directories),
            previewSVGURL: firstExistingFile(named: ["preview.svg"], in: directories),
            previewPDFURL: previewPDFURL,
            previewImageURL: firstExistingFile(named: ["preview.png", "preview.jpg", "preview.jpeg"], in: directories),
            previewPageURLs: imageFiles(in: firstExistingDirectory(named: "preview_pages", in: directories)),
            previewTileURLs: imageFiles(in: firstExistingDirectory(named: "preview_tiles", in: directories)),
            searchedDirectories: directories
        )
    }

    private static func candidateDirectories(for fileURL: URL) -> [URL] {
        let parent = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return [
            parent.appendingPathComponent("Fallback").appendingPathComponent(stem, isDirectory: true),
            parent.appendingPathComponent("\(stem).fallback", isDirectory: true),
            parent.appendingPathComponent(stem, isDirectory: true),
            parent
        ]
    }

    private static func firstExistingFile(named names: [String], in directories: [URL]) -> URL? {
        for directory in directories {
            for name in names {
                let candidate = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func firstExistingDirectory(named name: String, in directories: [URL]) -> URL? {
        for directory in directories {
            let candidate = directory.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func imageFiles(in directory: URL?) -> [URL] {
        guard let directory else { return [] }
        do {
            return try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            StorageIssueLog.record("CAD 兼容预览目录读取失败：\(directory.lastPathComponent)，\(error.localizedDescription)")
            return []
        }
    }
}
