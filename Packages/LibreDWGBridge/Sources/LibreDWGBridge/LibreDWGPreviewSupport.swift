import Foundation
import SwiftUI
import PDFKit

enum PreviewState {
    case loading
    case dxf(DXFPreviewModel, String?)
    case pdf(URL, String?)
    case dwgMetadata(DWGMetadata)
    case failed(String)
}

struct DWGMetadata {
    let fileName: String
    let fileSize: String
    let modifiedAt: String
    let headerHex: String
    let hints: [String]

    static func from(fileURL: URL, hints: [String] = []) throws -> DWGMetadata {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let bytes = values.fileSize ?? 0
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        sizeFormatter.countStyle = .file
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let modified = values.contentModificationDate.map(dateFormatter.string(from:)) ?? "-"

        let raw = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let header = raw.prefix(32)
        let hex = header.map { String(format: "%02X", $0) }.joined(separator: " ")

        return DWGMetadata(
            fileName: fileURL.lastPathComponent,
            fileSize: sizeFormatter.string(fromByteCount: Int64(bytes)),
            modifiedAt: modified,
            headerHex: hex,
            hints: hints
        )
    }
}

struct DWGSidecarFiles {
    var dxfURL: URL?
    var pdfURL: URL?

    var hints: [String] {
        var value: [String] = []
        if let pdfURL {
            value.append("检测到同名 PDF：\(pdfURL.lastPathComponent)")
        }
        return value
    }
}

enum DWGSidecarResolver {
    static func resolve(for dwgURL: URL) -> DWGSidecarFiles {
        let baseName = dwgURL.deletingPathExtension().lastPathComponent
        let normalized = normalize(baseName)
        guard !normalized.isEmpty else { return DWGSidecarFiles() }

        let folder = dwgURL.deletingLastPathComponent()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return DWGSidecarFiles()
        }

        var result = DWGSidecarFiles()
        for candidate in urls {
            let ext = candidate.pathExtension.lowercased()
            guard ext == "dxf" || ext == "pdf" else { continue }
            let candidateNormalized = normalize(candidate.deletingPathExtension().lastPathComponent)
            guard candidateNormalized == normalized else { continue }
            if ext == "dxf", result.dxfURL == nil {
                result.dxfURL = candidate
            } else if ext == "pdf", result.pdfURL == nil {
                result.pdfURL = candidate
            }
        }
        return result
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[\\s_\\-]+", with: "", options: .regularExpression)
    }
}

struct DWGMetadataPreview: View {
    let fileURL: URL
    let info: DWGMetadata

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("DWG 元数据视图", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("已尝试使用 LibreDWG C 内核解析这份 DWG，但没有生成可显示的基础几何。DWG 原件已保留，可继续归档和外部打开。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Group {
                    metadataRow("文件", info.fileName)
                    metadataRow("大小", info.fileSize)
                    metadataRow("修改时间", info.modifiedAt)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("文件头（前 32 字节）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(info.headerHex)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if !info.hints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("可用替代预览")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(info.hints, id: \.self) { hint in
                            Label(hint, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ShareLink(item: fileURL) {
                    Label("用其他 CAD App 打开", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }
}

struct PDFSidecarPreview: View {
    let fileURL: URL
    let sourceHint: String?

    var body: some View {
        VStack(spacing: 10) {
            if let sourceHint, !sourceHint.isEmpty {
                Label(sourceHint, systemImage: "arrow.triangle.swap")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            PDFKitView(url: fileURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(10)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
