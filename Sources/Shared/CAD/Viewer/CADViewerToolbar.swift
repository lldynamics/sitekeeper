import SwiftUI

struct CADViewerToolbar: View {
    let fileURL: URL
    let displayName: String
    let onReportIssue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 12)

            ShareLink(item: fileURL) {
                Label("下载原图", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button(action: onReportIssue) {
                Label("反馈问题", systemImage: "exclamationmark.bubble")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
