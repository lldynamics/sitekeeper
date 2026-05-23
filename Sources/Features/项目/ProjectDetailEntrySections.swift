import SwiftUI

struct ProjectDetailEntryShortcut: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let statusColor: Color
    let action: () -> Void
}

struct ProjectDetailEntryShortcutsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let entries: [ProjectDetailEntryShortcut]

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var columns: [GridItem] {
        if usesWideLayout {
            return [GridItem(.adaptive(minimum: 176), spacing: AppSpacing.tight)]
        }
        return [
            GridItem(.flexible(), spacing: AppSpacing.tight),
            GridItem(.flexible(), spacing: AppSpacing.tight)
        ]
    }

    private var iconSize: CGFloat {
        usesWideLayout ? 30 : 28
    }

    private var minHeight: CGFloat {
        usesWideLayout ? 72 : 56
    }

    private var horizontalPadding: CGFloat {
        usesWideLayout ? AppSpacing.normal : AppSpacing.tight
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.tight) {
            ForEach(entries) { entry in
                Button(action: entry.action) {
                    HStack(spacing: AppSpacing.tight) {
                        Image(systemName: entry.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(entry.tint)
                            .frame(width: iconSize, height: iconSize)
                            .background(entry.tint.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(usesWideLayout ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .appListPrimaryTextLayout(lines: 1)
                            Text(entry.subtitle)
                                .font((usesWideLayout ? Font.caption : Font.caption2).weight(.medium))
                                .foregroundStyle(entry.statusColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 6)
                    .background(Color.appPrimarySurfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.title)，\(entry.subtitle)")
            }
        }
    }
}

struct ProjectNextStepSuggestion: Identifiable {
    enum Action {
        case addLog
        case records
        case finance
        case assets
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: Action
}

struct ProjectNextStepSuggestionsView: View {
    let suggestions: [ProjectNextStepSuggestion]
    let onAddLog: () -> Void
    let onOpenRecords: () -> Void
    let onOpenFinance: () -> Void
    let onOpenAssets: () -> Void

    var body: some View {
        if suggestions.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Label(String(localized: "当前项目状态良好"), systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.appSuccess)
                Text(String(localized: "暂无需要优先处理的日志、延期、回款或票据问题。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else {
            ForEach(suggestions) { suggestion in
                Button {
                    perform(suggestion.action)
                } label: {
                    HStack(spacing: AppSpacing.normal) {
                        Image(systemName: suggestion.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(suggestion.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func perform(_ action: ProjectNextStepSuggestion.Action) {
        switch action {
        case .addLog:
            onAddLog()
        case .records:
            onOpenRecords()
        case .finance:
            onOpenFinance()
        case .assets:
            onOpenAssets()
        }
    }
}
