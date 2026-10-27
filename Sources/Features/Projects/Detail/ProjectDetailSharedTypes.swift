import SwiftUI

struct OptionalProjectDatePicker: View {
    private let title: String
    private let emptyToggleTitle: String
    @Binding private var value: BusinessDateValue
    private let defaultDate: Date

    init(_ title: String, value: Binding<BusinessDateValue>, defaultDate: Date = Date()) {
        self.title = title
        self.emptyToggleTitle = String(format: AppLocalization.string("填写%@"), title)
        _value = value
        self.defaultDate = defaultDate
    }

    var body: some View {
        Toggle(emptyToggleTitle, isOn: Binding(
            get: { !value.isEmpty },
            set: { value = $0 ? .day(CalendarDay(date: defaultDate)) : .empty }
        ))
        if !value.isEmpty {
            DatePicker(title, selection: $value.daySelection, displayedComponents: .date)
            if !value.isResolved {
                Text(value.storageText).font(.caption).foregroundStyle(.secondary)
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
        case .overview: AppLocalization.string("概览")
        case .records: AppLocalization.string("现场")
        case .assets: AppLocalization.string("资料")
        case .finance: AppLocalization.string("成本")
        case .timeline: AppLocalization.string("时间线")
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
        case .all: AppLocalization.string("台账")
        case .current: AppLocalization.string("当前版")
        case .withIssue: AppLocalization.string("有问题")
        }
    }
}

struct ProjectPhotoItem: Identifiable {
    var id: UUID { photo.id }
    let logId: UUID
    let date: BusinessDateValue
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
