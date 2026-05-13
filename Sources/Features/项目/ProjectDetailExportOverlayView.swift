import SwiftUI

struct ProjectPackageExportOverlayView: View {
    let progress: ProjectPackageExportProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            Text(String(localized: "正在导出项目交付包"))
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
                Button(String(localized: "取消导出"), role: .destructive) {
                    AppHaptics.warning()
                    onCancel()
                }
            }
        }
        .padding(AppSpacing.relaxed)
        .frame(maxWidth: 320)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "显示导出进度并可取消当前导出"))
    }
}
