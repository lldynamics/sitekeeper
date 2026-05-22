import SwiftUI

struct ToolboxIconCard: View {
    let icon: String
    let title: String
    let desc: String
    let color: Color
    var iconCentered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if iconCentered { Spacer(minLength: 0) }
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(desc)
        .accessibilityHint(String(localized: "双击打开"))
    }
}

struct QuickToolEditorView: View {
    let currentOrderIDs: [String]
    let defaultOrderIDs: [String]
    let allTools: [QuickToolEntry]
    let onSave: ([String]) -> Void

    @State private var selectedIDs: Set<String>
    @State private var orderedIDs: [String]
    @Environment(\.dismiss) private var dismiss

    init(currentOrderIDs: [String], defaultOrderIDs: [String], allTools: [QuickToolEntry], onSave: @escaping ([String]) -> Void) {
        self.currentOrderIDs = currentOrderIDs
        self.defaultOrderIDs = defaultOrderIDs
        self.allTools = allTools
        self.onSave = onSave
        _selectedIDs = State(initialValue: Set(currentOrderIDs))
        _orderedIDs = State(initialValue: currentOrderIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(allTools) { tool in
                        HStack(spacing: 12) {
                            Toggle(isOn: binding(for: tool.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.title).font(.subheadline.weight(.medium))
                                    Text(tool.desc).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityHint(String(localized: "双击切换是否显示在快捷工具"))
                        }
                    }
                } header: {
                    Text(String(localized: "quick_tool_editor_header"))
                } footer: {
                    Text(String(localized: "quick_tool_unselected_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        let defaults = defaultOrderIDs.filter { id in allTools.contains(where: { $0.id == id }) }
                        selectedIDs = Set(defaults)
                        orderedIDs = defaults
                    } label: {
                        Label(String(localized: "quick_tool_editor_reset_default"), systemImage: "arrow.counterclockwise")
                    }
                }

                if selectedIDs.count > 1 {
                    Section(String(localized: "quick_tool_editor_sort_section")) {
                        ForEach(orderedIDs.filter { selectedIDs.contains($0) }, id: \.self) { id in
                            if let tool = allTools.first(where: { $0.id == id }) {
                                Label(tool.title, systemImage: tool.icon)
                                    .font(.subheadline)
                                    .accessibilityHint(String(localized: "按住后拖动可调整顺序"))
                            }
                        }
                        .onMove { source, destination in
                            var visible = orderedIDs.filter { selectedIDs.contains($0) }
                            visible.move(fromOffsets: source, toOffset: destination)

                            let hidden = orderedIDs.filter { !selectedIDs.contains($0) }
                            orderedIDs = visible + hidden
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "quick_tool_editor_title"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        let saved = orderedIDs.filter { selectedIDs.contains($0) }
                        onSave(saved)
                        dismiss()
                    }
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isOn in
                if isOn {
                    selectedIDs.insert(id)
                    if !orderedIDs.contains(id) {
                        orderedIDs.append(id)
                    }
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }
}
