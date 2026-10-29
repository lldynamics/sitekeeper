import SwiftUI
import Foundation

struct QuotationView: View {
    @Environment(DataStore.self) var store
    @AppStorage(UserPreferenceKeys.companyName) var companyName = ""
    @AppStorage(UserPreferenceKeys.companyPhone) var companyPhone = ""
    @AppStorage(UserPreferenceKeys.companyAddress) var companyAddress = ""
    @AppStorage(UserPreferenceKeys.quoteValidityDays) var quoteValidityDays = 15
    let focusedQuoteId: UUID?
    @State var searchText = ""
    @State var projectFilter: UUID?
    @State var statusFilter: QuoteStatus?
    @State var activeSheet: QuotationSheetRoute?
    @State var editingId: UUID?
    @State var didOpenFocusedQuote = false

    // 表单字段
    @State var formName = ""
    @State var formUnit = AppLocalization.string("项")
    @State var formPrice = ""
    @State var formQty = ""
    @State var formNotes = ""
    @State var formTax = "0"
    @State var formDiscount = "0"
    @State var formVersionName = "V1"
    @State var formStatus: QuoteStatus = .draft
    @State var formCustomerConfirmedDate: BusinessDateValue = .empty
    @State var formContractAmount = ""
    @State var formProjectId: UUID?
    @State var showQuoteDeleteConfirm = false
    @State var generateProjectId: UUID?
    @State var materialQuotePriceMode: MaterialQuotePriceMode?
    @State var defaultMaterialPrice = ""
    @State var defaultLaborRate = "120"
    @State var generateTax = "0"
    @State var generateDiscount = "0"
    @State var exportPayload: ExportPayload?
    @State var showExporter = false
    @State var quoteCustomerName = ""
    @State var quoteProjectAddress = ""
    @State var quoteSignerName = AppLocalization.string("项目负责人")
    @State var operationNotice: OperationToastNotice?
    @State var contractWriteVersion = ""
    @State var contractWritePlan: QuotationContractWritePlan?
    @State var contractWriteRefreshMessage = ""
    @State var isSavingBusinessQuoteVersion = false
    @State var businessVersionFilter: QuotationBusinessVersionFilter?
    @State var undoableDeletion = UndoableDeletionCoordinator()

    init(focusedQuoteId: UUID? = nil, initialProjectId: UUID? = nil) {
        self.focusedQuoteId = focusedQuoteId
        _projectFilter = State(initialValue: initialProjectId)
    }

    var body: some View {
        // Register scalar form dependencies before the first sheet presentation.
        // Bindings already read live values; the title and validation must do so too.
        let isEditingQuote = editingId != nil
        let canSaveQuote = canSaveQuoteForm
        let validationMessages = quoteFormValidationMessages
        List {
            QuotationScopeSection(
                projects: store.projects,
                projectFilter: $projectFilter,
                statusChipBinding: statusChipBinding,
                projectQuoteSummaries: projectQuoteSummaries
            )

            if let businessVersionFilter {
                Section(AppLocalization.string("quote_reference_version_scope")) {
                    LabeledContent(AppLocalization.string("quote_business_selection_version"), value: businessVersionFilter.version)
                    if !businessVersionFilterIsValid {
                        Text(AppLocalization.string("quote_reference_version_filter_stale"))
                            .font(.footnote)
                            .foregroundStyle(Color.appWarning)
                    }
                    Button(AppLocalization.string("quote_reference_version_filter_off")) {
                        self.businessVersionFilter = nil
                    }
                    .accessibilityIdentifier("quotation-current-business-version-filter-off")
                }
            }

            if let projectFilter, let project = store.projects.first(where: { $0.id == projectFilter }) {
                businessQuoteSelectionSection(project: project)
            }

            QuotationItemsSection(
                items: filtered,
                projects: store.projects,
                statusColor: statusColor(_:),
                onEdit: openEdit(_:),
                onDelete: { idx in
                    let ids = idx.map { filtered[$0].id }
                    deleteQuotesWithUndo(ids: ids)
                }
            )

            QuotationTotalsSection(summary: filteredReferenceSummary)
        }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索报价名称"))
        .navigationTitle(AppLocalization.string("预结算信息"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                QuotationToolbarMenu(
                    materialItems: store.materialItems,
                    onOpenGenerate: {
                        materialQuotePriceMode = nil
                        defaultMaterialPrice = ""
                        activeSheet = .generate
                    },
                    onOpenExport: {
                        openQuotationExportSheet()
                    },
                    onAppendFromMaterial: { material in
                        appendQuote(from: material)
                    }
                )
                Button { openAdd() } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel(AppLocalization.string("新建报价"))
            }
            if let projectFilter, store.projects.contains(where: { $0.id == projectFilter }) {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalization.string("写入合同")) {
                        openContractWriteSheet()
                    }
                    .accessibilityLabel(AppLocalization.string("选择已确认报价版本写入项目合同金额"))
                    .accessibilityIdentifier("quotation-write-contract")
                }
            }
        }
        .sheet(item: $activeSheet) { route in
            switch route {
            case .edit:
                quoteForm(isEditing: isEditingQuote, canSave: canSaveQuote, validationMessages: validationMessages)
            case .generate:
                generateQuoteForm
            case .export:
                quotationExportForm
            case .contractWrite:
                contractWriteForm
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .pdf,
            defaultFilename: exportPayload?.defaultFilename ?? AppLocalization.string("报价单.pdf")
        ) { result in
            switch result {
            case .success:
                AppHaptics.success()
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    AppHaptics.error()
                }
            }
        }
        .onChange(of: projectFilter) { _, _ in
            businessVersionFilter = nil
        }
        .onAppear(perform: openFocusedQuoteIfNeeded)
        .onDisappear {
            flushPendingQuoteDeletionIfNeeded()
        }
        .operationToast(notice: $operationNotice)
    }

    private func businessQuoteSelectionSection(project: Project) -> some View {
        let metrics = ProjectBusinessQuoteMetrics(project: project, quotes: store.quoteItems)
        return Section(AppLocalization.string("quote_business_selection_title")) {
            LabeledContent(
                AppLocalization.string("quote_business_selection_version"),
                value: metrics.selectedVersion ?? AppLocalization.string("quote_business_selection_none")
            )
            LabeledContent(
                AppLocalization.string("quote_business_selection_amount"),
                value: metrics.amount.map { ReportBuilder.money($0) } ?? AppLocalization.string("quote_business_selection_review")
            )
            Menu(AppLocalization.string("quote_business_selection_choose")) {
                ForEach(metrics.confirmedVersions, id: \.self) { version in
                    Button(version) {
                        saveBusinessQuoteVersion(version, project: project)
                    }
                }
            }
            .disabled(isSavingBusinessQuoteVersion || metrics.confirmedVersions.isEmpty)
            .accessibilityIdentifier("quotation-business-version-picker")
            if project.businessQuoteVersion != nil {
                Button(AppLocalization.string("quote_business_selection_clear")) {
                    saveBusinessQuoteVersion(nil, project: project)
                }
                .disabled(isSavingBusinessQuoteVersion)
                .accessibilityIdentifier("quotation-business-version-clear")
            }
            Toggle(AppLocalization.string("quote_reference_current_version_only"), isOn: Binding(
                get: { businessVersionFilter != nil },
                set: { enabled in
                    if enabled, metrics.state == .ready, let version = metrics.selectedVersion {
                        businessVersionFilter = QuotationBusinessVersionFilter(projectID: project.id, version: version)
                    } else {
                        businessVersionFilter = nil
                    }
                }
            ))
            .disabled(businessVersionFilter == nil && metrics.state != .ready)
            .accessibilityIdentifier("quotation-current-business-version-only")
            Text(AppLocalization.string("quote_business_selection_rule"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
