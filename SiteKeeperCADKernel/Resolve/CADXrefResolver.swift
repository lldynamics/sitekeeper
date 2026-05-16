extension SiteKeeperCADKernel {
    struct CADXrefResolver {
        func resolve(database: CADDatabase) -> CADDatabase {
            var copy = database
            let unresolved = database.entities.filter { $0.kind == .xref }
            unresolved.forEach { entity in
                copy.diagnostics.entries.append(
                    CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_XREF_UNRESOLVED",
                        message: "External reference is not resolved.",
                        detail: entity.sourceHandle
                    )
                )
            }
            return copy
        }
    }
}
