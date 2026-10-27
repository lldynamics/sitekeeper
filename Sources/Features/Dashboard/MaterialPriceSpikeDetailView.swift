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
            set: { store.setMaterialPriceSpikeThreshold($0) }
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

            Section(AppLocalization.string("预警设置")) {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    HStack {
                        Text(AppLocalization.string("涨幅阈值"))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(thresholdPercentText)
                            .font(.headline)
                            .foregroundStyle(Color.appFinance)
                    }
                    Slider(value: thresholdBinding, in: 0.05...0.50, step: 0.01)
                        .tint(Color.appFinance)
                    HStack {
                        Text(AppLocalization.string("仅比较同材料最近两次采购单价"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(AppLocalization.string("恢复 10%")) {
                            store.setMaterialPriceSpikeThreshold(0.10)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                Toggle(AppLocalization.string("显示已忽略项"), isOn: $showIgnored)

                LabeledContent(AppLocalization.string("当前命中")) {
                    Text(String(format: AppLocalization.string("%lld 项"), Int64(activeSpikeCount)))
                        .foregroundStyle(activeSpikeCount > 0 ? Color.appFinance : .secondary)
                }
                LabeledContent(AppLocalization.string("涉及项目")) {
                    Text(String(format: AppLocalization.string("%lld 个"), Int64(affectedProjectCount)))
                        .foregroundStyle(.secondary)
                }
                if ignoredSpikeCount > 0 {
                    LabeledContent(AppLocalization.string("已忽略")) {
                        Text(String(format: AppLocalization.string("%lld 项"), Int64(ignoredSpikeCount)))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(AppLocalization.string("异动明细")) {
                if displayedSpikeDetails.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.string("暂无价格异动"),
                        systemImage: "checkmark.shield",
                        description: Text(AppLocalization.string("当前阈值下没有命中项"))
                    )
                } else {
                    ForEach(displayedSpikeDetails) { detail in
                        MaterialPriceSpikeRow(
                            detail: detail,
                            projectName: projectNameByID[detail.projectId] ?? AppLocalization.string("未命名工程"),
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
            AppLocalization.string("调整涨幅阈值"),
            isPresented: $showThresholdAdjustmentDialog,
            titleVisibility: .visible,
            presenting: pendingThresholdAdjustment
        ) { detail in
            let target = thresholdSuggestion(for: detail)
            Button(String(format: AppLocalization.string("调整到 %@"), percentText(target))) {
                applyThresholdSuggestion(for: detail)
            }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        } message: { detail in
            Text(String(
                format: AppLocalization.string("该操作会把全局阈值提高到 %@，低于新阈值的异动将不再提醒。"),
                percentText(thresholdSuggestion(for: detail))
            ))
        }
        .navigationTitle(AppLocalization.string("材料价格异动"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setIgnored(_ ignored: Bool, for detail: MaterialPriceSpikeDetail) {
        store.setMaterialPriceSpikeIgnored(ignored, for: detail.id)
        AppHaptics.impact(.light)
        actionFeedbackMessage = ignored
            ? String(format: AppLocalization.string("material.priceSpike.ignored.message"), spikeMaterialTitle(detail))
            : String(format: AppLocalization.string("material.priceSpike.unignored.message"), spikeMaterialTitle(detail))
    }

    private func thresholdSuggestion(for detail: MaterialPriceSpikeDetail) -> Double {
        var ratioPercent = detail.ratio * 100
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &ratioPercent, 0, .up)
        let roundedPercent = NSDecimalNumber(decimal: rounded).doubleValue
        let suggestion = (roundedPercent + 1) / 100
        return min(max(suggestion, financeStore.materialPriceSpikeThreshold), 0.50)
    }

    private func applyThresholdSuggestion(for detail: MaterialPriceSpikeDetail) {
        let current = financeStore.materialPriceSpikeThreshold
        let target = thresholdSuggestion(for: detail)
        guard abs(current - target) > 0.0001 else {
            AppHaptics.warning()
            actionFeedbackMessage = AppLocalization.string("当前阈值已覆盖该异动，无需调整")
            return
        }
        store.setMaterialPriceSpikeThreshold(target)
        AppHaptics.success()
        actionFeedbackMessage = String(
            format: AppLocalization.string("已将阈值调整为 %@"),
            percentText(target)
        )
    }

    private func createPurchaseReminder(for detail: MaterialPriceSpikeDetail) {
        let marker = "[price-spike:\(detail.id)]"
        let duplicate = store.siteTodos.contains { todo in
            !todo.isDone && todo.projectId == detail.projectId && todo.note.contains(marker)
        }
        if duplicate {
            AppHaptics.warning()
            actionFeedbackMessage = AppLocalization.string("该材料已生成采购提醒")
            return
        }

        let projectName = projectNameByID[detail.projectId] ?? AppLocalization.string("未命名工程")
        let reminder = SiteTodo(
            title: String(
                format: AppLocalization.string("material.priceSpike.purchaseReminder.title"),
                spikeMaterialTitle(detail)
            ),
            owner: "",
            dueDate: .day(CalendarDay(date: Date())),
            priority: .medium,
            issueType: .material,
            note: String(
                format: AppLocalization.string("material.priceSpike.purchaseReminder.note"),
                projectName,
                ReportBuilder.money(detail.previousPrice),
                detail.unit,
                spikeDisplayDate(detail.previousDate),
                ReportBuilder.money(detail.latestPrice),
                detail.unit,
                spikeDisplayDate(detail.latestDate),
                spikeRatioText(detail),
                marker
            ),
            projectId: detail.projectId
        )
        store.insertSiteTodoAtTop(reminder)
        store.scheduleSave()
        AppHaptics.success()
        actionFeedbackMessage = AppLocalization.string("已生成采购提醒")
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
                            Text(AppLocalization.string("已忽略"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: AppSpacing.tight * 0.375) {
                        Text(String(
                            format: AppLocalization.string("上次 %@/%@（%@）"),
                            ReportBuilder.money(detail.previousPrice),
                            detail.unit,
                            spikeDisplayDate(detail.previousDate)
                        ))
                        Text(String(
                            format: AppLocalization.string("本次 %@/%@（%@）"),
                            ReportBuilder.money(detail.latestPrice),
                            detail.unit,
                            spikeDisplayDate(detail.latestDate)
                        ))
                        .foregroundStyle(.primary)
                    }
                    .font(.caption)
                }
            }

            HStack(spacing: AppSpacing.tight) {
                Button {
                    onSetIgnored(!detail.isIgnored)
                } label: {
                    Label(detail.isIgnored ? AppLocalization.string("取消忽略") : AppLocalization.string("忽略本次"), systemImage: detail.isIgnored ? "arrow.uturn.backward.circle" : "eye.slash")
                }
                .tint(detail.isIgnored ? Color.appWarning : Color.secondary)

                Button {
                    onAdjustThreshold()
                } label: {
                    Label(AppLocalization.string("调整阈值"), systemImage: "slider.horizontal.3")
                }
                .tint(Color.appFinance)

                Button {
                    onCreateReminder()
                } label: {
                    Label(AppLocalization.string("生成采购提醒"), systemImage: "bell.badge")
                }
                .tint(Color.appWarning)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .contextMenu {
            Button(detail.isIgnored ? AppLocalization.string("取消忽略") : AppLocalization.string("忽略本次")) {
                onSetIgnored(!detail.isIgnored)
            }
            Button(AppLocalization.string("调整阈值")) {
                onAdjustThreshold()
            }
            Button(AppLocalization.string("生成采购提醒")) {
                onCreateReminder()
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(AppLocalization.string("提醒")) {
                onCreateReminder()
            }
            .tint(Color.appWarning)
            Button(AppLocalization.string("阈值")) {
                onAdjustThreshold()
            }
            .tint(Color.appFinance)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(detail.isIgnored ? AppLocalization.string("取消忽略") : AppLocalization.string("忽略")) {
                onSetIgnored(!detail.isIgnored)
            }
            .tint(detail.isIgnored ? Color.appWarning : Color.appMuted)
        }
    }
}

private func spikeRatioText(_ detail: MaterialPriceSpikeDetail) -> String {
    detail.ratio.formatted(.percent.precision(.fractionLength(1)))
}

private func spikeMaterialTitle(_ detail: MaterialPriceSpikeDetail) -> String {
    let spec = detail.specification.trimmingCharacters(in: .whitespacesAndNewlines)
    if spec.isEmpty { return detail.materialName }
    return DashboardSubtitleBuilder.joined([detail.materialName, spec])
}

private func spikeDisplayDate(_ value: BusinessDateValue) -> String {
    return value.isEmpty ? AppLocalization.string("未记录日期") : Formatters.displayDateText(value)
}
