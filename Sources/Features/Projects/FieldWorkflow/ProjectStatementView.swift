import SwiftUI

private struct StatementPreviewLine: Identifiable {
    let id: Int
    let text: String
}

struct ProjectStatementView: View {
    let project: Project
    @Environment(DataStore.self) private var store
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var endDate = Date()
    @State private var previewURL: URL?
    @State private var exportFailed = false

    private var liveProject: Project { store.projects.first { $0.id == project.id } ?? project }
    private var period: ProjectReportPeriod { ProjectReportPeriod(start: startDate, end: endDate) }
    private var statement: ProjectCustomerStatement {
        ProjectCustomerStatement(project: liveProject, period: period, records: store.projectFinancialRecords)
    }

    private func statementLines(for snapshot: ProjectCustomerStatement) -> [StatementPreviewLine] {
        ReportBuilder.customerStatementLines(snapshot).enumerated().map {
            StatementPreviewLine(id: $0.offset, text: $0.element)
        }
    }

    var body: some View {
        let snapshot = statement
        List {
            Section(AppLocalization.string("对账期间")) {
                Text(liveProject.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                DatePicker(AppLocalization.string("开始日期"), selection: $startDate, displayedComponents: .date)
                DatePicker(AppLocalization.string("结束日期"), selection: $endDate, displayedComponents: .date)
                if !period.isValid {
                    Text(AppLocalization.string("结束日期不能早于开始日期。")).foregroundStyle(.red)
                }
            }
            Section(AppLocalization.string("客户对账预览")) {
                ForEach(statementLines(for: snapshot)) { line in
                    if !line.text.isEmpty {
                        Text(line.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section {
                Button {
                    do {
                        previewURL = try ProjectReportPreviewFile.write(
                            ReportBuilder.makeCustomerStatementPDF(snapshot), name: "customer-statement"
                        )
                    } catch { exportFailed = true }
                } label: {
                    Label(AppLocalization.string("预览客户对账 PDF"), systemImage: "doc.text.magnifyingglass")
                }
                .disabled(!period.isValid)
            } footer: {
                Text(AppLocalization.string("打开 PDF 预览后，可手动点击分享；不会自动发送。"))
            }
        }
        .navigationTitle(AppLocalization.string("客户精简对账单"))
        .navigationBarTitleDisplayMode(.inline)
        .appFilePreview($previewURL)
        .alert(AppLocalization.string("无法生成报表"), isPresented: $exportFailed) {
            Button(AppLocalization.string("关闭"), role: .cancel) { }
        } message: { Text(AppLocalization.string("报表文件写入失败，请重试。")) }
    }
}
