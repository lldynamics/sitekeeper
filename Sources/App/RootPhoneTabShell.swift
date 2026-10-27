import SwiftUI

struct RootPhoneTabShell: View {
    @Binding var selectedTab: Tab
    let projectComposerOpenToken: Int
    let onComposerConsumed: (Int) -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            tabs.tabViewStyle(.sidebarAdaptable)
        } else {
            tabs
        }
    }

    // Keep one tab/content identity while the system adapts its navigation chrome.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(Tab.dashboard.title, systemImage: Tab.dashboard.systemImage) }
                .tag(Tab.dashboard)

            ProjectWorkspaceView(
                autoOpenComposerToken: projectComposerOpenToken,
                onAutoOpenComposerConsumed: onComposerConsumed
            )
            .tabItem { Label(Tab.records.title, systemImage: Tab.records.systemImage) }
            .tag(Tab.records)

            ChecklistTabView()
                .tabItem { Label(Tab.checklist.title, systemImage: Tab.checklist.systemImage) }
                .tag(Tab.checklist)

            QuickNoteView()
                .tabItem { Label(Tab.quickNote.title, systemImage: Tab.quickNote.systemImage) }
                .tag(Tab.quickNote)

            ProfileTabView()
                .tabItem { Label(Tab.profile.title, systemImage: Tab.profile.systemImage) }
                .tag(Tab.profile)
        }
    }
}
