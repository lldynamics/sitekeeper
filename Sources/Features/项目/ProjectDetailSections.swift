import SwiftUI

struct ProjectOverviewView<LogRowContent: View>: View {
    let project: Project
    let paidAmount: Double
    let unpaidAmount: Double
    let materialCost: Double
    let laborCost: Double
    let estimatedProfit: Double
    let laborHours: String
    let projectBookIncome: Double
    let projectBookExpense: Double
    let logDayCount: Int
    let materialCount: Int
    let contactCount: Int
    let financialCount: Int
    let documentCount: Int
    let recentLogs: [DailyLog]
    let todos: [SiteTodo]
    let logRow: (DailyLog) -> LogRowContent

    var body: some View {
        Group {
            Section("经营概览") {
                LabeledContent("合同金额", value: ReportBuilder.money(ReportBuilder.number(project.contractAmount)))
                LabeledContent("已收款", value: ReportBuilder.money(paidAmount))
                LabeledContent("未收款", value: ReportBuilder.money(unpaidAmount))
                LabeledContent("收款状态", value: paymentStatus.displayName)
                LabeledContent("材料成本", value: ReportBuilder.money(materialCost))
                LabeledContent("人工成本", value: ReportBuilder.money(laborCost))
                LabeledContent("毛利估算", value: ReportBuilder.money(estimatedProfit))
                LabeledContent("人工工时", value: laborHours)
                LabeledContent("零星收入", value: ReportBuilder.money(projectBookIncome))
                LabeledContent("零星支出", value: ReportBuilder.money(projectBookExpense))
                LabeledContent("日志天数", value: "\(logDayCount)")
                LabeledContent("材料项", value: "\(materialCount)")
                LabeledContent("联系人", value: "\(contactCount)")
                LabeledContent("记账笔数", value: "\(financialCount)")
                LabeledContent("票据/资料", value: "\(documentCount)")
            }

            Section("最近日志") {
                if recentLogs.isEmpty {
                    Text("暂无施工日志").foregroundStyle(.secondary)
                } else {
                    ForEach(recentLogs.sorted { $0.date > $1.date }.prefix(3)) { log in
                        logRow(log)
                    }
                }
            }

            Section("现场待办") {
                if todos.isEmpty {
                    Text("暂无未完成待办").foregroundStyle(.secondary)
                } else {
                    ForEach(todos.prefix(4)) { todo in
                        HStack {
                            Text(todo.title).font(.callout)
                            Spacer()
                            Text(todo.isOverdue ? "延期" : todo.dueDate)
                                .font(.caption)
                                .foregroundStyle(todo.isOverdue ? .red : .secondary)
                        }
                    }
                }
            }
        }
    }

    private var paymentStatus: PaymentStatus {
        let contract = ReportBuilder.number(project.contractAmount)
        if paidAmount <= 0 { return .unpaid }
        if contract > 0, paidAmount >= contract { return .paid }
        if contract <= 0 { return .partial }
        return .partial
    }
}

struct ProjectBookkeepingView: View {
    let records: [ProjectFinancialRecord]
    let linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    let onEdit: (ProjectFinancialRecord) -> Void
    let onDelete: (Set<UUID>) -> Void
    let onAddRecord: () -> Void

    @State private var directionFilter: BookDirectionFilter = .all
    @State private var categoryFilter: BookCategoryFilter = .all
    @State private var attachmentFilter: BookAttachmentFilter = .all
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        Group {
            Section("账目操作") {
                Button {
                    onAddRecord()
                } label: {
                    Label("新增账目", systemImage: "plus.circle.fill")
                }
            }

            Section("项目财务汇总") {
                LabeledContent("收入", value: ReportBuilder.money(totalIncome))
                LabeledContent("支出", value: ReportBuilder.money(totalExpense))
                LabeledContent("净额", value: ReportBuilder.money(totalIncome - totalExpense))
                LabeledContent("未附票据", value: "\(unattachedCount) 笔")
            }

            Section("筛选") {
                Picker("收支", selection: $directionFilter) {
                    ForEach(BookDirectionFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Picker("票据类型", selection: $categoryFilter) {
                    ForEach(BookCategoryFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Picker("票据附件", selection: $attachmentFilter) {
                    ForEach(BookAttachmentFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Toggle("限定日期范围", isOn: $useDateRange)
                if useDateRange {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, displayedComponents: .date)
                }
            }

            Section("项目财务流水 (\(filteredRecords.count))") {
                if filteredRecords.isEmpty {
                    Text("当前筛选下暂无记录").foregroundStyle(.secondary)
                } else {
                    ForEach(filteredRecords) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.date).font(.callout.weight(.medium))
                                    Text(record.category)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(record.direction) \(ReportBuilder.money(ReportBuilder.number(record.amount)))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(record.direction == ProjectFinancialDirection.income.rawValue ? .green : .red)
                                }
                                HStack(spacing: 8) {
                                    if !record.counterparty.isEmpty { Text(record.counterparty) }
                                    if !record.invoiceNumber.isEmpty { Text("票号 \(record.invoiceNumber)") }
                                    if !linkedDocuments(record).isEmpty { Text("已附票据\(linkedDocuments(record).count)") }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                if !record.note.isEmpty {
                                    Text(record.note).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { filteredRecords.indices.contains($0) ? filteredRecords[$0].id : nil }
                        onDelete(Set(ids))
                    }
                }
            }
        }
    }

    private var filteredRecords: [ProjectFinancialRecord] {
        records.filter { record in
            if !directionFilter.matches(record) { return false }
            if !categoryFilter.matches(record) { return false }
            if !attachmentFilter.matches(record, linkedDocuments: linkedDocuments) { return false }
            if useDateRange {
                guard let date = Formatters.date.date(from: record.date) else { return false }
                let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                if date < startDate || date > endOfDay { return false }
            }
            return true
        }
    }

    private var totalIncome: Double {
        records
            .filter { $0.direction == ProjectFinancialDirection.income.rawValue }
            .reduce(0) { $0 + ReportBuilder.number($1.amount) }
    }

    private var totalExpense: Double {
        records
            .filter { $0.direction == ProjectFinancialDirection.expense.rawValue }
            .reduce(0) { $0 + ReportBuilder.number($1.amount) }
    }

    private var unattachedCount: Int {
        records.filter { $0.requiresAttachment && linkedDocuments($0).isEmpty }.count
    }
}

private enum BookDirectionFilter: String, CaseIterable {
    case all
    case income
    case expense

    var displayName: String {
        switch self {
        case .all: "全部"
        case .income: "收入"
        case .expense: "支出"
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .income:
            return record.direction == ProjectFinancialDirection.income.rawValue
        case .expense:
            return record.direction == ProjectFinancialDirection.expense.rawValue
        }
    }
}

private enum BookCategoryFilter: String, CaseIterable {
    case all
    case invoice
    case receipt

    var displayName: String {
        switch self {
        case .all: "全部"
        case .invoice: "发票"
        case .receipt: "收据"
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .invoice:
            return record.category == ProjectFinancialCategory.invoice.rawValue
        case .receipt:
            return record.category == ProjectFinancialCategory.receipt.rawValue
        }
    }
}

private enum BookAttachmentFilter: String, CaseIterable {
    case all
    case attached
    case unattached

    var displayName: String {
        switch self {
        case .all: "全部"
        case .attached: "已附票据"
        case .unattached: "未附票据"
        }
    }

    func matches(
        _ record: ProjectFinancialRecord,
        linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .attached:
            return !linkedDocuments(record).isEmpty
        case .unattached:
            return record.requiresAttachment && linkedDocuments(record).isEmpty
        }
    }
}

struct ProjectDocumentsView: View {
    let documents: [ProjectDocument]
    let icon: (String) -> String
    let onOpen: (ProjectDocument) -> Void
    @State private var categoryFilter: DocumentCategoryFilter = .all
    @State private var relationFilter: DocumentRelationFilter = .all
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var minAmount = ""
    @State private var maxAmount = ""

    private var filteredDocuments: [ProjectDocument] {
        documents.filter { document in
            if !categoryFilter.matches(document) { return false }
            if !relationFilter.matches(document) { return false }
            if useDateRange {
                guard let date = parseDate(document.createdAt) else { return false }
                let start = Calendar.current.startOfDay(for: min(startDate, endDate))
                let endStart = Calendar.current.startOfDay(for: max(startDate, endDate))
                let end = Calendar.current.date(byAdding: .day, value: 1, to: endStart) ?? endStart
                if date < start || date >= end { return false }
            }
            let amount = ReportBuilder.number(document.amount)
            if !minAmount.isEmpty && amount < ReportBuilder.number(minAmount) { return false }
            if !maxAmount.isEmpty && amount > ReportBuilder.number(maxAmount) { return false }
            return true
        }
    }

    var body: some View {
        Group {
            Section("资料筛选") {
                Button {
                    showFilterSheet = true
                } label: {
                    HStack {
                        Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                        Spacer()
                        Text(filterSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if hasActiveFilters {
                    Button("清除筛选") {
                        resetFilters()
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Section("票据与项目资料 (\(filteredDocuments.count))") {
                if filteredDocuments.isEmpty {
                    Text("暂无扫描件").foregroundStyle(.secondary)
                } else {
                    ForEach(filteredDocuments) { document in
                        Button {
                            onOpen(document)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(document.category))
                                    .foregroundStyle(.indigo)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(document.title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text(document.category)
                                        Text("\(document.pageCount) 页")
                                        if ReportBuilder.number(document.amount) > 0 {
                                            Text(ReportBuilder.money(ReportBuilder.number(document.amount)))
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    Text(document.createdAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            NavigationStack {
                Form {
                    filterForm
                }
                .navigationTitle("资料筛选")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("重置") {
                            resetFilters()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            showFilterSheet = false
                        }
                    }
                }
            }
        }
    }

    @State private var showFilterSheet = false

    @ViewBuilder
    private var filterForm: some View {
        Section("类型") {
            Picker("资料类型", selection: $categoryFilter) {
                ForEach(DocumentCategoryFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            Picker("关联状态", selection: $relationFilter) {
                ForEach(DocumentRelationFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
        Section("日期") {
            Toggle("限定日期范围", isOn: $useDateRange)
            if useDateRange {
                DatePicker("开始", selection: $startDate, displayedComponents: .date)
                DatePicker("结束", selection: $endDate, displayedComponents: .date)
            }
        }
        Section("金额") {
            LabeledContent("最小金额") {
                TextField("0", text: $minAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("最大金额") {
                TextField("不限", text: $maxAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var hasActiveFilters: Bool {
        categoryFilter != .all || relationFilter != .all || useDateRange || !minAmount.isEmpty || !maxAmount.isEmpty
    }

    private var filterSummary: String {
        guard hasActiveFilters else { return "全部资料" }
        var parts: [String] = []
        if categoryFilter != .all { parts.append(categoryFilter.displayName) }
        if relationFilter != .all { parts.append(relationFilter.displayName) }
        if useDateRange { parts.append("日期") }
        if !minAmount.isEmpty || !maxAmount.isEmpty { parts.append("金额") }
        return parts.joined(separator: " · ")
    }

    private func resetFilters() {
        categoryFilter = .all
        relationFilter = .all
        useDateRange = false
        minAmount = ""
        maxAmount = ""
    }

    private func parseDate(_ text: String) -> Date? {
        if let dt = Formatters.dateTime.date(from: text) {
            return dt
        }
        return Formatters.date.date(from: text)
    }
}

private enum DocumentCategoryFilter: String, CaseIterable {
    case all
    case invoice
    case receipt
    case construction

    var displayName: String {
        switch self {
        case .all: "全部"
        case .invoice: "发票"
        case .receipt: "收据"
        case .construction: "施工资料"
        }
    }

    func matches(_ document: ProjectDocument) -> Bool {
        switch self {
        case .all:
            return true
        case .invoice:
            return document.category == ProjectDocumentCategory.invoice.rawValue
        case .receipt:
            return document.category == ProjectDocumentCategory.receipt.rawValue
        case .construction:
            return document.category == ProjectDocumentCategory.construction.rawValue
        }
    }
}

private enum DocumentRelationFilter: String, CaseIterable {
    case all
    case linked
    case unlinked

    var displayName: String {
        switch self {
        case .all: "全部"
        case .linked: "已关联账目"
        case .unlinked: "未关联账目"
        }
    }

    func matches(_ document: ProjectDocument) -> Bool {
        switch self {
        case .all:
            return true
        case .linked:
            return document.linkedFinancialRecordId != nil
        case .unlinked:
            return document.linkedFinancialRecordId == nil
        }
    }
}

struct ProjectContactsView: View {
    let contacts: [ProjectContact]
    let onAdd: () -> Void
    let onEdit: (ProjectContact) -> Void
    let onDelete: (Set<UUID>) -> Void
    @State private var roleFilter = "全部"

    private var roleOptions: [String] {
        ["全部"] + Set(contacts.map(\.role).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).sorted()
    }

    var body: some View {
        Group {
            Section("联系人操作") {
                Button(action: onAdd) {
                    Label("添加联系人", systemImage: "person.crop.circle.badge.plus")
                }
            }

            Section(String(localized: "联系人 (\(filteredContacts.count))")) {
                Picker("角色筛选", selection: $roleFilter) {
                    ForEach(roleOptions, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                if filteredContacts.isEmpty {
                    ContentUnavailableView(
                        "暂无联系人",
                        systemImage: "person.crop.circle",
                        description: Text("记录客户、监理、供应商和施工班组等联系人。")
                    )
                    Button(action: onAdd) {
                        Label("添加联系人", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    ForEach(filteredContacts) { contact in
                        Button {
                            onEdit(contact)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(contact.name).font(.callout.weight(.medium))
                                    Text(contact.role)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.blue)
                                    Spacer()
                                    contactActionLinks(phone: contact.phone)
                                }
                                if !contact.company.isEmpty || !contact.note.isEmpty {
                                    Text([contact.company, contact.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { filteredContacts.indices.contains($0) ? filteredContacts[$0].id : nil }
                        onDelete(Set(ids))
                    }
                }
            }
        }
    }

    private var filteredContacts: [ProjectContact] {
        guard roleFilter != "全部" else { return contacts }
        return contacts.filter { $0.role == roleFilter }
    }

    @ViewBuilder
    private func contactActionLinks(phone: String) -> some View {
        let tel = telURL(for: phone)
        let sms = smsURL(for: phone)
        if tel != nil || sms != nil {
            HStack(spacing: 10) {
                if let tel {
                    Link(destination: tel) {
                        Image(systemName: "phone.fill")
                    }
                }
                if let sms {
                    Link(destination: sms) {
                        Image(systemName: "message.fill")
                    }
                }
            }
        }
    }

    private func telURL(for phone: String) -> URL? {
        let cleaned = normalizedPhone(phone)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel:\(cleaned)")
    }

    private func smsURL(for phone: String) -> URL? {
        let cleaned = normalizedPhone(phone)
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "sms:\(cleaned)")
    }

    private func normalizedPhone(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let allowed = Set("+0123456789")
        var filtered = String(trimmed.filter { allowed.contains($0) })
        guard !filtered.isEmpty else { return "" }

        let hasLeadingPlus = filtered.first == "+"
        filtered.removeAll { $0 == "+" }
        guard !filtered.isEmpty else { return "" }

        return hasLeadingPlus ? "+\(filtered)" : filtered
    }
}
