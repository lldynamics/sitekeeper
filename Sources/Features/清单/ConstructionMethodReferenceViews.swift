import SwiftUI

enum ConstructionMethodReferenceAction: String, CaseIterable, Identifiable {
    case todo
    case dailyLog
    case rectification

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo:
            return String(localized: "生成待办")
        case .dailyLog:
            return String(localized: "写入日志")
        case .rectification:
            return String(localized: "生成整改")
        }
    }

    var detail: String {
        switch self {
        case .todo:
            return String(localized: "用于现场检查、复核或安排执行")
        case .dailyLog:
            return String(localized: "把工艺依据写入今天的施工日志")
        case .rectification:
            return String(localized: "生成质量整改待办并关联该工艺")
        }
    }

    var systemImage: String {
        switch self {
        case .todo:
            return "checklist.checked"
        case .dailyLog:
            return "book.pages.fill"
        case .rectification:
            return "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .todo:
            return .appDoc
        case .dailyLog:
            return .appSuccess
        case .rectification:
            return .appRisk
        }
    }
}

struct ConstructionMethodReferenceBlock: View {
    let onSelect: (ConstructionMethodReferenceAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(String(localized: "引用到现场"), systemImage: "link.badge.plus")
                .font(.headline)
            Text(String(localized: "把这条工艺直接变成待办、日志或整改依据。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: AppSpacing.tight) {
                ForEach(ConstructionMethodReferenceAction.allCases) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: action.systemImage)
                                .font(.headline)
                            Text(action.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .tint(action.tint)
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.detail)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ConstructionMethodReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let method: ConstructionMethod
    let action: ConstructionMethodReferenceAction
    let projects: [Project]
    let onSave: (ConstructionMethodReferenceAction, UUID?) -> Void

    @State private var selectedProjectId: UUID?

    private var sortedProjects: [Project] {
        projects.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "工艺")) {
                    LabeledContent(String(localized: "名称"), value: methodDisplayTitle(method))
                    LabeledContent(String(localized: "专业"), value: method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未分类") : method.trade)
                    LabeledContent(String(localized: "动作"), value: action.title)
                }
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "项目"), selection: $selectedProjectId) {
                        Text(String(localized: "不关联项目")).tag(nil as UUID?)
                        ForEach(sortedProjects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section(String(localized: "将写入")) {
                    Text(action.detail)
                        .font(.callout)
                    Text(constructionMethodReferenceText(method))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "生成")) {
                        onSave(action, selectedProjectId)
                        dismiss()
                    }
                }
            }
        }
    }
}

func methodDisplayTitle(_ method: ConstructionMethod) -> String {
    let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? String(localized: "未命名工艺") : title
}

func constructionMethodReferenceText(_ method: ConstructionMethod) -> String {
    var sections: [String] = []
    let title = methodDisplayTitle(method)
    let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
    sections.append(String(format: String(localized: "工艺：%@"), title))
    if !trade.isEmpty {
        sections.append(String(format: String(localized: "专业：%@"), trade))
    }
    if !method.versionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        sections.append(String(format: String(localized: "版本：%@"), method.versionName))
    }
    if !method.procedureSteps.isEmpty {
        sections.append(String(format: String(localized: "施工步骤：\n%@"), numberedLines(method.procedureSteps)))
    }
    if !method.qualityChecklist.isEmpty {
        sections.append(String(format: String(localized: "质量要点：\n%@"), numberedLines(method.qualityChecklist)))
    }
    if !method.safetyChecklist.isEmpty {
        sections.append(String(format: String(localized: "安全注意：\n%@"), numberedLines(method.safetyChecklist)))
    }
    return sections.joined(separator: "\n\n")
}

func numberedLines(_ lines: [String]) -> String {
    lines
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .enumerated()
        .map { "\($0.offset + 1). \($0.element)" }
        .joined(separator: "\n")
}
