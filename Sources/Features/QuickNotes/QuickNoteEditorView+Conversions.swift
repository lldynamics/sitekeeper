import SwiftUI

extension QuickNoteEditSheet {
    func convertToTodo() {
        guard let projectId else { return showNeedProject() }
        let text = currentText
        store.appendSiteTodo(SiteTodo(
            title: String((text.isEmpty ? updatedNote.title : text).prefix(40)),
            owner: "",
            dueDate: .day(CalendarDay(date: Date())),
            note: text,
            projectId: projectId
        ))
        store.scheduleSave()
        showMessage(AppLocalization.string("已新增现场待办。"))
    }

    func convertToDailyLog() {
        guard projectId != nil else { return showNeedProject() }
        dailyLogPreparationTask?.cancel()
        isPreparingDailyLogDraft = true
        dailyLogPreparationTask = Task {
            let seedPhotos = await buildDailyLogSeedPhotos()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                preparedDailyLogSeedPhotos = seedPhotos
                isPreparingDailyLogDraft = false
                showDailyLogDraft = true
                dailyLogPreparationTask = nil
            }
        }
    }

    func buildDailyLogSeedPhotos() async -> [DailyLogSeedPhoto] {
        let candidates = Array(attachments.prefix(6))
        let seedNote = String(
            format: AppLocalization.string("来源: 随手记\n记录时间: %@"),
            Formatters.displayDateText(note.createdAt)
        )
        let capturedAt = Formatters.parseDateOrDateTime(note.createdAt)
        var seedPhotos: [DailyLogSeedPhoto] = []
        for attachment in candidates where [.photo, .drawing].contains(attachment.attachmentKind) {
            guard !Task.isCancelled else { break }
            guard let data = await QuickNoteAttachmentStorage.dataAsync(for: attachment.fileName) else { continue }
            seedPhotos.append(
                DailyLogSeedPhoto(
                    data: data,
                    note: seedNote,
                    tag: .general,
                    capturedAt: capturedAt
                )
            )
        }
        return seedPhotos
    }

    func convertToProjectDocument() {
        guard let projectId else { return showNeedProject() }
        projectDocumentGenerationTask?.cancel()
        isPreparingProjectDocument = true
        projectDocumentGenerationTask = Task {
            let imageDataByFileName = await buildProjectDocumentImageDataMap()
            guard !Task.isCancelled else { return }
            let pdfData = makeProjectDocumentPDF(imageDataByFileName: imageDataByFileName)
            let fileName: String
            do {
                fileName = try ProjectDocumentStorage.savePDFOrThrow(data: pdfData, projectId: projectId)
            } catch {
                await MainActor.run {
                    isPreparingProjectDocument = false
                    projectDocumentGenerationTask = nil
                    showMessage(String(format: AppLocalization.string("项目资料生成失败：%@"), error.localizedDescription))
                }
                return
            }
            await MainActor.run {
                store.appendProjectDocument(ProjectDocument(
                    projectId: projectId,
                    title: updatedNote.title.isEmpty ? AppLocalization.string("随手记资料") : updatedNote.title,
                    category: .constructionRecord,
                    fileName: fileName,
                    fileType: "pdf",
                    pageCount: 1,
                    note: AppLocalization.string("由随手记转入")
                ))
                store.scheduleSave()
                isPreparingProjectDocument = false
                projectDocumentGenerationTask = nil
                showMessage(AppLocalization.string("已生成项目资料 PDF。"))
            }
        }
    }

    func convertToFinancialMemo() {
        guard projectId != nil else { return showNeedProject() }
        showFinancialDraft = true
    }

    var currentText: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func showNeedProject() {
        showMessage(AppLocalization.string("请先关联工程。"))
    }

    func showMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    func makeProjectDocumentPDF(imageDataByFileName: [String: Data]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 36
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            var y = margin
            y = drawText(AppLocalization.string("随手记资料"), atY: y, font: .boldSystemFont(ofSize: 22), page: page, margin: margin)
            y = drawText(String(format: AppLocalization.string("生成时间: %@"), Formatters.displayNow()), atY: y + 8, font: .systemFont(ofSize: 11), color: .secondaryLabel, page: page, margin: margin)
            if let projectId, let project = projects.first(where: { $0.id == projectId }) {
                y = drawText(String(format: AppLocalization.string("关联工程: %@"), project.name), atY: y + 4, font: .systemFont(ofSize: 11), color: .secondaryLabel, page: page, margin: margin)
            }
            y = drawText(currentText.isEmpty ? updatedNote.title : currentText, atY: y + 18, font: .systemFont(ofSize: 14), page: page, margin: margin)
            for attachment in attachments where [.photo, .drawing].contains(attachment.attachmentKind) {
                guard let data = imageDataByFileName[attachment.fileName], let image = UIImage(data: data) else { continue }
                if y > page.height - 260 {
                    context.beginPage()
                    y = margin
                }
                let maxWidth = page.width - margin * 2
                let ratio = min(maxWidth / image.size.width, 220 / image.size.height, 1)
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                image.draw(in: CGRect(x: margin, y: y + 12, width: size.width, height: size.height))
                y += size.height + 22
            }
        }
    }

    func buildProjectDocumentImageDataMap() async -> [String: Data] {
        let imageAttachments = attachments.filter { [.photo, .drawing].contains($0.attachmentKind) }
        var dataByFileName: [String: Data] = [:]
        for attachment in imageAttachments {
            guard !Task.isCancelled else { break }
            guard let data = await QuickNoteAttachmentStorage.dataAsync(for: attachment.fileName) else { continue }
            dataByFileName[attachment.fileName] = data
        }
        return dataByFileName
    }

    func drawText(_ text: String, atY y: CGFloat, font: UIFont, color: UIColor = .label, page: CGRect, margin: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: page.width - margin * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        (text as NSString).draw(in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: ceil(rect.height)), withAttributes: attributes)
        return y + ceil(rect.height)
    }
}
