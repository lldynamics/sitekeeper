import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DeprecatedProjectPackageSidecarTests {
    @Test func drawingStorageCopiesLibreDWGSidecarWithImportedDWG() throws {
        let projectId = UUID()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwg-sidecar-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceDWGURL = folder.appendingPathComponent("original.dwg")
        let sourceSidecarURL = sourceDWGURL.appendingPathExtension("sitekeeper-cad.json")
        let sidecarData = Data("""
        {
          "schema": "sitekeeper-cad-worker-v1",
          "importSource": "sitekeeper.dwg.libredwg",
          "geometryParsed": true,
          "isDiagnosticOnly": false,
          "units": { "name": "unitless" },
          "extents": { "minX": 0, "minY": 0, "maxX": 1, "maxY": 1 },
          "layers": [{ "id": "0", "name": "0" }],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "entities": []
        }
        """.utf8)
        try Data("AC1032 source dwg".utf8).write(to: sourceDWGURL, options: .atomic)
        try sidecarData.write(to: sourceSidecarURL, options: .atomic)

        let drawing = try DrawingStorage.saveImportedFileOrThrow(from: sourceDWGURL, projectId: projectId)
        let storedSidecarURL = DrawingStorage.sidecarURL(for: drawing.fileName)
        defer {
            if DrawingStorage.exists(fileName: drawing.fileName) {
                DrawingStorage.delete(fileName: drawing.fileName)
            }
        }

        #expect(FileManager.default.fileExists(atPath: storedSidecarURL.path))
        #expect(try Data(contentsOf: storedSidecarURL) == sidecarData)
        #expect(DrawingStorage.referencedFileNames(for: [drawing]).contains(DrawingStorage.sidecarFileName(for: drawing.fileName)))
        #expect(DrawingStorage.orphanFileNames(for: [drawing]).contains(DrawingStorage.sidecarFileName(for: drawing.fileName)) == false)
        #expect(DrawingStorage.backupFiles(for: [drawing]).contains { $0.fileName == DrawingStorage.sidecarFileName(for: drawing.fileName) })

        DrawingStorage.delete(fileName: drawing.fileName)
        #expect(FileManager.default.fileExists(atPath: storedSidecarURL.path) == false)
    }

    @Test func remoteLibreDWGConversionAdapterCachesReturnedCADDatabase() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwg-remote-conversion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let dwgURL = folder.appendingPathComponent("remote-source.dwg")
        try Data("AC1032 remote dwg".utf8).write(to: dwgURL, options: .atomic)
        let sidecarURL = dwgURL.appendingPathExtension("sitekeeper-cad.json")

        let responseJSON = Data("""
        {
          "schema": "sitekeeper-cad-worker-v1",
          "importSource": "sitekeeper.dwg.libredwg",
          "geometryParsed": true,
          "isDiagnosticOnly": false,
          "units": { "name": "unitless" },
          "extents": { "minX": 0, "minY": 0, "maxX": 10, "maxY": 0 },
          "layers": [{ "id": "0", "name": "0" }],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "textStyles": [{ "id": "standard", "name": "Standard" }],
          "blocks": [],
          "entities": [
            {
              "id": "remote-line-1",
              "type": "line",
              "layerID": "0",
              "start": { "x": 0, "y": 0 },
              "end": { "x": 10, "y": 0 },
              "bounds": { "minX": 0, "minY": 0, "maxX": 10, "maxY": 0 }
            }
          ]
        }
        """.utf8)

        CADRemoteDWGConversionMockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/convert/dwg")
            #expect(request.value(forHTTPHeaderField: "X-SiteKeeper-File-Name") == "remote-source.dwg")
            guard let requestURL = request.url else {
                throw CADRemoteDWGConversionError.invalidResponse
            }
            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) else {
                throw CADRemoteDWGConversionError.invalidResponse
            }
            return (response, responseJSON)
        }
        defer { CADRemoteDWGConversionMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CADRemoteDWGConversionMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let adapter = CADRemoteDWGConversionAdapter(
            endpointProvider: { URL(string: "https://cad.example.test") },
            session: session
        )

        let file = SiteKeeperCADKernel.CADFile(url: dwgURL, displayName: "remote-source.dwg", format: .dwg)
        #expect(adapter.canImportDWG(file: file))

        let drawing = try await adapter.importDWG(file: file)
        #expect(drawing.entities.count == 1)
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))

        let engineDatabase = try await SiteKeeperCADKernel.DWGImportEngine(geometryAdapter: adapter)
            .importDrawing(file: file)
        #expect(engineDatabase.importSource == adapter.id)
        #expect(engineDatabase.drawableEntityCount == 1)

        let database = try await SiteKeeperCADKernel.IntermediateJSONImportEngine().importDrawing(
            file: SiteKeeperCADKernel.CADFile(
                url: sidecarURL,
                displayName: sidecarURL.lastPathComponent,
                format: .intermediateJSON
            )
        )
        #expect(database.geometryParsed)
        #expect(database.drawableEntityCount == 1)
    }

    @Test func cadRemoteConversionEndpointAcceptsHostWithoutScheme() {
        let endpoint = CADRemoteDWGConversionSettings.endpointURL(from: "127.0.0.1:8765")
        #expect(endpoint?.scheme == "http")
        #expect(endpoint?.host == "127.0.0.1")
        #expect(endpoint?.port == 8765)
    }
}

final class CADRemoteDWGConversionMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "cad.example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: CADRemoteDWGConversionError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
