import SwiftUI

struct ProjectFileCategoryView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var searchText = ""
    @State private var healthFilter: ProjectFileHealthFilter = .all
    @State private var previewURL: URL?
    let project: Project
    private let summaryColumns: [GridItem] = [
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading)
    ]

    init(project: Project, initialHealthFilter: ProjectFileHealthFilter = .all) {
        self.project = project
        _healthFilter = State(initialValue: initialHealthFilter)
    }

    private var summary: ProjectFileSummary {
        ProjectFileSummary(projectId: project.id, projectStore: projectStore)
    }

    private var recentItems: [ProjectFileItem] {
        let all = ProjectFileCollector.allItems(for: project.id, projectStore: projectStore)
            .filter { healthFilter.matches($0) }
            .sorted { $0.sortDate > $1.sortDate }
            .prefix(8)
        return SearchMatcher.filter(Array(all), keyword: searchText)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.title3.weight(.semibold))
                            if !project.location.isEmpty {
                                Text(project.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(summary.totalCount)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(summary.totalCount > 0 ? Color.appPrimaryAction : .secondary)
                        Text(AppLocalization.string("个文件"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 8) {
                        ProjectFileCountChip(title: AppLocalization.string("图片"), value: summary.imageCount, color: .appDoc)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProjectFileCountChip(title: AppLocalization.string("图纸"), value: summary.drawingCount, color: .appPrimaryAction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProjectFileCountChip(title: AppLocalization.string("票据"), value: summary.documentCount, color: .appPrimaryAction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProjectFileCountChip(title: AppLocalization.string("附件"), value: summary.quickNoteAttachmentCount, color: .appPrimaryAction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(AppLocalization.string("文件分类")) {
                ForEach(ProjectFileCategory.allCases, id: \.self) { category in
                    let count = summary.count(for: category)
                    NavigationLink {
                        ProjectFileListView(
                            project: project,
                            category: category,
                            initialHealthFilter: healthFilter
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.systemImage)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(category.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.title)
                                    .font(.body.weight(.medium))
                                Text(category.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(count > 0 ? category.tint : .secondary)
                        }
                    }
                }
            }

            ProjectFileHealthFilterSection(selection: $healthFilter)

            if !recentItems.isEmpty {
                Section(AppLocalization.string("最近文件")) {
                    ForEach(recentItems) { item in
                        ProjectFileItemRow(item: item) {
                            previewURL = item.url
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索本项目的文件")
        .appFilePreview($previewURL)
    }
}
