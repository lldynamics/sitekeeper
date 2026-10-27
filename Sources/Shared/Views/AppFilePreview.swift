import SwiftUI
import QuickLook

enum AppFilePreviewRoute: Equatable {
    case pdf
    case quickLook

    static func route(for url: URL) -> Self {
        url.pathExtension.lowercased() == "pdf" ? .pdf : .quickLook
    }

    static func dismiss(_ route: Self, selection: inout URL?) {
        guard let current = selection, Self.route(for: current) == route else { return }
        selection = nil
    }
}

extension View {
    func appFilePreview(_ selection: Binding<URL?>) -> some View {
        modifier(AppFilePreviewModifier(selection: selection))
    }
}

private struct AppPDFPreviewItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct AppFilePreviewModifier: ViewModifier {
    @Binding var selection: URL?

    func body(content: Content) -> some View {
        content
            .sheet(item: pdfSelection) { item in
                AppPDFPreviewSheet(url: item.url)
            }
            .quickLookPreview(quickLookSelection)
    }

    private var pdfSelection: Binding<AppPDFPreviewItem?> {
        Binding(
            get: {
                guard let selection, AppFilePreviewRoute.route(for: selection) == .pdf else { return nil }
                return AppPDFPreviewItem(url: selection)
            },
            set: { item in
                if let item { selection = item.url } else {
                    AppFilePreviewRoute.dismiss(.pdf, selection: &selection)
                }
            }
        )
    }

    private var quickLookSelection: Binding<URL?> {
        Binding(
            get: {
                guard let selection, AppFilePreviewRoute.route(for: selection) == .quickLook else { return nil }
                return selection
            },
            set: { url in
                if let url { selection = url } else {
                    AppFilePreviewRoute.dismiss(.quickLook, selection: &selection)
                }
            }
        )
    }
}

private struct AppPDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            AppPDFDocumentView(url: url)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppLocalization.string("关闭")) { dismiss() }
                            .accessibilityIdentifier("app-pdf-preview-close")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Label(AppLocalization.string("分享/打开"), systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("app-pdf-preview-share")
                    }
                }
        }
    }
}
