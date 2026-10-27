import SwiftUI

extension ProjectDetailContainer {
    var editingMaterialBinding: Binding<MaterialItem?> {
        Binding(
            get: {
                guard case .material(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .material(item)
                case (.material, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }

    var editingQuoteBinding: Binding<QuoteItem?> {
        Binding(
            get: {
                guard case .quote(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .quote(item)
                case (.quote, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }

    var editingLaborBinding: Binding<LaborRecord?> {
        Binding(
            get: {
                guard case .labor(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .labor(item)
                case (.labor, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }

    var editingProgressBinding: Binding<ProgressTask?> {
        Binding(
            get: {
                guard case .progress(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .progress(item)
                case (.progress, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }
}
