import SwiftUI

/// Keeps the navigation tree and unfinished forms alive while storage is unavailable.
struct StoreAvailabilityOverlay: View {
    let failed: Bool
    let onRetry: () -> Void
    let onRestore: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .background(Color(.systemBackground))
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            if failed {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                Text(AppLocalization.string("本地数据暂不可用"))
                    .font(.title2.weight(.semibold))
                Text(AppLocalization.string("已暂停编辑并保留原文件。请重试读取，或从备份恢复后继续。"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(AppLocalization.string("重试读取本地数据"), action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("storage-recovery-retry")
                Button(AppLocalization.string("从备份恢复"), action: onRestore)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("storage-recovery-restore")
            } else {
                ProgressView()
                Text(AppLocalization.string("正在准备本地数据，请稍候…"))
            }
        }
    }
}
