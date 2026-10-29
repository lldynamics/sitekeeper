import SwiftUI

private struct FieldReportPreviewLine: Identifiable {
    let id: Int
    let text: String
}

struct ProjectFieldReportView: View {
    let project: Project
    @Environment(DataStore.self) private var store
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var endDate = Calendar.current.startOfDay(for: Date())
    @State private var kind: FieldReportKind = .daily
    @State private var selectedPhotoIDs: Set<String> = []
    @State private var previewURL: URL?
    @State private var exportError: String?
    @State private var isPreparingPhotos = false

    private var liveProject: Project { store.projects.first { $0.id == project.id } ?? project }
    private var period: ProjectReportPeriod {
        ProjectReportPeriod(start: startDate, end: kind == .daily ? startDate : endDate)
    }
    private var report: ProjectFieldReport {
        ProjectFieldReport(project: liveProject, period: period, logs: store.dailyLogs,
                           todos: store.siteTodos, tasks: store.progressTasks)
    }

    var body: some View {
        let snapshot = report
        List {
            Section(AppLocalization.string("报表设置")) {
                Text(liveProject.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Picker(AppLocalization.string("报表类型"), selection: $kind) {
                    ForEach(FieldReportKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                DatePicker(AppLocalization.string("开始日期"), selection: $startDate, displayedComponents: .date)
                if kind == .weekly {
                    DatePicker(AppLocalization.string("结束日期"), selection: $endDate, displayedComponents: .date)
                }
                if !period.isValid {
                    Text(AppLocalization.string("结束日期不能早于开始日期。")).foregroundStyle(.red)
                }
            }
            Section(AppLocalization.string("报表内容预览")) {
                let reportLines = ReportBuilder.fieldReportLines(snapshot, title: kind.title, selectedPhotoIDs: selectedPhotoIDs)
                    .enumerated()
                    .map { FieldReportPreviewLine(id: $0.offset, text: $0.element) }
                ForEach(reportLines) { line in
                    if !line.text.isEmpty {
                        Text(line.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section {
                if snapshot.photos.isEmpty {
                    Text(AppLocalization.string("本期间没有日志照片。")).foregroundStyle(.secondary)
                }
                ForEach(snapshot.photos) { item in
                    Toggle(isOn: photoSelection(item.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(ReportBuilder.fieldReportDate(item.date)) · \(item.photo.tag.displayName)")
                            if !item.photo.note.isEmpty { Text(item.photo.note).font(.caption) }
                            if !PhotoStorage.exists(fileName: item.photo.fileName) {
                                Text(AppLocalization.string("照片文件缺失")).font(.caption).foregroundStyle(.red)
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text(AppLocalization.string("可选照片"))
            } footer: {
                Text(AppLocalization.string("照片通过独立照片 PDF 预览和分享，正文 PDF 不含图片。缺失或无法读取的照片会保留占位提示。"))
            }
            Section {
                Button {
                    prepareBody(snapshot)
                } label: {
                    Label(AppLocalization.string("预览正文 PDF"), systemImage: "doc.text.magnifyingglass")
                }
                .disabled(!period.isValid || isPreparingPhotos)
                Button {
                    preparePhotos(snapshot)
                } label: {
                    if isPreparingPhotos { ProgressView() }
                    else { Label(AppLocalization.string("预览独立照片 PDF"), systemImage: "photo.on.rectangle") }
                }
                .disabled(!period.isValid || !snapshot.photos.contains { selectedPhotoIDs.contains($0.id) } || isPreparingPhotos)
                Text(AppLocalization.string("打开 PDF 预览后，可手动点击分享；不会自动发送。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(AppLocalization.string("日报与周报"))
        .navigationBarTitleDisplayMode(.inline)
        .appFilePreview($previewURL)
        .alert(AppLocalization.string("无法生成报表"), isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button(AppLocalization.string("关闭"), role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
        .onChange(of: kind) { _, newValue in
            if newValue == .weekly {
                endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
            }
        }
    }

    private func photoSelection(_ id: String) -> Binding<Bool> {
        Binding(get: { selectedPhotoIDs.contains(id) }, set: { selected in
            if selected { selectedPhotoIDs.insert(id) } else { selectedPhotoIDs.remove(id) }
        })
    }

    private func prepareBody(_ report: ProjectFieldReport) {
        do {
            let data = ReportBuilder.makeFieldReportPDF(report, title: kind.title, selectedPhotoIDs: selectedPhotoIDs)
            previewURL = try ProjectReportPreviewFile.write(data, name: "field-report")
        } catch { exportError = AppLocalization.string("报表文件写入失败，请重试。") }
    }

    private func preparePhotos(_ report: ProjectFieldReport) {
        let selection = selectedPhotoIDs
        isPreparingPhotos = true
        Task { @MainActor in
            defer { isPreparingPhotos = false }
            let data = await ReportBuilder.makeFieldReportPhotosPDF(report, selectedPhotoIDs: selection)
            do { previewURL = try ProjectReportPreviewFile.write(data, name: "field-report-photos") }
            catch { exportError = AppLocalization.string("报表文件写入失败，请重试。") }
        }
    }
}

private enum FieldReportKind: String, CaseIterable, Identifiable {
    case daily, weekly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: AppLocalization.string("施工日报")
        case .weekly: AppLocalization.string("施工周报")
        }
    }
}

/// Preview URLs are newly generated temporary files; no project data is edited.
enum ProjectReportPreviewFile {
    static func write(_ data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectReportPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
