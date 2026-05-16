import Foundation

struct CADKernelImportRequest: Equatable {
    var fileURL: URL
    var format: CADKernelFileFormat
    var preferredLayoutID: String?
    var visibleLayerIDs: Set<String>?

    init(
        fileURL: URL,
        format: CADKernelFileFormat? = nil,
        preferredLayoutID: String? = nil,
        visibleLayerIDs: Set<String>? = nil
    ) {
        self.fileURL = fileURL
        self.format = format ?? CADKernelFileFormat(fileExtension: fileURL.pathExtension)
        self.preferredLayoutID = preferredLayoutID
        self.visibleLayerIDs = visibleLayerIDs
    }
}

struct CADKernelImportResult: Equatable {
    var document: CADKernelDocument
    var diagnostics: [CADKernelDiagnostic]

    init(document: CADKernelDocument, diagnostics: [CADKernelDiagnostic] = []) {
        self.document = document
        self.diagnostics = diagnostics
    }
}

protocol CADKernelImportEngine {
    var id: String { get }
    var displayName: String { get }
    var supportedFormats: Set<CADKernelFileFormat> { get }

    func canImport(_ request: CADKernelImportRequest) -> Bool
    func importDocument(_ request: CADKernelImportRequest) async throws -> CADKernelImportResult
}

extension CADKernelImportEngine {
    func canImport(_ request: CADKernelImportRequest) -> Bool {
        supportedFormats.contains(request.format)
    }
}

@MainActor
enum CADKernelImportRegistry {
    private static var engines: [CADKernelImportEngine] = [
        CADKernelDiagnosticImportEngine()
    ]

    static func register(_ engine: CADKernelImportEngine) {
        engines.removeAll { $0.id == engine.id }
        engines.append(engine)
    }

    static func replaceEnginesForTesting(_ replacement: [CADKernelImportEngine]) {
        engines = replacement
    }

    static func resetDefaultEngines() {
        engines = [CADKernelDiagnosticImportEngine()]
    }

    static func registeredEngineIDs() -> [String] {
        engines.map(\.id)
    }

    static func importDocument(_ request: CADKernelImportRequest) async -> CADKernelImportResult {
        guard let engine = engines.first(where: { $0.canImport(request) }) else {
            return CADKernelImportResult(
                document: CADKernelDocument(
                    metadata: CADKernelMetadata(
                        sourceFileName: request.fileURL.lastPathComponent,
                        sourceFormat: request.format,
                        importerID: "none"
                    ),
                    diagnostics: [
                        CADKernelDiagnostic(
                            severity: .blocker,
                            code: "CAD_IMPORT_ENGINE_MISSING",
                            message: "没有可用的 CAD 导入引擎",
                            detail: "新内核已接管看图入口，但当前文件类型没有注册 ImportEngine。"
                        )
                    ]
                )
            )
        }

        do {
            return try await engine.importDocument(request)
        } catch {
            let diagnostic = CADKernelDiagnostic(
                severity: .blocker,
                code: "CAD_IMPORT_FAILED",
                message: "CAD 导入失败",
                detail: error.localizedDescription,
                source: engine.id
            )
            let document = CADKernelDocument(
                metadata: CADKernelMetadata(
                    sourceFileName: request.fileURL.lastPathComponent,
                    sourceFormat: request.format,
                    importerID: engine.id
                ),
                diagnostics: [diagnostic]
            )
            return CADKernelImportResult(document: document, diagnostics: [diagnostic])
        }
    }
}

struct CADKernelDiagnosticImportEngine: CADKernelImportEngine {
    let id = "sitekeeper.diagnostic-import"
    let displayName = "工地掌柜 CAD 诊断导入"
    let supportedFormats: Set<CADKernelFileFormat> = [.dwg, .dxf]

    func importDocument(_ request: CADKernelImportRequest) async throws -> CADKernelImportResult {
        let header = try CADKernelFileInspector.inspect(fileURL: request.fileURL, format: request.format)
        let diagnostics = diagnostics(for: request, header: header)
        let document = CADKernelDocument(
            metadata: CADKernelMetadata(
                sourceFileName: request.fileURL.lastPathComponent,
                sourceFormat: request.format,
                dwgVersion: header.dwgVersion,
                declaredCodePage: header.declaredCodePage,
                importerID: id
            ),
            diagnostics: diagnostics
        )
        return CADKernelImportResult(document: document, diagnostics: diagnostics)
    }

    private func diagnostics(
        for request: CADKernelImportRequest,
        header: CADKernelFileInspection
    ) -> [CADKernelDiagnostic] {
        var result: [CADKernelDiagnostic] = [
                CADKernelDiagnostic(
                    severity: .warning,
                    code: "CAD_IMPORT_ENGINE_BOOTSTRAP_ONLY",
                    message: "CAD 诊断 ImportEngine 已接管入口，真实几何解析待接入",
                    detail: "当前阶段只生成统一文档模型和诊断，旧 CAD 桥接链路已停用。",
                    source: id
                )
        ]

        if request.format == .dwg, header.dwgVersion == nil {
            result.append(
                CADKernelDiagnostic(
                    severity: .error,
                    code: "CAD_DWG_VERSION_UNKNOWN",
                    message: "未识别 DWG 版本头",
                    detail: "导入引擎接入后必须把 DWG 版本、错误码和不支持对象写入诊断。",
                    source: id
                )
            )
        }

        if request.format == .dxf {
            result.append(
                CADKernelDiagnostic(
                    severity: .info,
                    code: "CAD_DXF_ENGINE_PENDING",
                    message: "DXF 诊断导入已接管，完整几何解析待完善",
                    detail: "新内核可以接入自研 DXF ImportEngine，Renderer 只消费 CADKernelDocument。",
                    source: id
                )
            )
        }

        if header.byteCount == 0 {
            result.append(
                CADKernelDiagnostic(
                    severity: .blocker,
                    code: "CAD_FILE_EMPTY",
                    message: "图纸文件为空",
                    detail: request.fileURL.lastPathComponent,
                    source: id
                )
            )
        }

        return result
    }
}
