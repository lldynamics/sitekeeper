import SwiftUI

struct MaterialPriceSpikeDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(FinanceStore.self) private var financeStore
    @Environment(ProjectStore.self) private var projectStore
    @State private var showIgnored = false
    @State private var actionFeedbackMessage: String?
    @State private var pendingThresholdAdjustment: MaterialPriceSpikeDetail?
    @State private var showThresholdAdjustmentDialog = false

    private var activeProjects: [Project] {
        projectStore.projects.filter { $0.status == .active || $0.status == .paused }
    }

    private var activeProjectIDs: Set<UUID> {
        Set(activeProjects.map(\.id))
    }

    private var projectNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projectStore.projects.map { ($0.id, $0.name) })
    }

    private var allSpikeDetails: [MaterialPriceSpikeDetail] {
        financeStore.materialPriceSpikeDetails(for: activeProjectIDs, includeIgnored: true)
    }

    private var displayedSpikeDetails: [MaterialPriceSpikeDetail] {
        if showIgnored {
            return allSpikeDetails
        }
        return allSpikeDetails.filter { !$0.isIgnored }
    }

    private var activeSpikeCount: Int {
        allSpikeDetails.filter { !$0.isIgnored }.count
    }

    private var ignoredSpikeCount: Int {
        allSpikeDetails.filter(\.isIgnored).count
    }

    private var affectedProjectCount: Int {
        Set(displayedSpikeDetails.map(\.projectId)).count
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { financeStore.materialPriceSpikeThreshold },
            set: { financeStore.setMaterialPriceSpikeThreshold($0) }
        )
    }

    private var thresholdPercentText: String {
        "\(Int((financeStore.materialPriceSpikeThreshold * 100).rounded()))%"
    }

    var body: some View {
        List {
            if let actionFeedbackMessage {
                Section {
                    Text(actionFeedbackMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "预警设置")) {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    HStack {
                        Text(String(localized: "涨幅阈值"))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(thresholdPercentText)
                            .font(.headline)
                            .foregroundStyle(Color.appFinance)
                    }
                    Slider(value: thresholdBinding, in: 0.05...0.50, step: 0.01)
                        .tint(Color.appFinance)
                    HStack {
                        Text(String(localized: "仅比较同材料最近两次采购单价"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "恢复 10%")) {
                            financeStore.setMaterialPriceSpikeThreshold(0.10)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                Toggle(String(localized: "显示已忽略项"), isOn: $showIgnored)

                LabeledContent(String(localized: "当前命中")) {
                    Text("\(activeSpikeCount) 项")
                        .foregroundStyle(activeSpikeCount > 0 ? Color.appFinance : .secondary)
                }
                LabeledContent(String(localized: "涉及项目")) {
                    Text("\(affectedProjectCount) 个")
                        .foregroundStyle(.secondary)
                }
                if ignoredSpikeCount > 0 {
                    LabeledContent(String(localized: "已忽略")) {
                        Text("\(ignoredSpikeCount) 项")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(String(localized: "异动明细")) {
                if displayedSpikeDetails.isEmpty {
                    ContentUnavailableView(
                        String(localized: "暂无价格异动"),
                        systemImage: "checkmark.shield",
                        description: Text(String(localized: "当前阈值下没有命中项"))
                    )
                } else {
                    ForEach(displayedSpikeDetails) { detail in
                        MaterialPriceSpikeRow(
                            detail: detail,
                            projectName: projectNameByID[detail.projectId] ?? String(localized: "未命名工程"),
                            onSetIgnored: { ignored in
                                setIgnored(ignored, for: detail)
                            },
                            onAdjustThreshold: {
                                pendingThresholdAdjustment = detail
                                showThresholdAdjustmentDialog = true
                            },
                            onCreateReminder: {
                                createPurchaseReminder(for: detail)
                            }
                        )
                    }
                }
            }
        }
        .task(id: actionFeedbackMessage) {
            guard actionFeedbackMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            actionFeedbackMessage = nil
        }
        .confirmationDialog(
            String(localized: "调整涨幅阈值"),
            isPresented: $showThresholdAdjustmentDialog,
            titleVisibility: .visible,
            presenting: pendingThresholdAdjustment
        ) { detail in
            let target = thresholdSuggestion(for: detail)
            Button("调整到 \(percentText(target))") {
                applyThresholdSuggestion(for: detail)
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: { detail in
            Text("该操作会把全局阈值提高到 \(percentText(thresholdSuggestion(for: detail)))，低于新阈值的异动将不再提醒。")
        }
        .navigationTitle(String(localized: "材料价格异动"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setIgnored(_ ignored: Bool, for detail: MaterialPriceSpikeDetail) {
        financeStore.setMaterialPriceSpikeIgnored(ignored, for: detail.id)
        AppHaptics.impact(.light)
        actionFeedbackMessage = ignored
            ? "已忽略：\(spikeMaterialTitle(detail))"
            : "已取消忽略：\(spikeMaterialTitle(detail))"
    }

    private func thresholdSuggestion(for detail: MaterialPriceSpikeDetail) -> Double {
        let ratioPercent = detail.ratio * 100
        let roundedPercent = ceil(ratioPercent)
        let suggestion = (roundedPercent + 1) / 100
        return min(max(suggestion, financeStore.materialPriceSpikeThreshold), 0.50)
    }

    private func applyThresholdSuggestion(for detail: MaterialPriceSpikeDetail) {
        let current = financeStore.materialPriceSpikeThreshold
        let target = thresholdSuggestion(for: detail)
        guard abs(current - target) > 0.0001 else {
            AppHaptics.warning()
            actionFeedbackMessage = "当前阈值已覆盖该异动，无需调整"
            return
        }
        financeStore.setMaterialPriceSpikeThreshold(target)
        AppHaptics.success()
        actionFeedbackMessage = "已将阈值调整为 \(percentText(target))"
    }

    private func createPurchaseReminder(for detail: MaterialPriceSpikeDetail) {
        let marker = "[price-spike:\(detail.id)]"
        let duplicate = store.siteTodos.contains { todo in
            !todo.isDone && todo.projectId == detail.projectId && todo.note.contains(marker)
        }
        if duplicate {
            AppHaptics.warning()
            actionFeedbackMessage = "该材料已生成采购提醒"
            return
        }

        let projectName = projectNameByID[detail.projectId] ?? String(localized: "未命名工程")
        let reminder = SiteTodo(
            title: "复核采购价：\(spikeMaterialTitle(detail))",
            owner: "",
            dueDate: Formatters.date.string(from: Date()),
            priority: .medium,
            issueType: .material,
            note: """
\(projectName)
上次 \(ReportBuilder.money(detail.previousPrice))/\(detail.unit)（\(spikeDisplayDate(detail.previousDateText))）
本次 \(ReportBuilder.money(detail.latestPrice))/\(detail.unit)（\(spikeDisplayDate(detail.latestDateText))）
涨幅 +\(spikeRatioText(detail))
\(marker)
""",
            projectId: detail.projectId
        )
        store.siteTodos.insert(reminder, at: 0)
        store.scheduleSave()
        AppHaptics.success()
        actionFeedbackMessage = "已生成采购提醒"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct MaterialPriceSpikeRow: View {
    let detail: MaterialPriceSpikeDetail
    let projectName: String
    let onSetIgnored: (Bool) -> Void
    let onAdjustThreshold: () -> Void
    let onCreateReminder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            NavigationLink {
                ProjectDetailView(projectId: detail.projectId)
            } label: {
                VStack(alignment: .leading, spacing: AppSpacing.tight * 0.625) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                        Text(spikeMaterialTitle(detail))
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text("+\(spikeRatioText(detail))")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(detail.isIgnored ? Color.secondary : Color.white)
                            .padding(.horizontal, AppSpacing.tight)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(detail.isIgnored ? Color.appMutedSurface : Color.appFinance)
                            )
                    }

                    HStack(spacing: AppSpacing.tight) {
                        Label(projectName, systemImage: "building.2")
                        if detail.isIgnored {
                            Text(String(localized: "已忽略"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: AppSpacing.tight * 0.375) {
                        Text("上次 \(ReportBuilder.money(detail.previousPrice))/\(detail.unit)（\(spikeDisplayDate(detail.previousDateText))）")
                        Text("本次 \(ReportBuilder.money(detail.latestPrice))/\(detail.unit)（\(spikeDisplayDate(detail.latestDateText))）")
                        .foregroundStyle(.primary)
                    }
                    .font(.caption)
                }
            }

            HStack(spacing: AppSpacing.tight) {
                Button {
                    onSetIgnored(!detail.isIgnored)
                } label: {
                    Label(detail.isIgnored ? String(localized: "取消忽略") : String(localized: "忽略本次"), systemImage: detail.isIgnored ? "arrow.uturn.backward.circle" : "eye.slash")
                }
                .tint(detail.isIgnored ? Color.appWarning : Color.secondary)

                Button {
                    onAdjustThreshold()
                } label: {
                    Label(String(localized: "调整阈值"), systemImage: "slider.horizontal.3")
                }
                .tint(Color.appFinance)

                Button {
                    onCreateReminder()
                } label: {
                    Label(String(localized: "生成采购提醒"), systemImage: "bell.badge")
                }
                .tint(Color.appWarning)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .contextMenu {
            Button(detail.isIgnored ? String(localized: "取消忽略") : String(localized: "忽略本次")) {
                onSetIgnored(!detail.isIgnored)
            }
            Button(String(localized: "调整阈值")) {
                onAdjustThreshold()
            }
            Button(String(localized: "生成采购提醒")) {
                onCreateReminder()
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(String(localized: "提醒")) {
                onCreateReminder()
            }
            .tint(Color.appWarning)
            Button(String(localized: "阈值")) {
                onAdjustThreshold()
            }
            .tint(Color.appFinance)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(detail.isIgnored ? String(localized: "取消忽略") : String(localized: "忽略")) {
                onSetIgnored(!detail.isIgnored)
            }
            .tint(detail.isIgnored ? Color.appWarning : Color.appMuted)
        }
    }
}

private func spikeRatioText(_ detail: MaterialPriceSpikeDetail) -> String {
    String(format: "%.1f%%", detail.ratio * 100)
}

private func spikeMaterialTitle(_ detail: MaterialPriceSpikeDetail) -> String {
    let spec = detail.specification.trimmingCharacters(in: .whitespacesAndNewlines)
    if spec.isEmpty { return detail.materialName }
    return "\(detail.materialName) · \(spec)"
}

private func spikeDisplayDate(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? String(localized: "未记录日期") : trimmed
}
