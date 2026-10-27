import SwiftUI

enum WidgetDeepLinkDestination: Identifiable, Equatable {
    case todos
    case lowStock
    case missingReceipt
    case backupOverdue
    case priceSpike
    case project(UUID)

    var id: String {
        switch self {
        case .todos:
            return "todos"
        case .lowStock:
            return "low-stock"
        case .missingReceipt:
            return "missing-receipt"
        case .backupOverdue:
            return "backup-overdue"
        case .priceSpike:
            return "price-spike"
        case .project(let projectId):
            return "project-\(projectId.uuidString)"
        }
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "sitekeeper",
              url.host?.lowercased() == "widget" else {
            return nil
        }
        let route = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch route {
        case "todos":
            self = .todos
        case "low-stock":
            self = .lowStock
        case "missing-receipt":
            self = .missingReceipt
        case "backup-overdue":
            self = .backupOverdue
        case "price-spike":
            self = .priceSpike
        case "project":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let projectIDText = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let projectID = UUID(uuidString: projectIDText) else {
                return nil
            }
            self = .project(projectID)
        default:
            return nil
        }
    }
}

enum Tab: Hashable, CaseIterable, Identifiable {
    case dashboard
    case records
    case checklist
    case quickNote
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard:
            return AppLocalization.string("工作台")
        case .records:
            return AppLocalization.string("项目")
        case .checklist:
            return AppLocalization.string("工具箱")
        case .quickNote:
            return AppLocalization.string("随手记")
        case .profile:
            return AppLocalization.string("我的")
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "house.fill"
        case .records:
            return "building.2.fill"
        case .checklist:
            return "books.vertical.fill"
        case .quickNote:
            return "square.and.pencil"
        case .profile:
            return "person.circle"
        }
    }
}

struct FirstLaunchOnboardingView: View {
    let onCreateProject: () -> Void
    let onImportBackup: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 0)
                Text("\(AppLocalization.string("欢迎使用")) \(AppBrand.displayName)")
                    .font(.largeTitle.bold())
                Text(AppLocalization.string("首次打开建议先选择一个开始方式"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(AppLocalization.string("数据默认保存在本机，可随时手动导出完整 ZIP 备份"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    Button(action: onCreateProject) {
                        actionRow(
                            title: AppLocalization.string("新建项目"),
                            subtitle: AppLocalization.string("从空白开始创建你的第一个工程"),
                            icon: "building.2.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appPrimaryAction)
                    .accessibilityIdentifier("onboarding-create-project")
                    Button(action: onImportBackup) {
                        actionRow(
                            title: AppLocalization.string("导入备份"),
                            subtitle: AppLocalization.string("从 ZIP 恢复已有项目数据"),
                            icon: "square.and.arrow.down.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    Button(AppLocalization.string("稍后设置"), action: onSkip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding-skip")
                }
                .buttonBorderShape(.roundedRectangle)
                Spacer()
            }
            .padding(20)
            .navigationTitle(AppLocalization.string("首次设置"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func actionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
            }
            Spacer()
        }
    }
}
