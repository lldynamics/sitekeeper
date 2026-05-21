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
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
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
