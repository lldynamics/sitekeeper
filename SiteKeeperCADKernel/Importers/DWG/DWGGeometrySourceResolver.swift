import Foundation

extension SiteKeeperCADKernel {
    struct DWGGeometrySourceResolver {
        var preferredAdapter: (any DWGGeometrySource)?
        var registeredAdapter: (CADFile) -> (any DWGGeometrySource)?
        var sidecarJSONAdapter: DWGSidecarJSONGeometryAdapter?
        var extraAdapters: [any DWGGeometrySource]

        init(
            preferredAdapter: (any DWGGeometrySource)? = nil,
            registeredAdapter: @escaping (CADFile) -> (any DWGGeometrySource)? = { CADDWGGeometryAdapterRegistry.adapter(for: $0) },
            sidecarJSONAdapter: DWGSidecarJSONGeometryAdapter? = DWGSidecarJSONGeometryAdapter(),
            extraAdapters: [any DWGGeometrySource] = []
        ) {
            self.preferredAdapter = preferredAdapter
            self.registeredAdapter = registeredAdapter
            self.sidecarJSONAdapter = sidecarJSONAdapter
            self.extraAdapters = extraAdapters
        }

        func resolveSources(for file: CADFile, context: DWGImportContext = .default) -> [any DWGGeometrySource] {
            var resolved: [any DWGGeometrySource] = []
            var seen = Set<String>()

            func append(_ adapter: (any DWGGeometrySource)?) {
                guard let adapter else { return }
                guard adapter.canImport(file: file, context: context) else { return }
                guard seen.insert(adapter.id).inserted else { return }
                resolved.append(adapter)
            }

            append(preferredAdapter)
            append(sidecarJSONAdapter)
            append(registeredAdapter(file))
            extraAdapters.forEach(append)
            return resolved
        }
    }
}
