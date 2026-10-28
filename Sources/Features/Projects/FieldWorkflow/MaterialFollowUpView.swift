import SwiftUI

struct MaterialFollowUpView: View {
    @Environment(DataStore.self) private var store
    let project: Project

    @State private var selectedSupplier: String?
    @State private var statusFilter: MaterialFollowUpFilter = .allPending
    @State private var pageIndex = 0
    @State private var exportPreview: MaterialFollowUpExportPreview?

    private var pendingRows: [MaterialFollowUpRow] {
        MaterialFollowUpSummary.rows(
            projectID: project.id,
            materials: store.financeStore.materialItems(for: project.id),
            movements: store.projectStore.projectWarehouseMovements(for: project.id)
        )
    }

    var body: some View {
        let allRows = pendingRows
        let suppliers = MaterialFollowUpSummary.suppliers(in: allRows)
        let supplier = selectedSupplier.flatMap { suppliers.contains($0) ? $0 : nil }
        let rows = allRows.filter {
            (supplier == nil || $0.supplier == supplier)
                && (statusFilter == .allPending || $0.followUpStatus == statusFilter)
        }
        let page = RecordPage(rows, index: pageIndex)
        List {
            Section(AppLocalization.string("筛选")) {
                Picker(AppLocalization.string("供应商"), selection: $selectedSupplier) {
                    Text(AppLocalization.string("material_follow_up_all_suppliers")).tag(Optional<String>.none)
                    ForEach(suppliers, id: \.self) { supplier in
                        Text(MaterialFollowUpSummary.supplierDisplayName(supplier)).tag(Optional(supplier))
                    }
                }
                Picker(AppLocalization.string("状态"), selection: $statusFilter) {
                    ForEach(MaterialFollowUpFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                Text(AppLocalization.string("material_follow_up_scope_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(AppLocalization.string("material_follow_up_receipt_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String(format: AppLocalization.string("material_follow_up_count_format"), Int64(rows.count))) {
                if rows.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.string("material_follow_up_empty"),
                        systemImage: "shippingbox",
                        description: Text(AppLocalization.string("material_follow_up_empty_detail"))
                    )
                } else {
                    ForEach(page.items) { row in
                        MaterialFollowUpRowView(row: row)
                    }
                    RecordPageControls(index: page.index, count: page.count, selection: $pageIndex)
                }
            }

            Section {
                Button {
                    let projectName = store.projects.first(where: { $0.id == project.id })?.name ?? project.name
                    exportPreview = MaterialFollowUpExportPreview(text: MaterialFollowUpSummary.exportText(
                        projectName: projectName, rows: rows, supplier: supplier, filter: statusFilter
                    ))
                } label: {
                    Label(AppLocalization.string("material_follow_up_preview_export"), systemImage: "doc.text.magnifyingglass")
                }
                .disabled(rows.isEmpty)
                .accessibilityIdentifier("material-follow-up.preview")
            }
        }
        .navigationTitle(AppLocalization.string("material_follow_up_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedSupplier) { _, _ in pageIndex = 0 }
        .onChange(of: statusFilter) { _, _ in pageIndex = 0 }
        .onChange(of: suppliers) { _, currentSuppliers in
            if let selectedSupplier, !currentSuppliers.contains(selectedSupplier) {
                self.selectedSupplier = nil
            }
        }
        .sheet(item: $exportPreview) { preview in
            MaterialFollowUpExportPreviewView(preview: preview)
        }
    }
}

private struct MaterialFollowUpRowView: View {
    let row: MaterialFollowUpRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.name).font(.body.weight(.medium))
            Text(row.specification.isEmpty ? AppLocalization.string("material_follow_up_unspecified") : row.specification)
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent(AppLocalization.string("供应商"), value: MaterialFollowUpSummary.supplierDisplayName(row.supplier))
            LabeledContent(AppLocalization.string("状态"), value: row.followUpStatus.displayName)
            LabeledContent(AppLocalization.string("material_follow_up_planned"), value: MaterialFollowUpSummary.quantityText(row.planned, unit: row.unit))
            LabeledContent(AppLocalization.string("material_follow_up_received"), value: MaterialFollowUpSummary.quantityText(row.received, unit: row.unit))
            LabeledContent(AppLocalization.string("material_follow_up_remaining"), value: MaterialFollowUpSummary.quantityText(row.remaining, unit: row.unit))
        }
        .font(.subheadline)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct MaterialFollowUpExportPreview: Identifiable {
    let id = UUID()
    let text: String
}

private struct MaterialFollowUpExportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: MaterialFollowUpExportPreview
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(preview.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section {
                    Button {
                        showShare = true
                    } label: {
                        Label(AppLocalization.string("material_follow_up_share_text"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("material-follow-up.share")
                }
            }
            .navigationTitle(AppLocalization.string("material_follow_up_export_preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("完成")) { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityShareSheet(activityItems: [preview.text])
            }
        }
    }
}
