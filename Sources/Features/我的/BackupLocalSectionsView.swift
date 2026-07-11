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
                Section(String(localized: "备份建议")) {
                    BackupQuickStartCard(
                        onExport: onExport,
                        onShowImporter: onShowImporter,
                        onDismiss: onDismissGuide
                    )
                }
            }

            if includeLocalSection {
                Section(String(localized: "本地备份")) {
                    Button(action: onExport) {
                        Label(String(localized: "导出完整备份 ZIP"), systemImage: "archivebox")
                    }
                    .disabled(isBusy)

                    Button(action: onShowImporter) {
                        Label(String(localized: "导入备份 ZIP"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(isBusy)

                    if showsUITestPreviewShortcut {
                        Button(String(localized: "UI测试：模拟覆盖导入预览")) {
                            onInjectUITestPreview()
                        }
                        .accessibilityIdentifier("ui-test-backup-preview")

                        Button(String(localized: "UI测试：触发覆盖二次确认")) {
                            onTriggerOverwriteConfirm()
                        }
                        .accessibilityIdentifier("ui-test-overwrite-confirm")
                    }
                }
            }
        }
    }
}
