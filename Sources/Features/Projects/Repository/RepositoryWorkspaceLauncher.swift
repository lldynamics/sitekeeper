import SwiftUI

struct RepositoryWorkspaceLauncher: View {
    @Environment(DataStore.self) private var store
    @State private var entries: [RepositoryWorkspaceEntry] = []
    @State private var session: RepositoryWorkspaceSession?
    @State private var activeRepository: SQLiteBusinessRepository?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var pendingDeletion: RepositoryWorkspaceEntry?
    @State private var showDeleteConfirmation = false
    @State private var exportFileURL: URL?
    @State private var showExporter = false
    @State private var exportSummary = ""
    private let catalog = RepositoryWorkspaceCatalog()

    var body: some View {
        List {
            Section {
                Text(AppLocalization.string("在独立副本中试用项目、日志、财务、仓储、材料清单与报价单。修改仅保存在所选副本中；原应用数据继续独立使用。"))
                Text(AppLocalization.string("副本保留附件引用，当前支持文字编辑。副本不包含附件文件，也不属于完整备份。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(AppLocalization.string("从当前数据创建副本")) { Task { await create() } }
                    .accessibilityIdentifier("repository-workspace-create")
                    .disabled(isBusy || store.loadState != .ready || store.isApplyingBackup)
            }
            Section(AppLocalization.string("继续使用已有副本")) {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            }
            if isBusy { ProgressView().accessibilityLabel(AppLocalization.string("正在准备副本")) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if !exportSummary.isEmpty { Text(exportSummary).font(.caption) }
        }
        .navigationTitle(AppLocalization.string("项目与日志试用副本"))
        .task { await refresh() }
        .refreshable { await refresh() }
        .fullScreenCover(isPresented: Binding(get: { session != nil }, set: { if !$0 { closeSession() } })) {
            if let session { RepositoryWorkspaceView(session: session) }
        }
        .sheet(isPresented: $showExporter, onDismiss: cleanupExport) {
            AppPreparedFileExporterSheet(fileURL: exportFileURL) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
                showExporter = false
            }
        }
        .alert(AppLocalization.string("删除试用副本"), isPresented: $showDeleteConfirmation, presenting: pendingDeletion) { entry in
            Button(AppLocalization.string("取消"), role: .cancel) { }
            Button(AppLocalization.string("删除试用副本"), role: .destructive) { Task { await delete(entry) } }
        } message: { _ in
            Text(AppLocalization.string("仅删除所选试用副本及其中的独立修改，无法撤销。请先导出需要保留的内容。"))
        }
    }

    private func entryRow(_ entry: RepositoryWorkspaceEntry) -> some View {
        HStack {
            Button { Task { await open(entry) } } label: {
                VStack(alignment: .leading) {
                    Text(entry.createdAt, style: .date)
                    Text(entry.createdAt, style: .time)
                    Text(String(entry.id.uuidString.prefix(8))).font(.caption).foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("repository-workspace-open-\(entry.id)")
            Menu {
                Button(AppLocalization.string("导出副本备份"), systemImage: "square.and.arrow.up") { Task { await export(entry) } }
                Button(AppLocalization.string("删除试用副本"), systemImage: "trash", role: .destructive) {
                    pendingDeletion = entry
                    showDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .padding(8)
                    .accessibilityLabel(AppLocalization.string("管理试用副本"))
            }
            .accessibilityIdentifier("repository-workspace-manage-\(entry.id)")
        }
        .buttonStyle(.borderless)
        .disabled(isBusy)
    }

    private func export(_ entry: RepositoryWorkspaceEntry) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        cleanupExport()
        defer { isBusy = false }
        do {
            let outcome = try await store.withBackupExport {
                try await RepositoryWorkspaceExport.prepare(entry, catalog: catalog)
            }
            exportFileURL = outcome.preparedFileURL
            exportSummary = outcome.summary
            showExporter = true
        } catch { errorMessage = RepositoryUserMessage.describe(error) }
    }

    private func cleanupExport() {
        if let exportFileURL { ExportFileURLPreparer.cleanup(fileURL: exportFileURL) }
        exportFileURL = nil
    }

    private func delete(_ entry: RepositoryWorkspaceEntry) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let source = store.storeURL
            try await FileIOTaskRunner.run { try RepositoryWorkspaceMaintenance.remove(entry, beside: source) }
            await refresh()
        } catch { errorMessage = RepositoryUserMessage.describe(error) }
    }

    private func refresh() async {
        do { entries = try await catalog.entries(beside: store.storeURL) } catch { errorMessage = RepositoryUserMessage.describe(error) }
    }

    private func closeSession() {
        guard let closingRepository = activeRepository else { return }
        session = nil
        activeRepository = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            // SwiftUI may retain a dismissed presentation. Release its database
            // connection explicitly before permitting another open or deletion.
            do { try await closingRepository.close() } catch { errorMessage = RepositoryUserMessage.describe(error) }
            await refresh()
        }
    }

    private func open(_ entry: RepositoryWorkspaceEntry) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { present(try await catalog.open(entry)) } catch { errorMessage = RepositoryUserMessage.describe(error) }
    }

    private func present(_ repository: SQLiteBusinessRepository) {
        activeRepository = repository
        session = RepositoryWorkspaceSession(repository: repository)
    }

    private func create() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            await store.awaitInitialLoad()
            let entry = try await store.withBackupExport {
                try await store.flushSaveOrThrow()
                let root = store.storeURL.deletingLastPathComponent()
                return try await catalog.create(source: store.storeURL, assets: [
                    .photos: root.appendingPathComponent("Photos"),
                    .drawings: root.appendingPathComponent("Drawings"),
                    .documents: root.appendingPathComponent("ProjectDocuments"),
                    .attachments: root.appendingPathComponent("QuickNoteAttachments")
                ])
            }
            await refresh()
            present(try await catalog.open(entry))
        } catch { errorMessage = RepositoryUserMessage.describe(error) }
    }
}
