import SwiftUI

enum ProjectDetailScrollTracking {
    static let coordinateSpaceName = "project-detail-scroll"
    static let topThreshold: CGFloat = 140

    static func currentAnchor(from offsets: [ProjectDetailAnchor: CGFloat]) -> ProjectDetailAnchor? {
        guard !offsets.isEmpty else { return nil }
        let sorted = offsets.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }
        if let passedTop = sorted
            .filter({ $0.value <= topThreshold })
            .max(by: { $0.value < $1.value })?.key {
            return passedTop
        }
        return sorted.first?.key
    }
}

struct ProjectDetailAnchorOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: [ProjectDetailAnchor: CGFloat] = [:]

    static func reduce(value: inout [ProjectDetailAnchor: CGFloat], nextValue: () -> [ProjectDetailAnchor: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Scroll targets belong to real sections. A standalone zero-height List row
/// still receives the system's minimum row height and grouped card background.
struct ProjectDetailAnchoredSection<Content: View>: View {
    let title: String
    let anchor: ProjectDetailAnchor
    @ViewBuilder let content: () -> Content

    init(_ title: String, anchor: ProjectDetailAnchor, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.anchor = anchor
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .id(anchor.scrollID)
                .accessibilityIdentifier("project-detail-section-\(anchor.rawValue)")
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ProjectDetailAnchorOffsetPreferenceKey.self,
                            value: [anchor: proxy.frame(in: .named(ProjectDetailScrollTracking.coordinateSpaceName)).minY]
                        )
                    }
                }
        }
    }
}
