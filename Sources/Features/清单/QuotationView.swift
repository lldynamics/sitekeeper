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
    @State var formUnit = String(localized: "项")
    @State var formPrice = ""
    @State var formQty = ""
    @State var formNotes = ""
    @State var formTax = "0"
    @State var formDiscount = "0"
    @State var formVersionName = "V1"
    @State var formStatus: QuoteStatus = .draft
    @State var formCustomerConfirmedDate = ""
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
    @State var quoteSignerName = String(localized: "项目负责人")
    @State var operationNotice: OperationToastNotice?
    @State var contractWriteVersion = ""
    @State var contractWritePlan: QuotationContractWritePlan?
    @State var contractWriteRefreshMessage = ""
    @State var undoableDeletion = UndoableDeletionCoordinator()

    init(focusedQuoteId: UUID? = nil) {
        self.focusedQuoteId = focusedQuoteId
    }

    var body: some View {
        List {
            QuotationScopeSection(
                projects: store.projects,
                projectFilter: $projectFilter,
                statusChipBinding: statusChipBinding,
                projectQuoteSummaries: projectQuoteSummaries
            )

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

            QuotationTotalsSection(
                subtotalBeforeValue: subtotalBeforeValue,
                totalTaxValue: totalTaxValue,
                totalDiscountValue: totalDiscountValue,
                grandTotalValue: grandTotalValue
            )
        }
        .searchable(text: $searchText, prompt: String(localized: "搜索报价名称"))
        .navigationTitle(String(localized: "预结算信息"))
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
                    .accessibilityLabel(String(localized: "新建报价"))
            }
            if let projectFilter, store.projects.contains(where: { $0.id == projectFilter }) {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "写入合同")) {
                        openContractWriteSheet()
                    }
                    .accessibilityLabel(String(localized: "选择已确认报价版本写入项目合同金额"))
                    .accessibilityIdentifier("quotation-write-contract")
                }
            }
        }
        .sheet(item: $activeSheet) { route in
            switch route {
            case .edit:
                quoteForm
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
            defaultFilename: exportPayload?.defaultFilename ?? String(localized: "报价单.pdf")
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
        .onAppear(perform: openFocusedQuoteIfNeeded)
        .onDisappear {
            flushPendingQuoteDeletionIfNeeded()
        }
        .operationToast(notice: $operationNotice)
    }
}
