import SwiftUI
import UniformTypeIdentifiers

struct LightingCircuitPlannerView: View {
    @Environment(DataStore.self) private var store

    @State private var selectedProjectId: UUID?
    @State private var selectedPlanId: UUID?
    @State private var planName: String = ""

    @State private var supplyType: CircuitSupplyType = .singlePhase
    @State private var voltage: String = "220"
    @State private var powerFactor: String = "0.90"
    @State private var demandFactor: String = "0.90"
    @State private var breakerFactor: String = "1.25"
    @State private var wireFactor: String = "1.15"
    @State private var mainBreakerLimitA: String = "100"
    @State private var imbalanceLimitPercent: String = "15"
    @State private var isCopper: Bool = true

    @State private var rows: [LightingCircuitLoad] = [LightingCircuitLoad(name: "照明回路 1", powerKW: "3.0")]
    @State private var resultText = ""
    @State private var exportFormat: CircuitPlanExportFormat = .pdf
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false

    init(initialProjectId: UUID? = nil) {
        _selectedProjectId = State(initialValue: initialProjectId)
    }

    var body: some View {
        Form {
            Section("方案归档") {
                Picker("所属项目", selection: $selectedProjectId) {
                    Text("通用（不绑定项目）").tag(Optional<UUID>.none)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .onChange(of: selectedProjectId) { _, _ in
                    if let pid = selectedPlanId,
                       !availablePlans.contains(where: { $0.id == pid }) {
                        selectedPlanId = nil
                    }
                }

                LabeledContent("方案名称") {
                    TextField("例如：3层公共照明", text: $planName)
                        .multilineTextAlignment(.trailing)
                }

                Picker("已保存方案", selection: $selectedPlanId) {
                    Text("未选择").tag(Optional<UUID>.none)
                    ForEach(availablePlans) { plan in
                        Text(plan.name).tag(Optional(plan.id))
                    }
                }

                Button("载入已选方案") { loadSelectedPlan() }
                    .disabled(selectedPlan == nil)
                Button("覆盖保存到已选方案") { savePlan(overwrite: true) }
                    .disabled(selectedPlan == nil)
                Button("另存为新方案") { savePlan(overwrite: false) }
                Button("删除已选方案", role: .destructive) { deleteSelectedPlan() }
                    .disabled(selectedPlan == nil)

                Picker("导出格式", selection: $exportFormat) {
                    ForEach(CircuitPlanExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Button("导出当前项目方案") { exportCurrentProjectPlans() }
                    .disabled(currentProject == nil || currentProjectPlans.isEmpty)
            }

            Section("供电参数") {
                Picker("供电类型", selection: $supplyType) {
                    ForEach(CircuitSupplyType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: supplyType) { _, newType in
                    voltage = newType.defaultVoltage
                }
                LabeledContent("电压 (V)") {
                    TextField("220 / 380", text: $voltage)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("功率因数") {
                    TextField("0.90", text: $powerFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("需用系数") {
                    TextField("0.90", text: $demandFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("断路器裕量") {
                    TextField("1.25", text: $breakerFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("线径裕量") {
                    TextField("1.15", text: $wireFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("铜导线", isOn: $isCopper)
            }

            Section("预警阈值") {
                LabeledContent("总开关容量 (A)") {
                    TextField("100", text: $mainBreakerLimitA)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("三相不平衡阈值 (%)") {
                    TextField("15", text: $imbalanceLimitPercent)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("回路负荷") {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("回路名称", text: $row.name)
                        LabeledContent("装机功率 (kW)") {
                            TextField("0", text: $row.powerKW)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        if rows.count > 1 {
                            Button("删除回路", role: .destructive) {
                                rows.removeAll { $0.id == row.id }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    rows.append(LightingCircuitLoad(name: "照明回路 \(rows.count + 1)", powerKW: ""))
                } label: {
                    Label("新增回路", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Button("生成回路表") { evaluate() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if !resultText.isEmpty {
                Section("计算结果") {
                    Text(resultText)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle("照明回路表")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .data,
            defaultFilename: exportPayload?.defaultFilename ?? "照明回路方案导出"
        ) { _ in }
    }

    private var availablePlans: [LightingCircuitPlan] {
        let filtered = store.lightingCircuitPlans.filter { $0.projectId == selectedProjectId }
        return filtered.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedPlan: LightingCircuitPlan? {
        guard let pid = selectedPlanId else { return nil }
        return store.lightingCircuitPlans.first { $0.id == pid }
    }

    private var currentProject: Project? {
        guard let pid = selectedProjectId else { return nil }
        return store.projects.first { $0.id == pid }
    }

    private var currentProjectPlans: [LightingCircuitPlan] {
        guard let pid = selectedProjectId else { return [] }
        return store.lightingCircuitPlans
            .filter { $0.projectId == pid }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private func evaluate() {
        guard let v = Double(voltage), v > 0,
              let pf = Double(powerFactor), pf > 0, pf <= 1,
              let demand = Double(demandFactor), demand > 0,
              let bFactor = Double(breakerFactor), bFactor > 0,
              let wFactor = Double(wireFactor), wFactor > 0,
              let mainBreakerLimit = Double(mainBreakerLimitA), mainBreakerLimit > 0,
              let imbalanceLimit = Double(imbalanceLimitPercent), imbalanceLimit > 0 else {
            resultText = "请输入有效参数"
            return
        }

        let validRows = rows.compactMap { row -> CircuitEvalRow? in
            let power = Double(row.powerKW) ?? 0
            guard power > 0 else { return nil }
            let demandPower = power * demand
            let current = EngineeringCalculations.circuitCurrent(
                powerKW: demandPower,
                voltage: v,
                powerFactor: pf,
                isThreePhase: supplyType == .threePhase
            )
            let breaker = EngineeringCalculations.recommendedBreaker(current: current, safetyFactor: bFactor)
            let wire = EngineeringCalculations.recommendedWireSectionByAmpacity(current: current, isCopper: isCopper, safetyFactor: wFactor)
            return CircuitEvalRow(
                name: row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名回路" : row.name,
                installedPowerKW: power,
                demandPowerKW: demandPower,
                currentA: current,
                breakerA: breaker,
                wireSection: wire
            )
        }

        guard !validRows.isEmpty else {
            resultText = "请至少填写一个回路的有效功率"
            return
        }

        var lines: [String] = []
        lines.append("供电: \(supplyType.displayName)  \(Int(v))V")
        lines.append("功率因数: \(String(format: "%.2f", pf))  需用系数: \(String(format: "%.2f", demand))")
        lines.append("断路器裕量: \(String(format: "%.2f", bFactor))  线径裕量: \(String(format: "%.2f", wFactor))")
        lines.append("")
        lines.append("回路明细:")

        let phaseAssignments: [Int]
        if supplyType == .threePhase {
            let currents = validRows.map(\.currentA)
            phaseAssignments = EngineeringCalculations.assignThreePhases(currents: currents)
        } else {
            phaseAssignments = Array(repeating: 0, count: validRows.count)
        }

        for (index, row) in validRows.enumerated() {
            let phaseLabel = supplyType == .threePhase ? "  相别\(phaseName(phaseAssignments[index]))" : ""
            lines.append(
                "- \(row.name): 装机\(fmt(row.installedPowerKW))kW, 计算\(fmt(row.demandPowerKW))kW, " +
                "I=\(fmt(row.currentA))A, 空开\(row.breakerA)A, 线径\(row.wireSection.map { fmtSection($0) + "mm²" } ?? "超规格")\(phaseLabel)"
            )
        }

        let totalInstalled = validRows.reduce(0) { $0 + $1.installedPowerKW }
        let totalDemand = validRows.reduce(0) { $0 + $1.demandPowerKW }
        let totalCurrent = validRows.reduce(0) { $0 + $1.currentA }

        lines.append("")
        lines.append("汇总:")
        lines.append("- 回路数: \(validRows.count)")
        lines.append("- 总装机功率: \(fmt(totalInstalled)) kW")
        lines.append("- 总计算功率: \(fmt(totalDemand)) kW")
        lines.append("- 电流合计: \(fmt(totalCurrent)) A")

        var warnings: [String] = []
        var currentForMainBreaker = totalCurrent

        if supplyType == .threePhase {
            let totals = EngineeringCalculations.phaseTotals(currents: validRows.map(\.currentA), assignments: phaseAssignments)
            let imbalance = EngineeringCalculations.threePhaseImbalancePercent(phaseTotals: totals)
            currentForMainBreaker = totals.max() ?? totalCurrent
            lines.append("- A/B/C相电流: \(fmt(totals[0])) / \(fmt(totals[1])) / \(fmt(totals[2])) A")
            lines.append("- 三相不平衡: \(fmt(imbalance))%")
            if imbalance > imbalanceLimit {
                warnings.append("三相不平衡 \(fmt(imbalance))% 超过阈值 \(fmt(imbalanceLimit))%")
            }
        }

        if currentForMainBreaker > mainBreakerLimit {
            warnings.append("计算电流 \(fmt(currentForMainBreaker))A 超过总开关容量 \(fmt(mainBreakerLimit))A")
        }
        let mainBreakerRecommend = EngineeringCalculations.recommendedBreaker(current: currentForMainBreaker, safetyFactor: bFactor)
        lines.append("- 主开关建议: \(mainBreakerRecommend)A（按断路器裕量）")

        lines.append("")
        if warnings.isEmpty {
            lines.append("预警: 未触发超限")
        } else {
            lines.append("预警:")
            lines += warnings.map { "- \($0)" }
        }

        resultText = lines.joined(separator: "\n")
        store.historyRecords.insert(
            HistoryRecord(
                tool: "照明回路表",
                input: "\(validRows.count)回路, \(Int(v))V",
                result: "总电流 \(fmt(totalCurrent))A",
                date: Formatters.now()
            ),
            at: 0
        )
        store.scheduleSave()
    }

    private func exportCurrentProjectPlans() {
        guard let project = currentProject else { return }
        let plans = currentProjectPlans
        guard !plans.isEmpty else { return }
        switch exportFormat {
        case .pdf:
            exportPayload = ExportPayload(
                data: ReportBuilder.makeLightingCircuitPlansPDF(projectName: project.name, plans: plans),
                contentType: .pdf,
                defaultFilename: "\(project.name)_照明回路方案.pdf"
            )
        case .excel:
            exportPayload = ExportPayload(
                data: ReportBuilder.makeLightingCircuitPlansExcelHTML(projectName: project.name, plans: plans),
                contentType: .excelHTML,
                defaultFilename: "\(project.name)_照明回路方案.xls"
            )
        }
        showExporter = true
    }

    private func loadSelectedPlan() {
        guard let plan = selectedPlan else { return }
        selectedProjectId = plan.projectId
        planName = plan.name
        supplyType = plan.supplyType
        voltage = plan.voltage
        powerFactor = plan.powerFactor
        demandFactor = plan.demandFactor
        breakerFactor = plan.breakerFactor
        wireFactor = plan.wireFactor
        isCopper = plan.isCopper
        rows = plan.loads.isEmpty ? [LightingCircuitLoad(name: "照明回路 1", powerKW: "")] : plan.loads
        resultText = ""
    }

    private func savePlan(overwrite: Bool) {
        let trimmedName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? defaultPlanName : trimmedName
        let normalizedRows = rows.map { load in
            LightingCircuitLoad(
                id: load.id,
                name: load.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名回路" : load.name,
                powerKW: load.powerKW
            )
        }

        if overwrite, let selected = selectedPlan,
           let idx = store.lightingCircuitPlans.firstIndex(where: { $0.id == selected.id }) {
            store.lightingCircuitPlans[idx] = LightingCircuitPlan(
                id: selected.id,
                name: finalName,
                projectId: selectedProjectId,
                supplyType: supplyType,
                voltage: voltage,
                powerFactor: powerFactor,
                demandFactor: demandFactor,
                breakerFactor: breakerFactor,
                wireFactor: wireFactor,
                isCopper: isCopper,
                loads: normalizedRows,
                updatedAt: Formatters.now()
            )
        } else {
            let plan = LightingCircuitPlan(
                name: finalName,
                projectId: selectedProjectId,
                supplyType: supplyType,
                voltage: voltage,
                powerFactor: powerFactor,
                demandFactor: demandFactor,
                breakerFactor: breakerFactor,
                wireFactor: wireFactor,
                isCopper: isCopper,
                loads: normalizedRows,
                updatedAt: Formatters.now()
            )
            store.lightingCircuitPlans.insert(plan, at: 0)
            selectedPlanId = plan.id
        }
        planName = finalName
        store.scheduleSave()
    }

    private func deleteSelectedPlan() {
        guard let selected = selectedPlan else { return }
        store.lightingCircuitPlans.removeAll { $0.id == selected.id }
        selectedPlanId = nil
        store.scheduleSave()
    }

    private var defaultPlanName: String {
        if let pid = selectedProjectId,
           let project = store.projects.first(where: { $0.id == pid }) {
            return "\(project.name)-照明回路"
        }
        return "通用照明回路"
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func fmtSection(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func phaseName(_ index: Int) -> String {
        switch index {
        case 0: return "A"
        case 1: return "B"
        case 2: return "C"
        default: return "-"
        }
    }
}

private struct CircuitEvalRow {
    var name: String
    var installedPowerKW: Double
    var demandPowerKW: Double
    var currentA: Double
    var breakerA: Int
    var wireSection: Double?
}

private enum CircuitPlanExportFormat: String, CaseIterable {
    case pdf
    case excel

    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .excel: "Excel"
        }
    }
}
