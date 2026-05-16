extension SiteKeeperCADKernel {
    struct CADProxyObjectHandler {
        func handle(_ entity: CADEntity) -> CADEntity {
            guard entity.kind == .proxy else { return entity }
            var copy = entity
            copy.unsupportedReason = copy.unsupportedReason ?? "Proxy object is preserved as diagnostic metadata."
            if copy.diagnostics.entries.isEmpty {
                copy.diagnostics.entries.append(
                    CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_PROXY_PRESERVED",
                        message: copy.unsupportedReason ?? "Proxy object is preserved as diagnostic metadata.",
                        detail: copy.sourceHandle
                    )
                )
            }
            return copy
        }
    }
}
