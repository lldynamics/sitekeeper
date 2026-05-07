import SwiftUI

struct ProjectDetailModeContent<Overview: View, Records: View, Finance: View, Assets: View>: View {
    let mode: ProjectDetailMode
    @ViewBuilder let overview: () -> Overview
    @ViewBuilder let records: () -> Records
    @ViewBuilder let finance: () -> Finance
    @ViewBuilder let assets: () -> Assets

    var body: some View {
        switch mode {
        case .overview:
            overview()
        case .records:
            records()
        case .finance:
            finance()
        case .assets:
            assets()
        }
    }
}

struct ProjectRecordHubSectionView: View {
    let logsCount: Int
    let progressCount: Int
    let photoCount: Int
    let logsDestination: AnyView
    let progressDestination: AnyView
    let photoDestination: AnyView

    var body: some View {
        ProjectModeHubSection(
            title: "记录",
            entries: [
                ProjectModeHubEntry(
                    title: "施工日志",
                    subtitle: "\(logsCount) 条",
                    systemImage: "book.pages.fill",
                    tint: .green,
                    destination: logsDestination
                ),
                ProjectModeHubEntry(
                    title: "进度任务",
                    subtitle: "\(progressCount) 项",
                    systemImage: "checklist.checked",
                    tint: .orange,
                    destination: progressDestination
                ),
                ProjectModeHubEntry(
                    title: "现场照片",
                    subtitle: "\(photoCount) 张",
                    systemImage: "photo.on.rectangle.angled",
                    tint: .blue,
                    destination: photoDestination
                )
            ]
        )
    }
}

struct ProjectFinanceHubSectionView: View {
    let financialCount: Int
    let quoteCount: Int
    let materialCount: Int
    let laborCount: Int
    let warehouseCount: Int
    let bookDestination: AnyView
    let quoteDestination: AnyView
    let materialDestination: AnyView
    let laborDestination: AnyView
    let warehouseDestination: AnyView
    let legacyPaymentsCount: Int
    let onMigrateLegacyPayments: () -> Void

    var body: some View {
        Group {
            ProjectModeHubSection(
                title: "财务",
                entries: [
                    ProjectModeHubEntry(
                        title: "项目财务流水",
                        subtitle: "\(financialCount) 笔",
                        systemImage: "receipt.long.fill",
                        tint: .pink,
                        destination: bookDestination
                    ),
                    ProjectModeHubEntry(
                        title: "报价明细",
                        subtitle: "\(quoteCount) 项",
                        systemImage: "doc.text.fill",
                        tint: .orange,
                        destination: quoteDestination
                    ),
                    ProjectModeHubEntry(
                        title: "材料清单",
                        subtitle: "\(materialCount) 项",
                        systemImage: "shippingbox.fill",
                        tint: .blue,
                        destination: materialDestination
                    ),
                    ProjectModeHubEntry(
                        title: "人工记录",
                        subtitle: "\(laborCount) 条",
                        systemImage: "person.2.fill",
                        tint: .purple,
                        destination: laborDestination
                    ),
                    ProjectModeHubEntry(
                        title: "项目仓库",
                        subtitle: "\(warehouseCount) 条出入库",
                        systemImage: "shippingbox.and.arrow.backward.fill",
                        tint: .brown,
                        destination: warehouseDestination
                    )
                ]
            )
            if legacyPaymentsCount > 0 {
                Section("旧版收款记录") {
                    Text(String(localized: "检测到 \(legacyPaymentsCount) 条历史收款记录，建议迁移到\"项目财务流水\"统一管理。"))
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

struct ProjectAssetHubSectionView: View {
    let drawingCount: Int
    let documentCount: Int
    let contactCount: Int
    let drawingDestination: AnyView
    let documentDestination: AnyView
    let contactDestination: AnyView

    var body: some View {
        ProjectModeHubSection(
            title: "资料",
            entries: [
                ProjectModeHubEntry(
                    title: "图纸",
                    subtitle: "\(drawingCount) 份",
                    systemImage: "doc.viewfinder.fill",
                    tint: .indigo,
                    destination: drawingDestination
                ),
                ProjectModeHubEntry(
                    title: "票据与资料",
                    subtitle: "\(documentCount) 份",
                    systemImage: "doc.richtext.fill",
                    tint: .brown,
                    destination: documentDestination
                ),
                ProjectModeHubEntry(
                    title: "联系人",
                    subtitle: "\(contactCount) 位",
                    systemImage: "person.crop.circle.badge.plus",
                    tint: .blue,
                    destination: contactDestination
                )
            ]
        )
    }
}
