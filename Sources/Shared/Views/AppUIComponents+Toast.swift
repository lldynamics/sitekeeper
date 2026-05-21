import SwiftUI

struct OperationToastNotice: Identifiable {
    let id = UUID()
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var autoDismissDuration: Duration = .milliseconds(1_600)

    static func info(_ message: String) -> OperationToastNotice {
        OperationToastNotice(message: message)
    }
}

private struct OperationToastBanner: View {
    let notice: OperationToastNotice
    var actionOverride: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(notice.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let actionTitle = notice.actionTitle {
                Button(actionTitle) {
                    actionOverride?() ?? notice.action?()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.appWarning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.black.opacity(0.78))
        )
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct UndoableDeletionAuditContext {
    let summary: String
    var detail: String = ""
    var source: String = ""
}

extension UndoableDeletionAuditContext {
    init(_ context: DataStoreDeletionAuditContext) {
        self.init(summary: context.summary, detail: context.detail, source: context.source)
    }
}

@MainActor
final class UndoableDeletionCoordinator {
    private var pendingCommitTask: Task<Void, Never>?
    private var pendingCommit: (() -> Void)?
    private let delay: Duration

    init(delay: Duration = .seconds(4)) {
        self.delay = delay
    }

    func queue(
        notice: Binding<OperationToastNotice?>,
        message: String,
        undoMessage: String = String(localized: "已撤销删除"),
        actionTitle: String = String(localized: "撤销"),
        commit: @escaping () -> Void,
        undo: @escaping () -> Void,
        audit: UndoableDeletionAuditContext? = nil
    ) {
        flushPendingCommit()

        if let audit {
            OperationAuditLog.record(
                action: .delete,
                outcome: .started,
                summary: audit.summary,
                detail: audit.detail,
                source: audit.source
            )
        }

        pendingCommit = {
            commit()
            if let audit {
                OperationAuditLog.record(
                    action: .delete,
                    outcome: .succeeded,
                    summary: audit.summary,
                    detail: audit.detail,
                    source: audit.source
                )
            }
        }

        let delay = delay
        pendingCommitTask = Task { @MainActor [weak self] in
            guard await DebouncedTask.wait(for: delay) else { return }
            self?.commitPending()
        }

        notice.wrappedValue = OperationToastNotice(
            message: message,
            actionTitle: actionTitle,
            action: { [weak self] in
                self?.cancelPendingCommit()
                undo()
                if let audit {
                    OperationAuditLog.record(
                        action: .delete,
                        outcome: .cancelled,
                        summary: audit.summary,
                        detail: audit.detail,
                        source: audit.source
                    )
                }
                notice.wrappedValue = .info(undoMessage)
            },
            autoDismissDuration: delay
        )
    }

    func flushPendingCommit() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        let commit = pendingCommit
        pendingCommit = nil
        commit?()
    }

    func cancelPendingCommit() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        pendingCommit = nil
    }

    private func commitPending() {
        let commit = pendingCommit
        pendingCommit = nil
        pendingCommitTask = nil
        commit?()
    }

    static func restoringItems<Item: Identifiable>(
        snapshot: [Item],
        current: [Item],
        deletedIDs: Set<Item.ID>
    ) -> [Item] where Item.ID: Hashable {
        let snapshotIDs = Set(snapshot.map(\.id))
        var currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for item in snapshot where deletedIDs.contains(item.id) {
            currentByID[item.id] = item
        }
        let newItems = current.filter { !snapshotIDs.contains($0.id) }
        let restoredSnapshotItems = snapshot.compactMap { currentByID[$0.id] }
        return newItems + restoredSnapshotItems
    }
}

struct OperationToastNoticeModifier: ViewModifier {
    @Binding var notice: OperationToastNotice?
    var onDismiss: (() -> Void)? = nil
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let notice {
                    OperationToastBanner(
                        notice: notice,
                        actionOverride: {
                            hideTask?.cancel()
                            withAnimation(.easeOut(duration: 0.2)) {
                                self.notice = nil
                            }
                            onDismiss?()
                            notice.action?()
                        }
                    )
                }
            }
            .onChange(of: notice?.id) { _, newID in
                hideTask?.cancel()
                guard newID != nil else {
                    onDismiss?()
                    return
                }
                AppHaptics.success()
                let duration = notice?.autoDismissDuration ?? .milliseconds(1_600)
                hideTask = Task { @MainActor in
                    guard await DebouncedTask.wait(for: duration) else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        notice = nil
                    }
                    onDismiss?()
                }
            }
            .animation(.easeOut(duration: 0.2), value: notice?.id)
    }
}

private struct OperationToastMessageBridgeModifier: ViewModifier {
    @Binding var message: String?
    @State private var notice: OperationToastNotice?

    func body(content: Content) -> some View {
        content
            .modifier(OperationToastNoticeModifier(
                notice: $notice,
                onDismiss: {
                    message = nil
                }
            ))
            .onChange(of: message) { _, newValue in
                guard let newValue, !newValue.isEmpty else {
                    notice = nil
                    return
                }
                notice = .info(newValue)
            }
            .onAppear {
                if let message, !message.isEmpty {
                    notice = .info(message)
                }
            }
    }
}

extension View {
    func operationToast(message: Binding<String?>) -> some View {
        modifier(OperationToastMessageBridgeModifier(message: message))
    }

    func operationToast(notice: Binding<OperationToastNotice?>) -> some View {
        modifier(OperationToastNoticeModifier(notice: notice))
    }
}
