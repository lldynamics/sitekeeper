import SwiftUI

extension ProjectDetailContainer {
    func applyPresentationModifiers<Content: View>(
        to content: Content,
        project: Project,
        snapshot: ProjectDetailSnapshot
    ) -> some View {
        content
            .projectDetailExportHost(
                exportPayload: $exportState.exportPayload,
                showExporter: $exportState.showExporter,
                pendingPackageProject: $exportState.pendingPackageProject,
                packageSizeWarningMessage: $exportState.packageSizeWarningMessage,
                showPackageSizeWarning: $exportState.showPackageSizeWarning,
                onContinuePackageExport: { exportProjectPackage($0, snapshot: snapshot) }
            )
            .projectDetailEntrySheetCoordinator(
                project: project,
                projectId: projectId,
                presentation: $routeState.presentation,
                documentScanCategory: $routeState.documentScanCategory,
                financialAddSeed: $financeState.financialAddSeed,
                imagePickerSource: $assetState.imagePickerSource,
                deliveryGuideData: deliveryGuideData(snapshot: snapshot),
                constructionMethods: store.constructionMethods,
                relatedProgress: snapshot.relatedProgress,
                recentFinancialRecords: snapshot.relatedFinancialRecords,
                onOpenModeFromDeliveryGuide: { mode in
                    openMode(mode, prefersInlineSections: usesSingleCanvasLayoutOnPad)
                },
                onRepairFromDeliveryGuide: { action in
                    handleDeliveryRepairAction(action, snapshot: snapshot)
                },
                onStartDeliveryExport: {
                    requestExportProjectPackage(project, snapshot: snapshot)
                },
                onExportDeliveryInspection: {
                    exportPreDeliveryInspection(project, snapshot: snapshot)
                },
                onUpdateProject: updateProject(_:),
                onCreateContact: { contact in
                    store.appendProjectContact(contact)
                    store.scheduleSave()
                },
                onCreateFinancialRecord: { record, shouldScan in
                    store.appendProjectFinancialRecord(record)
                    if shouldScan {
                        assetState.scanTarget = scanTarget(for: record)
                    }
                    store.scheduleSave()
                },
                onCreateScanTarget: { target in
                    assetState.scanTarget = target
                },
                onImportCapturedImage: { image in
                    importCapturedImage(image)
                }
            )
            .projectDetailEditingSheetCoordinator(
                editingMaterial: editingMaterialBinding,
                editingQuote: editingQuoteBinding,
                editingLabor: editingLaborBinding,
                editingProgress: editingProgressBinding,
                selectedPhotoContext: $assetState.selectedPhotoContext,
                editingDrawing: $assetState.editingDrawing,
                editingDocument: $assetState.editingDocument,
                editingContact: $assetState.editingContact,
                editingFinancialRecord: $financeState.editingFinancialRecord,
                attachmentManagingRecord: $financeState.attachmentManagingRecord,
                timelineContext: $assetState.timelineContext,
                dependencies: ProjectDetailEditingCoordinatorDependencies(
                    useMetric: useMetric,
                    projects: projectStore.projects,
                    constructionMethods: store.constructionMethods,
                    relatedLogs: snapshot.relatedLogs,
                    relatedTodos: snapshot.relatedTodos,
                    relatedDrawings: snapshot.relatedDrawings,
                    relatedFinancialRecords: snapshot.relatedFinancialRecords,
                    relatedDocuments: snapshot.relatedDocuments,
                    linkedDocuments: linkedDocuments(for:),
                    attachmentSheetBuilder: { record in
                        attachmentSheet(record: record, documents: snapshot.relatedDocuments)
                    },
                    timelineDrawings: { name in
                        timelineDrawings(name: name, drawings: snapshot.relatedDrawings)
                    }
                ),
                handlers: ProjectDetailEditingCoordinatorHandlers(
                    onSaveMaterial: saveMaterial,
                    onDeleteMaterial: deleteMaterial(id:),
                    onSaveQuote: saveQuote,
                    onDeleteQuote: deleteQuote(id:),
                    onSaveLabor: saveLabor,
                    onDeleteLabor: deleteLabor,
                    onSaveProgress: saveProgress,
                    onDeleteProgress: deleteProgress(id:),
                    onUpdatePhoto: { context, note, tag in
                        updateProjectPhoto(context: context, note: note, tag: tag)
                    },
                    onDeletePhoto: { context in
                        deleteProjectPhoto(context: context)
                    },
                    onSaveDrawing: saveDrawing(_:),
                    onDeleteDrawing: deleteDrawing(_:),
                    onPreviewDrawing: previewDrawing(_:),
                    onSaveDocument: saveDocumentEdit(_:),
                    onDeleteDocument: deleteDocument(_:),
                    onPreviewDocument: previewDocument(_:),
                    onSaveContact: saveContact(_:),
                    onDeleteContact: deleteContact(_:),
                    onSaveFinancialRecord: saveFinancialRecord,
                    onDeleteFinancialRecord: requestDeleteFinancialRecord(_:),
                    onScanFinancialRecord: { target in
                        assetState.scanTarget = scanTarget(for: target)
                    },
                    onManageAttachments: { target in
                        financeState.attachmentManagingRecord = target
                    },
                    onSetDrawingCurrentVersion: setDrawingAsCurrentVersion(_:),
                    onEditDrawingFromTimeline: { drawing in
                        assetState.editingDrawing = drawing
                    }
                )
            )
            .projectDetailImportFlowCoordinator(
                showDrawingImporter: $assetState.showDrawingImporter,
                drawingImportTypes: Self.drawingImportTypes,
                onImportDrawings: importDrawings(_:),
                showDocumentFileImporter: $assetState.showDocumentFileImporter,
                documentImportTypes: Self.documentImportTypes,
                onImportDocuments: { urls, settings in
                    importProjectDocuments(urls, ledgerSettings: settings)
                },
                selectedPhotoItem: $assetState.selectedPhotoItem,
                onImportPhotoItem: { item in
                    await importPhotoItem(item)
                },
                quickLookURL: $assetState.quickLookURL,
                scanTarget: $assetState.scanTarget,
                onSaveScannedDocument: saveScannedDocument(target:data:pageCount:),
                onPresentImportError: presentImportError(_:),
                showImportError: $assetState.showImportError,
                importErrorMessage: $assetState.importErrorMessage
            )
            .sheet(isPresented: drawingShareSheetPresented) {
                if let drawingShareURL = assetState.drawingShareURL {
                    ActivityShareSheet(activityItems: [drawingShareURL], onComplete: { completed in
                        ProjectDetailAssetActions.recordDrawingExternalOpenResult(
                            completed: completed,
                            drawingID: assetState.drawingShareDrawingID,
                            store: store
                        )
                        assetState.drawingShareURL = nil
                        assetState.drawingShareDrawingID = nil
                    })
                }
            }
            .confirmationDialog(String(localized: "删除账目"), isPresented: $financeState.showFinancialDeleteConfirm, titleVisibility: .visible) {
                Button(String(localized: "仅删除账目（保留票据）"), role: .destructive) {
                    performDeleteFinancialRecords(deleteLinkedDocuments: false)
                }
                Button(String(localized: "删除账目并删除票据"), role: .destructive) {
                    performDeleteFinancialRecords(deleteLinkedDocuments: true)
                }
                Button(String(localized: "取消"), role: .cancel) {
                    financeState.pendingDeleteFinancialRecordIDs.removeAll()
                }
            } message: {
                Text(String(format: String(localized: "将删除 %d 条账目。可选择保留票据为项目资料。"), financeState.pendingDeleteFinancialRecordIDs.count))
            }
            .confirmationDialog(String(localized: "同名图纸导入策略"), isPresented: $assetState.showDrawingImportStrategyDialog, titleVisibility: .visible) {
                ForEach(ProjectDrawingImportStrategy.allCases) { strategy in
                    Button(strategy.displayName) {
                        applyPendingDrawingImportStrategy(strategy)
                    }
                }
                Button(String(localized: "取消"), role: .cancel) {
                    clearPendingDrawingImportStrategy()
                }
            } message: {
                Text(drawingImportConflictDialogMessage)
            }
            .overlay {
                if exportState.isExportingProjectPackage {
                    ZStack {
                        Color.black.opacity(0.22)
                            .ignoresSafeArea()
                        ProjectPackageExportOverlayView(
                            progress: exportState.projectPackageExportProgress,
                            onCancel: cancelProjectPackageExport
                        )
                    }
                }
            }
            .operationToast(notice: $operationNotice)
    }
}
