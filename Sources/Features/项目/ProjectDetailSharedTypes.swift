import SwiftUI

enum ProjectDateInput {
    static func date(from text: String) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Formatters.parseDateOrDateTime(normalized)
    }

    static func string(from date: Date) -> String {
        Formatters.date.string(from: date)
    }

    static func normalizedStorageText(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        return date(from: normalized).map(string(from:)) ?? normalized
    }
}

struct OptionalProjectDatePicker: View {
    private let title: String
    private let emptyToggleTitle: String
    @Binding private var text: String
    @State private var hasDate: Bool
    @State private var selectedDate: Date

    init(_ title: String, text: Binding<String>, defaultDate: Date = Date()) {
        self.title = title
        self.emptyToggleTitle = String(format: String(localized: "填写%@"), title)
        _text = text
        let parsed = ProjectDateInput.date(from: text.wrappedValue)
        _hasDate = State(initialValue: parsed != nil)
        _selectedDate = State(initialValue: parsed ?? defaultDate)
    }

    var body: some View {
        Toggle(emptyToggleTitle, isOn: Binding(
            get: { hasDate },
            set: { newValue in
                hasDate = newValue
                text = newValue ? ProjectDateInput.string(from: selectedDate) : ""
            }
        ))
        if hasDate {
            DatePicker(title, selection: Binding(
                get: { selectedDate },
                set: { newValue in
                    selectedDate = newValue
                    text = ProjectDateInput.string(from: newValue)
                }
            ), displayedComponents: .date)
            .onAppear {
                text = ProjectDateInput.string(from: selectedDate)
            }
        }
    }
}

enum ProjectDetailMode: String, CaseIterable {
    case overview
    case records
    case assets
    case finance
    case timeline

    static var allCases: [ProjectDetailMode] {
        [.overview, .records, .assets, .finance, .timeline]
    }

    var displayName: String {
        switch self {
        case .overview: String(localized: "概览")
        case .records: String(localized: "现场")
        case .assets: String(localized: "资料")
        case .finance: String(localized: "成本")
        case .timeline: String(localized: "时间线")
        }
    }
}

enum ProjectFinanceJumpFilter: Equatable {
    case none
    case unsettled
    case missingReceipt
}

enum DrawingListFilter: String, CaseIterable {
    case all
    case current
    case withIssue

    var displayName: String {
        switch self {
        case .all: String(localized: "台账")
        case .current: String(localized: "当前版")
        case .withIssue: String(localized: "有问题")
        }
    }
}

struct ProjectPhotoItem: Identifiable {
    var id: UUID { photo.id }
    let logId: UUID
    let date: String
    let photo: LogPhoto
}

struct ProjectPhotoContext: Identifiable {
    var id: String { "\(logId.uuidString)-\(photoId.uuidString)" }
    let logId: UUID
    let photoId: UUID
    let legacyFileName: String
}

struct DrawingTimelineContext: Identifiable {
    var id: String { name }
    let name: String
}
