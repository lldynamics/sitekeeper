extension SiteKeeperCADKernel {
    struct CADDrawingDiagnostics: Equatable, Codable {
        enum Severity: String, Equatable, Codable {
            case info
            case warning
            case error
            case blocker
        }

        struct Entry: Identifiable, Equatable, Codable {
            var id: String
            var severity: Severity
            var code: String
            var message: String
            var detail: String?

            enum CodingKeys: String, CodingKey {
                case id
                case severity
                case code
                case message
                case detail
            }

            init(id: String? = nil, severity: Severity, code: String, message: String, detail: String? = nil) {
                self.id = id ?? code
                self.severity = severity
                self.code = code
                self.message = message
                self.detail = detail
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                severity = try container.decode(Severity.self, forKey: .severity)
                code = try container.decode(String.self, forKey: .code)
                message = try container.decode(String.self, forKey: .message)
                detail = try container.decodeIfPresent(String.self, forKey: .detail)
                id = try container.decodeIfPresent(String.self, forKey: .id) ?? code
            }
        }

        var entries: [Entry]

        init(entries: [Entry] = []) {
            self.entries = entries
        }

        var hasBlockers: Bool {
            entries.contains { $0.severity == .blocker }
        }

        mutating func append(_ entry: Entry) {
            entries.append(entry)
        }

        func appending(_ entry: Entry) -> CADDrawingDiagnostics {
            var copy = self
            copy.append(entry)
            return copy
        }

        func merging(_ other: CADDrawingDiagnostics) -> CADDrawingDiagnostics {
            CADDrawingDiagnostics(entries: entries + other.entries)
        }
    }
}
