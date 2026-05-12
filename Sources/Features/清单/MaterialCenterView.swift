import SwiftUI

enum MaterialCenterTab: String, CaseIterable, Hashable {
    case warehouse = "仓库"
    case sheet = "材料单"
    case library = "材料库"
}

struct MaterialCenterView: View {
    @State private var selectedTab: MaterialCenterTab

    init(initialTab: MaterialCenterTab = .warehouse) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: AppSpacing.normal) {
            Picker("材料中心", selection: $selectedTab) {
                ForEach(MaterialCenterTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
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
        .navigationTitle("材料中心")
        .navigationBarTitleDisplayMode(.inline)
    }
}
