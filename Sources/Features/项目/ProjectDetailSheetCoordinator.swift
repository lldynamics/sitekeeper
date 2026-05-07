import SwiftUI
import VisionKit
import UIKit

private struct ProjectDetailEntrySheetCoordinatorModifier: ViewModifier {
    let project: Project
    let projectId: UUID
    @Binding var showSheet: DetailSheet?
    @Binding var showProjectEdit: Bool
    @Binding var showContactAdd: Bool
    @Binding var showFinancialAdd: Bool
    @Binding var showDocumentScanSetup: Bool
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSource: UIImagePickerController.SourceType

    let onUpdateProject: (Project) -> Void
    let onCreateContact: (ProjectContact) -> Void
    let onCreateFinancialRecord: (ProjectFinancialRecord, Bool) -> Void
    let onCreateScanTarget: (ProjectScanTarget) -> Void
    let onImportCapturedImage: (UIImage) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $showSheet) { sheet in
                QuickAddSheet(sheet: sheet, projectId: projectId)
            }
            .sheet(isPresented: $showProjectEdit) {
                ProjectEditSheet(project: project) { updated in
                    onUpdateProject(updated)
                }
            }
            .sheet(isPresented: $showContactAdd) {
                ProjectContactAddSheet(projectId: projectId) { contact in
                    onCreateContact(contact)
                }
            }
            .sheet(isPresented: $showFinancialAdd) {
                ProjectFinancialRecordAddSheet(projectId: projectId) { record, shouldScan in
                    onCreateFinancialRecord(record, shouldScan)
                }
            }
            .sheet(isPresented: $showDocumentScanSetup) {
                ProjectDocumentScanSetupSheet(projectId: projectId) { target in
                    onCreateScanTarget(target)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(sourceType: imagePickerSource) { image in
                    onImportCapturedImage(image)
                }
            }
    }
}

private struct ProjectDetailEditingSheetCoordinatorModifier: ViewModifier {
    @Binding var editingMaterial: MaterialItem?
    @Binding var editingQuote: QuoteItem?
    @Binding var editingLabor: LaborRecord?
    @Binding var editingProgress: ProgressTask?
    @Binding var selectedPhotoContext: ProjectPhotoContext?
    @Binding var editingDrawing: ProjectDrawing?
    @Binding var editingDocument: ProjectDocument?
    @Binding var editingContact: ProjectContact?
    @Binding var editingFinancialRecord: ProjectFinancialRecord?
    @Binding var attachmentManagingRecord: ProjectFinancialRecord?
    @Binding var scanTarget: ProjectScanTarget?
    @Binding var timelineContext: DrawingTimelineContext?

    let useMetric: Bool
    let projects: [Project]
    let relatedLogs: [DailyLog]
    let relatedFinancialRecords: [ProjectFinancialRecord]
    let linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    let attachmentSheetBuilder: (ProjectFinancialRecord) -> AnyView
    let timelineDrawings: (String) -> [ProjectDrawing]

    let onSaveMaterial: (MaterialItem) -> Void
    let onDeleteMaterial: (UUID) -> Void
    let onSaveQuote: (QuoteItem) -> Void
    let onDeleteQuote: (UUID) -> Void
    let onSaveLabor: (LaborRecord) -> Void
    let onDeleteLabor: (LaborRecord) -> Void
    let onSaveProgress: (ProgressTask) -> Void
    let onDeleteProgress: (UUID) -> Void
    let onUpdatePhoto: (ProjectPhotoContext, String, String) -> Void
    let onDeletePhoto: (ProjectPhotoContext) -> Void
    let onSaveDrawing: (ProjectDrawing) -> Void
    let onDeleteDrawing: (ProjectDrawing) -> Void
    let onPreviewDrawing: (ProjectDrawing) -> Void
    let onSaveDocument: (ProjectDocument) -> Void
    let onDeleteDocument: (ProjectDocument) -> Void
    let onPreviewDocument: (ProjectDocument) -> Void
    let onSaveContact: (ProjectContact) -> Void
    let onDeleteContact: (ProjectContact) -> Void
    let onSaveFinancialRecord: (ProjectFinancialRecord) -> Void
    let onDeleteFinancialRecord: (ProjectFinancialRecord) -> Void
    let onScanFinancialRecord: (ProjectFinancialRecord) -> Void
    let onManageAttachments: (ProjectFinancialRecord) -> Void
    let onSaveScannedDocument: (ProjectScanTarget, Data, Int) -> Void
    let onPresentImportError: (String) -> Void
    let onSetDrawingCurrentVersion: (ProjectDrawing) -> Void
    let onEditDrawingFromTimeline: (ProjectDrawing) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $editingMaterial) { item in
                MaterialEditSheet(item: item, useMetric: useMetric) { updated in
                    onSaveMaterial(updated)
                } onDelete: { id in
                    onDeleteMaterial(id)
                }
            }
            .sheet(item: $editingQuote) { item in
                QuoteEditSheet(item: item) { updated in
                    onSaveQuote(updated)
                } onDelete: { id in
                    onDeleteQuote(id)
                }
            }
            .sheet(item: $editingLabor) { record in
                LaborRecordEditSheet(record: record, projects: projects) { updated in
                    onSaveLabor(updated)
                } onDelete: { target in
                    onDeleteLabor(target)
                }
            }
            .sheet(item: $editingProgress) { item in
                ProgressEditSheet(item: item) { updated in
                    onSaveProgress(updated)
                } onDelete: { id in
                    onDeleteProgress(id)
                }
            }
            .sheet(item: $selectedPhotoContext) { context in
                ProjectPhotoDetailSheet(context: context, allLogs: relatedLogs) { note, tag in
                    onUpdatePhoto(context, note, tag)
                } onDelete: {
                    onDeletePhoto(context)
                }
            }
            .sheet(item: $editingDrawing) { drawing in
                ProjectDrawingEditSheet(drawing: drawing) { updated in
                    onSaveDrawing(updated)
                } onDelete: { target in
                    onDeleteDrawing(target)
                } onPreview: { target in
                    onPreviewDrawing(target)
                }
            }
            .sheet(item: $editingDocument) { document in
                ProjectDocumentDetailSheet(
                    document: document,
                    financialRecords: relatedFinancialRecords
                ) { target in
                    onPreviewDocument(target)
                } onSave: { updated in
                    onSaveDocument(updated)
                } onDelete: { target in
                    onDeleteDocument(target)
                }
            }
            .sheet(item: $editingContact) { contact in
                ProjectContactEditSheet(contact: contact) { updated in
                    onSaveContact(updated)
                } onDelete: { target in
                    onDeleteContact(target)
                }
            }
            .sheet(item: $editingFinancialRecord) { record in
                ProjectFinancialRecordEditSheet(
                    record: record,
                    linkedAttachmentCount: linkedDocuments(record).count
                ) { updated in
                    onSaveFinancialRecord(updated)
                } onDelete: { target in
                    onDeleteFinancialRecord(target)
                } onScan: { target in
                    onScanFinancialRecord(target)
                } onManageAttachments: { target in
                    onManageAttachments(target)
                }
            }
            .sheet(item: $attachmentManagingRecord) { record in
                attachmentSheetBuilder(record)
            }
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
                        ContentUnavailableView("当前设备不支持扫描", systemImage: "camera.viewfinder", description: Text("请在支持相机扫描的 iPhone 或 iPad 上使用。"))
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("关闭") { scanTarget = nil }
                                }
                            }
                    }
                }
            }
            .sheet(item: $timelineContext) { context in
                ProjectDrawingTimelineSheet(
                    drawingName: context.name,
                    drawings: timelineDrawings(context.name),
                    onSetCurrent: { drawing in
                        onSetDrawingCurrentVersion(drawing)
                    },
                    onPreview: { drawing in
                        onPreviewDrawing(drawing)
                    },
                    onEdit: { drawing in
                        onEditDrawingFromTimeline(drawing)
                    }
                )
            }
    }
}

extension View {
    func projectDetailEntrySheetCoordinator(
        project: Project,
        projectId: UUID,
        showSheet: Binding<DetailSheet?>,
        showProjectEdit: Binding<Bool>,
        showContactAdd: Binding<Bool>,
        showFinancialAdd: Binding<Bool>,
        showDocumentScanSetup: Binding<Bool>,
        showImagePicker: Binding<Bool>,
        imagePickerSource: Binding<UIImagePickerController.SourceType>,
        onUpdateProject: @escaping (Project) -> Void,
        onCreateContact: @escaping (ProjectContact) -> Void,
        onCreateFinancialRecord: @escaping (ProjectFinancialRecord, Bool) -> Void,
        onCreateScanTarget: @escaping (ProjectScanTarget) -> Void,
        onImportCapturedImage: @escaping (UIImage) -> Void
    ) -> some View {
        modifier(
            ProjectDetailEntrySheetCoordinatorModifier(
                project: project,
                projectId: projectId,
                showSheet: showSheet,
                showProjectEdit: showProjectEdit,
                showContactAdd: showContactAdd,
                showFinancialAdd: showFinancialAdd,
                showDocumentScanSetup: showDocumentScanSetup,
                showImagePicker: showImagePicker,
                imagePickerSource: imagePickerSource,
                onUpdateProject: onUpdateProject,
                onCreateContact: onCreateContact,
                onCreateFinancialRecord: onCreateFinancialRecord,
                onCreateScanTarget: onCreateScanTarget,
                onImportCapturedImage: onImportCapturedImage
            )
        )
    }

    func projectDetailEditingSheetCoordinator(
        editingMaterial: Binding<MaterialItem?>,
        editingQuote: Binding<QuoteItem?>,
        editingLabor: Binding<LaborRecord?>,
        editingProgress: Binding<ProgressTask?>,
        selectedPhotoContext: Binding<ProjectPhotoContext?>,
        editingDrawing: Binding<ProjectDrawing?>,
        editingDocument: Binding<ProjectDocument?>,
        editingContact: Binding<ProjectContact?>,
        editingFinancialRecord: Binding<ProjectFinancialRecord?>,
        attachmentManagingRecord: Binding<ProjectFinancialRecord?>,
        scanTarget: Binding<ProjectScanTarget?>,
        timelineContext: Binding<DrawingTimelineContext?>,
        useMetric: Bool,
        projects: [Project],
        relatedLogs: [DailyLog],
        relatedFinancialRecords: [ProjectFinancialRecord],
        linkedDocuments: @escaping (ProjectFinancialRecord) -> [ProjectDocument],
        attachmentSheetBuilder: @escaping (ProjectFinancialRecord) -> AnyView,
        timelineDrawings: @escaping (String) -> [ProjectDrawing],
        onSaveMaterial: @escaping (MaterialItem) -> Void,
        onDeleteMaterial: @escaping (UUID) -> Void,
        onSaveQuote: @escaping (QuoteItem) -> Void,
        onDeleteQuote: @escaping (UUID) -> Void,
        onSaveLabor: @escaping (LaborRecord) -> Void,
        onDeleteLabor: @escaping (LaborRecord) -> Void,
        onSaveProgress: @escaping (ProgressTask) -> Void,
        onDeleteProgress: @escaping (UUID) -> Void,
        onUpdatePhoto: @escaping (ProjectPhotoContext, String, String) -> Void,
        onDeletePhoto: @escaping (ProjectPhotoContext) -> Void,
        onSaveDrawing: @escaping (ProjectDrawing) -> Void,
        onDeleteDrawing: @escaping (ProjectDrawing) -> Void,
        onPreviewDrawing: @escaping (ProjectDrawing) -> Void,
        onSaveDocument: @escaping (ProjectDocument) -> Void,
        onDeleteDocument: @escaping (ProjectDocument) -> Void,
        onPreviewDocument: @escaping (ProjectDocument) -> Void,
        onSaveContact: @escaping (ProjectContact) -> Void,
        onDeleteContact: @escaping (ProjectContact) -> Void,
        onSaveFinancialRecord: @escaping (ProjectFinancialRecord) -> Void,
        onDeleteFinancialRecord: @escaping (ProjectFinancialRecord) -> Void,
        onScanFinancialRecord: @escaping (ProjectFinancialRecord) -> Void,
        onManageAttachments: @escaping (ProjectFinancialRecord) -> Void,
        onSaveScannedDocument: @escaping (ProjectScanTarget, Data, Int) -> Void,
        onPresentImportError: @escaping (String) -> Void,
        onSetDrawingCurrentVersion: @escaping (ProjectDrawing) -> Void,
        onEditDrawingFromTimeline: @escaping (ProjectDrawing) -> Void
    ) -> some View {
        modifier(
            ProjectDetailEditingSheetCoordinatorModifier(
                editingMaterial: editingMaterial,
                editingQuote: editingQuote,
                editingLabor: editingLabor,
                editingProgress: editingProgress,
                selectedPhotoContext: selectedPhotoContext,
                editingDrawing: editingDrawing,
                editingDocument: editingDocument,
                editingContact: editingContact,
                editingFinancialRecord: editingFinancialRecord,
                attachmentManagingRecord: attachmentManagingRecord,
                scanTarget: scanTarget,
                timelineContext: timelineContext,
                useMetric: useMetric,
                projects: projects,
                relatedLogs: relatedLogs,
                relatedFinancialRecords: relatedFinancialRecords,
                linkedDocuments: linkedDocuments,
                attachmentSheetBuilder: attachmentSheetBuilder,
                timelineDrawings: timelineDrawings,
                onSaveMaterial: onSaveMaterial,
                onDeleteMaterial: onDeleteMaterial,
                onSaveQuote: onSaveQuote,
                onDeleteQuote: onDeleteQuote,
                onSaveLabor: onSaveLabor,
                onDeleteLabor: onDeleteLabor,
                onSaveProgress: onSaveProgress,
                onDeleteProgress: onDeleteProgress,
                onUpdatePhoto: onUpdatePhoto,
                onDeletePhoto: onDeletePhoto,
                onSaveDrawing: onSaveDrawing,
                onDeleteDrawing: onDeleteDrawing,
                onPreviewDrawing: onPreviewDrawing,
                onSaveDocument: onSaveDocument,
                onDeleteDocument: onDeleteDocument,
                onPreviewDocument: onPreviewDocument,
                onSaveContact: onSaveContact,
                onDeleteContact: onDeleteContact,
                onSaveFinancialRecord: onSaveFinancialRecord,
                onDeleteFinancialRecord: onDeleteFinancialRecord,
                onScanFinancialRecord: onScanFinancialRecord,
                onManageAttachments: onManageAttachments,
                onSaveScannedDocument: onSaveScannedDocument,
                onPresentImportError: onPresentImportError,
                onSetDrawingCurrentVersion: onSetDrawingCurrentVersion,
                onEditDrawingFromTimeline: onEditDrawingFromTimeline
            )
        )
    }
}