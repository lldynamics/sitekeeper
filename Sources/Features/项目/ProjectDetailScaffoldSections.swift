import SwiftUI

struct ProjectDetailHeaderSection<RiskStrip: View>: View {
    let project: Project
    @Binding var status: ProjectStatus
    let progressValue: String
    let quoteValue: String
    let todoValue: String
    let riskStrip: RiskStrip
    let customerLine: String?
    let periodLine: String?
    let showsStatus: Bool
    let onEditProject: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.normal) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.title3.weight(.bold))
                        Text(project.location.isEmpty ? "未填写地址" : project.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if showsStatus {
                        Picker("状态", selection: $status) {
                            ForEach(ProjectStatus.allCases, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                HStack {
                    metric("进度", progressValue, .orange)
                    metric("报价", quoteValue, .blue)
                    metric("待办", todoValue, .orange)
                }
                riskStrip
                if let customerLine {
                    Text(customerLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let periodLine {
                    Text(periodLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onEditProject()
                } label: {
                    Label("编辑项目资料", systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProjectDetailQuickActionSection: View {
    let onAddLog: () -> Void
    let onAddFinance: () -> Void
    let onAddContact: () -> Void
    let onImportDrawing: () -> Void
    let onAddMaterial: () -> Void
    let onAddQuote: () -> Void
    let onAddLabor: () -> Void

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    actionChip("日志", systemImage: "book.pages.fill", color: .green, action: onAddLog)
                    actionChip("记账", systemImage: "receipt.fill", color: .pink, action: onAddFinance)
                    actionChip("联系人", systemImage: "person.crop.circle.badge.plus", color: .blue, action: onAddContact)
                    actionChip("图纸", systemImage: "doc.viewfinder.fill", color: .indigo, action: onImportDrawing)
                    actionChip("材料", systemImage: "shippingbox.fill", color: .orange, action: onAddMaterial)
                    actionChip("报价", systemImage: "doc.text.fill", color: .brown, action: onAddQuote)
                    actionChip("人工", systemImage: "person.2.fill", color: .purple, action: onAddLabor)
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 0))
        }
    }

    private func actionChip(_ title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, 7)
                .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
