import SwiftUI
import MessageUI

struct FeedbackView: View {
    @State private var feedbackText: String = ""
    @State private var contactEmail: String = ""
    @State private var showActionSheet = false
    @State private var showMail = false
    @State private var copiedToast = false

    private var feedbackContent: String {
        """
        意见反馈

        联系方式: \(contactEmail.isEmpty ? "未填写" : contactEmail)

        \(feedbackText)
        """
    }

    var body: some View {
        Form {
            Section("反馈内容") {
                TextField("您的邮箱（可选）", text: $contactEmail)
                    .keyboardType(.emailAddress)
                TextEditor(text: $feedbackText)
                    .frame(minHeight: 150)
            }

            Section {
                Button {
                    showActionSheet = true
                } label: {
                    Label("发送反馈", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("收件人：\(AppContact.supportEmail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("意见反馈")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("发送方式", isPresented: $showActionSheet, titleVisibility: .visible) {
            if MFMailComposeViewController.canSendMail() {
                Button("系统邮件") { showMail = true }
            }
            Button("复制反馈内容") {
                ClipboardService.copy(feedbackContent)
                copiedToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToast = false }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择一种方式发送反馈")
        }
        .sheet(isPresented: $showMail) {
            MailView(
                subject: "\(AppBrand.displayName) 意见反馈",
                recipients: [AppContact.supportEmail],
                body: feedbackContent
            ) {
                feedbackText = ""
                contactEmail = ""
            }
        }
        .overlay(alignment: .bottom) {
            if copiedToast {
                Text("已复制到剪贴板")
                    .font(.caption).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring, value: copiedToast)
            }
        }
    }
}

// MARK: - Mail View

struct MailView: UIViewControllerRepresentable {
    let subject: String
    let recipients: [String]
    let body: String
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setToRecipients(recipients)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { self.onDismiss() }
        }
    }
}
