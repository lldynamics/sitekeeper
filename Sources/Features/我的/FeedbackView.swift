import SwiftUI
import MessageUI

struct FeedbackView: View {
    @State private var feedbackText: String = ""
    @State private var contactEmail: String = ""
    @State private var showActionSheet = false
    @State private var showMail = false
    @State private var operationMessage: String?
    @State private var mailFeedbackMessage = ""

    private var feedbackContent: String {
        let contact = contactEmail.isEmpty ? String(localized: "未填写") : contactEmail
        return [
            String(localized: "意见反馈"),
            "",
            String(format: String(localized: "联系方式：%@"), contact),
            "",
            feedbackText
        ].joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section(String(localized: "反馈内容")) {
                TextField(String(localized: "您的邮箱（可选）"), text: $contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextEditor(text: $feedbackText)
                    .frame(minHeight: 150)
            }

            Section {
                Button {
                    showActionSheet = true
                } label: {
                    Label(String(localized: "发送反馈"), systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(String(format: String(localized: "收件人：%@"), AppContact.supportEmail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "意见反馈"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(String(localized: "发送方式"), isPresented: $showActionSheet, titleVisibility: .visible) {
            if MFMailComposeViewController.canSendMail() {
                Button(String(localized: "系统邮件")) { showMail = true }
            }
            Button(String(localized: "复制反馈内容")) {
                ClipboardService.copy(feedbackContent)
                operationMessage = String(localized: "已复制到剪贴板")
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "选择一种方式发送反馈"))
        }
        .sheet(isPresented: $showMail) {
            MailView(
                subject: String(format: String(localized: "%@ 意见反馈"), AppBrand.displayName),
                recipients: [AppContact.supportEmail],
                body: feedbackContent
            ) { result, error in
                showMail = false
                switch result {
                case .sent:
                    feedbackText = ""
                    contactEmail = ""
                    mailFeedbackMessage = ""
                    operationMessage = String(localized: "反馈邮件已发送")
                case .saved:
                    operationMessage = String(localized: "反馈邮件已存入草稿")
                case .cancelled:
                    operationMessage = String(localized: "已取消发送反馈")
                case .failed:
                    mailFeedbackMessage = error?.localizedDescription
                        ?? String(localized: "系统邮件未能完成发送。")
                @unknown default:
                    mailFeedbackMessage = String(localized: "系统邮件返回了未知状态。")
                }
            }
        }
        .alert(String(localized: "邮件未发送"), isPresented: Binding(
            get: { !mailFeedbackMessage.isEmpty },
            set: { if !$0 { mailFeedbackMessage = "" } }
        )) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: {
            Text(mailFeedbackMessage)
        }
        .operationToast(message: $operationMessage)
    }
}

// MARK: - Mail View

struct MailView: UIViewControllerRepresentable {
    let subject: String
    let recipients: [String]
    let body: String
    let onFinish: (MFMailComposeResult, Error?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setToRecipients(recipients)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, Error?) -> Void
        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { self.onFinish(result, error) }
        }
    }
}
