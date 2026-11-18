import Foundation
import Testing
@testable import sitekeeper

struct QuickNoteSearchTests {
    @MainActor @Test func importedAudioDurationCanBeDisplayedSafely() throws {
        let attachment = QuickNoteAttachment(kind: .audio, fileName: "recording.m4a", durationSeconds: 1e300)
        let encoded = try JSONEncoder().encode(attachment)
        let restored = try JSONDecoder().decode(QuickNoteAttachment.self, from: encoded)
        #expect(restored.durationSeconds == 1e300)
        #expect(restored.displayDurationSeconds == nil)

        for value in [Double.infinity, -Double.infinity, Double.nan, -1, 0, Double(Int.max)] {
            var invalid = attachment
            invalid.durationSeconds = value
            #expect(invalid.displayDurationSeconds == nil)
        }
        var ordinary = attachment
        ordinary.durationSeconds = 12.75
        #expect(ordinary.displayDurationSeconds == 12)
        #expect(QuickNoteAudioPlayer.safeTime(1e300) == 0)
        #expect(QuickNoteAudioPlayer.safeTime(.nan) == 0)
        #expect(QuickNoteAudioPlayer.safeTime(12.75) == 12.75)
    }

    @Test @MainActor func earlierResultCannotOverwriteNewerQuery() async {
        let gate = SearchTestGate()
        let oldNote = QuickNote(content: "old")
        let newNote = QuickNote(content: "new")
        let model = QuickNoteSearchModel { notes, _, keyword in
            if keyword == "old" { await gate.suspend() }
            return notes
        }
        let earlier = Task { await model.refresh(notes: [oldNote], projects: [], keyword: "old", debounce: .zero) }
        await gate.waitUntilStarted()
        await model.refresh(notes: [newNote], projects: [], keyword: "new", debounce: .zero)
        await gate.release()
        await earlier.value
        #expect(model.notes.map(\.id) == [newNote.id])
    }

    @Test @MainActor func cancelledSearchDoesNotPublishAndNewDataRefreshes() async {
        let gate = SearchTestGate()
        let note = QuickNote(content: "record")
        let model = QuickNoteSearchModel { notes, _, _ in
            await gate.suspend()
            return notes
        }
        let request = Task { await model.refresh(notes: [note], projects: [], keyword: "", debounce: .zero) }
        await gate.waitUntilStarted()
        request.cancel()
        await gate.release()
        await request.value
        #expect(model.notes.isEmpty)

        let liveModel = QuickNoteSearchModel()
        var project = Project(name: "old", location: "", status: .active)
        let linkedNote = QuickNote(content: "record", projectId: project.id)
        await liveModel.refresh(notes: [linkedNote], projects: [project], keyword: "new", debounce: .zero)
        #expect(liveModel.notes.isEmpty)
        project.name = "new"
        await liveModel.refresh(notes: [linkedNote], projects: [project], keyword: "new", debounce: .zero)
        #expect(liveModel.notes.map(\.id) == [linkedNote.id])
        await liveModel.refresh(notes: [], projects: [project], keyword: "new", debounce: .zero)
        #expect(liveModel.notes.isEmpty)
    }

    @Test func matchesContentAndAssociatedProjectWithWhitespaceAndStableOrdering() {
        let project = Project(name: "北区工程", location: "", status: .active)
        let older = QuickNote(content: "防水验收", projectId: project.id, createdAt: BusinessDateValue(legacyText: "2026-09-01"))
        let newer = QuickNote(content: "现场记录", projectId: project.id, createdAt: BusinessDateValue(legacyText: "2026-09-09"))
        let unassigned = QuickNote(content: "防水验收", createdAt: BusinessDateValue(legacyText: "2026-09-08"))
        let notes = [older, newer, unassigned]
        #expect(QuickNoteSearch.filter(notes, projects: [project], keyword: " 北区 ").map(\.id) == [newer.id, older.id])
        #expect(QuickNoteSearch.filter(notes, projects: [project], keyword: "防水").map(\.id) == [unassigned.id, older.id])
        #expect(QuickNoteSearch.filter(notes, projects: [project], keyword: "  ").map(\.id) == [newer.id, unassigned.id, older.id])
        #expect(QuickNoteSearch.filter(notes, projects: [], keyword: "北区").isEmpty)
    }
}
