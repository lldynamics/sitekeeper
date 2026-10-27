import SwiftUI

extension ProjectDetailContainer {
    func content(snapshot: ProjectDetailSnapshot) -> some View {
        let project = snapshot.project
        let baseContent = detailCanvas(snapshot: snapshot, statusBinding: projectStatusBinding(for: project))
        let navigatedContent = applyNavigationAndLifecycleModifiers(
            to: baseContent,
            project: project,
            snapshot: snapshot
        )
        return applyPresentationModifiers(
            to: navigatedContent,
            project: project,
            snapshot: snapshot
        )
    }

    func projectStatusBinding(for project: Project) -> Binding<ProjectStatus> {
        Binding(
            get: { project.status },
            set: { newValue in
                if let idx = projectStore.projects.firstIndex(where: { $0.id == projectId }) {
                    var updatedProject = projectStore.projects[idx]
                    updatedProject.status = newValue
                    if store.updateProject(updatedProject) {
                        store.scheduleSave()
                    }
                }
            }
        )
    }

    func detailCanvas(
        snapshot: ProjectDetailSnapshot,
        statusBinding: Binding<ProjectStatus>
    ) -> some View {
        GeometryReader { proxy in
            ProjectDetailContent(
                snapshot: snapshot,
                projectId: projectId,
                useMetric: useMetric,
                statusBinding: statusBinding,
                mode: routeState.mode,
                anchorRequest: routeState.anchorRequest,
                financeJumpFilter: routeState.financeJumpFilter,
                prefersInlineSections: usesInlineDetailLayout(for: proxy.size.width),
                showsAllSections: usesInlineDetailLayout(for: proxy.size.width),
                allProjectContacts: projectStore.projectContacts,
                constructionMethods: store.constructionMethods,
                supplierProfiles: store.supplierProfiles,
                allProjects: projectStore.projects,
                allFinancialRecords: projectStore.projectFinancialRecords,
                allDocuments: projectStore.projectDocuments,
                drawingFilter: $routeState.drawingFilter,
                selectedPhotoItem: $assetState.selectedPhotoItem,
                showDocumentFileImporter: $assetState.showDocumentFileImporter,
                onSelectMode: { newMode in
                    openMode(newMode, prefersInlineSections: usesInlineDetailLayout(for: proxy.size.width))
                },
                onOpenRecordsMetric: openRecordsModeFromMetric,
                onOpenFinanceFromQuoteMetric: openFinanceModeFromQuoteMetric,
                onOpenTodoFilter: openTodoFilterFromMetric,
                onOpenFinanceFilter: openFinanceModeFromMetric(filter:),
                onEditProject: { routeState.presentation = .editProject },
                onOpenDeliveryGuide: { routeState.presentation = .deliveryGuide },
                onAddLog: { routeState.presentation = .quickAdd(.log) },
                onAddMaterial: { routeState.presentation = .quickAdd(.material) },
                onAddQuote: { routeState.presentation = .quickAdd(.quote) },
                onAddLabor: { routeState.presentation = .quickAdd(.labor) },
                onAddFinancialRecord: { routeState.presentation = .addFinancial },
                onAddContact: { routeState.presentation = .addContact },
                onImportDrawing: { assetState.showDrawingImporter = true },
                onOpenMode: { mode in
                    openMode(mode, prefersInlineSections: usesInlineDetailLayout(for: proxy.size.width))
                },
                onScanDocument: {
                    routeState.documentScanCategory = nil
                    routeState.presentation = .documentScanSetup
                },
                onScanDocumentCategory: { category in
                    routeState.documentScanCategory = category
                    routeState.presentation = .documentScanSetup
                },
                onCaptureDocumentPhoto: {
                    assetState.imagePickerSource = .camera
                    routeState.presentation = .imagePicker
                },
                onEditMaterial: { routeState.editingRoute = .material($0) },
                onEditQuote: { routeState.editingRoute = .quote($0) },
                onEditLabor: { routeState.editingRoute = .labor($0) },
                onEditProgress: { routeState.editingRoute = .progress($0) },
                onOpenPhotoContext: { assetState.selectedPhotoContext = $0 },
                onEditDrawing: { assetState.editingDrawing = $0 },
                onShowDrawingTimeline: { assetState.timelineContext = DrawingTimelineContext(name: $0) },
                onPreviewDrawing: previewDrawing(_:),
                onDeleteDrawing: deleteDrawing(_:),
                onEditContact: { assetState.editingContact = $0 },
                onDeleteContacts: { ids in
                    ids.forEach { removeContactAssociation(contactID: $0, from: projectId) }
                    store.scheduleSave()
                },
                onEditFinancialRecord: { financeState.editingFinancialRecord = $0 },
                onDeleteFinancialRecords: deleteFinancialRecords(ids:),
                onOpenDocument: { assetState.editingDocument = $0 },
                onLinkDocumentToFinancialRecord: linkDocument(_:to:),
                linkedDocuments: linkedDocuments(for:),
                onResetFinanceJumpFilter: resetFinanceJumpFilter
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
