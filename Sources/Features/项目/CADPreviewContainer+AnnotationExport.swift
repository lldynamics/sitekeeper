import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    func exportAnnotationSummary(format: CADAnnotationExportFormat) {
        let rows = annotationExportRows()
        switch format {
        case .csv:
            let csv = rows.map(csvRow).joined(separator: "\n")
            annotationExportPayload = ExportPayload(
                data: Data(csv.utf8),
                contentType: .commaSeparatedText,
                defaultFilename: annotationExportFileName(format: .csv)
            )
        case .pdf:
            guard let data = buildAnnotationSummaryPDF(rows: rows) else {
                alertMessage = String(localized: "PDF 导出失败，当前设备不支持该导出路径。")
                showAlert = true
                return
            }
            guard !data.isEmpty else {
                alertMessage = String(localized: "PDF 导出失败，导出内容为空。")
                showAlert = true
                return
            }
            annotationExportPayload = ExportPayload(
                data: data,
                contentType: .pdf,
                defaultFilename: annotationExportFileName(format: .pdf)
            )
        }
    }

    func annotationExportRows() -> [[String]] {
        var rows: [[String]] = [[
            String(localized: "类型"),
            String(localized: "名称"),
            String(localized: "内容"),
            String(localized: "数量"),
            String(localized: "单位"),
            String(localized: "来源"),
            String(localized: "图层"),
            String(localized: "颜色"),
            String(localized: "坐标"),
            String(localized: "时间")
        ]]

        for stroke in snapshot.strokes {
            rows.append([
                stroke.kind == .cloud ? String(localized: "云线") : String(localized: "批注线"),
                "",
                "\(stroke.points.count) \(String(localized: "点"))",
                "",
                "",
                String(localized: "图纸批注"),
                strokeLayerName(stroke),
                strokeColorHex(stroke),
                coordinateListText(stroke.points.map(\.cgPoint)),
                ""
            ])
        }

        for arrow in snapshot.arrowAnnotations {
            rows.append([
                String(localized: "箭头"),
                "",
                String(localized: "箭头批注"),
                "",
                "",
                String(localized: "图纸批注"),
                strokeLayerName(arrow),
                arrowColorHex(arrow),
                coordinateListText([arrow.start.cgPoint, arrow.end.cgPoint]),
                arrow.createdAt
            ])
        }

        for measurement in snapshot.lengthMeasurements {
            rows.append([
                String(localized: "线长"),
                measurement.name,
                lengthLabel(for: measurement.points.map(\.cgPoint)),
                Formatters.number(lengthInMeters(for: measurement.points.map(\.cgPoint)), minFraction: 2, maxFraction: 3),
                "m",
                String(localized: "测量"),
                "",
                lengthMeasurementColorHex(measurement),
                coordinateListText(measurement.points.map(\.cgPoint)),
                ""
            ])
        }

        for measurement in snapshot.areaMeasurements {
            rows.append([
                String(localized: "面积"),
                measurement.name,
                areaLabel(for: measurement.points.map(\.cgPoint)),
                Formatters.number(areaInSquareMeters(for: measurement.points.map(\.cgPoint)), minFraction: 2, maxFraction: 3),
                "m²",
                String(localized: "测量"),
                "",
                areaMeasurementColorHex(measurement),
                coordinateListText(measurement.points.map(\.cgPoint)),
                ""
            ])
        }

        for note in snapshot.notes {
            rows.append([
                String(localized: "文字批注"),
                "",
                note.text,
                "",
                "",
                String(localized: "图纸批注"),
                "",
                noteColorHex(note),
                coordinateText(note.point.cgPoint),
                note.createdAt
            ])
        }

        for marker in snapshot.countMarkers {
            rows.append([
                String(localized: "数数"),
                marker.category,
                marker.category,
                "1",
                String(localized: "个"),
                String(localized: "点位"),
                "",
                "",
                coordinateText(marker.point.cgPoint),
                marker.createdAt
            ])
        }

        for marker in snapshot.issueMarkers {
            rows.append([
                String(localized: "问题点"),
                marker.title,
                marker.photoFileName == nil ? marker.note : "\(marker.note) \(String(localized: "照片"))：\(marker.photoFileName ?? "")",
                "1",
                String(localized: "个"),
                String(localized: "兼容预览"),
                issueMarkerLayerText(marker),
                issueMarkerColorHex(marker),
                coordinateText(marker.normalizedPoint.cgPoint),
                marker.createdAt
            ])
        }

        for item in snapshot.quantityItems {
            rows.append([
                String(localized: "算量"),
                item.name,
                "\(item.quantity) \(item.unit)",
                item.quantity,
                item.unit,
                item.source,
                "",
                "",
                quantitySourceCoordinateText(item),
                ""
            ])
        }
        return rows
    }

    func annotationExportFileName(format: CADAnnotationExportFormat) -> String {
        let baseName = activeRequest.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = baseName.isEmpty ? activeRequest.fileURL.deletingPathExtension().lastPathComponent : baseName
        switch format {
        case .csv:
            return "\(name)_CAD批注测量.csv"
        case .pdf:
            return "\(name)_CAD批注测量.pdf"
        }
    }

    func buildAnnotationSummaryPDF(rows: [[String]]) -> Data? {
#if os(iOS)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5)
        ]
        let headerLine = rows.first?.joined(separator: " | ") ?? ""
        let contentLines = rows.dropFirst().map { $0.joined(separator: " | ") }

        let data = renderer.pdfData { context in
            var y: CGFloat = 40
            var lineIndex = 0
            let leftInset: CGFloat = 24
            let rightInset: CGFloat = 24
            let lineHeight: CGFloat = 16
            let bodyWidth = pageRect.width - leftInset - rightInset

            func beginPage() {
                context.beginPage()
                y = 40
                (String(localized: "CAD 批注测量导出") as NSString)
                    .draw(in: CGRect(x: leftInset, y: y, width: bodyWidth, height: 22), withAttributes: titleAttributes)
                y += 24
                let subTitle = "\(String(localized: "图纸"))：\(activeRequest.displayName)    \(String(localized: "时间"))：\(Formatters.dateTime.string(from: Date()))"
                (subTitle as NSString)
                    .draw(in: CGRect(x: leftInset, y: y, width: bodyWidth, height: lineHeight), withAttributes: bodyAttributes)
                y += 18
                (headerLine as NSString)
                    .draw(in: CGRect(x: leftInset, y: y, width: bodyWidth, height: lineHeight), withAttributes: bodyAttributes)
                y += 14
                UIBezierPath(rect: CGRect(x: leftInset, y: y, width: bodyWidth, height: 1)).fill()
                y += 8
            }

            beginPage()
            while lineIndex < contentLines.count {
                if y > pageRect.height - 40 {
                    beginPage()
                }
                let line = contentLines[lineIndex]
                (line as NSString).draw(
                    in: CGRect(x: leftInset, y: y, width: bodyWidth, height: lineHeight * 2),
                    withAttributes: bodyAttributes
                )
                y += lineHeight
                lineIndex += 1
            }
        }
        return data
#else
        return nil
#endif
    }

    func csvRow(_ fields: [String]) -> String {
        fields.map { field in
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }.joined(separator: ",")
    }

    func coordinateListText(_ points: [CGPoint]) -> String {
        points.map(coordinateText).joined(separator: "；")
    }

    func coordinateText(_ point: CGPoint) -> String {
        "X:\(Formatters.number(Double(point.x), minFraction: 0, maxFraction: 3)) Y:\(Formatters.number(Double(point.y), minFraction: 0, maxFraction: 3))"
    }

    func quantitySourceCoordinateText(_ item: CADQuantityItem) -> String {
        guard let target = quantityHighlightTarget(for: item) else { return "" }
        return coordinateListText(storedPoints(for: target))
    }

    func createSiteTodo(fromCADIssue marker: CADFallbackIssueMarker) {
        let screenshotData = cadIssueScreenshotData(for: marker)
        let photoFileName = saveCADIssueTodoScreenshot(screenshotData)
        let todo = SiteTodo(
            title: cadIssueRecordTitle(for: marker),
            dueDate: Formatters.date.string(from: Date()),
            priority: .high,
            issueType: .quality,
            rectificationBeforePhotoFileName: photoFileName,
            note: cadIssueRecordBody(for: marker, screenshotSaved: photoFileName != nil),
            projectId: activeRequest.projectId
        )
        store.insertSiteTodoAtTop(todo)
        store.scheduleSave()
        alertMessage = String(localized: "已从 CAD 问题点生成现场待办。")
        showAlert = true
        AppHaptics.success()
    }

    func createQuickNote(fromCADIssue marker: CADFallbackIssueMarker) {
        let screenshotData = cadIssueScreenshotData(for: marker)
        let attachments = cadIssueQuickNoteAttachments(from: marker, screenshotData: screenshotData)
        let note = QuickNote(
            title: cadIssueRecordTitle(for: marker),
            content: cadIssueRecordBody(for: marker, screenshotSaved: attachments.isEmpty == false),
            projectId: activeRequest.projectId,
            attachments: attachments
        )
        store.insertQuickNoteAtTop(note)
        store.scheduleSave()
        alertMessage = String(localized: "已从 CAD 问题点生成随手记。")
        showAlert = true
        AppHaptics.success()
    }

    func createTodoAndQuickNote(fromCADIssue marker: CADFallbackIssueMarker) {
        let screenshotData = cadIssueScreenshotData(for: marker)
        let todoPhotoFileName = saveCADIssueTodoScreenshot(screenshotData)
        let quickNoteAttachments = cadIssueQuickNoteAttachments(from: marker, screenshotData: screenshotData)
        let body = cadIssueRecordBody(
            for: marker,
            screenshotSaved: todoPhotoFileName != nil || quickNoteAttachments.isEmpty == false
        )
        store.insertSiteTodoAtTop(
            SiteTodo(
                title: cadIssueRecordTitle(for: marker),
                dueDate: Formatters.date.string(from: Date()),
                priority: .high,
                issueType: .quality,
                rectificationBeforePhotoFileName: todoPhotoFileName,
                note: body,
                projectId: activeRequest.projectId
            )
        )
        store.insertQuickNoteAtTop(
            QuickNote(
                title: cadIssueRecordTitle(for: marker),
                content: body,
                projectId: activeRequest.projectId,
                attachments: quickNoteAttachments
            )
        )
        store.scheduleSave()
        alertMessage = String(localized: "已从 CAD 问题点生成现场待办和随手记。")
        showAlert = true
        AppHaptics.success()
    }

    func cadIssueRecordTitle(for marker: CADFallbackIssueMarker) -> String {
        let drawingName = activeRequest.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = marker.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if drawingName.isEmpty {
            return title.isEmpty ? String(localized: "CAD 图纸问题点") : title
        }
        if title.isEmpty {
            return "\(String(localized: "CAD 图纸问题"))：\(drawingName)"
        }
        return "\(title) · \(drawingName)"
    }

    func cadIssueRecordBody(for marker: CADFallbackIssueMarker, screenshotSaved: Bool) -> String {
        let note = marker.note.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [
            String(localized: "CAD 图纸问题点"),
            "\(String(localized: "图纸"))：\(activeRequest.displayName)",
            "\(String(localized: "位置"))：\(coordinateText(marker.point.cgPoint))",
            "\(String(localized: "图层"))：\(issueMarkerLayerText(marker))",
            "\(String(localized: "测量结果"))：\(issueMarkerMeasurementText(marker))",
            "\(String(localized: "截图"))：\(screenshotSaved ? String(localized: "已随记录保存") : String(localized: "未能自动生成"))",
            "\(String(localized: "创建时间"))：\(marker.createdAt)"
        ]
        if let photoFileName = marker.photoFileName, !photoFileName.isEmpty {
            lines.append("\(String(localized: "现场照片"))：\(photoFileName)")
        }
        if !note.isEmpty {
            lines.append("\(String(localized: "备注"))：\(note)")
        }
        return lines.joined(separator: "\n")
    }

    func issueMarkerLayerText(_ marker: CADFallbackIssueMarker) -> String {
        let storedLayer = marker.layerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedLayer, !storedLayer.isEmpty { return storedLayer }
        if let layer = nearestDrawingLayerName(toStoredPoint: marker.point.cgPoint) {
            return layer
        }
        return String(localized: "未识别")
    }

    func issueMarkerMeasurementText(_ marker: CADFallbackIssueMarker) -> String {
        let storedSummary = marker.measurementSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedSummary, !storedSummary.isEmpty { return storedSummary }
        if let summary = nearestMeasurementSummary(toStoredPoint: marker.point.cgPoint) {
            return summary
        }
        return String(localized: "暂无附近测量")
    }

    func nearestDrawingLayerName(toStoredPoint point: CGPoint) -> String? {
        let candidates = nativeSnapSourcePoints
        guard !candidates.isEmpty else { return nil }
        let markerCanvasPoint = canvasPoint(fromStored: point)
        var bestLayer: String?
        var bestDistance = max(overlaySnapTolerance * 2, 36)
        for candidate in candidates {
            let candidateCanvasPoint = canvasPoint(fromStored: candidate.point)
            let distance = hypot(candidateCanvasPoint.x - markerCanvasPoint.x, candidateCanvasPoint.y - markerCanvasPoint.y)
            guard distance <= bestDistance else { continue }
            let layer = candidate.layer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !layer.isEmpty else { continue }
            bestDistance = distance
            bestLayer = layer
        }
        return bestLayer
    }

    func nearestMeasurementSummary(toStoredPoint point: CGPoint) -> String? {
        let canvasPoint = canvasPoint(fromStored: point)
        var bestSummary: String?
        var bestDistance = max(overlaySnapTolerance * 2.5, 44)

        func consider(summary: String, distance: CGFloat) {
            guard distance <= bestDistance else { return }
            bestDistance = distance
            bestSummary = summary
        }

        for measurement in snapshot.lengthMeasurements {
            let points = measurement.points.map(\.cgPoint)
            let renderedPoints = canvasPoints(fromStored: points)
            consider(
                summary: "\(measurement.name)：\(lengthLabel(for: points))",
                distance: distanceFrom(canvasPoint, toPolyline: renderedPoints)
            )
        }

        for measurement in snapshot.areaMeasurements {
            let points = measurement.points.map(\.cgPoint)
            let renderedPoints = canvasPoints(fromStored: points)
            let distance = isPoint(canvasPoint, insidePolygon: renderedPoints)
                ? 0
                : distanceFrom(canvasPoint, toPolyline: closedPolylinePoints(renderedPoints))
            consider(
                summary: "\(measurement.name)：\(areaLabel(for: points))",
                distance: distance
            )
        }

        return bestSummary
    }

    func saveCADIssueTodoScreenshot(_ data: Data?) -> String? {
        guard let data else { return nil }
        return PhotoStorage.save(original: data, fileName: "cad-issue-todo-\(UUID().uuidString).jpg")
    }

    func cadIssueQuickNoteAttachments(from marker: CADFallbackIssueMarker, screenshotData: Data?) -> [QuickNoteAttachment] {
        var attachments: [QuickNoteAttachment] = []
        if let screenshotData,
           let attachment = saveQuickNoteImageAttachment(
            data: screenshotData,
            originalName: "\(cadIssueSafeFileStem(marker.title))-CAD截图.jpg"
           ) {
            attachments.append(attachment)
        }
        if let photoFileName = marker.photoFileName,
           let photoData = PhotoStorage.data(for: photoFileName),
           let attachment = saveQuickNoteImageAttachment(
            data: photoData,
            originalName: "\(cadIssueSafeFileStem(marker.title))-现场照片.jpg"
           ) {
            attachments.append(attachment)
        }
        return attachments
    }

    func saveQuickNoteImageAttachment(data: Data, originalName: String) -> QuickNoteAttachment? {
        do {
            let fileName = try QuickNoteAttachmentStorage.saveDataOrThrow(
                data,
                fileName: QuickNoteAttachmentStorage.makeFileName(extension: "jpg")
            )
            return QuickNoteAttachment(kind: .photo, fileName: fileName, originalName: originalName)
        } catch {
            StorageIssueLog.recordEvent(
                "cad_issue.quick_note_attachment_save_failed",
                category: .fileStorage,
                details: ["drawing": activeRequest.displayName],
                error: error
            )
            return nil
        }
    }

    func cadIssueSafeFileStem(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? String(localized: "CAD问题点") : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return fallback
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .prefix(40)
            .description
    }

    func cadIssueScreenshotData(for marker: CADFallbackIssueMarker) -> Data? {
#if os(iOS)
        if let windowImage = currentWindowScreenshotImage(),
           let data = windowImage.jpegData(compressionQuality: 0.78) {
            return data
        }
        return cadIssueContextImage(for: marker).jpegData(compressionQuality: 0.82)
#else
        return nil
#endif
    }

#if os(iOS)
    func currentWindowScreenshotImage() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard let window else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    func cadIssueContextImage(for marker: CADFallbackIssueMarker) -> UIImage {
        let size = CGSize(width: 1280, height: 720)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.label
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 25),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let markerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.white
            ]

            (cadIssueRecordTitle(for: marker) as NSString)
                .draw(in: CGRect(x: 48, y: 42, width: 1184, height: 50), withAttributes: titleAttributes)

            let lines = cadIssueRecordBody(for: marker, screenshotSaved: true).components(separatedBy: "\n")
            var y: CGFloat = 116
            for line in lines.prefix(7) {
                (line as NSString)
                    .draw(in: CGRect(x: 48, y: y, width: 1184, height: 34), withAttributes: bodyAttributes)
                y += 38
            }

            let drawingRect = CGRect(x: 48, y: 410, width: 1184, height: 240)
            UIColor.secondarySystemGroupedBackground.setFill()
            UIBezierPath(roundedRect: drawingRect, cornerRadius: 14).fill()
            UIColor.systemRed.setFill()
            let markerPoint = CGPoint(x: drawingRect.midX, y: drawingRect.midY)
            UIBezierPath(ovalIn: CGRect(x: markerPoint.x - 22, y: markerPoint.y - 22, width: 44, height: 44)).fill()
            ("!" as NSString)
                .draw(in: CGRect(x: markerPoint.x - 6, y: markerPoint.y - 16, width: 20, height: 32), withAttributes: markerAttributes)
        }
    }
#endif
}
