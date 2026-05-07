import SwiftUI
import UIKit

struct FileURLDocumentExporter: UIViewControllerRepresentable {
    let fileURL: URL
    let onCompletion: (Result<URL, Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        controller.delegate = context.coordinator
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<URL, Error>) -> Void

        init(onCompletion: @escaping (Result<URL, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onCompletion(.success(url))
            } else {
                onCompletion(.failure(CocoaError(.fileNoSuchFile)))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.failure(CocoaError(.userCancelled)))
        }
    }
}
