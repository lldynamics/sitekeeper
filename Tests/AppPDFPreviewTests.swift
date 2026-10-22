import Foundation
import PDFKit
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct AppPDFPreviewTests {
    @Test func pdfRoutingIsCaseInsensitiveAndKeepsOtherFormatsOnQuickLook() {
        for name in ["document.pdf", "document.PDF", "photo.jpg.pdf"] {
            #expect(AppFilePreviewRoute.route(for: URL(fileURLWithPath: name)) == .pdf)
        }
        for name in ["image.png", "notes.txt", "drawing.dwg", "document.pdf.zip", "no-extension"] {
            #expect(AppFilePreviewRoute.route(for: URL(fileURLWithPath: name)) == .quickLook)
        }
    }

    @Test func delayedDismissalDoesNotClearASelectionOwnedByTheOtherPreview() {
        var pdf: URL? = URL(fileURLWithPath: "/document.pdf")
        AppFilePreviewRoute.dismiss(.quickLook, selection: &pdf)
        #expect(pdf != nil)
        AppFilePreviewRoute.dismiss(.pdf, selection: &pdf)
        #expect(pdf == nil)
        var text: URL? = URL(fileURLWithPath: "/document.txt")
        AppFilePreviewRoute.dismiss(.pdf, selection: &text)
        #expect(text != nil)
        AppFilePreviewRoute.dismiss(.quickLook, selection: &text)
        #expect(text == nil)
    }

    @Test func realDocumentLoadsOnlyAfterLayoutAndSupportsPagingAndTextSearch() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("review.pdf")
        let bytes = makePDF()
        try bytes.write(to: url)
        let controller = AppPDFPreviewController(url: url)
        controller.loadViewIfNeeded()
        controller.view.frame = .zero
        // Exercise the load guard without asking UIKit to fit a toolbar into a zero-height view.
        controller.viewDidLayoutSubviews()
        #expect(controller.document == nil)
        layout(controller)
        let document = try #require(controller.document)
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.string?.contains("Review page one") == true)
        #expect(document.findString("page two", withOptions: .caseInsensitive).count == 1)
        #expect(controller.pageLabel.text == "1 / 2")
        #expect(!controller.previousButton.isEnabled)
        #expect(controller.nextButton.isEnabled)
        controller.pdfView.go(to: try #require(document.page(at: 1)))
        #expect(controller.pageLabel.text == "2 / 2")
        #expect(controller.previousButton.isEnabled)
        #expect(!controller.nextButton.isEnabled)
        #expect(controller.searchButton.isEnabled)
        controller.search(text: "page two")
        #expect(controller.searchMatches.count == 1)
        #expect(controller.pdfView.currentPage === controller.document?.page(at: 1))
        #expect(controller.pdfView.currentSelection?.string?.lowercased().contains("page two") == true)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func ordinaryUpdatesPreserveDocumentPageAndZoomWhileNewURLLoadsFreshContent() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try makePDF().write(to: first)
        try makePDF(prefix: "Replacement").write(to: second)
        let controller = AppPDFPreviewController(url: first)
        layout(controller)
        let document = try #require(controller.document)
        controller.pdfView.go(to: try #require(document.page(at: 1)))
        controller.pdfView.autoScales = false
        controller.pdfView.scaleFactor = 1.4
        controller.update(url: first)
        controller.viewDidLayoutSubviews()
        #expect(controller.document === document)
        #expect(controller.pdfView.currentPage === document.page(at: 1))
        #expect(abs(controller.pdfView.scaleFactor - 1.4) < 0.001)
        controller.update(url: second)
        #expect(controller.document !== document)
        #expect(controller.document?.page(at: 0)?.string?.contains("Replacement") == true)
        #expect(controller.pageLabel.text == "1 / 2")
        controller.search(text: "page two")
        #expect(controller.searchMatches.count == 1)
        #expect(controller.pdfView.currentPage === controller.document?.page(at: 1))
        #expect(controller.pdfView.currentSelection?.string?.lowercased().contains("page two") == true)
    }

    @Test func missingAndCorruptDocumentsShowAnErrorAndCanRecoverOnAnotherURL() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.pdf")
        let corrupt = directory.appendingPathComponent("corrupt.pdf")
        let valid = directory.appendingPathComponent("valid.pdf")
        try Data("Not a PDF".utf8).write(to: corrupt)
        try makePDF().write(to: valid)
        let controller = AppPDFPreviewController(url: missing)
        layout(controller)
        for url in [missing, corrupt] {
            controller.update(url: url)
            #expect(controller.pdfView.document == nil)
            #expect(!controller.messageLabel.isHidden)
            #expect(controller.messageLabel.text == String(localized: "pdf_preview_unavailable"))
            #expect(!controller.searchButton.isEnabled)
            #expect(!controller.nextButton.isEnabled)
            #expect(controller.pageLabel.text == "0 / 0")
        }
        controller.update(url: valid)
        #expect(controller.pdfView.document?.pageCount == 2)
        #expect(controller.messageLabel.isHidden)
        #expect(controller.searchButton.isEnabled)
    }

    @Test func passwordProtectedDocumentCanBeUnlockedWithoutChangingTheOriginalFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("protected.pdf")
        let source = try #require(PDFDocument(data: makePDF()))
        #expect(source.write(to: url, withOptions: [.userPasswordOption: "reader", .ownerPasswordOption: "owner"]))
        let bytes = try Data(contentsOf: url)
        let controller = AppPDFPreviewController(url: url)
        layout(controller)
        #expect(controller.document?.isLocked == true)
        #expect(controller.pdfView.document == nil)
        #expect(!controller.unlockButton.isHidden)
        #expect(!controller.unlockDocument(password: "wrong"))
        #expect(!controller.messageLabel.isHidden)
        #expect(controller.unlockDocument(password: "reader"))
        #expect(controller.pdfView.document?.pageCount == 2)
        #expect(controller.messageLabel.isHidden)
        #expect(controller.unlockButton.isHidden)
        controller.search(text: "page two")
        #expect(controller.searchMatches.count == 1)
        #expect(controller.pdfView.currentPage === controller.document?.page(at: 1))
        #expect(controller.pdfView.currentSelection?.string?.lowercased().contains("page two") == true)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func searchNavigatesMatchesClearsMissesAndResetsOnReplacement() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try makePDF().write(to: first)
        try makePDF(prefix: "Replacement").write(to: second)
        let controller = AppPDFPreviewController(url: first)
        layout(controller)
        controller.search(text: "page")
        #expect(controller.searchMatches.count == 2)
        #expect(controller.searchResultLabel.text == "1 / 2")
        controller.nextMatchButton.sendActions(for: .touchUpInside)
        #expect(controller.searchResultLabel.text == "2 / 2")
        #expect(controller.pdfView.currentPage === controller.document?.page(at: 1))
        controller.nextMatchButton.sendActions(for: .touchUpInside)
        #expect(controller.searchResultLabel.text == "1 / 2")
        controller.previousMatchButton.sendActions(for: .touchUpInside)
        #expect(controller.searchResultLabel.text == "2 / 2")
        controller.search(text: "absent query")
        #expect(controller.searchMatches.isEmpty)
        #expect(controller.pdfView.currentSelection == nil)
        #expect(controller.searchResultLabel.text == "0 / 0")
        controller.search(text: "Review")
        controller.update(url: second)
        #expect(controller.searchMatches.isEmpty)
        #expect(controller.pdfView.currentSelection == nil)
        controller.search(text: "Replacement")
        #expect(controller.searchMatches.count == 2)
        controller.search(text: "   ")
        #expect(controller.searchMatches.isEmpty)
    }

    private func layout(_ controller: AppPDFPreviewController) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePDF(prefix: String = "Review") -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).pdfData { context in
            for name in ["one", "two"] {
                context.beginPage()
                ("\(prefix) page \(name)" as NSString).draw(at: CGPoint(x: 30, y: 30),
                                                         withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
    }
}
