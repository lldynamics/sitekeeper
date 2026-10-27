import SwiftUI

extension ProjectFinancialRecordEditSheet {
    @MainActor
    func handleOCRImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let size = QuickNoteAttachmentStorage.fileSize(at: url)
            if size > ImportLimitPolicy.maxImportBytes {
                ocrErrorMessage = ImportLimitPolicy.fileTooLargeMessage(fileName: url.lastPathComponent, size: size)
                showOCRError = true
                AppHaptics.warning()
                return
            }
            startOCR(for: url)
        case .failure(let error):
            ocrErrorMessage = String(format: AppLocalization.string("打开票据失败：%@"), error.localizedDescription)
            showOCRError = true
            AppHaptics.error()
        }
    }

    @MainActor
    func startOCR(for url: URL) {
        ocrTask?.cancel()
        isRecognizingReceipt = true
        ocrTask = Task { @MainActor in
            defer {
                isRecognizingReceipt = false
                ocrTask = nil
            }
            do {
                let parsed = try await ReceiptOCRService.recognize(from: url)
                applyOCRResult(parsed)
                ocrPreview = parsed
                AppHaptics.success()
            } catch is CancellationError {
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                StorageIssueLog.recordEvent(
                    "project_finance.receipt_ocr_failed",
                    category: .fileStorage,
                    details: [
                        "source": "ProjectFinancialRecordEditSheet.startOCR",
                        "file_name": url.lastPathComponent
                    ],
                    error: error
                )
                ocrErrorMessage = message
                showOCRError = true
                AppHaptics.error()
            }
        }
    }

    @MainActor
    func startOCRFromLinkedDocuments() {
        let candidates = linkedOCRCandidates
        guard !candidates.isEmpty else {
            ocrErrorMessage = AppLocalization.string("已关联票据暂不支持识别，请使用图片或 PDF。")
            showOCRError = true
            AppHaptics.warning()
            return
        }
        ocrTask?.cancel()
        isRecognizingReceipt = true
        ocrTask = Task { @MainActor in
            defer {
                isRecognizingReceipt = false
                ocrTask = nil
            }
            await recognizeLinkedDocuments(candidates)
        }
    }

    @MainActor
    private func recognizeLinkedDocuments(_ candidates: [ProjectDocument]) async {
        var firstFailureMessage: String?
        for document in candidates {
            if Task.isCancelled { return }
            let url = ProjectDocumentStorage.fileURL(for: document.fileName)
            do {
                let parsed = try await ReceiptOCRService.recognize(from: url)
                applyOCRResult(parsed)
                ocrPreview = parsed
                AppHaptics.success()
                return
            } catch is CancellationError {
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                StorageIssueLog.recordEvent(
                    "project_finance.linked_receipt_ocr_failed",
                    category: .fileStorage,
                    details: [
                        "source": "ProjectFinancialRecordEditSheet.startOCRFromLinkedDocuments",
                        "file_name": document.fileName
                    ],
                    error: error
                )
                if firstFailureMessage == nil {
                    firstFailureMessage = message
                }
            }
        }
        if let firstFailureMessage {
            ocrErrorMessage = String(
                format: AppLocalization.string("已尝试 %lld 份关联票据，仍未提取到可回填字段（%@）。"),
                Int64(candidates.count),
                firstFailureMessage
            )
        } else {
            ocrErrorMessage = String(
                format: AppLocalization.string("已尝试 %lld 份关联票据，仍未提取到可回填字段。"),
                Int64(candidates.count)
            )
        }
        showOCRError = true
        AppHaptics.error()
    }

    @MainActor
    func applyOCRResult(_ result: ReceiptOCRResult) {
        if result.amountCandidates.isEmpty,
           let amountText = result.amount,
           !amountText.isEmpty {
            amount = NumericInputSupport.sanitize(amountText, kind: .amount)
        }
        if let party = result.counterparty, !party.isEmpty {
            counterparty = party
        }
        if let number = result.invoiceNumber, !number.isEmpty {
            invoiceNumber = number
        }
        if let dateText = result.date,
           let recognizedDate = Formatters.date.date(from: dateText) {
            date = ProjectFinancialReceiptOCRSupport.mergeDate(recognizedDate, keepingTimeOf: date)
        }
    }

    @MainActor
    func applyOCRAmountCandidate(_ candidate: ReceiptOCRAmountCandidate) {
        amount = NumericInputSupport.sanitize(candidate.amount, kind: .amount)
        AppHaptics.success()
    }
}
