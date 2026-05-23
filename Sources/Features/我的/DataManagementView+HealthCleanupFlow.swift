import SwiftUI

extension DataManagementView {
    func refreshRiskSnapshot() {
        cleanupTrashBatchCount = StorageCleanupTrashStore.loadBatches().count
        store.scheduleDataHealthScanIfStale(reason: .scheduled)
    }

    var healthAndCleanupContent: some View {
        VStack(spacing: usesWideLayout ? AppSpacing.normal : AppSpacing.tight) {
            Picker(String(localized: "体检与清理"), selection: $healthCleanupSection) {
                ForEach(HealthCleanupSection.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if usesWideLayout {
                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    Image(systemName: healthCleanupSection.icon)
                        .foregroundStyle(.appWarning)
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)
                    Text(healthCleanupSection.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            Group {
                switch healthCleanupSection {
                case .health:
                    DataHealthView(showsNavigationTitle: false)
                case .storage:
                    StorageCleanupCenterView(showsNavigationTitle: false)
                case .audit:
                    OperationAuditLogView(showsNavigationTitle: false)
                }
            }
            .id(healthCleanupSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
