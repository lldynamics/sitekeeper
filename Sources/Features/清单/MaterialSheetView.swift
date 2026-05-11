import SwiftUI
import PhotosUI

// MARK: - Material Sheet Item

struct MaterialSheetItem: Identifiable {
    let id = UUID()
    var name: String
    var specification: String
    var unit: String
    var quantity: String
    var unitPrice: String
    var laborCost: String = ""
    var supplier: String = ""
    var usageLocation: String = ""
    var note: String = ""
    var attachmentData: Data?
    var attachmentFileName: String?

    var hasAttachment: Bool { attachmentData != nil }
    var isExpanded: Bool = false
}

// MARK: - Export Column Toggles

struct MaterialSheetExportOptions {
    var showPrice = true
    var showLabor = false
    var showSupplier = false
    var showLocation = true
    var showNote = false
}

// MARK: - Material Sheet View

struct MaterialSheetView: View {
    @Environment(DataStore.self) private var store
    @State private var sheetItems: [MaterialSheetItem] = []
    @State private var searchText = ""
    @State private var manualName = ""; @State private var manualSpec = ""; @State private var manualUnit = ""
    @State private var manualQty = "1"; @State private var manualPrice = ""; @State private var manualLabor = ""
    @State private var manualSupplier = ""; @State private var manualNote = ""; @State private var manualLocation = ""
    @State private var showManualAdd = false
    @State private var showClearConfirm = false
    @State private var exportFileURL: URL?
    @State private var showExporter = false
    @State private var showExportChoice = false
    @State private var isExporting = false
    @State private var exportOptions = MaterialSheetExportOptions()
    @State private var rowPhotoSelections: [UUID: [PhotosPickerItem]] = [:]
    @State private var itemExpanded: Set<UUID> = []
    @State private var exportProjectName = ""
    @State private var exportPreparer = ""

    private var priceSuggestions: [MaterialPriceEntry] {
        guard !searchText.isEmpty else { return [] }
        return Array(SearchMatcher.filter(store.materialPriceEntries, keyword: searchText).prefix(10))
    }
    private var librarySuggestions: [CommonMaterial] {
        guard !searchText.isEmpty else { return [] }
        return Array(SearchMatcher.filter(MaterialLibrary.all, keyword: searchText).prefix(10))
    }
    private var hasSearchResults: Bool { !priceSuggestions.isEmpty || !librarySuggestions.isEmpty }

    private var totalEstimateValue: MoneyValue {
        sheetItems.reduce(MoneyValue.zero) { total, item in
            total + lineTotalValue(for: item)
        }
    }
    private var totalLaborValue: MoneyValue {
        sheetItems.reduce(MoneyValue.zero) { total, item in
            total + MoneyValue(text: item.laborCost)
        }
    }
    private var grandTotalValue: MoneyValue {
        totalEstimateValue + totalLaborValue
    }
    private var totalEstimate: Double {
        totalEstimateValue.doubleValue
    }
    private var totalLabor: Double {
        totalLaborValue.doubleValue
    }
    private var totalEstimateText: String {
        String(format: "¥%.2f", totalEstimateValue.doubleValue)
    }
    private var totalLaborText: String {
        String(format: "¥%.2f", totalLaborValue.doubleValue)
    }
    private var grandTotalText: String {
        String(format: "¥%.2f", grandTotalValue.doubleValue)
    }

    var body: some View {
        List {
            // Search
            Section("添加材料") {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索材料库或输入新材料名称", text: $searchText).submitLabel(.search)
                }
                if !searchText.isEmpty {
                    if !hasSearchResults {
                        Button {
                            manualName = searchText; manualSpec = ""; manualUnit = ""; manualQty = "1"
                            manualPrice = ""; manualLabor = ""; manualSupplier = ""; manualNote = ""
                            showManualAdd = true
                        } label: { Label("手动添加「\(searchText)」", systemImage: "plus.circle.fill") }
                    }
                    ForEach(priceSuggestions) { librarySearchRow(entry: $0) }
                    ForEach(librarySuggestions) { presetSearchRow(material: $0) }
                }
            }

            // Manual add
            Section {
                Button {
                    manualName = ""; manualSpec = ""; manualUnit = ""; manualQty = "1"
                    manualPrice = ""; manualLabor = ""; manualSupplier = ""; manualNote = ""
                    showManualAdd = true
                } label: { Label("手动输入材料", systemImage: "square.and.pencil") }
            }

            // Sheet items
            Section {
                if sheetItems.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text").font(.system(size: 36)).foregroundStyle(.secondary)
                            Text("材料单为空").foregroundStyle(.secondary)
                            Text("在上方搜索材料库或手动添加").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    ForEach($sheetItems) { $item in materialItemRow($item) }
                        .onDelete { sheetItems.remove(atOffsets: $0) }
                }
            } header: {
                HStack {
                    Text("当前材料单")
                    Spacer()
                    if !sheetItems.isEmpty { Text("\(sheetItems.count) 项").font(.caption).foregroundStyle(.secondary) }
                }
            }

            // Export header info
            if !sheetItems.isEmpty {
                Section("导出表头信息") {
                    TextField("项目名称", text: $exportProjectName)
                    TextField("编制人", text: $exportPreparer)
                    Text("导出日期: \(Formatters.date.string(from: Date()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Export column toggles
            if !sheetItems.isEmpty {
                exportColumnToggleSection
            }

            // Summary
            if totalEstimateValue.isPositive || totalLaborValue.isPositive {
                summarySection
            }

            // Export actions
            if !sheetItems.isEmpty {
                Section("导出与操作") {
                    Button { exportAsPDF() } label: { Label("导出 PDF", systemImage: "doc.richtext.fill") }.disabled(isExporting)
                    Button { exportAsCSV() } label: { Label("导出 CSV", systemImage: "tablecells.fill") }.disabled(isExporting)
                    Button { exportAsImage() } label: { Label("导出图片", systemImage: "photo") }.disabled(isExporting)
                    Button(role: .destructive) { showClearConfirm = true } label: { Label("清空材料单", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("材料单").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sheetItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: exportAsPDF) {
                            Label("导出 PDF", systemImage: "doc.richtext.fill")
                        }
                        Button(action: exportAsCSV) {
                            Label("导出 CSV", systemImage: "tablecells.fill")
                        }
                        Button(action: exportAsImage) {
                            Label("导出图片", systemImage: "photo")
                        }
                        Divider()
                        Button(action: saveSheetToMaterialListAndClear) {
                            Label("保存到材料清单", systemImage: "shippingbox.fill")
                        }
                    } label: {
                        if isExporting { ProgressView().controlSize(.small) }
                        else { Image(systemName: "square.and.arrow.up") }
                    }.disabled(isExporting)
                }
            }
            KeyboardDismissToolbar {
                AppKeyboard.dismiss()
            }
        }
        .confirmationDialog("导出方式", isPresented: $showExportChoice) {
            if let url = exportFileURL {
                Button { showExporter = true } label: { Label("保存到文件", systemImage: "folder") }
                ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
            }
            Button("关闭", role: .cancel) { cleanupExportFileIfNeeded() }
        } message: {
            Text("选择保存位置或分享给其他人")
        }
        .sheet(isPresented: $showExporter) {
            if let exportFileURL {
                FileURLDocumentExporter(fileURL: exportFileURL) { _ in
                    showExporter = false
                    cleanupExportFileIfNeeded()
                }
            } else {
                ProgressView("正在准备导出文件...")
                    .padding()
            }
        }
        .sheet(isPresented: $showManualAdd) { manualAddSheet }
        .alert("清空材料单？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { sheetItems.removeAll() }
        } message: { Text("当前材料单中的 \(sheetItems.count) 项材料将被移除。") }
    }

    private var exportColumnToggleSection: some View {
        Section("导出列设置") {
            Toggle("估价", isOn: $exportOptions.showPrice)
            Toggle("人工费", isOn: $exportOptions.showLabor)
            Toggle("使用部位", isOn: $exportOptions.showLocation)
            Toggle("供应商", isOn: $exportOptions.showSupplier)
            Toggle("备注", isOn: $exportOptions.showNote)
        }
    }

    private var summarySection: some View {
        Section("合计") {
            if totalEstimateValue.isPositive {
                HStack {
                    Text("材料估价").font(.callout)
                    Spacer()
                    Text(totalEstimateText).font(.body.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            if totalLaborValue.isPositive {
                HStack {
                    Text("人工费").font(.callout)
                    Spacer()
                    Text(totalLaborText).font(.body.weight(.semibold)).foregroundStyle(.blue)
                }
            }
            if totalEstimateValue.isPositive, totalLaborValue.isPositive {
                HStack {
                    Text("总计").font(.body.weight(.bold))
                    Spacer()
                    Text(grandTotalText).font(.title3.weight(.bold)).foregroundStyle(.orange)
                }
            }
        }
    }

    private func saveSheetToMaterialListAndClear() {
        saveToMaterialList()
        sheetItems.removeAll()
    }

    private func photoSelectionBinding(for itemId: UUID) -> Binding<[PhotosPickerItem]> {
        Binding(
            get: { rowPhotoSelections[itemId] ?? [] },
            set: { newItems in
                rowPhotoSelections[itemId] = newItems
                guard !newItems.isEmpty else { return }
                Task {
                    await attachSelectedPhoto(itemId: itemId, items: newItems)
                }
            }
        )
    }

    @MainActor
    private func attachSelectedPhoto(itemId: UUID, items: [PhotosPickerItem]) async {
        defer {
            rowPhotoSelections[itemId] = []
        }
        guard let first = items.first else { return }
        guard let data = try? await first.loadTransferable(type: Data.self) else { return }
        guard let idx = sheetItems.firstIndex(where: { $0.id == itemId }) else { return }
        sheetItems[idx].attachmentData = data
        sheetItems[idx].attachmentFileName = "照片.jpg"
    }

    // MARK: - Item Row

    private func materialItemRow(_ item: Binding<MaterialSheetItem>) -> some View {
        let isExpanded = itemExpanded.contains(item.wrappedValue.id)
        return VStack(spacing: 0) {
            // Compact header row
            Button { toggleExpand(item.wrappedValue.id) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.wrappedValue.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                        if !item.wrappedValue.specification.isEmpty {
                            Text(item.wrappedValue.specification).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text(item.wrappedValue.quantity).font(.callout.weight(.semibold)).foregroundStyle(.orange)
                        Text(item.wrappedValue.unit).font(.caption).foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                Divider().padding(.vertical, 6)
                VStack(spacing: 8) {
                    // Price + Labor row
                    HStack(spacing: 10) {
                        TextField("估价 ¥", text: item.unitPrice).keyboardType(.decimalPad)
                            .frame(width: 100).textFieldStyle(.roundedBorder).font(.callout)
                        autoFillButton(for: item)
                        TextField("人工费 ¥", text: item.laborCost).keyboardType(.decimalPad)
                            .frame(width: 100).textFieldStyle(.roundedBorder).font(.callout)
                        Spacer()
                    }

                    // Supplier + Location
                    HStack(spacing: 10) {
                        TextField("供应商", text: item.supplier)
                            .textFieldStyle(.roundedBorder).font(.callout)
                        TextField("使用部位", text: item.usageLocation)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }

                    // Note
                    HStack(spacing: 10) {
                        TextField("备注", text: item.note)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }

                    // Attachment
                    HStack(spacing: 8) {
                        PhotosPicker(selection: photoSelectionBinding(for: item.wrappedValue.id), maxSelectionCount: 1, matching: .images) {
                            Label(item.wrappedValue.hasAttachment ? "已添加照片" : "添加照片",
                                  systemImage: item.wrappedValue.hasAttachment ? "photo.fill" : "photo.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered).controlSize(.small)

                        if item.wrappedValue.hasAttachment {
                            Text(item.wrappedValue.attachmentFileName ?? "附件")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Button {
                                item.wrappedValue.attachmentData = nil
                                item.wrappedValue.attachmentFileName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                            }.buttonStyle(.borderless)
                        }
                        Spacer()
                    }

                    // Delete
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            sheetItems.removeAll { $0.id == item.wrappedValue.id }
                        } label: {
                            Label("删除此项", systemImage: "trash").font(.caption)
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func toggleExpand(_ id: UUID) {
        if itemExpanded.contains(id) { itemExpanded.remove(id) }
        else { itemExpanded.insert(id) }
    }

    @ViewBuilder
    private func autoFillButton(for item: Binding<MaterialSheetItem>) -> some View {
        let name = item.wrappedValue.name
        let spec = item.wrappedValue.specification
        let match = store.materialPriceEntries.first { e in
            e.name.localizedCaseInsensitiveContains(name) && (spec.isEmpty || e.specification.localizedCaseInsensitiveContains(spec))
        }
        let price = match?.referencePrice ?? ""
        if !price.isEmpty, price != item.wrappedValue.unitPrice {
            Button { item.wrappedValue.unitPrice = price } label: {
                Text("¥\(price)").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Search Rows

    private func librarySearchRow(entry: MaterialPriceEntry) -> some View {
        Button {
            addToSheet(name: entry.name, spec: entry.specification, unit: entry.unit, price: entry.referencePrice)
            searchText = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if !entry.specification.isEmpty { Text(entry.specification).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                HStack(spacing: 4) {
                    if !entry.referencePrice.isEmpty { Text("¥\(entry.referencePrice)").font(.caption).foregroundStyle(.orange) }
                    Text(entry.unit).font(.caption).foregroundStyle(.secondary)
                    Text("材料库").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                }
                Image(systemName: "plus.circle.fill").foregroundStyle(.orange).font(.title3)
            }
        }
    }

    private func presetSearchRow(material: CommonMaterial) -> some View {
        Button {
            addToSheet(name: material.name, spec: material.specification, unit: material.unit)
            searchText = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(material.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(material.specification).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(material.unit).font(.caption).foregroundStyle(.secondary)
                    Text("预置材料").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                }
                Image(systemName: "plus.circle.fill").foregroundStyle(.orange).font(.title3)
            }
        }
    }

    // MARK: - Manual Add

    private var manualAddSheet: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("材料名称", text: $manualName)
                    TextField("规格/型号", text: $manualSpec)
                    TextField("单位", text: $manualUnit)
                    TextField("数量", text: $manualQty).keyboardType(.decimalPad)
                }
                Section("费用（选填）") {
                    TextField("估价 ¥", text: $manualPrice).keyboardType(.decimalPad)
                    TextField("人工费 ¥", text: $manualLabor).keyboardType(.decimalPad)
                }
                Section("其他（选填）") {
                    TextField("供应商", text: $manualSupplier)
                    TextField("使用部位", text: $manualLocation)
                    TextField("备注", text: $manualNote)
                }
            }
            .navigationTitle("手动添加").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showManualAdd = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        guard !manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        addToSheet(
                            name: manualName.trimmingCharacters(in: .whitespacesAndNewlines),
                            spec: manualSpec.trimmingCharacters(in: .whitespacesAndNewlines),
                            unit: manualUnit.trimmingCharacters(in: .whitespacesAndNewlines),
                            price: manualPrice.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        if !sheetItems.isEmpty {
                            let q = manualQty.trimmingCharacters(in: .whitespacesAndNewlines)
                            let l = manualLabor.trimmingCharacters(in: .whitespacesAndNewlines)
                            let s = manualSupplier.trimmingCharacters(in: .whitespacesAndNewlines)
                            let loc = manualLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                            let n = manualNote.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !q.isEmpty { sheetItems[sheetItems.count - 1].quantity = q }
                            if !l.isEmpty { sheetItems[sheetItems.count - 1].laborCost = l }
                            if !s.isEmpty { sheetItems[sheetItems.count - 1].supplier = s }
                            if !loc.isEmpty { sheetItems[sheetItems.count - 1].usageLocation = loc }
                            if !n.isEmpty { sheetItems[sheetItems.count - 1].note = n }
                        }
                        showManualAdd = false
                    }.disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }.presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func lineTotalValue(for item: MaterialSheetItem) -> MoneyValue {
        QuantityValue(text: item.quantity) * MoneyValue(text: item.unitPrice)
    }

    private func addToSheet(name: String, spec: String, unit: String, price: String = "") {
        sheetItems.append(MaterialSheetItem(
            name: name, specification: spec, unit: unit,
            quantity: "1", unitPrice: price
        ))
    }

    private func saveToMaterialList() {
        for item in sheetItems {
            let q = item.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalQty: String
            if QuantityValue(text: q).isPositive {
                finalQty = q
            } else {
                finalQty = "1"
            }
            let price = item.unitPrice.trimmingCharacters(in: .whitespacesAndNewlines)
            store.materialItems.append(MaterialItem(
                name: item.name, quantity: finalQty,
                unit: item.unit.isEmpty ? "个" : item.unit,
                unitPrice: price, specification: item.specification
            ))
        }
        store.scheduleSave()
    }

    // MARK: - Export

    private func exportAsPDF() {
        isExporting = true
        defer { isExporting = false }
        let d = generatePDF()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("材料单_\(formattedNow()).pdf")
        do {
            try d.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    private func exportAsCSV() {
        isExporting = true
        defer { isExporting = false }
        let d = Data(generateCSV().utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("材料单_\(formattedNow()).csv")
        do {
            try d.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    private func exportAsImage() {
        isExporting = true
        defer { isExporting = false }
        guard let data = generateImage() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("材料单_\(formattedNow()).png")
        do {
            try data.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    private func generateImage() -> Data? {
        let cols = activeColumns()
        let rh: CGFloat = 24
        let headerH: CGFloat = 120
        let footerH: CGFloat = 76
        let totalH = headerH + CGFloat(sheetItems.count) * rh + footerH
        let totalW: CGFloat = cols.reduce(30) { $0 + $1.1 } + 20

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalW, height: max(totalH, 100)))
        let projectTitle = exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preparer = exportPreparer.trimmingCharacters(in: .whitespacesAndNewlines)
        let exportDate = Formatters.date.string(from: Date())

        return renderer.pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: totalW, height: max(totalH, 100)))
            UIColor.black.setStroke()

            var y: CGFloat = 10
            y = drawImageText("材料单", at: CGPoint(x: 10, y: y), w: totalW - 20, f: .boldSystemFont(ofSize: 22), a: .center) + 4
            if !projectTitle.isEmpty {
                y = drawImageText("项目: \(projectTitle)", at: CGPoint(x: 10, y: y), w: totalW - 20, f: .systemFont(ofSize: 13), a: .center)
            }
            var infoLine = "导出日期: \(exportDate)"
            if !preparer.isEmpty { infoLine += "    编制人: \(preparer)" }
            y = drawImageText(infoLine, at: CGPoint(x: 10, y: y), w: totalW - 20, f: .systemFont(ofSize: 11), a: .center)
            y = drawImageText("共 \(sheetItems.count) 项    \(AppBrand.displayName)", at: CGPoint(x: 10, y: y), w: totalW - 20, f: .systemFont(ofSize: 10), a: .center) + 6
            y = drawImageHeader(cols, x: 10, y: y, h: rh)

            for (i, item) in sheetItems.enumerated() {
                var vs = itemRowValues(item)
                vs[0] = "\(i + 1)"
                y = drawImageRow(vs, cols, x: 10, y: y, h: rh)
            }

            y += 8
            if totalEstimateValue.isPositive || totalLaborValue.isPositive {
                y = drawImageText("总计: ¥\(String(format: "%.2f", grandTotalValue.doubleValue))", at: CGPoint(x: 10, y: y), w: totalW - 20, f: .boldSystemFont(ofSize: 14))
            }
            y += 8
            _ = drawImageText("—— 本材料单由工地掌柜生成 ——", at: CGPoint(x: 10, y: y), w: totalW - 20, f: .systemFont(ofSize: 10), a: .center)
        }
    }

    private func cleanupExportFileIfNeeded() {
        guard let exportFileURL else { return }
        try? FileManager.default.removeItem(at: exportFileURL)
        self.exportFileURL = nil
        showExportChoice = false
    }

    private func drawImageText(_ t: String, at o: CGPoint, w: CGFloat, f: UIFont, a: NSTextAlignment = .left) -> CGFloat {
        let p = NSMutableParagraphStyle(); p.alignment = a; p.lineBreakMode = .byWordWrapping
        let attr = [NSAttributedString.Key.font: f, .paragraphStyle: p, .foregroundColor: UIColor.black]
        let ns = NSAttributedString(string: t, attributes: attr)
        let r = ns.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let h = ceil(r.height); ns.draw(in: CGRect(x: o.x, y: o.y, width: w, height: h))
        return o.y + max(18, h + 4)
    }

    private func drawImageHeader(_ cols: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var cx = x
        let attr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black]
        for c in cols {
            let rect = CGRect(x: cx, y: y, width: c.1, height: h)
            UIBezierPath(rect: rect).stroke()
            NSAttributedString(string: c.0, attributes: attr).draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: rect.height - 8))
            cx += c.1
        }
        return y + h
    }

    private func drawImageRow(_ vs: [String], _ cols: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var cx = x
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        let attr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .paragraphStyle: p, .foregroundColor: UIColor.black]
        for (i, c) in cols.enumerated() {
            let rect = CGRect(x: cx, y: y, width: c.1, height: h)
            UIBezierPath(rect: rect).stroke()
            let v = vs.indices.contains(i) ? vs[i] : ""
            NSAttributedString(string: v, attributes: attr).draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: rect.height - 8))
            cx += c.1
        }
        return y + h
    }

    private func activeColumns() -> [(String, CGFloat)] {
        var cols: [(String, CGFloat)] = [("序号", 30), ("材料名称", 110), ("规格/型号", 64), ("单位", 30), ("数量", 38)]
        if exportOptions.showLocation { cols.append(("使用部位", 60)) }
        if exportOptions.showPrice { cols.append(("单价", 46)); cols.append(("金额", 52)) }
        if exportOptions.showLabor { cols.append(("人工费", 46)) }
        if exportOptions.showSupplier { cols.append(("供应商", 56)) }
        if exportOptions.showNote { cols.append(("备注", 60)) }
        let fixed = cols.dropFirst().reduce(0) { $0 + $1.1 }
        let nameW = max(70, 595 - 60 - fixed)
        cols[1] = ("材料名称", nameW)
        return cols
    }

    private func itemRowValues(_ item: MaterialSheetItem) -> [String] {
        let q = item.quantity; let p = item.unitPrice
        let lineTotal = lineTotalValue(for: item)
        var vs: [String] = ["", item.name, item.specification, item.unit, q]
        if exportOptions.showLocation { vs.append(item.usageLocation.isEmpty ? "-" : item.usageLocation) }
        if exportOptions.showPrice {
            vs.append(p.isEmpty ? "-" : p)
            vs.append(lineTotal.isPositive ? String(format: "%.2f", lineTotal.doubleValue) : "-")
        }
        if exportOptions.showLabor { vs.append(item.laborCost.isEmpty ? "-" : item.laborCost) }
        if exportOptions.showSupplier { vs.append(item.supplier.isEmpty ? "-" : item.supplier) }
        if exportOptions.showNote { vs.append(item.note.isEmpty ? "-" : item.note) }
        return vs
    }

    private func csvHeader() -> String {
        var hdrs = ["序号", "材料名称", "规格/型号", "单位", "数量"]
        if exportOptions.showLocation { hdrs.append("使用部位") }
        if exportOptions.showPrice { hdrs.append(contentsOf: ["单价", "金额"]) }
        if exportOptions.showLabor { hdrs.append("人工费") }
        if exportOptions.showSupplier { hdrs.append("供应商") }
        if exportOptions.showNote { hdrs.append("备注") }
        return hdrs.map { "\"\($0)\"" }.joined(separator: ",")
    }

    private func csvItemRow(_ item: MaterialSheetItem, index: Int) -> String {
        let esc: (String) -> String = { $0.replacingOccurrences(of: "\"", with: "\"\"") }
        let q = item.quantity; let p = item.unitPrice
        let lineTotal = lineTotalValue(for: item)
        var vs = ["\"\(index + 1)\"", "\"\(esc(item.name))\"", "\"\(esc(item.specification))\"", "\"\(esc(item.unit))\"", "\"\(q)\""]
        if exportOptions.showLocation { vs.append("\"\(esc(item.usageLocation))\"") }
        if exportOptions.showPrice {
            vs.append("\"\(p)\"")
            vs.append(lineTotal.isPositive ? "\"\(String(format: "%.2f", lineTotal.doubleValue))\"" : "\"\"")
        }
        if exportOptions.showLabor { vs.append("\"\(item.laborCost)\"") }
        if exportOptions.showSupplier { vs.append("\"\(esc(item.supplier))\"") }
        if exportOptions.showNote { vs.append("\"\(esc(item.note))\"") }
        return vs.joined(separator: ",")
    }

    private func generatePDF() -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let r = UIGraphicsPDFRenderer(bounds: page)
        let m: CGFloat = 30; let mw = page.width - m * 2
        let cols = activeColumns()
        let rh: CGFloat = 22

        let projectTitle = exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preparer = exportPreparer.trimmingCharacters(in: .whitespacesAndNewlines)

        return r.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 30
            y = drawText("材料单", at: CGPoint(x: m, y: y), w: mw, f: .boldSystemFont(ofSize: 20), a: .center) + 4
            if !projectTitle.isEmpty {
                y = drawText("项目: \(projectTitle)", at: CGPoint(x: m, y: y), w: mw, f: .systemFont(ofSize: 11), a: .center)
            }
            var infoLine = "导出日期: \(Formatters.date.string(from: Date()))"
            if !preparer.isEmpty { infoLine += "    编制人: \(preparer)" }
            y = drawText(infoLine, at: CGPoint(x: m, y: y), w: mw, f: .systemFont(ofSize: 9), a: .center)
            y = drawText("共 \(sheetItems.count) 项    \(AppBrand.displayName)", at: CGPoint(x: m, y: y), w: mw, f: .systemFont(ofSize: 8), a: .center) + 10
            y = drawHeader(cols, x: m, y: y, h: rh)

            for (i, item) in sheetItems.enumerated() {
                if y > page.height - 90 { ctx.beginPage(); y = 44; y = drawHeader(cols, x: m, y: y, h: rh) }
                var vs = itemRowValues(item)
                vs[0] = "\(i + 1)"
                y = drawRow(vs, cols, x: m, y: y, h: rh)
            }

            y += 8
            if exportOptions.showPrice, totalEstimateValue.isPositive {
                y = drawText("材料估价合计: ¥\(String(format: "%.2f", totalEstimateValue.doubleValue))", at: CGPoint(x: m, y: y), w: mw, f: .systemFont(ofSize: 10))
            }
            if exportOptions.showLabor, totalLaborValue.isPositive {
                y = drawText("人工费合计: ¥\(String(format: "%.2f", totalLaborValue.doubleValue))", at: CGPoint(x: m, y: y), w: mw, f: .systemFont(ofSize: 10))
            }
            if totalEstimateValue.isPositive || totalLaborValue.isPositive {
                y = drawText("总计: ¥\(String(format: "%.2f", grandTotalValue.doubleValue))", at: CGPoint(x: m, y: y), w: mw, f: .boldSystemFont(ofSize: 12))
            }
            y += 16
            _ = drawText("—— 本材料单由 \(AppBrand.displayName) 生成 ——", at: CGPoint(x: m, y: y), w: mw, f: .systemFont(ofSize: 8), a: .center)
        }
    }

    private func generateCSV() -> String {
        var lines = [csvHeader()]
        for (i, item) in sheetItems.enumerated() {
            lines.append(csvItemRow(item, index: i))
        }
        return lines.joined(separator: "\n")
    }

    private func formattedNow() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f.string(from: Date())
    }

    // MARK: - PDF Helpers

    private func drawText(_ t: String, at o: CGPoint, w: CGFloat, f: UIFont, a: NSTextAlignment = .left) -> CGFloat {
        let p = NSMutableParagraphStyle(); p.alignment = a; p.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: t, attributes: [.font: f, .paragraphStyle: p])
        let r = attr.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let h = ceil(r.height); attr.draw(in: CGRect(x: o.x, y: o.y, width: w, height: h))
        return o.y + max(16, h + 3)
    }

    private func drawHeader(_ cols: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var cx = x
        for c in cols {
            let rect = CGRect(x: cx, y: y, width: c.1, height: h); UIBezierPath(rect: rect).stroke()
            NSAttributedString(string: c.0, attributes: [.font: UIFont.boldSystemFont(ofSize: 9), .foregroundColor: UIColor.black])
                .draw(in: CGRect(x: rect.minX + 3, y: rect.minY + 5, width: rect.width - 6, height: rect.height - 6))
            cx += c.1
        }
        return y + h
    }

    private func drawRow(_ vs: [String], _ cols: [(String, CGFloat)], x: CGFloat, y: CGFloat, h: CGFloat) -> CGFloat {
        var cx = x
        for (i, c) in cols.enumerated() {
            let rect = CGRect(x: cx, y: y, width: c.1, height: h); UIBezierPath(rect: rect).stroke()
            let v = vs.indices.contains(i) ? vs[i] : ""
            let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: v, attributes: [.font: UIFont.systemFont(ofSize: 9), .paragraphStyle: p, .foregroundColor: UIColor.black])
                .draw(in: CGRect(x: rect.minX + 3, y: rect.minY + 5, width: rect.width - 6, height: rect.height - 6))
            cx += c.1
        }
        return y + h
    }
}
