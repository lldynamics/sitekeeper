import SwiftUI

struct ProfileStorageStatusCard: View {
    let backupStatusText: String
    let localStorageUsageText: String
    let storageCaptionText: String
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string("备份与存储"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(backupStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: AppLocalization.string("本机占用：%@"), localStorageUsageText))
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Text(storageCaptionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appStrokeSecondary, lineWidth: 1)
        )
    }
}
