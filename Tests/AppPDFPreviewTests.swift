import Foundation
import PDFKit
import Testing
import UIKit
import SwiftUI
@testable import sitekeeper

@MainActor
struct AppPDFPreviewTests {
    @Test func realWindowAttachmentLoadsDocumentAndReportsCorruption() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = directory.appendingPathComponent("window.pdf")
        let corrupt = directory.appendingPathComponent("corrupt-window.pdf")
        try makePDF().write(to: valid)
        try Data("Not a PDF".utf8).write(to: corrupt)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        let controller = AppPDFPreviewController(url: valid)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil }
        for _ in 0..<20 where controller.document == nil {
            window.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.view.window === window)
        #expect(controller.pdfView.bounds.height > 0)
        #expect(controller.document?.pageCount == 2)
        #expect(controller.pageLabel.text == "1 / 2")
        controller.update(url: corrupt)
        #expect(!controller.messageLabel.isHidden)
        #expect(controller.messageLabel.text == String(localized: "pdf_preview_unavailable"))
    }

    @Test func swiftUIEmbeddedPreviewLoadsWithoutForcingControllerRelayout() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("embedded.pdf")
        try makePDF().write(to: file)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NavigationStack { AppPDFDocumentView(url: file) })
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil }
        func preview(in parent: UIViewController) -> AppPDFPreviewController? {
            if let value = parent as? AppPDFPreviewController { return value }
            return parent.children.lazy.compactMap { preview(in: $0) }.first
        }
        var loaded: AppPDFPreviewController?
        for _ in 0..<40 {
            loaded = preview(in: host)
            if loaded?.document != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let controller = try #require(loaded)
        #expect(controller.document?.pageCount == 2)
        #expect(controller.pageLabel.text == "1 / 2")
        #expect(controller.nextButton.isEnabled)
    }

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

    @Test func resizingPreservesPDFSearchQueryMatchPageAndDocument() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("resize.pdf")
        let original = makePDF()
        try original.write(to: url)
        let controller = AppPDFPreviewController(url: url)
        layout(controller)
        let document = try #require(controller.document)
        controller.searchButton.sendActions(for: .touchUpInside)
        controller.searchBar.text = "page"
        controller.search(text: "page")
        controller.nextMatchButton.sendActions(for: .touchUpInside)
        for width: CGFloat in [390, 800, 390, 800] {
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 700)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.viewDidLayoutSubviews()
            #expect(controller.document === document)
            #expect(controller.searchBar.text == "page")
            #expect(controller.searchMatches.count == 2)
            #expect(controller.selectedMatchIndex == 1)
            #expect(controller.searchResultLabel.text == "2 / 2")
            #expect(controller.pdfView.currentPage === document.page(at: 1))
            #expect(controller.pdfView.bounds.width > 0)
            #expect(controller.pdfView.bounds.height > 0)
        }
        #expect(try Data(contentsOf: url) == original)
    }
}

private extension AppPDFPreviewTests {
    func layout(_ controller: AppPDFPreviewController) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
    }

    func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makePDF(prefix: String = "Review") -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).pdfData { context in
            for name in ["one", "two"] {
                context.beginPage()
                ("\(prefix) page \(name)" as NSString).draw(at: CGPoint(x: 30, y: 30),
                                                         withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
    }
}

extension AppPDFPreviewTests {
    @Test func restoringAReferencedPageDoesNotStealTheAdjacentEditorsKeyboard() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("adjacent-editor.pdf")
        try makePDF().write(to: url)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        let controller = AppPDFPreviewController(url: url)
        let editor = UITextField(frame: CGRect(x: 20, y: 20, width: 300, height: 44))
        editor.text = "Issue draft"
        window.rootViewController = root
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        root.view.addSubview(editor)
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        controller.view.frame = CGRect(x: 0, y: 80, width: 390, height: 500)
        controller.view.layoutIfNeeded()
        let secondPage = try #require(controller.document?.page(at: 1))
        controller.pdfView.go(to: secondPage)
        let originalDocument = controller.document
        controller.setPreviewVisible(false)
        #expect(controller.view.isHidden)
        #expect(!controller.view.isUserInteractionEnabled)
        #expect(controller.pdfView.documentView?.isFirstResponder == false)
        try #require(editor.becomeFirstResponder())
        editor.selectedTextRange = editor.textRange(from: editor.endOfDocument, to: editor.endOfDocument)

        for size in [CGSize(width: 780, height: 350), CGSize(width: 390, height: 500)] {
            controller.view.frame.size = size
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            #expect(controller.pdfView.currentPage === secondPage)
            #expect(editor.isFirstResponder, "Restoring the referenced PDF page must not take the editor's focus.")
        }
        controller.setPreviewVisible(true)
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!controller.view.isHidden)
        #expect(controller.document === originalDocument)
        #expect(controller.pdfView.currentPage === secondPage)
        #expect(editor.isFirstResponder)
        editor.insertText(" retained")
        #expect(editor.text == "Issue draft retained")
    }

    @Test func firstPageSurvivesShortViewportAndRestoresReadingPosition() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("first-page-resize.pdf")
        try makePDF().write(to: url)
        let controller = AppPDFPreviewController(url: url)
        layout(controller)
        let document = try #require(controller.document)
        controller.searchButton.sendActions(for: .touchUpInside)
        controller.searchBar.text = "page one"
        controller.search(text: "page one")
        #expect(controller.pdfView.currentPage === document.page(at: 0))
        for size in [CGSize(width: 466, height: 380), CGSize(width: 660, height: 220),
                     CGSize(width: 466, height: 380)] {
            controller.view.frame.size = size
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            #expect(controller.document === document)
            #expect(controller.searchBar.text == "page one")
            #expect(controller.searchMatches.count == 1)
            #expect(controller.pdfView.currentPage === document.page(at: 0))
            #expect(controller.pageLabel.text == "1 / 2")
        }
    }

    @Test func resizingKeepsManualZoomAndReadingPageWithoutReplacingTheDocument() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("zoom-resize.pdf")
        try makePDF().write(to: url)
        let controller = AppPDFPreviewController(url: url)
        layout(controller)
        let document = try #require(controller.document)
        controller.pdfView.go(to: try #require(document.page(at: 1)))
        controller.pdfView.autoScales = false
        controller.pdfView.scaleFactor = 1.8
        let page = try #require(document.page(at: 1))
        let readingTop = controller.pdfView.convert(controller.pdfView.bounds.origin, to: page).y
        for width: CGFloat in [390, 900, 390] {
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            #expect(controller.document === document)
            #expect(controller.pdfView.currentPage === document.page(at: 1))
            #expect(abs(controller.pdfView.scaleFactor - 1.8) < 0.01)
            let restoredTop = controller.pdfView.convert(controller.pdfView.bounds.origin, to: page).y
            #expect(abs(restoredTop - readingTop) < 1)
        }
    }
}
