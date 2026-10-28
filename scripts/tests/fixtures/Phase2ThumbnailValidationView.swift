#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit

/// Opt-in component acceptance surface, available only in an isolated simulator build.
struct Phase2ThumbnailValidationView: View {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            && ProcessInfo.processInfo.environment["UITEST_PHASE2_THUMBNAILS"] == "1"
            && Bundle.main.bundleIdentifier?.contains(".validation.followup.") == true
    }

    @State private var fixture: Phase2ThumbnailFixture?
    @State private var revision = 0
    @State private var showsImages = true
    @State private var pointSize: CGFloat = 96
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("隔离缩略图验证").font(.headline)
            if let fixture {
                if showsImages { thumbnails(fixture) }
                Text("样本版本 \(revision)").accessibilityIdentifier("phase2-image-revision")
                Button("替换同名样本") { replace(fixture) }
                    .accessibilityIdentifier("phase2-replace-images")
                Button("发送内存警告") {
                    NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
                }.accessibilityIdentifier("phase2-memory-warning")
                Button("切换缩略图尺寸") { pointSize = pointSize == 96 ? 32 : 96 }
                    .accessibilityIdentifier("phase2-resize-images")
                Button("显示或隐藏缩略图") { showsImages.toggle() }
                    .accessibilityIdentifier("phase2-toggle-images")
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).accessibilityIdentifier("phase2-fixture-error")
            }
        }
        .padding()
        .task {
            guard fixture == nil else { return }
            do {
                fixture = try Phase2ThumbnailFixture()
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    private func thumbnails(_ fixture: Phase2ThumbnailFixture) -> some View {
        HStack(spacing: 16) {
            AsyncPhotoThumbnailImageView(fileName: fixture.photoName, maxPointSize: pointSize) { image in
                image.resizable().scaledToFill()
            } placeholder: { Color.gray }
            .frame(width: 80, height: 80).clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("照片缩略图")
            .accessibilityIdentifier("phase2-photo-image")

            AsyncQuickNoteAttachmentImageView(fileName: fixture.attachmentName, maxPointSize: pointSize) { image in
                image.resizable().scaledToFill()
            } placeholder: { Color.gray }
            .frame(width: 80, height: 80).clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("附件缩略图")
            .accessibilityIdentifier("phase2-attachment-image")

            ProjectFileThumbnail(item: fixture.projectFile)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("项目文件缩略图")
                .accessibilityIdentifier("phase2-project-image")
        }
    }

    private func replace(_ fixture: Phase2ThumbnailFixture) {
        do {
            try fixture.replace(color: revision.isMultiple(of: 2) ? .blue : .red)
            revision += 1
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

@MainActor
private struct Phase2ThumbnailFixture {
    let photoName = "phase2-ui-photo-\(UUID().uuidString).jpg"
    let attachmentName = "phase2-ui-attachment-\(UUID().uuidString).jpg"

    init() throws { try replace(color: .red) }

    func replace(color: UIColor) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
            .jpegData(withCompressionQuality: 0.9) { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            }
        _ = try PhotoStorage.saveOrThrow(original: data, fileName: photoName)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(data, fileName: attachmentName)
    }

    var projectFile: ProjectFileItem {
        ProjectFileItem(
            id: photoName, title: "独立照片", subtitle: "合成样本", fileType: "jpg",
            url: PhotoStorage.fileURL(for: photoName), exists: true, size: 0,
            category: .images, systemImage: "photo", thumbnailToken: .photo(fileName: photoName),
            sortDate: Date(timeIntervalSince1970: 0), documentStatus: nil
        )
    }
}
#endif
