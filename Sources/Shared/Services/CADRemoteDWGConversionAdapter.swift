import Foundation

struct CADRemoteDWGConversionAdapter: SiteKeeperCADKernel.CADDWGGeometryAdapter {
    let id = "sitekeeper.dwg.libredwg.remote"

    private let endpointProvider: () -> URL?
    private let session: URLSession
    private let fileManager: FileManager

    init(
        endpointProvider: @escaping () -> URL? = { CADRemoteDWGConversionSettings.endpointURL },
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.endpointProvider = endpointProvider
        self.session = session
        self.fileManager = fileManager
    }

    func canImportDWG(file: SiteKeeperCADKernel.CADFile) -> Bool {
        file.format == .dwg && endpointProvider() != nil
    }

    func importDWG(file: SiteKeeperCADKernel.CADFile) async throws -> SiteKeeperCADKernel.CADExternalSDKDrawing {
        guard let configuredEndpoint = endpointProvider() else {
            throw CADRemoteDWGConversionError.missingEndpoint
        }

        let requestURL = conversionEndpoint(from: configuredEndpoint)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(file.displayName, forHTTPHeaderField: "X-SiteKeeper-File-Name")

        let body: Data
        do {
            body = try Data(contentsOf: file.url)
        } catch {
            throw CADRemoteDWGConversionError.unreadableFile(file.url.lastPathComponent)
        }

        let (responseData, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CADRemoteDWGConversionError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let detail = String(data: responseData.prefix(4096), encoding: .utf8) ?? ""
            throw CADRemoteDWGConversionError.httpStatus(httpResponse.statusCode, detail)
        }
        guard !responseData.isEmpty else {
            throw CADRemoteDWGConversionError.emptyResponse
        }

        let sidecarURL = file.url.appendingPathExtension("sitekeeper-cad.json")
        do {
            if fileManager.fileExists(atPath: sidecarURL.path) {
                try fileManager.removeItem(at: sidecarURL)
            }
            try responseData.write(to: sidecarURL, options: .atomic)
        } catch {
            throw CADRemoteDWGConversionError.writeFailed(sidecarURL.lastPathComponent)
        }

        let sidecarFile = SiteKeeperCADKernel.CADFile(
            url: sidecarURL,
            displayName: "\(file.displayName).sitekeeper-cad.json",
            format: .intermediateJSON
        )
        var database = try await SiteKeeperCADKernel.IntermediateJSONImportEngine()
            .importDrawing(file: sidecarFile)
        database.diagnostics.append(
            SiteKeeperCADKernel.CADDrawingDiagnostics.Entry(
                severity: .info,
                code: "CAD_DWG_REMOTE_LIBREDWG_JSON_USED",
                message: "LibreDWG conversion service returned SiteKeeper CAD JSON.",
                detail: requestURL.absoluteString
            )
        )
        database.setImportMetadata(
            geometryParsed: database.drawableEntityCount > 0 && database.geometryParsed,
            isMetadataOnly: database.drawableEntityCount == 0 || !database.geometryParsed,
            importSource: database.drawableEntityCount > 0 ? id : database.importSource
        )
        return SiteKeeperCADKernel.CADExternalSDKDrawing(database: database)
    }

    private func conversionEndpoint(from configuredEndpoint: URL) -> URL {
        let trimmedPath = configuredEndpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmedPath.isEmpty else {
            return configuredEndpoint
        }
        return configuredEndpoint
            .appendingPathComponent("convert")
            .appendingPathComponent("dwg")
    }
}

enum CADRemoteDWGConversionSettings {
    static var endpointURL: URL? {
        endpointURL(from: UserPreferences.string(UserPreferenceKeys.cadDWGConversionServiceURL))
    }

    static func endpointURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        let withScheme = "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else {
            return nil
        }
        return url
    }
}

enum CADRemoteDWGConversionError: LocalizedError, Equatable {
    case missingEndpoint
    case unreadableFile(String)
    case invalidResponse
    case httpStatus(Int, String)
    case emptyResponse
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "CAD conversion service endpoint is not configured."
        case .unreadableFile(let name):
            return "CAD source file is not readable: \(name)"
        case .invalidResponse:
            return "CAD conversion service returned an invalid response."
        case .httpStatus(let statusCode, let detail):
            let suffix = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty
                ? "CAD conversion service failed with HTTP \(statusCode)."
                : "CAD conversion service failed with HTTP \(statusCode): \(suffix)"
        case .emptyResponse:
            return "CAD conversion service returned an empty response."
        case .writeFailed(let name):
            return "CAD conversion result could not be cached: \(name)"
        }
    }
}
