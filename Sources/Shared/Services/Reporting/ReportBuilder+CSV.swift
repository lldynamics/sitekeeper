import Foundation

extension ReportBuilder {
    static func makeCSV(snapshot: BackupSnapshot, options: ExportContentOptions) -> Data {
        var rows: [String] = []
        rows += materialCSVRows(snapshot: snapshot, options: options)
        rows += quoteCSVRows(snapshot: snapshot, options: options)
        rows += laborCSVRows(snapshot: snapshot, options: options)
        rows += dailyLogCSVRows(snapshot: snapshot, options: options)
        rows += progressCSVRows(snapshot: snapshot, options: options)
        rows += todoCSVRows(snapshot: snapshot, options: options)
        rows += projectFinanceCSVRows(snapshot: snapshot, options: options)
        rows += projectDocumentCSVRows(snapshot: snapshot, options: options)
        rows += projectContactCSVRows(snapshot: snapshot, options: options)
        rows += projectDrawingCSVRows(snapshot: snapshot, options: options)
        rows += warehouseMovementCSVRows(snapshot: snapshot, options: options)
        rows += quickNoteCSVRows(snapshot: snapshot, options: options)
        rows += operationAuditCSVRows(options: options)
        return csvData(rows: rows)
    }

    /// UTF-8 BOM lets spreadsheet apps detect Chinese text; CRLF separates CSV records.
    static func csvData(rows: [String]) -> Data {
        guard !rows.isEmpty else { return Data() }
        return Data(("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
