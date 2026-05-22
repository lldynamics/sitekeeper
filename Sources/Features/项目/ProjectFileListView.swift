import SwiftUI
import QuickLook

struct ProjectFileListView: View {
    let project: Project
    let category: ProjectFileCategory
    @Environment(ProjectStore.self) private var projectStore
    @State private var healthFilter: ProjectFileHealthFilter = .all
    @State private var previewURL: URL?

    init(
        project: Project,
        category: ProjectFileCategory,
        initialHealthFilter: ProjectFileHealthFilter = .all
    ) {
        self.project = project
        self.category = category
        _healthFilter = State(initialValue: initialHealthFilter)
    }

    private var rawItems: [ProjectFileItem] {
        ProjectFileCollector.items(for: project.id, category: category, projectStore: projectStore)
    }

    private var items: [ProjectFileItem] {
        rawItems.filter { healthFilter.matches($0) }
    }

    private var missingItemCount: Int {
        items.reduce(0) { result, item in
            result + (item.exists ? 0 : 1)
        }
    }

    private var emptyDescription: String {
        switch category {
        case .images:
            return String(localized: "先去施工日志或随手记添加照片，这里会按项目自动汇总。")
        case .drawings:
            return String(localized: "先去项目详情导入图纸原件；DWG/DXF 后续通过外部专业看图软件打开。")
        case .documents:
            return String(localized: "先去项目详情添加票据或扫描资料。")
        case .quickNoteAttachments:
            return String(localized: "先去随手记添加视频或文档附件。")
        }
    }

    private var emptyActionTitle: String {
        switch category {
        case .images:
            return String(localized: "去写日志并添加照片")
        case .drawings:
            return String(localized: "去项目详情导入图纸原件")
        case .documents:
            return String(localized: "去项目详情添加资料")
        case .quickNoteAttachments:
            return String(localized: "去随手记添加附件")
        }
    }

    @ViewBuilder
    private var emptyActionDestination: some View {
        switch category {
        case .images:
            DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
        case .drawings:
            ProjectDetailView(projectId: project.id, initialMode: .assets)
        case .documents:
            ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
        case .quickNoteAttachments:
            QuickNoteView()
        }
    }

    var body: some View {
        List {
            if !rawItems.isEmpty {
                ProjectFileHealthFilterSection(selection: $healthFilter)
            }

            if rawItems.isEmpty {
                Section(String(localized: "建议下一步")) {
                    AppActionableEmptyState(
                        title: String(format: String(localized: "暂无%@"), category.title),
                        systemImage: category.systemImage,
                        message: emptyDescription
                    ) {
                        NavigationLink {
                            emptyActionDestination
                        } label: {
                            Label(emptyActionTitle, systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appProminent())
                    }
                }
            } else if items.isEmpty {
                Section(String(localized: "筛选结果")) {
                    AppActionableEmptyState(
                        title: String(localized: "没有匹配文件"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        message: String(localized: "当前筛选下没有文件。")
                    ) {
                        Button {
                            healthFilter = .all
                        } label: {
                            Label(String(localized: "查看全部文件"), systemImage: "tray.full")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appProminent())
                    }
                }
            } else {
                if missingItemCount > 0 {
                    Section(String(localized: "建议下一步")) {
                        ProjectFileMicroGuideRow(
                            icon: "exclamationmark.triangle.fill",
                            color: .appRisk,
                            title: String(
                                format: String(localized: "本分类有 %lld 个文件缺失"),
                                Int64(missingItemCount)
                            ),
                            detail: category == .drawings
                                ? String(localized: "建议尽快补齐，避免外部打开、分享或导出时失败。")
                                : String(localized: "建议尽快补齐，避免预览、分享或导出时失败。")
                        )
                        NavigationLink {
                            emptyActionDestination
                        } label: {
                            Label(emptyActionTitle, systemImage: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("\(project.name) · \(category.title)") {
                    ForEach(items) { item in
                        ProjectFileItemRow(item: item) {
                            previewURL = item.url
                        }
                    }
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
    }
}
