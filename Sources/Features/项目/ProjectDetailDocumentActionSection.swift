import SwiftUI
import PhotosUI
import UIKit

struct ProjectDetailDocumentActionSection: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onScanDocument: () -> Void
    let onImportFiles: () -> Void
    let onCapturePhoto: () -> Void

    var body: some View {
        Section {
            Menu {
                Button {
                    onScanDocument()
                } label: {
                    Label("扫描项目资料", systemImage: "viewfinder")
                }
                Button {
                    onImportFiles()
                } label: {
                    Label("从文件导入 PDF/图片", systemImage: "doc.badge.plus")
                }
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        onCapturePhoto()
                    } label: {
                        Label("拍照保存", systemImage: "camera")
                    }
                }
            } label: {
                Label("加资料", systemImage: "plus.circle.fill")
            }
        }
    }
}
