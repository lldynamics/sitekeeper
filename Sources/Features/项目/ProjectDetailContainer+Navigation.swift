import SwiftUI

extension ProjectDetailContainer {
    func applyNavigationAndLifecycleModifiers<Content: View>(
        to content: Content,
        project: Project,
        snapshot: ProjectDetailSnapshot
    ) -> some View {
        content
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    projectAddMenu
                    projectMoreMenu(project: project, snapshot: snapshot)
                }
            }
            .onAppear {
                handleOnAppear(snapshot: snapshot)
                syncSingleCanvasAnchorIfNeeded(for: routeState.mode)
            }
            .onChange(of: routeState.mode) { _, newValue in
                if newValue != .finance {
                    routeState.financeJumpFilter = .none
                }
                syncSingleCanvasAnchorIfNeeded(for: newValue)
            }
            .onDisappear {
                exportState.cancelExportTask()
                flushPendingProjectDeletionIfNeeded()
            }
            .navigationDestination(isPresented: $showTodoFilterView) {
                SiteTodoView(initialProjectId: projectId)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(item: $dataManagementDestination) { destination in
                DataManagementView(initialRoute: destination.route)
                    .navigationBarTitleDisplayMode(.inline)
            }
    }
}
