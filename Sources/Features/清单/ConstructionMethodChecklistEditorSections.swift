import SwiftUI

struct ConstructionMethodProcessEditorSections: View {
    @Binding var procedureSteps: [String]
    @Binding var newProcedureStep: String

    private var stepTemplates: [String] {
        [
            String(localized: "现场交底"),
            String(localized: "材料进场验收"),
            String(localized: "放线定位"),
            String(localized: "分步施工"),
            String(localized: "隐蔽验收"),
            String(localized: "成品保护")
        ]
    }

    var body: some View {
        Group {
            Section(String(localized: "施工步骤")) {
                if procedureSteps.isEmpty {
                    Text(String(localized: "暂无步骤，先新增一条。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(procedureSteps.indices, id: \.self) { index in
                    ConstructionMethodChecklistItemRow(
                        title: String(format: String(localized: "步骤 %lld"), Int64(index + 1)),
                        text: constructionMethodChecklistBinding(for: $procedureSteps, index: index),
                        canMoveUp: index > 0,
                        canMoveDown: index < procedureSteps.count - 1,
                        onMoveUp: { moveProcedureStepUp(index) },
                        onMoveDown: { moveProcedureStepDown(index) },
                        onDelete: { removeProcedureStep(index) }
                    )
                }
                ConstructionMethodChecklistAddRow(
                    placeholder: String(localized: "新增步骤"),
                    text: $newProcedureStep,
                    onAdd: appendProcedureStep
                )
            }
            Section(String(localized: "常用步骤模板")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stepTemplates, id: \.self) { template in
                            Button(template) { applyStepTemplate(template) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func applyStepTemplate(_ template: String) {
        let normalized = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !procedureSteps.contains(normalized) else { return }
        procedureSteps.append(normalized)
    }

    private func appendProcedureStep() {
        let value = newProcedureStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        procedureSteps.append(value)
        newProcedureStep = ""
    }

    private func moveProcedureStepUp(_ index: Int) {
        guard procedureSteps.indices.contains(index), index > 0 else { return }
        procedureSteps.swapAt(index, index - 1)
    }

    private func moveProcedureStepDown(_ index: Int) {
        guard procedureSteps.indices.contains(index), index < procedureSteps.count - 1 else { return }
        procedureSteps.swapAt(index, index + 1)
    }

    private func removeProcedureStep(_ index: Int) {
        guard procedureSteps.indices.contains(index) else { return }
        procedureSteps.remove(at: index)
    }
}

struct ConstructionMethodQualityChecklistEditorSections: View {
    @Binding var qualityChecklist: [String]
    @Binding var safetyChecklist: [String]
    @Binding var newQualityItem: String
    @Binding var newSafetyItem: String

    var body: some View {
        Group {
            Section(String(localized: "质量检查项")) {
                if qualityChecklist.isEmpty {
                    Text(String(localized: "暂无质量检查项。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(qualityChecklist.indices, id: \.self) { index in
                    ConstructionMethodChecklistItemRow(
                        title: String(format: String(localized: "检查项 %lld"), Int64(index + 1)),
                        text: constructionMethodChecklistBinding(for: $qualityChecklist, index: index),
                        canMoveUp: index > 0,
                        canMoveDown: index < qualityChecklist.count - 1,
                        onMoveUp: { moveQualityItemUp(index) },
                        onMoveDown: { moveQualityItemDown(index) },
                        onDelete: { removeQualityItem(index) }
                    )
                }
                ConstructionMethodChecklistAddRow(
                    placeholder: String(localized: "新增质量检查项"),
                    text: $newQualityItem,
                    onAdd: appendQualityItem
                )
            }
            Section(String(localized: "安全注意项")) {
                if safetyChecklist.isEmpty {
                    Text(String(localized: "暂无安全注意项。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(safetyChecklist.indices, id: \.self) { index in
                    ConstructionMethodChecklistItemRow(
                        title: String(format: String(localized: "注意项 %lld"), Int64(index + 1)),
                        text: constructionMethodChecklistBinding(for: $safetyChecklist, index: index),
                        canMoveUp: index > 0,
                        canMoveDown: index < safetyChecklist.count - 1,
                        onMoveUp: { moveSafetyItemUp(index) },
                        onMoveDown: { moveSafetyItemDown(index) },
                        onDelete: { removeSafetyItem(index) }
                    )
                }
                ConstructionMethodChecklistAddRow(
                    placeholder: String(localized: "新增安全注意项"),
                    text: $newSafetyItem,
                    onAdd: appendSafetyItem
                )
            }
        }
    }

    private func appendQualityItem() {
        let value = newQualityItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        qualityChecklist.append(value)
        newQualityItem = ""
    }

    private func appendSafetyItem() {
        let value = newSafetyItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        safetyChecklist.append(value)
        newSafetyItem = ""
    }

    private func moveQualityItemUp(_ index: Int) {
        guard qualityChecklist.indices.contains(index), index > 0 else { return }
        qualityChecklist.swapAt(index, index - 1)
    }

    private func moveQualityItemDown(_ index: Int) {
        guard qualityChecklist.indices.contains(index), index < qualityChecklist.count - 1 else { return }
        qualityChecklist.swapAt(index, index + 1)
    }

    private func removeQualityItem(_ index: Int) {
        guard qualityChecklist.indices.contains(index) else { return }
        qualityChecklist.remove(at: index)
    }

    private func moveSafetyItemUp(_ index: Int) {
        guard safetyChecklist.indices.contains(index), index > 0 else { return }
        safetyChecklist.swapAt(index, index - 1)
    }

    private func moveSafetyItemDown(_ index: Int) {
        guard safetyChecklist.indices.contains(index), index < safetyChecklist.count - 1 else { return }
        safetyChecklist.swapAt(index, index + 1)
    }

    private func removeSafetyItem(_ index: Int) {
        guard safetyChecklist.indices.contains(index) else { return }
        safetyChecklist.remove(at: index)
    }
}

private struct ConstructionMethodChecklistItemRow: View {
    let title: String
    @Binding var text: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(String(localized: "输入内容"), text: $text, axis: .vertical)
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct ConstructionMethodChecklistAddRow: View {
    let placeholder: String
    @Binding var text: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private func constructionMethodChecklistBinding(for items: Binding<[String]>, index: Int) -> Binding<String> {
    Binding(
        get: {
            guard items.wrappedValue.indices.contains(index) else { return "" }
            return items.wrappedValue[index]
        },
        set: { newValue in
            guard items.wrappedValue.indices.contains(index) else { return }
            items.wrappedValue[index] = newValue
        }
    )
}
