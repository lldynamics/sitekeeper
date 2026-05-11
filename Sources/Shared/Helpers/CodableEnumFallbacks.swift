import Foundation

enum StringEnumFallback {
    static func value<T>(
        _ rawValue: String,
        default defaultValue: T
    ) -> T where T: RawRepresentable, T.RawValue == String {
        T(rawValue: rawValue) ?? defaultValue
    }

    static func value<T>(
        _ rawValue: String?,
        default defaultValue: T
    ) -> T where T: RawRepresentable, T.RawValue == String {
        guard let rawValue else { return defaultValue }
        return value(rawValue, default: defaultValue)
    }
}

extension KeyedDecodingContainer {
    func decodeStringEnum<T>(
        _ type: T.Type,
        forKey key: Key,
        default defaultValue: T
    ) throws -> T where T: RawRepresentable, T.RawValue == String {
        let rawValue = try decodeIfPresent(String.self, forKey: key)
        return StringEnumFallback.value(rawValue, default: defaultValue)
    }
}
