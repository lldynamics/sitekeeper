import Observation
import SwiftUI
import Testing
import UIKit
@testable import sitekeeper

@MainActor
@Suite(.serialized)
struct ProjectEditContinuityTests {
    @Test func recreatingTheEditorRetainsDraftAndKeyboardFocus() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        let original = Project(name: "Retained project", location: "Existing location")
        let draft = ProjectEditDraft(project: original)
        draft.focusedField = .name
        let identity = EditorRecreationIdentity()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: EditorRecreationHarness(draft: draft, identity: identity).environment(store))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }

        try await waitUntil { input(in: host.view, text: original.name)?.isFirstResponder == true }
        let before = try #require(input(in: host.view, text: original.name))
        before.selectedTextRange = before.textRange(from: before.endOfDocument, to: before.endOfDocument)
        before.insertText(" draft")
        try await waitUntil { draft.name == "Retained project draft" }

        // Recreate just the presented editor, as native Duo adaptation does.
        // The coordinator's draft and remembered input target live outside that boundary.
        identity.value = UUID()
        try await waitUntil {
            guard let after = input(in: host.view, text: "Retained project draft") else { return false }
            return after !== before && after.isFirstResponder
        }
        let after = try #require(input(in: host.view, text: "Retained project draft"))
        after.insertText(" retained")
        try await waitUntil { draft.name == "Retained project draft retained" }
        #expect(original.name == "Retained project")
        #expect(draft.updatedProject(basedOn: original).name == "Retained project draft retained")
        #expect(draft.updatedProject(basedOn: original).id == original.id)
        #expect(draft.updatedProject(basedOn: original).location == original.location)

        after.resignFirstResponder()
        try await waitUntil { draft.focusedField == nil }
        identity.value = UUID()
        try await waitUntil {
            guard let recreated = input(in: host.view, text: draft.name) else { return false }
            return recreated !== after
        }
        #expect(input(in: host.view, text: draft.name)?.isFirstResponder == false)
    }

    @Test func savingRetainedDraftPreservesConcurrentProjectTotalsAndStatus() {
        let original = Project(name: "Original", location: "Site")
        let draft = ProjectEditDraft(project: original)
        draft.name = "Edited"
        var current = original
        current.status = .paused
        current.paidAmount = NumericInputSupport.money("120")
        current.materialCost = NumericInputSupport.money("45")
        current.laborCost = NumericInputSupport.money("90")

        let updated = draft.updatedProject(basedOn: current)
        #expect(updated.name == "Edited")
        #expect(updated.status == .paused)
        #expect(updated.paidAmount == current.paidAmount)
        #expect(updated.materialCost == current.materialCost)
        #expect(updated.laborCost == current.laborCost)
        #expect(original.name == "Original")
    }

    private func input(in view: UIView, text: String) -> UITextField? {
        if let field = view as? UITextField, field.text == text { return field }
        return view.subviews.lazy.compactMap { input(in: $0, text: text) }.first
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<60 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(condition(), "Editor state or keyboard focus did not settle.")
    }
}

@MainActor
@Observable
private final class EditorRecreationIdentity {
    var value = UUID()
}

private struct EditorRecreationHarness: View {
    let draft: ProjectEditDraft
    let identity: EditorRecreationIdentity

    var body: some View {
        VStack {
            ProjectEditSheet(draft: draft) { _ in }
                .id(identity.value)
        }
    }
}
