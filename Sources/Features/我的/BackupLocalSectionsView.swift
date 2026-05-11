import SwiftUI

struct BackupLocalSectionsView: View {
    let shouldShowFirstBackupGuide: Bool
    let includeLocalSection: Bool
    let showsUITestPreviewShortcut: Bool
    let isBusy: Bool
    let onExport: () -> Void
    let onDismissGuide: () -> Void
    let onShowImporter: () -> Void
    let onInjectUITestPreview: () -> Void
    let onTriggerOverwriteConfirm: () -> Void

    var body: some View {
        Group {
            if shouldShowFirstBackupGuide {
                Section("备份建议") {
                    BackupQuickStartCard(
                        onExport: onExport,
                        onDismiss: onDismissGuide
                    )
                }
            }

            if includeLocalSection {
                Section("本地备份") {
                    Button(action: onExport) {
                        Label("导出完整备份 ZIP", systemImage: "archivebox")
                    }
                    .disabled(isBusy)

                    Button(action: onShowImporter) {
                        Label("导入备份 ZIP", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isBusy)

                    if showsUITestPreviewShortcut {
                        Button("UI测试：模拟覆盖导入预览") {
                            onInjectUITestPreview()
                        }
                        .accessibilityIdentifier("ui-test-backup-preview")

                        Button("UI测试：触发覆盖二次确认") {
                            onTriggerOverwriteConfirm()
                        }
                        .accessibilityIdentifier("ui-test-overwrite-confirm")
                    }
                }
            }
        }
    }
}
