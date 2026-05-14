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
    let dwgVersion: String
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

        let header = try readPrefixBytes(fileURL: fileURL, count: 32)
        let magic = String(data: header.prefix(6), encoding: .ascii) ?? ""
        let hex = header.map { String(format: "%02X", $0) }.joined(separator: " ")

        return DWGMetadata(
            fileName: fileURL.lastPathComponent,
            fileSize: sizeFormatter.string(fromByteCount: Int64(bytes)),
            modifiedAt: modified,
            dwgVersion: dwgVersionDescription(for: magic),
            headerHex: hex,
            hints: hints
        )
    }

    private static func readPrefixBytes(fileURL: URL, count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    }

    private static func dwgVersionDescription(for magic: String) -> String {
        switch magic {
        case "AC1009":
            return "AutoCAD R12 (AC1009)"
        case "AC1012":
            return "AutoCAD R13 (AC1012)"
        case "AC1014":
            return "AutoCAD R14 (AC1014)"
        case "AC1015":
            return "AutoCAD 2000/2000i/2002 (AC1015)"
        case "AC1018":
            return "AutoCAD 2004/2005/2006 (AC1018)"
        case "AC1021":
            return "AutoCAD 2007/2008/2009 (AC1021)"
        case "AC1024":
            return "AutoCAD 2010/2011/2012 (AC1024)"
        case "AC1027":
            return "AutoCAD 2013-2017 (AC1027)"
        case "AC1032":
            return "AutoCAD 2018-2025 (AC1032)"
        case "AC1036":
            return "AutoCAD 2026+ (AC1036)"
        case "":
            return "无法读取 DWG 版本"
        default:
            return "\(magic)（未知 DWG 版本）"
        }
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
                Text("当前显示这份 DWG 的文件信息。应用会按 DWG 原文件解析，不使用 PDF/DXF 代理预览。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Group {
                    metadataRow("文件", info.fileName)
                    metadataRow("大小", info.fileSize)
                    metadataRow("修改时间", info.modifiedAt)
                    metadataRow("DWG 版本", info.dwgVersion)
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
                        Text("打不开原因")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                        ForEach(info.hints, id: \.self) { hint in
                            Label(hint, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
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
