import Foundation

extension ReportBuilder {
    static func makePDF(snapshot: BackupSnapshot, options: ExportContentOptions, title: String = "\(AppBrand.displayName) 数据导出") -> Data {
        var lines: [String] = [title, "生成时间: \(Formatters.displayNow())", ""]
        ReportBuilderPDFSections.appendSections(snapshot: snapshot, options: options, lines: &lines)
        return pdfData(lines: lines)
    }
}
