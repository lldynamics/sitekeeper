import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    func recordUndoSnapshot() {
        guard overlayUndoStack.last != snapshot else { return }
        overlayUndoStack.append(snapshot)
        if overlayUndoStack.count > overlayUndoLimit {
            overlayUndoStack.removeFirst(overlayUndoStack.count - overlayUndoLimit)
        }
        overlayRedoStack.removeAll()
    }

    private func appendUndoSnapshotForHistory(_ value: CADOverlaySnapshot) {
        guard overlayUndoStack.last != value else { return }
        overlayUndoStack.append(value)
        if overlayUndoStack.count > overlayUndoLimit {
            overlayUndoStack.removeFirst(overlayUndoStack.count - overlayUndoLimit)
        }
    }

    private func appendRedoSnapshotForHistory(_ value: CADOverlaySnapshot) {
        guard overlayRedoStack.last != value else { return }
        overlayRedoStack.append(value)
        if overlayRedoStack.count > overlayUndoLimit {
            overlayRedoStack.removeFirst(overlayRedoStack.count - overlayUndoLimit)
        }
    }

    private func restoreOverlaySnapshotFromHistory(_ value: CADOverlaySnapshot) {
        snapshot = value
        applyOverlayDisplayPreferences(from: value)
        selectedStrokeID = nil
        quantityHighlightTarget = nil
        clearInProgress()
    }

    func undoLastOverlayChange() {
        guard let previous = overlayUndoStack.popLast() else { return }
        appendRedoSnapshotForHistory(snapshot)
        restoreOverlaySnapshotFromHistory(previous)
        AppHaptics.impact(.light, intensity: 0.55)
    }

    func redoOverlayChange() {
        guard let next = overlayRedoStack.popLast() else { return }
        appendUndoSnapshotForHistory(snapshot)
        restoreOverlaySnapshotFromHistory(next)
        AppHaptics.impact(.light, intensity: 0.55)
    }
}
