import Foundation

enum FileStorageError: LocalizedError, Equatable {
    case invalidImageData
    case imageEncodingFailed
    case unsupportedFileType(String)
    case directoryCreationFailed(String)
    case copyFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return String(localized: "无法识别图片数据。")
        case .imageEncodingFailed:
            return String(localized: "图片编码失败。")
        case .unsupportedFileType(let type):
            return String(format: String(localized: "暂不支持的文件类型：%@。"), type)
        case .directoryCreationFailed(let name):
            return String(format: String(localized: "无法创建存储目录：%@。"), name)
        case .copyFailed(let name):
            return String(format: String(localized: "文件复制失败：%@。"), name)
        case .writeFailed(let name):
            return String(format: String(localized: "文件写入失败：%@。"), name)
        case .readFailed(let name):
            return String(format: String(localized: "文件读取失败：%@。"), name)
        case .deleteFailed(let name):
            return String(format: String(localized: "文件删除失败：%@。"), name)
        }
    }
}
