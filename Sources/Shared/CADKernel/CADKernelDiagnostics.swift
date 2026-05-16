import Foundation

struct CADKernelFileInspection: Equatable {
    var fileName: String
    var format: CADKernelFileFormat
    var byteCount: Int
    var allocatedByteCount: Int
    var headerHex: String
    var dwgVersion: String?
    var declaredCodePage: String?
}

enum CADKernelFileInspector {
    static func inspect(fileURL: URL, format: CADKernelFileFormat? = nil) throws -> CADKernelFileInspection {
        let detectedFormat = format ?? CADKernelFileFormat(fileExtension: fileURL.pathExtension)
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        let byteCount = values.fileSize ?? 0
        let allocatedByteCount = values.totalFileAllocatedSize ?? byteCount
        let headerData = try readHeader(fileURL: fileURL, byteLimit: 64)
        let headerHex = headerData.map { String(format: "%02X", $0) }.joined(separator: " ")
        let asciiHeader = String(data: headerData, encoding: .ascii) ?? ""

        return CADKernelFileInspection(
            fileName: fileURL.lastPathComponent,
            format: detectedFormat,
            byteCount: byteCount,
            allocatedByteCount: allocatedByteCount,
            headerHex: headerHex,
            dwgVersion: dwgVersion(in: asciiHeader),
            declaredCodePage: declaredCodePage(in: asciiHeader)
        )
    }

    private static func readHeader(fileURL: URL, byteLimit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        return try handle.read(upToCount: byteLimit) ?? Data()
    }

    private static func dwgVersion(in asciiHeader: String) -> String? {
        guard asciiHeader.hasPrefix("AC") else { return nil }
        let version = String(asciiHeader.prefix(6))
        return version.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : version
    }

    private static func declaredCodePage(in asciiHeader: String) -> String? {
        if asciiHeader.localizedStandardContains("ANSI_936") {
            return "ANSI_936"
        }
        if asciiHeader.localizedStandardContains("GBK") {
            return "GBK"
        }
        if asciiHeader.localizedStandardContains("GB18030") {
            return "GB18030"
        }
        return nil
    }
}

enum CADKernelDiagnosticReportBuilder {
    static func makeReport(
        for fileURL: URL,
        diagnostics: [CADKernelDiagnostic] = [],
        importerID: String? = nil
    ) async throws -> String {
        let inspection = try CADKernelFileInspector.inspect(fileURL: fileURL)
        var lines: [String] = []
        lines.append("CAD 图纸诊断日志")
        lines.append("生成时间：\(Formatters.dateTime.string(from: Date()))")
        lines.append("")
        lines.append("## 新 CAD 内核")
        lines.append("内核：Sitekeeper2DCADKernel")
        lines.append("导入引擎：\(importerID ?? "未指定")")
        lines.append("旧桥接：已停用")
        lines.append("Renderer 输入：CADKernelDocument")
        lines.append("")
        lines.append("## 文件")
        lines.append("文件名：\(inspection.fileName)")
        lines.append("路径：\(fileURL.path)")
        lines.append("类型：\(inspection.format.displayName)")
        lines.append("大小：\(QuickNoteAttachmentStorage.formattedFileSize(inspection.byteCount))")
        lines.append("文件头 Hex：\(inspection.headerHex.isEmpty ? "-" : inspection.headerHex)")
        if let dwgVersion = inspection.dwgVersion {
            lines.append("DWG 版本头：\(dwgVersion)")
        } else if inspection.format == .dwg {
            lines.append("DWG 版本头：未识别")
        }
        if let declaredCodePage = inspection.declaredCodePage {
            lines.append("声明编码：\(declaredCodePage)")
        }
        lines.append("")
        lines.append("## 诊断")

        if diagnostics.isEmpty {
            lines.append("- [warning] CAD_IMPORT_ENGINE_BOOTSTRAP_ONLY：自有 CAD 内核已接管入口，真实 DWG/DXF ImportEngine 待接入。")
        } else {
            for diagnostic in diagnostics.sorted(by: diagnosticSort) {
                let detail = diagnostic.detail.isEmpty ? "" : "；\(diagnostic.detail)"
                lines.append("- [\(diagnostic.severity.rawValue)] \(diagnostic.code)：\(diagnostic.message)\(detail)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func diagnosticSort(_ lhs: CADKernelDiagnostic, _ rhs: CADKernelDiagnostic) -> Bool {
        if lhs.severity.sortRank != rhs.severity.sortRank {
            return lhs.severity.sortRank < rhs.severity.sortRank
        }
        return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
    }
}
