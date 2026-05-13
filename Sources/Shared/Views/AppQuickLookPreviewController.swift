import SwiftUI
import QuickLook

struct AppQuickLookPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let previewController = QLPreviewController()
        previewController.dataSource = context.coordinator
        let navigationController = UINavigationController(rootViewController: previewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.url = url
        guard let previewController = controller.viewControllers.first as? QLPreviewController else {
            return
        }
        previewController.dataSource = context.coordinator
        previewController.currentPreviewItemIndex = 0
        previewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
