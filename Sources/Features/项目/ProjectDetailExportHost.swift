import SwiftUI
import Foundation

struct ProjectDetailExportHost: ViewModifier {
    @Binding var exportPayload: ExportPayload?
    @Binding var showExporter: Bool
    @Binding var pendingPackageProject: Project?
    @Binding var packageSizeWarningMessage: String
    @Binding var showPackageSizeWarning: Bool

    let onContinuePackageExport: (Project) -> Void

    func body(content: Content) -> some View {
        let showDataExporter = Binding<Bool>(
            get: { showExporter && exportPayload?.sourceFileURL == nil },
            set: { if !$0 { showExporter = false } }
        )
        let showFileURLExporter = Binding<Bool>(
            get: { showExporter && exportPayload?.sourceFileURL != nil },
            set: { if !$0 { showExporter = false } }
        )

        content
            .fileExporter(
                isPresented: showDataExporter,
                document: ExportDocument(data: exportPayload?.data ?? Data()),
                contentType: exportPayload?.contentType ?? .pdf,
                defaultFilename: exportPayload?.defaultFilename ?? "项目资料包.pdf"
            ) { _ in
                exportPayload = nil
            }
            .sheet(isPresented: showFileURLExporter) {
                if let sourceFileURL = exportPayload?.sourceFileURL {
                    FileURLDocumentExporter(fileURL: sourceFileURL) { _ in
                        showExporter = false
                        ExportFileURLPreparer.cleanup(fileURL: sourceFileURL)
                        exportPayload = nil
                    }
                } else {
                    ProgressView("正在准备导出文件...")
                        .padding()
                }
            }
            .alert("交付包较大", isPresented: $showPackageSizeWarning) {
                Button("取消", role: .cancel) {
                    pendingPackageProject = nil
                }
                Button("继续导出") {
                    if let project = pendingPackageProject {
                        onContinuePackageExport(project)
                    }
                    pendingPackageProject = nil
                }
            } message: {
                Text(packageSizeWarningMessage)
            }
    }
}

extension View {
    func projectDetailExportHost(
        exportPayload: Binding<ExportPayload?>,
        showExporter: Binding<Bool>,
        pendingPackageProject: Binding<Project?>,
        packageSizeWarningMessage: Binding<String>,
        showPackageSizeWarning: Binding<Bool>,
        onContinuePackageExport: @escaping (Project) -> Void
    ) -> some View {
        modifier(ProjectDetailExportHost(
            exportPayload: exportPayload,
            showExporter: showExporter,
            pendingPackageProject: pendingPackageProject,
            packageSizeWarningMessage: packageSizeWarningMessage,
            showPackageSizeWarning: showPackageSizeWarning,
            onContinuePackageExport: onContinuePackageExport
        ))
    }
}
