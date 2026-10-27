import SwiftUI

struct ProjectPackageExportOverlayView: View {
    let progress: ProjectPackageExportProgress
    let onCancel: () -> Void

    var body: some View {
        AppPanel(
            tone: .materialThick,
            cornerRadius: 14,
            padding: AppSpacing.relaxed,
            shadow: .overlay
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.normal) {
                Text(AppLocalization.string("正在导出项目交付包"))
                    .font(.headline)
                Text(progress.currentItem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                ProgressView(value: progress.fractionCompleted)
                Text("\(progress.completedSteps)/\(max(progress.totalSteps, 1))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(AppLocalization.string("取消导出"), role: .destructive) {
                        AppHaptics.warning()
                        onCancel()
                    }
                }
            }
        }
        .frame(maxWidth: 320)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLocalization.string("显示导出进度并可取消当前导出"))
    }
}
