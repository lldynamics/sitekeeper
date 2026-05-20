import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CADKernelUnavailableView: View {
    let fileURL: URL
    let message: String
    let technicalDetails: CADOpenTechnicalDetails?
    let onReportIssue: () -> Void

    private struct UserDiagnosticSummary {
        let headline: String
        let detail: String
        let layerLabel: String
    }

    private var userDiagnosticSummary: UserDiagnosticSummary {
        guard let details = technicalDetails else {
            return UserDiagnosticSummary(
                headline: String(localized: "暂未获取完整诊断信息"),
                detail: String(localized: "请点击“反馈问题”导出诊断包，我们会根据机器 trace 继续排查。"),
                layerLabel: String(localized: "未识别")
            )
        }
        guard let trace = details.pipelineTrace else {
            if details.geometryParsed, details.drawableEntityCount > 0 {
                return UserDiagnosticSummary(
                    headline: String(localized: "图纸已完成基础解析"),
                    detail: String(localized: "当前阻塞更可能发生在渲染或显示配置阶段。"),
                    layerLabel: String(localized: "渲染")
                )
            }
            return UserDiagnosticSummary(
                headline: String(localized: "图纸未形成可渲染对象"),
                detail: String(localized: "建议先导出诊断包，重点检查导入和结构转换阶段。"),
                layerLabel: String(localized: "导入/转换")
            )
        }

        switch failureLayer(for: trace) {
        case "none":
            return UserDiagnosticSummary(
                headline: String(localized: "图纸数据已进入可渲染阶段"),
                detail: String(localized: "当前问题更可能与显示配置、视图状态或设备环境有关。"),
                layerLabel: String(localized: "渲染完成")
            )
        case "libredwg":
            return UserDiagnosticSummary(
                headline: String(localized: "导入阶段未产出有效几何"),
                detail: String(localized: "常见原因是图纸版本或对象类型暂不兼容。"),
                layerLabel: String(localized: "导入")
            )
        case "adapter":
            return UserDiagnosticSummary(
                headline: String(localized: "结构转换未生成实体"),
                detail: String(localized: "原始数据存在，但转换层尚未产出可用数据库实体。"),
                layerLabel: String(localized: "转换")
            )
        case "database":
            return UserDiagnosticSummary(
                headline: String(localized: "实体已生成但不可绘制"),
                detail: String(localized: "建议重点排查实体构建与可绘制对象映射。"),
                layerLabel: String(localized: "实体")
            )
        case "render":
            return UserDiagnosticSummary(
                headline: String(localized: "渲染命令未生成"),
                detail: String(localized: "可绘制实体存在，但渲染阶段未输出可显示命令。"),
                layerLabel: String(localized: "渲染")
            )
        default:
            return UserDiagnosticSummary(
                headline: String(localized: "已识别异常但暂未定位层级"),
                detail: String(localized: "请导出诊断包，我们会结合机器 trace 继续定位。"),
                layerLabel: String(localized: "未知")
            )
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text("当前图纸暂不支持交互预览")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ShareLink(item: fileURL) {
                Label("下载原图", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent(tint: .appDoc))
            .controlSize(.large)

            Button {
                onReportIssue()
            } label: {
                Label("反馈问题", systemImage: "exclamationmark.bubble")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "诊断结论"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(userDiagnosticSummary.headline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(userDiagnosticSummary.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(String(localized: "定位层"))：\(userDiagnosticSummary.layerLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "详细机器 trace 已写入反馈包中的 pipeline_trace.json。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appStrokeSecondary, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(String(localized: "诊断结论"))，\(userDiagnosticSummary.headline)，\(userDiagnosticSummary.detail)"
            )
            .accessibilityHint(String(localized: "反馈包中包含可供技术排查的机器 trace 文件"))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func failureLayer(for trace: SiteKeeperCADKernel.DWGOpenPipelineTrace) -> String {
        if trace.openState == .rendered || trace.failureStage == "rendered" {
            return "none"
        }
        if trace.jsonRawEntityCount == 0,
           trace.dxfRawEntityCount == 0,
           trace.adapterEntityCount == 0,
           trace.databaseEntityCount == 0 {
            return "libredwg"
        }
        if trace.adapterEntityCount == 0 { return "adapter" }
        if trace.drawableEntityCount == 0 { return "database" }
        if trace.renderCommandCount == 0 { return "render" }

        let stage = trace.failureStage.lowercased()
        if stage.contains("libredwg") || stage.contains("geometry_source") || stage.contains("import") {
            return "libredwg"
        }
        if stage.contains("adapter") { return "adapter" }
        if stage.contains("database") || stage.contains("drawable") { return "database" }
        if stage.contains("render") { return "render" }
        return "unknown"
    }
}
