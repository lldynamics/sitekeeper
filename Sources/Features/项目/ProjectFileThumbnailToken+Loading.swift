import UIKit

extension ProjectFileThumbnailToken {
    func loadImageAsync() async -> UIImage? {
        switch self {
        case .photo(let fileName):
            return await PhotoStorage.thumbnailAsync(for: fileName)
        case .quickNote(let kind, let fileName):
            switch kind {
            case .photo, .drawing:
                guard let data = await QuickNoteAttachmentStorage.dataAsync(for: fileName) else { return nil }
                return await loadDetachedThumbnail {
                    guard !Task.isCancelled else { return nil }
                    return ImageDownsampleService.downsampledImage(data, maxPixelSize: 256)
                }
            case .video:
                return await loadDetachedThumbnail {
                    guard !Task.isCancelled else { return nil }
                    return QuickNoteAttachmentStorage.videoThumbnail(for: fileName)
                }
            case .audio, .file:
                return nil
            }
        }
    }

    private func loadDetachedThumbnail(_ work: @escaping @Sendable () -> UIImage?) async -> UIImage? {
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            let image = work()
            guard !Task.isCancelled else { return nil }
            return image
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
