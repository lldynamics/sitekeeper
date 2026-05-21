import SwiftUI

struct AppBusinessEditForm<Content: View>: View {
    let title: String
    var cancelTitle: String = String(localized: "取消")
    var primaryActionTitle: String = String(localized: "保存")
    var isPrimaryActionDisabled = false
    let onCancel: () -> Void
    let onPrimaryAction: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        cancelTitle: String = String(localized: "取消"),
        primaryActionTitle: String = String(localized: "保存"),
        isPrimaryActionDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onPrimaryAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.primaryActionTitle = primaryActionTitle
        self.isPrimaryActionDisabled = isPrimaryActionDisabled
        self.onCancel = onCancel
        self.onPrimaryAction = onPrimaryAction
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle, action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(primaryActionTitle, action: onPrimaryAction)
                            .disabled(isPrimaryActionDisabled)
                    }
                }
        }
    }
}

struct AppBusinessFormValidationSection: View {
    let messages: [String]

    var body: some View {
        if !messages.isEmpty {
            Section(String(localized: "表单问题")) {
                ForEach(messages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                }
            }
        }
    }
}

struct AppBusinessFormDestructiveActionSection: View {
    let title: String
    var systemImage: String = "trash"
    let action: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: action) {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

extension View {
    func appListPrimaryTextLayout(lines: Int = 2) -> some View {
        lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }

    func appListSecondaryTextLayout(lines: Int = 2) -> some View {
        lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}
