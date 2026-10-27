import SwiftUI

extension Text {
    init(_ value: BusinessDateValue) {
        self.init(verbatim: Formatters.displayDateText(value))
    }

    /// Raw numeric text belongs to the presentation boundary. Currency labels
    /// use the currency formatter; input fields keep their own editable String.
    init<Value: DecimalDomainValue>(_ value: Value) {
        self.init(verbatim: value.wireText)
    }
}

extension Binding where Value == BusinessDateValue {
    var daySelection: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.date() ?? Calendar.current.startOfDay(for: Date()) },
            set: { wrappedValue = .day(CalendarDay(date: $0)) }
        )
    }

    var instantSelection: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.date() ?? Date() },
            set: { wrappedValue = .instant($0) }
        )
    }

    /// Editable text exists only at the form boundary. Partial/unknown input is
    /// retained explicitly rather than substituting a fabricated date.
    var dateInputText: Binding<String> {
        Binding<String>(
            get: { wrappedValue.storageText },
            set: { wrappedValue = BusinessDateValue(legacyText: $0) }
        )
    }
}

extension LabeledContent where Label == Text, Content == Text {
    init(_ title: String, value: BusinessDateValue) {
        self.init(title, value: Formatters.displayDateText(value))
    }
}

extension LocalizedStringKey.StringInterpolation {
    mutating func appendInterpolation(_ value: BusinessDateValue) {
        appendInterpolation(Formatters.displayDateText(value))
    }

    mutating func appendInterpolation<Value: DecimalDomainValue>(_ value: Value) {
        appendInterpolation(value.wireText)
    }
}
