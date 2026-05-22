import SwiftUI

private struct MaterialSheetPresentationsModifier: ViewModifier {
    @Binding var showExportChoice: Bool
    @Binding var exportFileURL: URL?
    @Binding var showExporter: Bool
    let onCleanupExportFile: () -> Void

    @Binding var showCreateDraftSheet: Bool
    @Binding var draftTitleInput: String
    @Binding var draftProjectIdInput: UUID?
    let projects: [Project]
    let onCreateDraft: (String, UUID?) -> Void

    @Binding var showRenameDraftSheet: Bool
    @Binding var renameDraftTitleInput: String
    let onRenameDraft: (String) -> Void

    @Binding var showClearConfirm: Bool
    let sheetItemCount: Int
    let onConfirmClear: () -> Void

    @Binding var showDeleteItemConfirm: Bool
    let pendingDeleteItemCount: Int
    let onConfirmDeleteItems: () -> Void
    let onCancelDeleteItems: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(String(localized: "导出方式"), isPresented: $showExportChoice) {
                if let url = exportFileURL {
                    Button {
                        showExporter = true
                    } label: {
                        Label(String(localized: "保存到文件"), systemImage: "folder")
                    }
                    ShareLink(item: url) {
                        Label(String(localized: "分享"), systemImage: "square.and.arrow.up")
                    }
                }
                Button(String(localized: "关闭"), role: .cancel) {
                    onCleanupExportFile()
                }
            } message: {
                Text(String(localized: "选择保存位置或分享给其他人"))
            }
            .sheet(isPresented: $showExporter) {
                if let exportFileURL {
                    FileURLDocumentExporter(fileURL: exportFileURL) { _ in
                        showExporter = false
                        onCleanupExportFile()
                    }
                } else {
                    ProgressView(String(localized: "正在准备导出文件..."))
                        .padding()
                }
            }
            .sheet(isPresented: $showCreateDraftSheet) {
                MaterialSheetCreateDraftSheet(
                    titleInput: $draftTitleInput,
                    projectIdInput: $draftProjectIdInput,
                    projects: projects,
                    onCancel: {
                        showCreateDraftSheet = false
                    },
                    onCreate: {
                        onCreateDraft(draftTitleInput, draftProjectIdInput)
                        showCreateDraftSheet = false
                    }
                )
            }
            .sheet(isPresented: $showRenameDraftSheet) {
                MaterialSheetRenameDraftSheet(
                    renameTitleInput: $renameDraftTitleInput,
                    onCancel: {
                        showRenameDraftSheet = false
                    },
                    onSave: {
                        onRenameDraft(renameDraftTitleInput)
                        showRenameDraftSheet = false
                    }
                )
            }
            .alert(String(localized: "清空材料单？"), isPresented: $showClearConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "清空"), role: .destructive) {
                    onConfirmClear()
                }
            } message: {
                Text(String(format: String(localized: "当前材料单中的 %d 项材料将被移除。"), sheetItemCount))
            }
            .confirmationDialog(String(localized: "删除材料项"), isPresented: $showDeleteItemConfirm, titleVisibility: .visible) {
                Button(String(localized: "删除"), role: .destructive) {
                    onConfirmDeleteItems()
                }
                Button(String(localized: "取消"), role: .cancel) {
                    onCancelDeleteItems()
                }
            } message: {
                Text(String(format: String(localized: "确认删除 %d 项材料吗？"), pendingDeleteItemCount))
            }
    }
}

extension View {
    func materialSheetPresentations(
        showExportChoice: Binding<Bool>,
        exportFileURL: Binding<URL?>,
        showExporter: Binding<Bool>,
        onCleanupExportFile: @escaping () -> Void,
        showCreateDraftSheet: Binding<Bool>,
        draftTitleInput: Binding<String>,
        draftProjectIdInput: Binding<UUID?>,
        projects: [Project],
        onCreateDraft: @escaping (String, UUID?) -> Void,
        showRenameDraftSheet: Binding<Bool>,
        renameDraftTitleInput: Binding<String>,
        onRenameDraft: @escaping (String) -> Void,
        showClearConfirm: Binding<Bool>,
        sheetItemCount: Int,
        onConfirmClear: @escaping () -> Void,
        showDeleteItemConfirm: Binding<Bool>,
        pendingDeleteItemCount: Int,
        onConfirmDeleteItems: @escaping () -> Void,
        onCancelDeleteItems: @escaping () -> Void
    ) -> some View {
        modifier(
            MaterialSheetPresentationsModifier(
                showExportChoice: showExportChoice,
                exportFileURL: exportFileURL,
                showExporter: showExporter,
                onCleanupExportFile: onCleanupExportFile,
                showCreateDraftSheet: showCreateDraftSheet,
                draftTitleInput: draftTitleInput,
                draftProjectIdInput: draftProjectIdInput,
                projects: projects,
                onCreateDraft: onCreateDraft,
                showRenameDraftSheet: showRenameDraftSheet,
                renameDraftTitleInput: renameDraftTitleInput,
                onRenameDraft: onRenameDraft,
                showClearConfirm: showClearConfirm,
                sheetItemCount: sheetItemCount,
                onConfirmClear: onConfirmClear,
                showDeleteItemConfirm: showDeleteItemConfirm,
                pendingDeleteItemCount: pendingDeleteItemCount,
                onConfirmDeleteItems: onConfirmDeleteItems,
                onCancelDeleteItems: onCancelDeleteItems
            )
        )
    }
}
