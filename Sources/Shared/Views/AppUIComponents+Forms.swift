import SwiftUI
import UIKit

struct AppBusinessFormSheet<Content: View>: View {
    let title: String
    var cancelTitle: String? = String(localized: "取消")
    var primaryActionTitle: String? = String(localized: "保存")
    var primaryActionRole: ButtonRole?
    var isPrimaryActionDisabled = false
    let onCancel: (() -> Void)?
    let onPrimaryAction: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        cancelTitle: String? = String(localized: "取消"),
        primaryActionTitle: String? = String(localized: "保存"),
        primaryActionRole: ButtonRole? = nil,
        isPrimaryActionDisabled: Bool = false,
        onCancel: (() -> Void)? = nil,
        onPrimaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionRole = primaryActionRole
        self.isPrimaryActionDisabled = isPrimaryActionDisabled
        self.onCancel = onCancel
        self.onPrimaryAction = onPrimaryAction
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let cancelTitle, let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle, action: onCancel)
                    }
                }
                if let primaryActionTitle, let onPrimaryAction {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(primaryActionTitle, role: primaryActionRole, action: onPrimaryAction)
                            .disabled(isPrimaryActionDisabled)
                    }
                }
            }
        }
    }
}

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

struct AppPreparedFileExporterSheet: View {
    let fileURL: URL?
    var preparingMessage: String = String(localized: "正在准备导出文件...")
    let onCompletion: (Result<URL, Error>) -> Void

    var body: some View {
        if let fileURL {
            FileURLDocumentExporter(fileURL: fileURL, onCompletion: onCompletion)
        } else {
            ProgressView(preparingMessage)
                .padding()
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

struct AdaptiveListDetailLayout<Compact: View, Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var forceSplit: Bool? = nil
    var visibility: NavigationSplitViewVisibility = .all
    @ViewBuilder let compact: () -> Compact
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    init(
        forceSplit: Bool? = nil,
        visibility: NavigationSplitViewVisibility = .all,
        @ViewBuilder compact: @escaping () -> Compact,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.forceSplit = forceSplit
        self.visibility = visibility
        self.compact = compact
        self.sidebar = sidebar
        self.detail = detail
    }

    private var usesSplitLayout: Bool {
        if let forceSplit {
            return forceSplit
        }
        return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                NavigationSplitView(columnVisibility: .constant(visibility)) {
                    sidebar()
                } detail: {
                    detail()
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                compact()
            }
        }
    }
}

struct KeyboardNavigationToolbar<Field: Hashable>: ToolbarContent {
    let focusedField: FocusState<Field?>.Binding
    let fields: [Field]

    private var currentIndex: Int? {
        guard let value = focusedField.wrappedValue else { return nil }
        return fields.firstIndex(of: value)
    }

    private var canMovePrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    private var canMoveNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex < fields.count - 1
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button(String(localized: "上一个")) {
                move(delta: -1)
            }
            .disabled(!canMovePrevious)

            Button(String(localized: "下一个")) {
                move(delta: 1)
            }
            .disabled(!canMoveNext)

            Spacer()

            Button(String(localized: "完成")) {
                focusedField.wrappedValue = nil
            }
        }
    }

    private func move(delta: Int) {
        guard let currentIndex else { return }
        let next = currentIndex + delta
        guard fields.indices.contains(next) else { return }
        focusedField.wrappedValue = fields[next]
    }
}

struct KeyboardDismissToolbar: ToolbarContent {
    let onDone: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(String(localized: "完成"), action: onDone)
        }
    }
}

@MainActor
enum AppKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
