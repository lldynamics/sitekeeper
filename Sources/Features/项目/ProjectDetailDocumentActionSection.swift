import SwiftUI
import PhotosUI
import UIKit

struct ProjectDetailDocumentActionSection: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var imagePickerSource: UIImagePickerController.SourceType
    @Binding var showImagePicker: Bool
    @Binding var showDocumentScanSetup: Bool
    @Binding var showDocumentFileImporter: Bool

    var body: some View {
        Section("资料操作") {
            Menu {
                Button {
                    showDocumentScanSetup = true
                } label: {
                    Label("扫描项目资料", systemImage: "viewfinder")
                }
                Button {
                    showDocumentFileImporter = true
                } label: {
                    Label("从文件导入 PDF/图片", systemImage: "doc.badge.plus")
                }
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        imagePickerSource = .camera
                        showImagePicker = true
                    } label: {
                        Label("拍照保存", systemImage: "camera")
                    }
                }
            } label: {
                Label("添加资料", systemImage: "plus.circle.fill")
            }
        }
    }
}
