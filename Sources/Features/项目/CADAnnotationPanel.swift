import SwiftUI

struct CADAnnotationPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

extension CADPreviewContainer {
    var noteEditorSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "批注内容")) {
                    TextField(String(localized: "输入批注说明"), text: $noteDraft, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(String(localized: "新增批注"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        showNoteSheet = false
                        pendingNotePoint = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false) else {
                            showNoteSheet = false
                            pendingNotePoint = nil
                            return
                        }
                        guard let point = pendingNotePoint else {
                            showNoteSheet = false
                            return
                        }
                        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        snapshot.notes.append(
                            CADTextNote(
                                text: text,
                                point: CADPoint(point),
                                createdAt: Formatters.now()
                            )
                        )
                        AppHaptics.success()
                        showNoteSheet = false
                        pendingNotePoint = nil
                    }
                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasNativeDrawingCoordinateSpace)
                }
            }
        }
    }

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
                stroke.kind == .redline ? String(localized: "红线") : String(localized: "批注线"),
                "",
                "\(stroke.points.count) \(String(localized: "点"))",
                "",
                "",
                String(localized: "图纸批注"),
                strokeLayerName(stroke),
                stroke.colorHex ?? "",
                coordinateListText(stroke.points.map(\.cgPoint)),
                ""
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
                "",
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
                "",
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
                "",
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
}
