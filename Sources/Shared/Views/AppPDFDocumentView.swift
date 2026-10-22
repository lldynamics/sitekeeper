import SwiftUI
import PDFKit

struct AppPDFDocumentView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AppPDFPreviewController {
        AppPDFPreviewController(url: url)
    }

    func updateUIViewController(_ controller: AppPDFPreviewController, context: Context) {
        controller.update(url: url)
    }
}

/// Render PDFs directly rather than entering Quick Look's document/AppIntents bridge.
/// Loading waits for real bounds; state updates and rotation keep the current page and zoom.
@MainActor
final class AppPDFPreviewController: UIViewController, UISearchBarDelegate {
    let pdfView = PDFView()
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

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.accessibilityIdentifier = "pdf-preview-document"
        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.textAlignment = .center
        pageLabel.accessibilityIdentifier = "pdf-preview-page"
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.accessibilityIdentifier = "pdf-preview-error"
        configure(previousButton, image: "chevron.up", label: String(localized: "pdf_preview_previous_page"),
                  identifier: "pdf-preview-previous", action: #selector(previousPage))
        configure(nextButton, image: "chevron.down", label: String(localized: "pdf_preview_next_page"),
                  identifier: "pdf-preview-next", action: #selector(nextPage))
        configure(searchButton, image: "magnifyingglass", label: String(localized: "pdf_preview_search"),
                  identifier: "pdf-preview-search", action: #selector(findText))
        unlockButton.setTitle(String(localized: "pdf_preview_unlock"), for: .normal)
        unlockButton.accessibilityIdentifier = "pdf-preview-unlock"
        unlockButton.addTarget(self, action: #selector(requestPassword), for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [previousButton, pageLabel, nextButton, searchButton])
        controls.spacing = 12
        controls.alignment = .center
        searchBar.placeholder = String(localized: "pdf_preview_search")
        searchBar.accessibilityIdentifier = "pdf-preview-search-field"
        searchBar.searchTextField.accessibilityIdentifier = "pdf-preview-search-input"
        searchBar.delegate = self
        searchBar.showsCancelButton = true
        searchResultLabel.accessibilityIdentifier = "pdf-preview-search-results"
        searchResultLabel.font = .preferredFont(forTextStyle: .caption1)
        searchResultLabel.adjustsFontForContentSizeCategory = true
        configure(previousMatchButton, image: "chevron.up", label: String(localized: "pdf_preview_previous_match"),
                  identifier: "pdf-preview-previous-match", action: #selector(previousMatch))
        configure(nextMatchButton, image: "chevron.down", label: String(localized: "pdf_preview_next_match"),
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
        let stack = UIStackView(arrangedSubviews: [controls, searchControls, messageLabel, unlockButton, pdfView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
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
        loadDocumentIfReady()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchBar.resignFirstResponder()
    }

    func update(url: URL) {
        guard self.url != url else { return }
        self.url = url
        loadDocumentIfReady()
    }

    private func configure(_ button: UIButton, image: String, label: String, identifier: String, action: Selector) {
        button.setImage(UIImage(systemName: image), for: .normal)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
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
            messageLabel.text = String(localized: "pdf_preview_unavailable")
            messageLabel.isHidden = false
            unlockButton.isHidden = true
            updatePageState()
            return
        }
        if document.isLocked {
            messageLabel.text = String(localized: "pdf_preview_password_required")
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
            messageLabel.text = String(localized: "pdf_preview_invalid_password")
            return false
        }
        display(document)
        updatePageState()
        return true
    }

    @objc private func requestPassword() {
        let prompt = UIAlertController(title: String(localized: "pdf_preview_unlock"),
                                       message: String(localized: "pdf_preview_password_required"), preferredStyle: .alert)
        prompt.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = String(localized: "pdf_preview_password")
            field.accessibilityIdentifier = "pdf-preview-password"
        }
        prompt.addAction(UIAlertAction(title: String(localized: "取消"), style: .cancel))
        prompt.addAction(UIAlertAction(title: String(localized: "pdf_preview_unlock"), style: .default) { [weak self, weak prompt] _ in
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
        pageLabel.text = String(format: String(localized: "pdf_preview_page_format"), Int64(count == 0 ? 0 : index + 1), Int64(count))
        previousButton.isEnabled = count > 0 && pdfView.canGoToPreviousPage
        nextButton.isEnabled = count > 0 && pdfView.canGoToNextPage
        searchButton.isEnabled = count > 0
    }
}
