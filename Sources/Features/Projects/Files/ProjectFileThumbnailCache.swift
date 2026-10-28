import UIKit

/// Project rows use the storage cache directly so replacement/deletion invalidation
/// cannot leave a second, independent image cache holding stale pixels.
enum ProjectFileThumbnailCache {
    static func image(for token: ProjectFileThumbnailToken) async -> UIImage? {
        await token.loadImageAsync()
    }
}
