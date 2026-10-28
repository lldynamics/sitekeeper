import SwiftUI

/// Edits the parent's draft; the parent persists the record with its normal save action.
struct SiteTodoReviewSection: View {
    @Binding var record: SiteTodo

    var body: some View {
        Section {
            Toggle(AppLocalization.string("启用整改复验"), isOn: Binding(
                get: { record.review != nil },
                set: { enabled in
                    if enabled { record.enableReview() } else { record.disableReviewIfUnused() }
                }
            ))
            .disabled(record.review.map { !$0.canDisable } ?? false)
            .accessibilityIdentifier("todo.review.enabled")

            if let review = record.review {
                LabeledContent(AppLocalization.string("复验状态"), value: review.status.displayName)
                TextField(AppLocalization.string("复验人"), text: Binding(
                    get: { record.review?.reviewer ?? "" },
                    set: { record.review?.reviewer = $0 }
                ), axis: .vertical)
                .lineLimit(1...3)
                .disabled(review.status == .closed)
                .accessibilityIdentifier("todo.review.reviewer")

                switch review.status {
                case .rectifying:
                    Button(AppLocalization.string("提交复验")) { record.requestCompletion() }
                        .accessibilityIdentifier("todo.review.submit")
                case .awaitingReview:
                    TextField(AppLocalization.string("本次复验备注"), text: Binding(
                        get: { record.review?.pendingNote ?? "" },
                        set: { record.review?.pendingNote = $0 }
                    ), axis: .vertical)
                        .lineLimit(2...6)
                    Button(AppLocalization.string("复验通过并关闭")) { decide(.passed) }
                        .disabled(review.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("todo.review.pass")
                    Button(AppLocalization.string("退回整改")) { decide(.returned) }
                        .disabled(review.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("todo.review.return")
                    Button(AppLocalization.string("撤回复验，继续整改")) { record.reopenForWork() }
                case .closed:
                    Button(AppLocalization.string("重新打开整改")) { record.reopenForWork() }
                        .accessibilityIdentifier("todo.review.reopen")
                }

                if !review.history.isEmpty {
                    Text(AppLocalization.string("复验历史")).font(.headline)
                    ForEach(review.history) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.outcome.displayName).font(.subheadline.weight(.semibold))
                            Text("\(entry.reviewer) · \(Formatters.displayDateText(entry.reviewedAt))")
                                .font(.caption).foregroundStyle(.secondary)
                            if !entry.note.isEmpty { Text(entry.note).font(.subheadline) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            Text(AppLocalization.string("整改复验"))
        } footer: {
            Text(AppLocalization.string(record.review == nil
                ? "可选启用复验；普通待办仍可直接完成。"
                : "提交复验后仍为未完成，通过复验才会关闭。操作随本页保存；已有复验历史不能关闭复验，重新打开会保留历史。"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func decide(_ outcome: SiteTodoReview.Record.Outcome) {
        let reviewer = record.review?.reviewer ?? ""
        let note = record.review?.pendingNote ?? ""
        record.recordReview(outcome: outcome, reviewer: reviewer, note: note)
    }
}
