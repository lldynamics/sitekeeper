import SwiftUI
import UIKit

struct ProjectDetailEditingCoordinatorDependencies<AttachmentSheet: View> {
    let useMetric: Bool
    let projects: [Project]
    let constructionMethods: [ConstructionMethod]
    let relatedLogs: [DailyLog]
    let relatedTodos: [SiteTodo]
    let relatedDrawings: [ProjectDrawing]
    let relatedFinancialRecords: [ProjectFinancialRecord]
    let relatedDocuments: [ProjectDocument]
    let linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    let attachmentSheetBuilder: (ProjectFinancialRecord) -> AttachmentSheet
    let timelineDrawings: (String) -> [ProjectDrawing]
}

struct ProjectDetailEditingCoordinatorHandlers {
    let onSaveMaterial: (MaterialItem) -> Void
    let onDeleteMaterial: (UUID) -> Void
    let onSaveQuote: (QuoteItem) -> Void
    let onDeleteQuote: (UUID) -> Void
    let onSaveLabor: (LaborRecord) -> Void
    let onDeleteLabor: (LaborRecord) -> Void
    let onSaveProgress: (ProgressTask) -> Void
    let onDeleteProgress: (UUID) -> Void
    let onUpdatePhoto: (ProjectPhotoContext, String, PhotoTag) -> Void
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
    let onSetDrawingCurrentVersion: (ProjectDrawing) -> Void
    let onEditDrawingFromTimeline: (ProjectDrawing) -> Void
}

private struct ProjectDetailEntrySheetCoordinatorModifier: ViewModifier {
    let project: Project
    let projectId: UUID
    @Binding var presentation: ProjectDetailPresentation?
    @Binding var documentScanCategory: ProjectDocumentCategory?
    @Binding var financialAddSeed: ProjectFinancialRecord?
    @Binding var imagePickerSource: UIImagePickerController.SourceType

    let deliveryGuideData: ProjectDeliveryGuideData
    let constructionMethods: [ConstructionMethod]
    let relatedProgress: [ProgressTask]
    let recentFinancialRecords: [ProjectFinancialRecord]
    let onOpenModeFromDeliveryGuide: (ProjectDetailMode) -> Void
    let onRepairFromDeliveryGuide: (ProjectDeliveryRepairAction) -> Void
    let onStartDeliveryExport: () -> Void
    let onUpdateProject: (Project) -> Void
    let onCreateContact: (ProjectContact) -> Void
    let onCreateFinancialRecord: (ProjectFinancialRecord, Bool) -> Void
    let onCreateScanTarget: (ProjectScanTarget) -> Void
    let onImportCapturedImage: (UIImage) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $presentation, onDismiss: {
                financialAddSeed = nil
                documentScanCategory = nil
            }) { presentation in
                switch presentation {
                case .quickAdd(let sheet):
                    QuickAddSheet(
                        sheet: sheet,
                        projectId: projectId,
                        constructionMethods: constructionMethods
                    )
                case .editProject:
                    ProjectEditSheet(project: project, progressTasks: relatedProgress) { updated in
                        onUpdateProject(updated)
                    }
                case .deliveryGuide:
                    ProjectDeliveryGuideView(
                        data: deliveryGuideData,
                        onStartExport: {
                            self.presentation = nil
                            onStartDeliveryExport()
                        },
                        onOpenMode: { mode in
                            self.presentation = nil
                            onOpenModeFromDeliveryGuide(mode)
                        },
                        onRepair: { action in
                            self.presentation = nil
                            onRepairFromDeliveryGuide(action)
                        }
                    )
                case .addContact:
                    ProjectContactAddSheet(projectId: projectId) { contact in
                        onCreateContact(contact)
                    }
                case .addFinancial:
                    ProjectFinancialRecordAddSheet(
                        projectId: projectId,
                        preset: financialAddSeed,
                        recentRecords: recentFinancialRecords
                    ) { record, shouldScan in
                        onCreateFinancialRecord(record, shouldScan)
                        financialAddSeed = nil
                    }
                case .documentScanSetup:
                    ProjectDocumentScanSetupSheet(
                        projectId: projectId,
                        constructionMethods: constructionMethods,
                        initialCategory: documentScanCategory ?? .constructionRecord
                    ) { target in
                        onCreateScanTarget(target)
                    }
                case .imagePicker:
                    ImagePickerView(sourceType: imagePickerSource) { image in
                        onImportCapturedImage(image)
                    }
                }
            }
    }
}

private struct ProjectDetailEditingSheetCoordinatorModifier<AttachmentSheet: View>: ViewModifier {
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
    @Binding var timelineContext: DrawingTimelineContext?

    let useMetric: Bool
    let projects: [Project]
    let constructionMethods: [ConstructionMethod]
    let relatedLogs: [DailyLog]
    let relatedTodos: [SiteTodo]
    let relatedDrawings: [ProjectDrawing]
    let relatedFinancialRecords: [ProjectFinancialRecord]
    let relatedDocuments: [ProjectDocument]
    let linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    let attachmentSheetBuilder: (ProjectFinancialRecord) -> AttachmentSheet
    let timelineDrawings: (String) -> [ProjectDrawing]

    let onSaveMaterial: (MaterialItem) -> Void
    let onDeleteMaterial: (UUID) -> Void
    let onSaveQuote: (QuoteItem) -> Void
    let onDeleteQuote: (UUID) -> Void
    let onSaveLabor: (LaborRecord) -> Void
    let onDeleteLabor: (LaborRecord) -> Void
    let onSaveProgress: (ProgressTask) -> Void
    let onDeleteProgress: (UUID) -> Void
    let onUpdatePhoto: (ProjectPhotoContext, String, PhotoTag) -> Void
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
                ProjectDrawingEditSheet(
                    drawing: drawing,
                    relatedDrawings: relatedDrawings,
                    relatedLogs: relatedLogs,
                    relatedTodos: relatedTodos,
                    relatedDocuments: relatedDocuments
                ) { updated in
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
                    financialRecords: relatedFinancialRecords,
                    projectDocuments: relatedDocuments,
                    constructionMethods: constructionMethods
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
                    linkedDocuments: linkedDocuments(record),
                    linkedAttachmentCount: linkedDocuments(record).count,
                    existingRecords: relatedFinancialRecords
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
        presentation: Binding<ProjectDetailPresentation?>,
        documentScanCategory: Binding<ProjectDocumentCategory?>,
        financialAddSeed: Binding<ProjectFinancialRecord?>,
        imagePickerSource: Binding<UIImagePickerController.SourceType>,
        deliveryGuideData: ProjectDeliveryGuideData,
        constructionMethods: [ConstructionMethod],
        relatedProgress: [ProgressTask],
        recentFinancialRecords: [ProjectFinancialRecord],
        onOpenModeFromDeliveryGuide: @escaping (ProjectDetailMode) -> Void,
        onRepairFromDeliveryGuide: @escaping (ProjectDeliveryRepairAction) -> Void,
        onStartDeliveryExport: @escaping () -> Void,
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
                presentation: presentation,
                documentScanCategory: documentScanCategory,
                financialAddSeed: financialAddSeed,
                imagePickerSource: imagePickerSource,
                deliveryGuideData: deliveryGuideData,
                constructionMethods: constructionMethods,
                relatedProgress: relatedProgress,
                recentFinancialRecords: recentFinancialRecords,
                onOpenModeFromDeliveryGuide: onOpenModeFromDeliveryGuide,
                onRepairFromDeliveryGuide: onRepairFromDeliveryGuide,
                onStartDeliveryExport: onStartDeliveryExport,
                onUpdateProject: onUpdateProject,
                onCreateContact: onCreateContact,
                onCreateFinancialRecord: onCreateFinancialRecord,
                onCreateScanTarget: onCreateScanTarget,
                onImportCapturedImage: onImportCapturedImage
            )
        )
    }

    func projectDetailEditingSheetCoordinator<AttachmentSheet: View>(
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
        timelineContext: Binding<DrawingTimelineContext?>,
        dependencies: ProjectDetailEditingCoordinatorDependencies<AttachmentSheet>,
        handlers: ProjectDetailEditingCoordinatorHandlers
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
                timelineContext: timelineContext,
                useMetric: dependencies.useMetric,
                projects: dependencies.projects,
                constructionMethods: dependencies.constructionMethods,
                relatedLogs: dependencies.relatedLogs,
                relatedTodos: dependencies.relatedTodos,
                relatedDrawings: dependencies.relatedDrawings,
                relatedFinancialRecords: dependencies.relatedFinancialRecords,
                relatedDocuments: dependencies.relatedDocuments,
                linkedDocuments: dependencies.linkedDocuments,
                attachmentSheetBuilder: dependencies.attachmentSheetBuilder,
                timelineDrawings: dependencies.timelineDrawings,
                onSaveMaterial: handlers.onSaveMaterial,
                onDeleteMaterial: handlers.onDeleteMaterial,
                onSaveQuote: handlers.onSaveQuote,
                onDeleteQuote: handlers.onDeleteQuote,
                onSaveLabor: handlers.onSaveLabor,
                onDeleteLabor: handlers.onDeleteLabor,
                onSaveProgress: handlers.onSaveProgress,
                onDeleteProgress: handlers.onDeleteProgress,
                onUpdatePhoto: handlers.onUpdatePhoto,
                onDeletePhoto: handlers.onDeletePhoto,
                onSaveDrawing: handlers.onSaveDrawing,
                onDeleteDrawing: handlers.onDeleteDrawing,
                onPreviewDrawing: handlers.onPreviewDrawing,
                onSaveDocument: handlers.onSaveDocument,
                onDeleteDocument: handlers.onDeleteDocument,
                onPreviewDocument: handlers.onPreviewDocument,
                onSaveContact: handlers.onSaveContact,
                onDeleteContact: handlers.onDeleteContact,
                onSaveFinancialRecord: handlers.onSaveFinancialRecord,
                onDeleteFinancialRecord: handlers.onDeleteFinancialRecord,
                onScanFinancialRecord: handlers.onScanFinancialRecord,
                onManageAttachments: handlers.onManageAttachments,
                onSetDrawingCurrentVersion: handlers.onSetDrawingCurrentVersion,
                onEditDrawingFromTimeline: handlers.onEditDrawingFromTimeline
            )
        )
    }
}
