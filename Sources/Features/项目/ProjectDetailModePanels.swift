import SwiftUI

struct ProjectDetailModeContent<Overview: View, Records: View, Assets: View, Finance: View, Timeline: View>: View {
    let mode: ProjectDetailMode
    @ViewBuilder let overview: () -> Overview
    @ViewBuilder let records: () -> Records
    @ViewBuilder let assets: () -> Assets
    @ViewBuilder let finance: () -> Finance
    @ViewBuilder let timeline: () -> Timeline

    var body: some View {
        switch mode {
        case .overview:
            overview()
        case .records:
            records()
        case .assets:
            assets()
        case .finance:
            finance()
        case .timeline:
            timeline()
        }
    }
}

struct ProjectRecordHubSectionView<LogsDestination: View, ProgressDestination: View, PhotoDestination: View>: View {
    let logsCount: Int
    let progressCount: Int
    let photoCount: Int
    @ViewBuilder let logsDestination: () -> LogsDestination
    @ViewBuilder let progressDestination: () -> ProgressDestination
    @ViewBuilder let photoDestination: () -> PhotoDestination

    var body: some View {
        ProjectModeHubSection(title: "记录") {
            ProjectModeHubRow(
                title: "施工日志",
                subtitle: "\(logsCount) 条",
                systemImage: "book.pages.fill",
                tint: .green,
                destination: logsDestination
            )
            ProjectModeHubRow(
                title: "进度任务",
                subtitle: "\(progressCount) 项",
                systemImage: "checklist.checked",
                tint: .orange,
                destination: progressDestination
            )
            ProjectModeHubRow(
                title: "现场照片",
                subtitle: "\(photoCount) 张",
                systemImage: "photo.on.rectangle.angled",
                tint: .blue,
                destination: photoDestination
            )
        }
    }
}

struct ProjectFinanceHubSectionView<BookDestination: View, QuoteDestination: View, MaterialDestination: View, LaborDestination: View, WarehouseDestination: View>: View {
    let financialCount: Int
    let quoteCount: Int
    let materialCount: Int
    let laborCount: Int
    let warehouseCount: Int
    @ViewBuilder let bookDestination: () -> BookDestination
    @ViewBuilder let quoteDestination: () -> QuoteDestination
    @ViewBuilder let materialDestination: () -> MaterialDestination
    @ViewBuilder let laborDestination: () -> LaborDestination
    @ViewBuilder let warehouseDestination: () -> WarehouseDestination
    let legacyPaymentsCount: Int
    let onMigrateLegacyPayments: () -> Void

    var body: some View {
        Group {
            ProjectModeHubSection(title: "财务") {
                ProjectModeHubRow(
                    title: "项目财务流水",
                    subtitle: "\(financialCount) 笔",
                    systemImage: "receipt.long.fill",
                    tint: .pink,
                    destination: bookDestination
                )
                ProjectModeHubRow(
                    title: "报价明细",
                    subtitle: "\(quoteCount) 项",
                    systemImage: "doc.text.fill",
                    tint: .orange,
                    destination: quoteDestination
                )
                ProjectModeHubRow(
                    title: "材料清单",
                    subtitle: "\(materialCount) 项",
                    systemImage: "shippingbox.fill",
                    tint: .blue,
                    destination: materialDestination
                )
                ProjectModeHubRow(
                    title: "人工记录",
                    subtitle: "\(laborCount) 条",
                    systemImage: "person.2.fill",
                    tint: .purple,
                    destination: laborDestination
                )
                ProjectModeHubRow(
                    title: "项目仓库",
                    subtitle: "\(warehouseCount) 条出入库",
                    systemImage: "shippingbox.and.arrow.backward.fill",
                    tint: .brown,
                    destination: warehouseDestination
                )
            }
            if legacyPaymentsCount > 0 {
                Section("旧版收款记录") {
                    Text(String(format: String(localized: "检测到 %d 条历史收款记录，建议迁移到\"项目财务流水\"统一管理。"), legacyPaymentsCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("迁移收款到财务流水") {
                        onMigrateLegacyPayments()
                    }
                }
            }
        }
    }
}

struct ProjectAssetHubSectionView<DrawingDestination: View, DocumentDestination: View, ContactDestination: View>: View {
    let drawingCount: Int
    let documentCount: Int
    let contactCount: Int
    @ViewBuilder let drawingDestination: () -> DrawingDestination
    @ViewBuilder let documentDestination: () -> DocumentDestination
    @ViewBuilder let contactDestination: () -> ContactDestination

    var body: some View {
        ProjectModeHubSection(title: "资料") {
            ProjectModeHubRow(
                title: "图纸",
                subtitle: "\(drawingCount) 份",
                systemImage: "doc.viewfinder.fill",
                tint: .indigo,
                destination: drawingDestination
            )
            ProjectModeHubRow(
                title: "票据与资料",
                subtitle: "\(documentCount) 份",
                systemImage: "doc.richtext.fill",
                tint: .brown,
                destination: documentDestination
            )
            ProjectModeHubRow(
                title: "联系人",
                subtitle: "\(contactCount) 位",
                systemImage: "person.crop.circle.badge.plus",
                tint: .blue,
                destination: contactDestination
            )
        }
    }
}
