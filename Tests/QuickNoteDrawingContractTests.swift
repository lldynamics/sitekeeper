import Foundation
import Testing

struct QuickNoteDrawingContractTests {
    @Test func compactComposerKeepsDrawingReachable() throws {
        let source = try Self.sourceText("Sources/Features/QuickNotes/QuickNoteMediaPicker.swift")

        #expect(source.contains("compactToolLabel(AppLocalization.string(\"quick_note_media_tool_drawing\"), systemImage: \"pencil.and.outline\")"))
        #expect(source.contains("compactDrawingButton"))
        #expect(source.contains("compactMoreMenu(includesAttachmentActions: true)"))
        #expect(source.contains(".accessibilityIdentifier(\"quick-note-add-drawing\")"))
    }

    @Test func drawingProtectsUnsavedContentAndResetsPhotoSelection() throws {
        let source = try Self.sourceText("Sources/Features/QuickNotes/QuickNoteDrawingSheet.swift")

        #expect(source.contains("showDiscardConfirmation = true"))
        #expect(source.contains("showClearConfirmation = true"))
        #expect(source.contains("selectedBackgroundItem = nil"))
        #expect(source.contains("backgroundLoadTask?.cancel()"))
    }

    private static func sourceText(_ relativePath: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        while root.path != "/" {
            let projectFile = root.appendingPathComponent("project.yml")
            if FileManager.default.fileExists(atPath: projectFile.path) {
                return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            }
            root.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
