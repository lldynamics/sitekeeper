extension SiteKeeperCADKernel {
    enum CADOpenStatus: String, Equatable, Codable {
        case rendered
        case diagnosticOnly
        case unsupported
        case failed

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = (try? container.decode(String.self)) ?? CADOpenStatus.failed.rawValue
            switch rawValue {
            case "opened":
                self = .rendered
            case CADOpenStatus.rendered.rawValue:
                self = .rendered
            case CADOpenStatus.diagnosticOnly.rawValue:
                self = .diagnosticOnly
            case CADOpenStatus.unsupported.rawValue:
                self = .unsupported
            default:
                self = .failed
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    struct CADOpenResult: Equatable, Codable {
        var status: CADOpenStatus
        var database: CADDatabase?
        var diagnostics: CADDrawingDiagnostics

        static func evaluated(_ database: CADDatabase) -> CADOpenResult {
            CADOpenResult(
                status: resolvedStatus(for: database),
                database: database,
                diagnostics: database.diagnostics
            )
        }

        static func unsupported(_ message: String) -> CADOpenResult {
            CADOpenResult(
                status: .unsupported,
                database: nil,
                diagnostics: CADDrawingDiagnostics(entries: [
                    CADDrawingDiagnostics.Entry(severity: .error, code: "CAD_ENGINE_NOT_INSTALLED", message: message)
                ])
            )
        }

        static func failed(_ diagnostics: CADDrawingDiagnostics) -> CADOpenResult {
            CADOpenResult(status: .failed, database: nil, diagnostics: diagnostics)
        }

        private static func resolvedStatus(for database: CADDatabase) -> CADOpenStatus {
            if !database.geometryParsed {
                return database.isDiagnosticOnly || database.entityCount > 0 ? .diagnosticOnly : .unsupported
            }
            if database.drawableEntityCount == 0 {
                if database.isDiagnosticOnly || database.placeholderEntityCount > 0 {
                    return .diagnosticOnly
                }
                return .unsupported
            }
            return .rendered
        }
    }
}
