import Foundation

/// 常用材料库条目
struct CommonMaterial: Identifiable, Codable {
    let name: String
    let specification: String
    let unit: String
    let category: MaterialCategory

    var id: String {
        [category.catalogKey, name, specification, unit].joined(separator: "|")
    }
}

enum MaterialCategory: String, CaseIterable, Identifiable, Codable {
    case wire = "电线"
    case cable = "电缆"
    case conduit = "线管"
    case tray = "桥架"
    case socket = "开关插座"
    case panel = "配电箱"
    case breaker = "断路器"
    case lighting = "灯具"
    case waterPipe = "水管/给排水"
    case fireProtection = "消防材料"
    case lowCurrent = "弱电/智能化"
    case accessory = "辅材/五金"
    case hvac = "暖通材料"
    case civil = "土建材料"
    case waterproof = "防水材料"
    case tools = "工具/仪器"
    case other = "其他"

    var displayName: String { rawValue }

    var id: String { rawValue }

    fileprivate var catalogKey: String {
        switch self {
        case .wire:
            return "wire"
        case .cable:
            return "cable"
        case .conduit:
            return "conduit"
        case .tray:
            return "tray"
        case .socket:
            return "socket"
        case .panel:
            return "panel"
        case .breaker:
            return "breaker"
        case .lighting:
            return "lighting"
        case .waterPipe:
            return "waterPipe"
        case .fireProtection:
            return "fireProtection"
        case .lowCurrent:
            return "lowCurrent"
        case .accessory:
            return "accessory"
        case .hvac:
            return "hvac"
        case .civil:
            return "civil"
        case .waterproof:
            return "waterproof"
        case .tools:
            return "tools"
        case .other:
            return "other"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let category = Self.allCases.first(where: { $0.rawValue == rawValue || $0.catalogKey == rawValue }) {
            self = category
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported material category: \(rawValue)"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(catalogKey)
    }
}

/// 预置常用材料库
enum MaterialLibrary {
    private static let catalogResourceName = "CommonMaterialCatalog"
    private static let catalogSubdirectory = "Materials"

    static var all: [CommonMaterial] { catalogIndex.all }

    static var byCategory: [MaterialCategory: [CommonMaterial]] { catalogIndex.byCategory }

    static func materials(for category: MaterialCategory) -> [CommonMaterial] {
        catalogIndex.byCategory[category] ?? []
    }

    static func decodeCatalog(from data: Data) throws -> [CommonMaterial] {
        try JSONDecoder().decode([CommonMaterial].self, from: data)
    }

    private static let catalogIndex = CatalogIndex(materials: CatalogLoader.load())

    private struct CatalogIndex {
        let all: [CommonMaterial]
        let byCategory: [MaterialCategory: [CommonMaterial]]

        init(materials: [CommonMaterial]) {
            self.all = materials
            self.byCategory = Dictionary(grouping: materials, by: \.category)
        }
    }

    private enum CatalogLoader {
        static func load() -> [CommonMaterial] {
            guard let data = loadCatalogData() else {
                StorageIssueLog.recordEvent(
                    "common_material_catalog.missing",
                    category: .dataStore,
                    details: ["file": catalogFileName]
                )
                return []
            }

            do {
                return try MaterialLibrary.decodeCatalog(from: data)
            } catch {
                StorageIssueLog.recordEvent(
                    "common_material_catalog.decode_failed",
                    category: .dataStore,
                    details: ["file": catalogFileName],
                    error: error
                )
                return []
            }
        }

        private static func loadCatalogData() -> Data? {
            for bundle in candidateBundles {
                let urls = [
                    bundle.url(
                        forResource: MaterialLibrary.catalogResourceName,
                        withExtension: "json",
                        subdirectory: MaterialLibrary.catalogSubdirectory
                    ),
                    bundle.url(
                        forResource: MaterialLibrary.catalogResourceName,
                        withExtension: "json"
                    )
                ].compactMap { $0 }

                for url in urls {
                    if let data = try? Data(contentsOf: url) {
                        return data
                    }
                }
            }
            return nil
        }

        private static var candidateBundles: [Bundle] {
            let bundles = [Bundle.main, Bundle(for: BundleToken.self)] + Bundle.allFrameworks
            var seen = Set<String>()
            return bundles.filter { seen.insert($0.bundleURL.path).inserted }
        }

        private static var catalogFileName: String {
            "\(MaterialLibrary.catalogSubdirectory)/\(MaterialLibrary.catalogResourceName).json"
        }

        private final class BundleToken {}
    }
}
