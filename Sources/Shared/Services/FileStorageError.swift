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
            return "无法识别图片数据。"
        case .imageEncodingFailed:
            return "图片编码失败。"
        case .unsupportedFileType(let type):
            return "暂不支持的文件类型：\(type)。"
        case .directoryCreationFailed(let name):
            return "无法创建存储目录：\(name)。"
        case .copyFailed(let name):
            return "文件复制失败：\(name)。"
        case .writeFailed(let name):
            return "文件写入失败：\(name)。"
        case .readFailed(let name):
            return "文件读取失败：\(name)。"
        case .deleteFailed(let name):
            return "文件删除失败：\(name)。"
        }
    }
}
