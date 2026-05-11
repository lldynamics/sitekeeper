import Foundation

enum MaterialIdentity {
    static func normalizedComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func normalizedCategory(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func key(name: String, specification: String, unit: String) -> String {
        "\(normalizedComponent(name))|\(normalizedComponent(specification))|\(normalizedComponent(unit))"
    }
}
