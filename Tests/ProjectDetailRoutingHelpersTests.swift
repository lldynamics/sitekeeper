import Foundation
import Testing
@testable import sitekeeper

struct ProjectDetailRoutingHelpersTests {
    @Test func onAppearRouterSetsAutoOpenFlagsOnlyWhenNotYetOpened() {
        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: true,
            didAutoOpenFinancialAdd: false,
            autoOpenDocumentScanSetup: true,
            didAutoOpenDocumentScanSetup: false,
            autoOpenDeliveryGuide: false,
            didAutoOpenDeliveryGuide: false,
            focus: nil,
            didOpenFocusedItem: false,
            financialRecords: [],
            documents: [],
            contacts: []
        )

        #expect(routing.shouldOpenFinancialAdd)
        #expect(routing.shouldOpenDocumentScanSetup)
        #expect(!routing.shouldConsumeFocusRequest)
        #expect(routing.focusedItem == nil)
    }

    @Test func onAppearRouterDoesNotAutoOpenAgainWhenAlreadyOpened() {
        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: true,
            didAutoOpenFinancialAdd: true,
            autoOpenDocumentScanSetup: true,
            didAutoOpenDocumentScanSetup: true,
            autoOpenDeliveryGuide: false,
            didAutoOpenDeliveryGuide: false,
            focus: nil,
            didOpenFocusedItem: false,
            financialRecords: [],
            documents: [],
            contacts: []
        )

        #expect(!routing.shouldOpenFinancialAdd)
        #expect(!routing.shouldOpenDocumentScanSetup)
        #expect(!routing.shouldConsumeFocusRequest)
        #expect(routing.focusedItem == nil)
    }

    @Test func onAppearRouterResolvesFocusedFinancialRecord() {
        let projectId = UUID()
        let record = ProjectFinancialRecord(id: UUID(), projectId: projectId, amount: "100")

        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: false,
            didAutoOpenFinancialAdd: false,
            autoOpenDocumentScanSetup: false,
            didAutoOpenDocumentScanSetup: false,
            autoOpenDeliveryGuide: false,
            didAutoOpenDeliveryGuide: false,
            focus: .financialRecord(record.id),
            didOpenFocusedItem: false,
            financialRecords: [record],
            documents: [],
            contacts: []
        )

        #expect(routing.shouldConsumeFocusRequest)
        guard case .financialRecord(let resolved)? = routing.focusedItem else {
            Issue.record("应解析出财务记录焦点")
            return
        }
        #expect(resolved.id == record.id)
        #expect(routing.focusedItem?.mode == .finance)
    }

    @Test func onAppearRouterConsumesFocusEvenWhenTargetMissing() {
        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: false,
            didAutoOpenFinancialAdd: false,
            autoOpenDocumentScanSetup: false,
            didAutoOpenDocumentScanSetup: false,
            autoOpenDeliveryGuide: false,
            didAutoOpenDeliveryGuide: false,
            focus: .document(UUID()),
            didOpenFocusedItem: false,
            financialRecords: [],
            documents: [],
            contacts: []
        )

        #expect(routing.shouldConsumeFocusRequest)
        #expect(routing.focusedItem == nil)
    }

    @Test func onAppearRouterSkipsFocusWhenAlreadyHandled() {
        let projectId = UUID()
        let document = ProjectDocument(projectId: projectId, title: "合同", fileName: "contract.pdf")

        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: false,
            didAutoOpenFinancialAdd: false,
            autoOpenDocumentScanSetup: false,
            didAutoOpenDocumentScanSetup: false,
            autoOpenDeliveryGuide: false,
            didAutoOpenDeliveryGuide: false,
            focus: .document(document.id),
            didOpenFocusedItem: true,
            financialRecords: [],
            documents: [document],
            contacts: []
        )

        #expect(!routing.shouldConsumeFocusRequest)
        #expect(routing.focusedItem == nil)
    }

    @Test func focusedItemApplierRoutesFinancialRecordOnly() {
        let projectId = UUID()
        let record = ProjectFinancialRecord(id: UUID(), projectId: projectId, amount: "200")
        var selectedFinancialRecord: ProjectFinancialRecord?
        var selectedDocument: ProjectDocument?
        var selectedContact: ProjectContact?

        ProjectDetailFocusedItemApplier.apply(
            .financialRecord(record),
            setFinancialRecord: { selectedFinancialRecord = $0 },
            setDocument: { selectedDocument = $0 },
            setContact: { selectedContact = $0 }
        )

        #expect(selectedFinancialRecord?.id == record.id)
        #expect(selectedDocument == nil)
        #expect(selectedContact == nil)
    }

    @Test func focusedItemApplierRoutesDocumentOnly() {
        let projectId = UUID()
        let document = ProjectDocument(projectId: projectId, title: "资料", fileName: "doc.pdf")
        var selectedFinancialRecord: ProjectFinancialRecord?
        var selectedDocument: ProjectDocument?
        var selectedContact: ProjectContact?

        ProjectDetailFocusedItemApplier.apply(
            .document(document),
            setFinancialRecord: { selectedFinancialRecord = $0 },
            setDocument: { selectedDocument = $0 },
            setContact: { selectedContact = $0 }
        )

        #expect(selectedFinancialRecord == nil)
        #expect(selectedDocument?.id == document.id)
        #expect(selectedContact == nil)
        #expect(ProjectDetailFocusedItem.document(document).mode == .assets)
    }

    @Test func focusedItemApplierRoutesContactOnly() {
        let projectId = UUID()
        let contact = ProjectContact(projectId: projectId, name: "张三")
        var selectedFinancialRecord: ProjectFinancialRecord?
        var selectedDocument: ProjectDocument?
        var selectedContact: ProjectContact?

        ProjectDetailFocusedItemApplier.apply(
            .contact(contact),
            setFinancialRecord: { selectedFinancialRecord = $0 },
            setDocument: { selectedDocument = $0 },
            setContact: { selectedContact = $0 }
        )

        #expect(selectedFinancialRecord == nil)
        #expect(selectedDocument == nil)
        #expect(selectedContact?.id == contact.id)
        #expect(ProjectDetailFocusedItem.contact(contact).mode == .assets)
    }
}
