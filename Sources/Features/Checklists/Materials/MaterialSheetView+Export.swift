import SwiftUI

extension MaterialSheetView {
    func exportAsPDF() {
        isExporting = true
        defer { isExporting = false }
        let data = MaterialSheetExportRenderer.generatePDF(
            sheetItems: sheetItems,
            options: exportOptions,
            exportProjectName: exportProjectName,
            exportPreparer: exportPreparer
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("material_sheet_\(MaterialSheetExportRenderer.timestampToken()).pdf")
        do {
            try data.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    func exportAsCSV() {
        isExporting = true
        defer { isExporting = false }
        let data = Data(
            MaterialSheetExportRenderer.generateCSV(
                sheetItems: sheetItems,
                options: exportOptions
            ).utf8
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("material_sheet_\(MaterialSheetExportRenderer.timestampToken()).csv")
        do {
            try data.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    func exportAsImage() {
        isExporting = true
        defer { isExporting = false }
        guard let data = MaterialSheetExportRenderer.generateImage(
            sheetItems: sheetItems,
            options: exportOptions,
            exportProjectName: exportProjectName,
            exportPreparer: exportPreparer
        ) else {
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("material_sheet_\(MaterialSheetExportRenderer.timestampToken()).png")
        do {
            try data.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    func cleanupExportFileIfNeeded() {
        guard let exportFileURL else { return }
        do {
            _ = try FileOps.removeIfExists(
                at: exportFileURL,
                context: .init(
                    event: "material_sheet.cleanup_export_file",
                    category: .fileStorage,
                    source: "MaterialSheetView.cleanupExportFileIfNeeded"
                )
            )
        } catch {
            StorageIssueLog.recordEvent(
                "material_sheet.cleanup_export_file_failed",
                category: .fileStorage,
                details: ["file": exportFileURL.lastPathComponent],
                error: error
            )
        }
        self.exportFileURL = nil
        showExportChoice = false
    }
}
