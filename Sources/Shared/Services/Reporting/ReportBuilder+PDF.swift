import Foundation

extension ReportBuilder {
    static func makePDF(
        snapshot: BackupSnapshot,
        options: ExportContentOptions,
        title: String = String(format: AppLocalization.string("report_pdf_export_title_format"), AppBrand.displayName)
    ) -> Data {
        var lines: [String] = [title, String(format: AppLocalization.string("生成时间: %@"), Formatters.displayNow()), ""]
        ReportBuilderPDFSections.appendSections(snapshot: snapshot, options: options, lines: &lines)
        return pdfData(lines: lines)
    }
}
