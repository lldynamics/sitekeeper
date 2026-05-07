import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    var entry: SitekeeperProvider.Entry
    let data: WidgetExportData

    init(entry: SitekeeperProvider.Entry) {
        self.entry = entry
        self.data = entry.data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("待办")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(data.pendingTodos)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("项待处理")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Image(systemName: "shippingbox")
                    .font(.caption2)
                Text("\(data.materialStockCount) 种材料")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            if data.lowStockCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("\(data.lowStockCount) 种不足")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediumWidgetView: View {
    var entry: SitekeeperProvider.Entry
    let data: WidgetExportData

    init(entry: SitekeeperProvider.Entry) {
        self.entry = entry
        self.data = entry.data
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧：待办统计
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundStyle(.orange)
                    Text("今日待办")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(data.pendingTodos)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("项待处理")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧：项目进度列表
            VStack(alignment: .leading, spacing: 8) {
                Text("项目进度")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if data.projects.isEmpty {
                    Text("暂无进行中的项目")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                } else {
                    ForEach(data.projects.prefix(3), id: \.id) { project in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(project.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(project.progress * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: project.progress)
                                .tint(project.status == "已完成" ? .green : .orange)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LargeWidgetView: View {
    var entry: SitekeeperProvider.Entry
    let data: WidgetExportData

    init(entry: SitekeeperProvider.Entry) {
        self.entry = entry
        self.data = entry.data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部摘要行
            HStack(spacing: 16) {
                SummaryBlock(
                    icon: "checklist",
                    value: "\(data.pendingTodos)",
                    label: "待办",
                    color: .orange
                )
                SummaryBlock(
                    icon: "shippingbox",
                    value: "\(data.materialStockCount)",
                    label: "材料种类",
                    color: .blue
                )
                if data.lowStockCount > 0 {
                    SummaryBlock(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(data.lowStockCount)",
                        label: "库存不足",
                        color: .red
                    )
                }
            }

            Divider()

            // 项目列表
            if data.projects.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "hammer")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("暂无进行中的项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(data.projects, id: \.id) { project in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(project.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Text(project.status)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(project.status == "已完成" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                )
                                .foregroundStyle(project.status == "已完成" ? .green : .orange)
                        }

                        HStack(spacing: 12) {
                            ProgressView(value: project.progress)
                                .tint(project.status == "已完成" ? .green : .orange)
                            Text("\(Int(project.progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }

                        if project.todoCount > 0 {
                            Text("\(project.todoCount) 项待办")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct SummaryBlock: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
