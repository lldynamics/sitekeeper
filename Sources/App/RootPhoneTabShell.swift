import SwiftUI
import UIKit

struct RootPhoneTabShell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: Tab
    @State private var containerWidth: CGFloat = 0
    @State private var compactNavigationHeight: CGFloat = 48
    @State private var isKeyboardVisible = false
    let projectComposerOpenToken: Int
    let onComposerConsumed: (Int) -> Void

    private var usesCompactNavigation: Bool {
        containerWidth > 0 && !ExpandedPhoneWorkspaceLayout.isAvailable(width: containerWidth)
    }

    private var showsCompactNavigation: Bool {
        usesCompactNavigation && !isKeyboardVisible
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                tabs.tabViewStyle(.sidebarAdaptable)
            } else {
                tabs
            }
        }
        .environment(\.expandedPhoneWorkspaceWidth, containerWidth)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { containerWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in containerWidth = width }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private var compactNavigation: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleCompactNavigation
            } else {
                regularCompactNavigation
            }
        }
        .background(.bar, ignoresSafeAreaEdges: .bottom)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: CompactPhoneNavigationHeightKey.self, value: geometry.size.height)
            }
        }
    }

    private var regularCompactNavigation: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.body.weight(.semibold))
                        Text(tab.title)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? Color.appPrimaryAction : Color.secondary)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier("primary-module-\(tab.id)")
            }
        }
        .padding(.horizontal, AppSpacing.tight)
    }

    private var accessibleCompactNavigation: some View {
        Menu {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    if selectedTab == tab {
                        Label(tab.title, systemImage: "checkmark")
                    } else {
                        Text(tab.title)
                    }
                }
            }
        } label: {
            HStack(spacing: AppSpacing.tight) {
                Label(selectedTab.title, systemImage: selectedTab.systemImage)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: AppSpacing.tight)
                Image(systemName: "chevron.up.chevron.down")
            }
            .padding(.horizontal, AppSpacing.relaxed)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .foregroundStyle(Color.appPrimaryAction)
        .accessibilityLabel(AppLocalization.string("导航"))
        .accessibilityValue(selectedTab.title)
        .accessibilityIdentifier("primary-module-menu")
    }

    private func phoneTabChrome<Content: View>(_ content: Content) -> some View {
        content
            .padding(.bottom, showsCompactNavigation ? compactNavigationHeight : 0)
            .toolbar(usesCompactNavigation ? .hidden : .automatic, for: .tabBar)
            .overlay(alignment: .bottom) {
                if showsCompactNavigation {
                    compactNavigation
                }
            }
            .onPreferenceChange(CompactPhoneNavigationHeightKey.self) { height in
                if height > 0, abs(height - compactNavigationHeight) > 0.5 {
                    compactNavigationHeight = height
                }
            }
    }

    // Keep one tab/content identity while the system adapts its navigation chrome.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            phoneTabChrome(DashboardView())
                .tabItem { Label(Tab.dashboard.title, systemImage: Tab.dashboard.systemImage) }
                .tag(Tab.dashboard)

            phoneTabChrome(ProjectWorkspaceView(
                autoOpenComposerToken: projectComposerOpenToken,
                onAutoOpenComposerConsumed: onComposerConsumed
            ))
            .tabItem { Label(Tab.records.title, systemImage: Tab.records.systemImage) }
            .tag(Tab.records)

            phoneTabChrome(ChecklistTabView())
                .tabItem { Label(Tab.checklist.title, systemImage: Tab.checklist.systemImage) }
                .tag(Tab.checklist)

            phoneTabChrome(QuickNoteView())
                .tabItem { Label(Tab.quickNote.title, systemImage: Tab.quickNote.systemImage) }
                .tag(Tab.quickNote)

            phoneTabChrome(ProfileTabView())
                .tabItem { Label(Tab.profile.title, systemImage: Tab.profile.systemImage) }
                .tag(Tab.profile)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

private struct CompactPhoneNavigationHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
