import SwiftUI

struct CADNoteEditorContext {
    let noteDraft: Binding<String>
    let canSave: Bool
    let cancel: () -> Void
    let save: () -> Void
}

struct CADNoteEditorView: View {
    let context: CADNoteEditorContext

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "批注内容")) {
                    TextField(String(localized: "输入批注说明"), text: context.noteDraft, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(String(localized: "新增批注"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        context.cancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        context.save()
                    }
                    .disabled(!context.canSave)
                }
            }
        }
    }
}

extension CADPreviewContainer {
    var noteEditorSheet: some View {
        CADNoteEditorView(context: noteEditorContext)
    }

    private var noteEditorContext: CADNoteEditorContext {
        CADNoteEditorContext(
            noteDraft: $noteDraft,
            canSave: canSaveNoteDraft,
            cancel: {
                cancelNoteEditing()
            },
            save: {
                saveNoteEditing()
            }
        )
    }

    private var canSaveNoteDraft: Bool {
        !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasNativeDrawingCoordinateSpace
    }

    private func cancelNoteEditing() {
        showNoteSheet = false
        pendingNotePoint = nil
    }

    private func saveNoteEditing() {
        guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false) else {
            cancelNoteEditing()
            return
        }
        guard let point = pendingNotePoint else {
            showNoteSheet = false
            return
        }
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recordUndoSnapshot()
        let note = CADTextNote(
            text: text,
            point: CADPoint(point),
            layoutId: SiteKeeperCADKernel.CADLayout.modelSpace.id,
            worldPoint: CADPoint(point),
            createdAt: Formatters.now(),
            colorHex: selectedNoteOverlayColorHex()
        )
        hiddenOverlayColorHexes.remove(noteColorHex(note))
        snapshot.notes.append(note)
        AppHaptics.success()
        showNoteSheet = false
        pendingNotePoint = nil
    }
}
