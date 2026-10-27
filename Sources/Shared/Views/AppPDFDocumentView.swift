import SwiftUI
import PDFKit

/// SwiftUI can finish arranging the PDF after its controller's layout callback.
/// Notify the controller when PDFKit receives its actual usable bounds.
final class AppLayoutPDFView: PDFView {
    var willResize: (() -> Void)?
    var didLayout: (() -> Void)?

    override var frame: CGRect {
        willSet {
            if frame.size != newValue.size { willResize?() }
        }
    }

    override var bounds: CGRect {
        willSet {
            if bounds.size != newValue.size { willResize?() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }
}

struct AppPDFDocumentView: UIViewControllerRepresentable {
    @Environment(\.appReviewPaneIsVisible) private var isPaneVisible
    let url: URL
    var onPageChange: ((Int) -> Void)? = nil

    func makeUIViewController(context: Context) -> AppPDFPreviewController {
        let controller = AppPDFPreviewController(url: url)
        controller.pageDidChange = onPageChange
        controller.setPreviewVisible(isPaneVisible)
        return controller
    }

    func updateUIViewController(_ controller: AppPDFPreviewController, context: Context) {
        controller.pageDidChange = onPageChange
        controller.setPreviewVisible(isPaneVisible)
        controller.update(url: url)
    }
}

/// Render PDFs directly rather than entering Quick Look's document/AppIntents bridge.
/// Loading waits for real bounds; state updates and rotation keep the current page and zoom.
@MainActor
final class AppPDFPreviewController: UIViewController, UISearchBarDelegate {
    var pageDidChange: ((Int) -> Void)?
    private var reportedPage = -1
    private var pendingViewport: (destination: PDFDestination, scale: CGFloat, fits: Bool)?
    private var isRestoringViewport = false
    let pdfView = AppLayoutPDFView()
    let pageLabel = UILabel()
    let messageLabel = UILabel()
    let previousButton = UIButton(type: .system)
    let nextButton = UIButton(type: .system)
    let searchButton = UIButton(type: .system)
    let unlockButton = UIButton(type: .system)
    let searchBar = UISearchBar()
    let searchResultLabel = UILabel()
    let previousMatchButton = UIButton(type: .system)
    let nextMatchButton = UIButton(type: .system)
    private let searchControls = UIStackView()
    private(set) var searchMatches: [PDFSelection] = []
    private(set) var selectedMatchIndex = 0
    private(set) var document: PDFDocument?
    private var url: URL
    private var loadedURL: URL?
    private var safeBottomConstraint: NSLayoutConstraint?
    private var keyboardBottomConstraint: NSLayoutConstraint?
    private var isPreviewVisible = true

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.isHidden = !isPreviewVisible
        view.isUserInteractionEnabled = isPreviewVisible
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.accessibilityIdentifier = "pdf-preview-document"
        pdfView.willResize = { [weak self] in self?.captureViewport() }
        pdfView.didLayout = { [weak self] in
            self?.loadDocumentIfReady()
            self?.restoreViewport()
        }
        configureStatusLabels()
        configure(previousButton, image: "chevron.up", label: AppLocalization.string("pdf_preview_previous_page"),
                  identifier: "pdf-preview-previous", action: #selector(previousPage))
        configure(nextButton, image: "chevron.down", label: AppLocalization.string("pdf_preview_next_page"),
                  identifier: "pdf-preview-next", action: #selector(nextPage))
        configure(searchButton, image: "magnifyingglass", label: AppLocalization.string("pdf_preview_search"),
                  identifier: "pdf-preview-search", action: #selector(findText))
        unlockButton.setTitle(AppLocalization.string("pdf_preview_unlock"), for: .normal)
        unlockButton.accessibilityIdentifier = "pdf-preview-unlock"
        unlockButton.addTarget(self, action: #selector(requestPassword), for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [previousButton, pageLabel, nextButton, searchButton])
        controls.spacing = 12
        controls.alignment = .center
        configureSearchControls()
        let stack = UIStackView(arrangedSubviews: [controls, searchControls, messageLabel, unlockButton, pdfView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        safeBottomConstraint = stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        keyboardBottomConstraint = stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        safeBottomConstraint?.isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            previousButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            previousButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            nextButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            searchButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            searchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            unlockButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        messageLabel.isHidden = true
        unlockButton.isHidden = true
        updatePageState()
        NotificationCenter.default.addObserver(self, selector: #selector(updatePageState),
                                               name: .PDFViewPageChanged, object: pdfView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A presenting editor's keyboard must not collapse a newly opened PDF.
        // Follow the guide only while this preview owns a usable search keyboard.
        let keyboardTop = view.keyboardLayoutGuide.layoutFrame.minY
        let usesKeyboardGuide = view.window != nil && searchBar.isFirstResponder
            && keyboardTop.isFinite && keyboardTop > view.safeAreaLayoutGuide.layoutFrame.minY + 44
        if keyboardBottomConstraint?.isActive != usesKeyboardGuide {
            safeBottomConstraint?.isActive = !usesKeyboardGuide
            keyboardBottomConstraint?.isActive = usesKeyboardGuide
            view.layoutIfNeeded()
        }
        loadDocumentIfReady()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchBar.resignFirstResponder()
    }

    func update(url: URL) {
        guard self.url != url else { return }
        pendingViewport = nil
        reportedPage = -1
        self.url = url
        loadDocumentIfReady()
    }

    func setPreviewVisible(_ visible: Bool) {
        isPreviewVisible = visible
        guard isViewLoaded else { return }
        if !visible {
            searchBar.resignFirstResponder()
            pdfView.documentView?.resignFirstResponder()
            pdfView.resignFirstResponder()
        }
        // SwiftUI opacity keeps the UIKit subtree mounted and responder-eligible.
        // Hide the actual preview while retaining its document, page and zoom.
        view.isHidden = !visible
        view.isUserInteractionEnabled = visible
        if visible {
            view.setNeedsLayout()
            pdfView.setNeedsLayout()
        }
    }

    private func loadDocumentIfReady() {
        guard isViewLoaded, loadedURL != url,
              pdfView.bounds.width.isFinite, pdfView.bounds.height.isFinite,
              pdfView.bounds.width > 0, pdfView.bounds.height > 0 else { return }
        loadedURL = url
        clearSearch()
        searchControls.isHidden = true
        pdfView.document = nil
        document = url.isFileURL ? PDFDocument(url: url) : nil
        guard let document, document.isLocked || document.pageCount > 0 else {
            messageLabel.text = AppLocalization.string("pdf_preview_unavailable")
            messageLabel.isHidden = false
            unlockButton.isHidden = true
            updatePageState()
            return
        }
        if document.isLocked {
            messageLabel.text = AppLocalization.string("pdf_preview_password_required")
            messageLabel.isHidden = false
            unlockButton.isHidden = false
        } else {
            display(document)
        }
        updatePageState()
    }

    private func display(_ document: PDFDocument) {
        messageLabel.isHidden = true
        unlockButton.isHidden = true
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.layoutDocumentView()
    }

    @discardableResult
    func unlockDocument(password: String) -> Bool {
        guard let document, document.isLocked else { return false }
        guard document.unlock(withPassword: password) else {
            messageLabel.text = AppLocalization.string("pdf_preview_invalid_password")
            return false
        }
        display(document)
        updatePageState()
        return true
    }

    @objc private func requestPassword() {
        let prompt = UIAlertController(title: AppLocalization.string("pdf_preview_unlock"),
                                       message: AppLocalization.string("pdf_preview_password_required"), preferredStyle: .alert)
        prompt.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = AppLocalization.string("pdf_preview_password")
            field.accessibilityIdentifier = "pdf-preview-password"
        }
        prompt.addAction(UIAlertAction(title: AppLocalization.string("取消"), style: .cancel))
        prompt.addAction(UIAlertAction(title: AppLocalization.string("pdf_preview_unlock"), style: .default) { [weak self, weak prompt] _ in
            self?.unlockDocument(password: prompt?.textFields?.first?.text ?? "")
        })
        present(prompt, animated: true)
    }

    @objc private func previousPage() { pdfView.goToPreviousPage(nil) }
    @objc private func nextPage() { pdfView.goToNextPage(nil) }
    @objc private func findText() {
        guard pdfView.document != nil else { return }
        searchControls.isHidden = false
        updateSearchResults()
        searchBar.becomeFirstResponder()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        search(text: searchBar.text ?? "")
        searchBar.resignFirstResponder()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Clear stale selections immediately; perform the full document search on Search.
        clearSearch(keepQuery: true)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        clearSearch()
        searchControls.isHidden = true
        searchBar.resignFirstResponder()
    }

    func search(text: String) {
        clearSearch(keepQuery: true)
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let document = pdfView.document else { return }
        searchMatches = document.findString(query, withOptions: .caseInsensitive)
        selectSearchMatch()
    }

    private func clearSearch(keepQuery: Bool = false) {
        searchMatches = []
        selectedMatchIndex = 0
        pdfView.highlightedSelections = nil
        pdfView.clearSelection()
        if !keepQuery { searchBar.text = nil }
        updateSearchResults()
    }

    @objc private func previousMatch() {
        guard !searchMatches.isEmpty else { return }
        selectedMatchIndex = (selectedMatchIndex + searchMatches.count - 1) % searchMatches.count
        selectSearchMatch()
    }

    @objc private func nextMatch() {
        guard !searchMatches.isEmpty else { return }
        selectedMatchIndex = (selectedMatchIndex + 1) % searchMatches.count
        selectSearchMatch()
    }

    private func selectSearchMatch() {
        if !searchMatches.isEmpty {
            let selection = searchMatches[selectedMatchIndex]
            // A newly replaced/unlocked document may not have a laid-out document view yet.
            // Resolve its pages before navigating; selection alone can leave currentPage stale.
            pdfView.layoutDocumentView()
            if let page = selection.pages.first {
                pdfView.go(to: page)
                pdfView.go(to: selection.bounds(for: page), on: page)
            }
            pdfView.setCurrentSelection(selection, animate: false)
        }
        updateSearchResults()
        updatePageState()
    }

    private func updateSearchResults() {
        searchResultLabel.text = "\(searchMatches.isEmpty ? 0 : selectedMatchIndex + 1) / \(searchMatches.count)"
        previousMatchButton.isEnabled = searchMatches.count > 1
        nextMatchButton.isEnabled = searchMatches.count > 1
    }

    @objc private func updatePageState() {
        let count = pdfView.document?.pageCount ?? 0
        let candidate = pdfView.currentPage.flatMap { pdfView.document?.index(for: $0) } ?? 0
        let index = (0..<count).contains(candidate) ? candidate : 0
        pageLabel.text = String(format: AppLocalization.string("pdf_preview_page_format"), Int64(count == 0 ? 0 : index + 1), Int64(count))
        previousButton.isEnabled = count > 0 && pdfView.canGoToPreviousPage
        nextButton.isEnabled = count > 0 && pdfView.canGoToNextPage
        searchButton.isEnabled = count > 0
        let visiblePage = count == 0 ? 0 : index + 1
        if reportedPage != visiblePage {
            reportedPage = visiblePage
            // PDFKit can notify during a SwiftUI layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.reportedPage == visiblePage else { return }
                self.pageDidChange?(visiblePage)
            }
        }
    }
}

private extension AppPDFPreviewController {
    func configure(_ button: UIButton, image: String, label: String, identifier: String, action: Selector) {
        button.setImage(UIImage(systemName: image), for: .normal)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    func configureStatusLabels() {
        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.textAlignment = .center
        pageLabel.accessibilityIdentifier = "pdf-preview-page"
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.accessibilityIdentifier = "pdf-preview-error"
    }

    func configureSearchControls() {
        searchBar.placeholder = AppLocalization.string("pdf_preview_search")
        searchBar.accessibilityIdentifier = "pdf-preview-search-field"
        searchBar.searchTextField.accessibilityIdentifier = "pdf-preview-search-input"
        searchBar.delegate = self
        searchBar.showsCancelButton = true
        searchResultLabel.accessibilityIdentifier = "pdf-preview-search-results"
        searchResultLabel.font = .preferredFont(forTextStyle: .caption1)
        searchResultLabel.adjustsFontForContentSizeCategory = true
        configure(previousMatchButton, image: "chevron.up", label: AppLocalization.string("pdf_preview_previous_match"),
                  identifier: "pdf-preview-previous-match", action: #selector(previousMatch))
        configure(nextMatchButton, image: "chevron.down", label: AppLocalization.string("pdf_preview_next_match"),
                  identifier: "pdf-preview-next-match", action: #selector(nextMatch))
        searchControls.axis = .vertical
        searchControls.addArrangedSubview(searchBar)
        let matches = UIStackView(arrangedSubviews: [previousMatchButton, searchResultLabel, nextMatchButton])
        matches.alignment = .center
        matches.distribution = .equalSpacing
        searchControls.addArrangedSubview(matches)
        searchControls.isHidden = true
        for button in [previousMatchButton, nextMatchButton] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
    }
}

private extension AppPDFPreviewController {
    func captureViewport() {
        guard !isRestoringViewport, pendingViewport == nil,
              loadedURL == url, let page = pdfView.currentPage else { return }
        // PDFKit's currentDestination can describe the bottom edge on the next page.
        // Anchor the visible top to the current page so a shorter viewport cannot jump ahead.
        let visibleTop = pdfView.convert(pdfView.bounds.origin, to: page)
        let pageBounds = page.bounds(for: pdfView.displayBox)
        let point = CGPoint(x: min(max(visibleTop.x, pageBounds.minX), pageBounds.maxX),
                            y: min(max(visibleTop.y, pageBounds.minY), pageBounds.maxY))
        let position = PDFDestination(page: page, at: point)
        position.zoom = kPDFDestinationUnspecifiedValue
        pendingViewport = (position, pdfView.scaleFactor, pdfView.autoScales)
    }

    func restoreViewport() {
        guard isPreviewVisible, !isRestoringViewport, let viewport = pendingViewport,
              pdfView.bounds.width > 0, pdfView.bounds.height > 0 else { return }
        pendingViewport = nil
        isRestoringViewport = true
        defer { isRestoringViewport = false }
        // Fit-to-page follows the new width; a user's manual zoom stays unchanged.
        pdfView.autoScales = viewport.fits
        if !viewport.fits { pdfView.scaleFactor = viewport.scale }
        pdfView.layoutDocumentView()
        // Automatic resizing only restores the viewport, without adding a PDF
        // navigation action or transferring focus away from a neighbouring editor.
        if let page = viewport.destination.page, let scroll = documentScrollView {
            let point = pdfView.convert(viewport.destination.point, from: page)
            let proposed = CGPoint(x: scroll.contentOffset.x + point.x - pdfView.bounds.minX,
                                   y: scroll.contentOffset.y + point.y - pdfView.bounds.minY)
            let inset = scroll.adjustedContentInset
            let maxX = max(-inset.left, scroll.contentSize.width - scroll.bounds.width + inset.right)
            let maxY = max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
            scroll.setContentOffset(CGPoint(x: min(max(proposed.x, -inset.left), maxX),
                                            y: min(max(proposed.y, -inset.top), maxY)), animated: false)
        }
        updatePageState()
    }

    var documentScrollView: UIScrollView? {
        var ancestor = pdfView.documentView?.superview
        while let view = ancestor, view !== pdfView {
            if let scroll = view as? UIScrollView { return scroll }
            ancestor = view.superview
        }
        return nil
    }
}
