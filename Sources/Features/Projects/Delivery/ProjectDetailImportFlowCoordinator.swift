import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import VisionKit

private struct ProjectDetailImportFlowCoordinatorModifier: ViewModifier {
    @State private var pendingDocumentImportRequest: ProjectDocumentImportConfirmationRequest?

    @Binding var showDrawingImporter: Bool
    let drawingImportTypes: [UTType]
    let onImportDrawings: ([URL]) -> Void

    @Binding var showDocumentFileImporter: Bool
    let documentImportTypes: [UTType]
    let onImportDocuments: ([URL], ProjectDocumentImportLedgerSettings) -> Void

    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onImportPhotoItem: (PhotosPickerItem) async -> Void

    @Binding var quickLookURL: URL?
    @Binding var scanTarget: ProjectScanTarget?
    let onSaveScannedDocument: (ProjectScanTarget, Data, Int) -> Void
    let onPresentImportError: (String) -> Void

    @Binding var showImportError: Bool
    @Binding var importErrorMessage: String
    let importErrorTitle: String

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showDrawingImporter,
                allowedContentTypes: drawingImportTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    onImportDrawings(urls)
                case .failure(let error):
                    StorageIssueLog.recordEvent(
                        "project.drawing.import_failed",
                        category: .fileStorage,
                        details: ["source": "ProjectDetailImportFlowCoordinator.fileImporter.drawing"],
                        error: error
                    )
                    onPresentImportError(
                        String(
                            format: AppLocalization.string("图纸导入失败：%@"),
                            error.localizedDescription
                        )
                    )
                }
            }
            .fileImporter(
                isPresented: $showDocumentFileImporter,
                allowedContentTypes: documentImportTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    pendingDocumentImportRequest = ProjectDocumentImportConfirmationRequest(
                        urls: urls,
                        defaultSettings: ProjectDocumentImportLedgerSettings(category: .constructionRecord)
                    )
                case .failure(let error):
                    StorageIssueLog.recordEvent(
                        "project.document.import_failed",
                        category: .fileStorage,
                        details: ["source": "ProjectDetailImportFlowCoordinator.fileImporter.document"],
                        error: error
                    )
                    onPresentImportError(
                        String(
                            format: AppLocalization.string("资料导入失败：%@"),
                            error.localizedDescription
                        )
                    )
                }
            }
            .sheet(item: $pendingDocumentImportRequest) { request in
                ProjectDocumentImportConfirmationSheet(
                    urls: request.urls,
                    defaultSettings: request.defaultSettings
                ) { settings in
                    onImportDocuments(request.urls, settings)
                    pendingDocumentImportRequest = nil
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    await onImportPhotoItem(item)
                    await MainActor.run {
                        selectedPhotoItem = nil
                    }
                }
            }
            .appFilePreview($quickLookURL)
            .sheet(item: $scanTarget) { target in
                if VNDocumentCameraViewController.isSupported {
                    DocumentScannerView(
                        onSave: { data, pageCount in
                            onSaveScannedDocument(target, data, pageCount)
                            scanTarget = nil
                        },
                        onError: { message in
                            onPresentImportError(message)
                            scanTarget = nil
                        }
                    )
                } else {
                    NavigationStack {
                        ContentUnavailableView(
                            AppLocalization.string("当前设备不支持扫描"),
                            systemImage: "camera.viewfinder",
                            description: Text(AppLocalization.string("请在支持相机扫描的 iPhone 或 iPad 上使用。"))
                        )
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(AppLocalization.string("关闭")) { scanTarget = nil }
                                }
                            }
                    }
                }
            }
            .alert(importErrorTitle, isPresented: $showImportError) {
                Button(AppLocalization.string("知道了"), role: .cancel) {}
            } message: {
                Text(importErrorMessage)
            }
    }
}

extension View {
    func projectDetailImportFlowCoordinator(
        showDrawingImporter: Binding<Bool>,
        drawingImportTypes: [UTType],
        onImportDrawings: @escaping ([URL]) -> Void,
        showDocumentFileImporter: Binding<Bool>,
        documentImportTypes: [UTType],
        onImportDocuments: @escaping ([URL], ProjectDocumentImportLedgerSettings) -> Void,
        selectedPhotoItem: Binding<PhotosPickerItem?>,
        onImportPhotoItem: @escaping (PhotosPickerItem) async -> Void,
        quickLookURL: Binding<URL?>,
        scanTarget: Binding<ProjectScanTarget?>,
        onSaveScannedDocument: @escaping (ProjectScanTarget, Data, Int) -> Void,
        onPresentImportError: @escaping (String) -> Void,
        showImportError: Binding<Bool>,
        importErrorMessage: Binding<String>,
        importErrorTitle: String = AppLocalization.string("操作失败")
    ) -> some View {
        modifier(
            ProjectDetailImportFlowCoordinatorModifier(
                showDrawingImporter: showDrawingImporter,
                drawingImportTypes: drawingImportTypes,
                onImportDrawings: onImportDrawings,
                showDocumentFileImporter: showDocumentFileImporter,
                documentImportTypes: documentImportTypes,
                onImportDocuments: onImportDocuments,
                selectedPhotoItem: selectedPhotoItem,
                onImportPhotoItem: onImportPhotoItem,
                quickLookURL: quickLookURL,
                scanTarget: scanTarget,
                onSaveScannedDocument: onSaveScannedDocument,
                onPresentImportError: onPresentImportError,
                showImportError: showImportError,
                importErrorMessage: importErrorMessage,
                importErrorTitle: importErrorTitle
            )
        )
    }
}
