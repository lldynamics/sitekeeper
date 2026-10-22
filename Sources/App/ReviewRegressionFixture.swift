#if DEBUG
import UIKit

/// Deterministic records for end-to-end regression tests. Release builds contain
/// neither this fixture nor its launch-environment entry point.
@MainActor
enum ReviewRegressionFixture {
    static func prepareIfRequested(store: DataStore) async {
        guard ProcessInfo.processInfo.environment["UITEST_REVIEW_REGRESSION_FIXTURE"] == "1" else { return }
        await store.awaitInitialLoad()
        guard store.loadState == .ready, !store.projects.contains(where: { $0.name == "Review Site A" }) else { return }
        do {
            let project = Project(name: "Review Site A", location: "North", status: .active, contractAmount: "100", paidAmount: "150")
            let other = Project(name: "Review Site B", location: "South", status: .active, contractAmount: "100")
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).pdfData { context in
                context.beginPage()
                ("Review Acceptance Page One" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
                context.beginPage()
                ("Review Acceptance Page Two" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
            let fileName = try ProjectDocumentStorage.savePDFOrThrow(data: pdf, projectId: project.id)
            store.appendProject(project)
            store.appendProject(other)
            store.appendProjectDocument(ProjectDocument(projectId: project.id, title: "Review Acceptance", fileName: fileName))
            let attachmentName = try QuickNoteAttachmentStorage.saveDataOrThrow(pdf, fileName: QuickNoteAttachmentStorage.makeFileName(extension: "pdf"))
            let brokenName = try QuickNoteAttachmentStorage.saveDataOrThrow(Data("Not a PDF".utf8), fileName: QuickNoteAttachmentStorage.makeFileName(extension: "pdf"))
            store.appendQuickNote(QuickNote(content: "Review Preview Attachments", projectId: project.id, attachments: [
                QuickNoteAttachment(kind: .file, fileName: attachmentName, originalName: "Review Preview.pdf"),
                QuickNoteAttachment(kind: .file, fileName: brokenName, originalName: "Review Broken.pdf")
            ]))
            store.appendUserMaterial(UserMaterial(name: "Review Copper", specification: "4 mm", unit: "m", category: "Electrical"))
            store.appendMaterialPriceEntry(MaterialPriceEntry(name: "Review Copper", specification: "4 mm", unit: "m", referencePrice: "500"))
            store.appendMaterialItem(MaterialItem(name: "Review Copper", quantity: "1", unit: "m", unitPrice: "500", projectId: project.id))
            store.scheduleSave()
        } catch {
            assertionFailure("Review regression fixture failed: \(error)")
        }
    }
}
#endif
