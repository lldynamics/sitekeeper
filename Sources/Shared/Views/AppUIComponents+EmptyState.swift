import SwiftUI

struct AppActionableEmptyState<Action: View>: View {
    let title: String
    let systemImage: String
    let message: Text
    @ViewBuilder let action: Action

    init(
        title: String,
        systemImage: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = Text(message)
        self.action = action()
    }

    init(
        title: String,
        systemImage: String,
        message: Text,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    message
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            action
        }
        .padding(.vertical, 4)
    }
}

extension AppActionableEmptyState where Action == EmptyView {
    init(
        title: String,
        systemImage: String,
        message: String
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = Text(message)
        self.action = EmptyView()
    }

    init(
        title: String,
        systemImage: String,
        message: Text
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.action = EmptyView()
    }
}

struct FilterChipBar<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(title(option))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection == option ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selection == option ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

enum InlineNoticeTone {
    case info
    case success
    case warning
    case error

    var icon: String {
        switch self {
        case .info:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info:
            .appPrimaryAction
        case .success:
            .appSuccess
        case .warning:
            .appWarning
        case .error:
            .appRisk
        }
    }

    var background: Color {
        switch self {
        case .info:
            .appPrimarySurfaceSubtle
        case .success:
            .appSuccessSurfaceSubtle
        case .warning:
            .appDynamicTint(AppTheme.current.palette.warningUIColor, lightOpacity: 0.12, darkOpacity: 0.24)
        case .error:
            .appRiskSurface
        }
    }
}

struct InlineNotice: View {
    let title: String
    var message: String? = nil
    var tone: InlineNoticeTone = .info

    var body: some View {
        AppPanel(
            tone: .tinted(tone.background),
            cornerRadius: 10,
            padding: AppSpacing.normal,
            stroke: tone.tint.opacity(0.18)
        ) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: tone.icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tone.tint)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct DataSafetyStatusItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var tone: StatusChipTone = .neutral
}

struct DataSafetyStatusStrip: View {
    let items: [DataSafetyStatusItem]

    var body: some View {
        AppPanel(
            tone: .grouped,
            cornerRadius: 12,
            padding: AppSpacing.normal,
            stroke: Color.appStrokeSecondary.opacity(0.45)
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), alignment: .topLeading)],
                alignment: .leading,
                spacing: AppSpacing.normal
            ) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        StatusChip(text: item.title, tone: item.tone, compact: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
