import SwiftUI

private struct MaterialCategoryManagementState {
    var renameSource = ""
    var renameTarget = ""
    var showRenameSheet = false
    var deleteSource = ""
    var deleteTarget = MaterialCategory.other.rawValue
    var showDeleteSheet = false
}

private struct CategoryUsage: Identifiable {
    let name: String
    let userMaterialCount: Int
    let priceEntryCount: Int

    var id: String { name }
}

struct MaterialCategoryManagementView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var state = MaterialCategoryManagementState()

    private var categoryUsage: [CategoryUsage] {
        let userCategories = store.userMaterials.map { normalizedCategory($0.category) }.filter { !$0.isEmpty }
        let priceCategories = store.materialPriceEntries.map { normalizedCategory($0.category) }.filter { !$0.isEmpty }
        let names = Set(userCategories + priceCategories)

        return names
            .map { name in
                CategoryUsage(
                    name: name,
                    userMaterialCount: userCategories.filter { $0 == name }.count,
                    priceEntryCount: priceCategories.filter { $0 == name }.count
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var migrationTargets: [String] {
        let preset = MaterialCategory.allCases.map(\.rawValue)
        let dynamic = categoryUsage.map(\.name)
        return Array(Set(preset + dynamic)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        List {
            if categoryUsage.isEmpty {
                ContentUnavailableView(String(localized: "暂无可管理分类"), systemImage: "tag")
            } else {
                Section(String(localized: "现有分类")) {
                    ForEach(categoryUsage) { usage in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(usage.name)
                                .font(.body.weight(.semibold))
                            Text(
                                String(
                                    format: String(localized: "自定义材料 %lld 条 · 价格条目 %lld 条"),
                                    Int64(usage.userMaterialCount),
                                    Int64(usage.priceEntryCount)
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(String(localized: "删除"), role: .destructive) {
                                state.deleteSource = usage.name
                                state.deleteTarget = defaultDeleteTarget(for: usage.name)
                                state.showDeleteSheet = true
                            }
                            Button(String(localized: "重命名")) {
                                state.renameSource = usage.name
                                state.renameTarget = usage.name
                                state.showRenameSheet = true
                            }
                            .tint(Color.appDoc)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "分类管理"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "完成")) { dismiss() }
            }
        }
        .sheet(isPresented: $state.showRenameSheet) {
            NavigationStack {
                Form {
                    Section(String(localized: "重命名分类")) {
                        LabeledContent(String(localized: "原分类"), value: state.renameSource)
                        TextField(String(localized: "新分类名称"), text: $state.renameTarget)
                    }
                }
                .navigationTitle(String(localized: "重命名"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "取消")) { state.showRenameSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "保存")) {
                            renameCategory(from: state.renameSource, to: state.renameTarget)
                            state.showRenameSheet = false
                        }
                        .disabled(
                            normalizedCategory(state.renameTarget).isEmpty ||
                            normalizedCategory(state.renameTarget) == normalizedCategory(state.renameSource)
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $state.showDeleteSheet) {
            NavigationStack {
                Form {
                    Section(String(localized: "删除分类并迁移")) {
                        Text(String(format: String(localized: "分类“%@”将被移除。"), state.deleteSource))
                            .font(.subheadline)
                        Picker(String(localized: "迁移到"), selection: $state.deleteTarget) {
                            ForEach(migrationTargets.filter { $0 != state.deleteSource }, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                .navigationTitle(String(localized: "删除分类"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "取消")) { state.showDeleteSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "删除并迁移"), role: .destructive) {
                            migrateCategory(from: state.deleteSource, to: state.deleteTarget)
                            state.showDeleteSheet = false
                        }
                        .disabled(state.deleteTarget == state.deleteSource || normalizedCategory(state.deleteTarget).isEmpty)
                    }
                }
            }
        }
    }

    private func renameCategory(from source: String, to target: String) {
        let normalizedSource = normalizedCategory(source)
        let normalizedTarget = normalizedCategory(target)
        guard !normalizedSource.isEmpty, !normalizedTarget.isEmpty, normalizedSource != normalizedTarget else { return }
        migrateCategory(from: normalizedSource, to: normalizedTarget)
    }

    private func migrateCategory(from source: String, to target: String) {
        let normalizedSource = normalizedCategory(source)
        let normalizedTarget = normalizedCategory(target)
        guard !normalizedSource.isEmpty, !normalizedTarget.isEmpty, normalizedSource != normalizedTarget else { return }

        var updatedUserMaterials = store.userMaterials
        var didUpdateUserMaterials = false
        for index in updatedUserMaterials.indices where normalizedCategory(updatedUserMaterials[index].category) == normalizedSource {
            updatedUserMaterials[index].category = normalizedTarget
            didUpdateUserMaterials = true
        }
        if didUpdateUserMaterials {
            store.replaceUserMaterials(updatedUserMaterials)
        }
        let materialPriceEntriesToMigrate = store.materialPriceEntries.filter {
            normalizedCategory($0.category) == normalizedSource
        }
        for entry in materialPriceEntriesToMigrate {
            var updated = entry
            updated.category = normalizedTarget
            store.upsertMaterialPriceEntry(updated)
        }
        store.scheduleSave()
    }

    private func defaultDeleteTarget(for source: String) -> String {
        let candidates = migrationTargets.filter { $0 != source }
        return candidates.first ?? MaterialCategory.other.rawValue
    }

    private func normalizedCategory(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
