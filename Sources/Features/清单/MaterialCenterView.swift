import SwiftUI

enum MaterialCenterTab: String, CaseIterable, Hashable {
    case warehouse
    case sheet
    case library

    var displayName: String {
        switch self {
        case .warehouse:
            return String(localized: "仓库")
        case .sheet:
            return String(localized: "材料单")
        case .library:
            return String(localized: "材料库")
        }
    }
}

struct MaterialCenterView: View {
    @State private var selectedTab: MaterialCenterTab

    init(initialTab: MaterialCenterTab = .warehouse) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: AppSpacing.normal) {
            Picker(String(localized: "材料中心"), selection: $selectedTab) {
                ForEach(MaterialCenterTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch selectedTab {
                case .warehouse:
                    ProjectWarehouseOverviewView()
                case .sheet:
                    MaterialSheetView()
                case .library:
                    MaterialLibraryView()
                }
            }
            .id(selectedTab)
        }
        .navigationTitle(String(localized: "材料中心"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
