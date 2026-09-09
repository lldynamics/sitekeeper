import SwiftUI

struct BackupLocalSectionsView: View {
    let shouldShowFirstBackupGuide: Bool
    let includeLocalSection: Bool
    let showsUITestPreviewShortcut: Bool
    let showsUITestRoundTrip: Bool
    let isUITestRoundTripReady: Bool
    let isBusy: Bool
    let onExport: () -> Void
    let onDismissGuide: () -> Void
    let onShowImporter: () -> Void
    let onInjectUITestPreview: () -> Void
    let onTriggerOverwriteConfirm: () -> Void
    let onRestoreUITestRoundTrip: () -> Void

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
                    .accessibilityIdentifier("backup-export-local")
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

                    if showsUITestRoundTrip {
                        Button(String(localized: "UI测试：读取已验证备份"), action: onRestoreUITestRoundTrip)
                            .disabled(!isUITestRoundTripReady)
                            .accessibilityIdentifier("ui-test-backup-roundtrip-restore")
                        if isUITestRoundTripReady {
                            Text(String(localized: "UI测试备份已就绪"))
                                .accessibilityIdentifier("ui-test-backup-roundtrip-ready")
                        }
                    }
                }
            }
        }
    }
}
