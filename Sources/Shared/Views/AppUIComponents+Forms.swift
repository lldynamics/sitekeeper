import SwiftUI
import UIKit

struct AppBusinessFormSheet<Content: View>: View {
    let title: String
    var cancelTitle: String? = AppLocalization.string("取消")
    var primaryActionTitle: String? = AppLocalization.string("保存")
    var primaryActionRole: ButtonRole?
    var isPrimaryActionDisabled = false
    let onCancel: (() -> Void)?
    let onPrimaryAction: (() -> Void)?
    @ViewBuilder let content: Content
    private var keyboardBarContent: AnyView?

    init(
        title: String,
        cancelTitle: String? = AppLocalization.string("取消"),
        primaryActionTitle: String? = AppLocalization.string("保存"),
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

    // The bar belongs to the Form's hosting page inside this sheet's NavigationStack.
    func keyboardBar<Bar: View>(@ViewBuilder content: () -> Bar) -> Self {
        var form = self
        form.keyboardBarContent = AnyView(content())
        return form
    }

    @ViewBuilder
    private var formContent: some View {
        let form = Form { content }
        if let keyboardBarContent {
            form.appKeyboardToolbar { keyboardBarContent }
        } else {
            form.appKeyboardToolbar {
                KeyboardDismissToolbar { AppKeyboard.dismiss() }
            }
        }
    }

    var body: some View {
        NavigationStack {
            formContent
                .environment(\.keyboardToolbarCancelAction, cancelTitle.flatMap { title in
                    onCancel.map { KeyboardToolbarCancelAction(title: title, perform: $0) }
                })
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
                                .accessibilityIdentifier("business-form-save")
                        }
                    }
                }
        }
    }
}

struct AppBusinessEditForm<Content: View>: View {
    let title: String
    var cancelTitle: String = AppLocalization.string("取消")
    var primaryActionTitle: String = AppLocalization.string("保存")
    var isPrimaryActionDisabled = false
    let onCancel: () -> Void
    let onPrimaryAction: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        cancelTitle: String = AppLocalization.string("取消"),
        primaryActionTitle: String = AppLocalization.string("保存"),
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
                .environment(\.keyboardToolbarCancelAction,
                             KeyboardToolbarCancelAction(title: cancelTitle, perform: onCancel))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle, action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(primaryActionTitle, action: onPrimaryAction)
                            .disabled(isPrimaryActionDisabled)
                            .accessibilityIdentifier("business-form-save")
                    }
                }
        }
    }
}

struct AppPreparedFileExporterSheet: View {
    let fileURL: URL?
    var preparingMessage: String = AppLocalization.string("正在准备导出文件...")
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
            Section(AppLocalization.string("表单问题")) {
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
        return horizontalSizeClass == .regular
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

private struct AppListRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct AppListRowAnchor: View {
    let id: UUID
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: AppListRowFramesKey.self, value: [id: geometry.frame(in: .global)])
        }
    }
}

struct AppPreserveListPosition: ViewModifier {
    let split: Bool
    let rowIDs: [UUID]
    @State private var viewport = CGRect.zero
    @State private var visibleID: UUID?
    @State private var deletionAnchor: UUID?
    @State private var measuredSplit: Bool?
    @State private var restoring = false
    @State private var currentIDs: [UUID] = []
    @State private var restoreGeneration = 0

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { currentIDs = rowIDs }
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { viewport = geometry.frame(in: .global) }
                            .onChange(of: geometry.frame(in: .global)) { _, frame in viewport = frame }
                    }
                }
                .onPreferenceChange(AppListRowFramesKey.self) { frames in
                    guard !restoring, measuredSplit == nil || measuredSplit == split, !viewport.isEmpty else { return }
                    measuredSplit = split
                    let visible = frames.filter {
                        rowIDs.contains($0.key) && $0.value.maxY > viewport.minY && $0.value.minY < viewport.maxY
                    }
                    if let anchor = deletionAnchor, visible[anchor] == nil {
                        deletionAnchor = nil
                    }
                    if let center = visible.min(by: {
                        abs($0.value.midY - viewport.midY) < abs($1.value.midY - viewport.midY)
                    }) {
                        visibleID = center.key
                    }
                }
                .onChange(of: rowIDs) { oldIDs, newIDs in
                    currentIDs = newIDs
                    restoreGeneration += 1
                    restoring = false
                    if let anchor = deletionAnchor, !newIDs.contains(anchor) { deletionAnchor = nil }
                    let removed = oldIDs.filter { !newIDs.contains($0) }
                    // A single removed row is the user's current context (for
                    // example, a swipe deletion). Follow its nearest survivor.
                    let id = removed.count == 1 ? removed[0] : visibleID
                    guard let id, !newIDs.contains(id) else { return }
                    guard let index = oldIDs.firstIndex(of: id) else { visibleID = nil; return }
                    let candidates = Array(oldIDs.dropFirst(index + 1)) + Array(oldIDs.prefix(index).reversed())
                    visibleID = candidates.first(where: { newIDs.contains($0) })
                    deletionAnchor = removed.count == 1 ? visibleID : nil
                }
                .onChange(of: split) { _, newValue in
                    // The compact filter section moves into the sidebar, so a
                    // raw offset alone would move the user's current row.
                    let id = deletionAnchor ?? visibleID
                    restoring = true
                    measuredSplit = newValue
                    restoreGeneration += 1
                    let generation = restoreGeneration
                    DispatchQueue.main.async {
                        guard generation == restoreGeneration else { return }
                        if let id, currentIDs.contains(id) { proxy.scrollTo(id, anchor: .center) }
                        // A split transition can finish laying out the list
                        // after its filter section moves to the sidebar.
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350)) {
                            guard generation == restoreGeneration else { return }
                            if let id, currentIDs.contains(id) { proxy.scrollTo(id, anchor: .center) }
                            restoring = false
                        }
                    }
                }
        }
    }
}

struct KeyboardNavigationToolbar<Field: Hashable>: View {
    let focusedField: FocusState<Field?>.Binding
    let currentField: Field?
    let fields: [Field]

    private var currentIndex: Int? {
        guard let value = currentField else { return nil }
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

    var body: some View {
        HStack {
            Button(AppLocalization.string("上一个")) {
                move(delta: -1)
            }
            .disabled(!canMovePrevious)
            .accessibilityIdentifier("keyboard-previous")

            Button(AppLocalization.string("下一个")) {
                move(delta: 1)
            }
            .disabled(!canMoveNext)
            .accessibilityIdentifier("keyboard-next")

            Spacer()

            Button(AppLocalization.string("完成")) {
                focusedField.wrappedValue = nil
                AppKeyboard.dismiss()
            }
            .accessibilityIdentifier("keyboard-done")
        }
    }

    private func move(delta: Int) {
        guard let currentIndex else { return }
        let next = currentIndex + delta
        guard fields.indices.contains(next) else { return }
        focusedField.wrappedValue = fields[next]
    }
}

struct KeyboardDismissToolbar: View {
    let onDone: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(AppLocalization.string("完成"), action: onDone)
                .accessibilityIdentifier("keyboard-done")
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
