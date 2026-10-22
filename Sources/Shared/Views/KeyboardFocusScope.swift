import SwiftUI

struct KeyboardFocusScope<Field: Hashable, Content: View>: View {
    @FocusState private var focusedField: Field?
    private let content: (FocusState<Field?>.Binding, Field?) -> Content

    init(
        _: Field.Type,
        @ViewBuilder content: @escaping (FocusState<Field?>.Binding, Field?) -> Content
    ) {
        self.content = content
    }

    var body: some View {
        content($focusedField, focusedField)
    }
}
