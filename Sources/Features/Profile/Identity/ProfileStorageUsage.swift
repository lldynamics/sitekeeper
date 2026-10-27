import Foundation

enum ProfileStorageUsage {
    nonisolated static func formattedFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    nonisolated static func calculateLocalStorageUsage() -> (totalBytes: Int64, fileCount: Int)? {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: documentsDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var totalBytes: Int64 = 0
        var fileCount = 0
        while let object = autoreleasepool(invoking: { enumerator.nextObject() }) {
            guard let fileURL = object as? URL else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            totalBytes += Int64(size)
            fileCount += 1
        }
        return (totalBytes, fileCount)
    }
}
