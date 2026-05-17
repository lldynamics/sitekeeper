import SwiftUI
import UniformTypeIdentifiers

struct LightingCircuitPlannerView: View {
    @Environment(DataStore.self) private var store

    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerPlanName) private var savedPlanName: String = ""
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerSupplyType) private var savedSupplyTypeRawValue: String = CircuitSupplyType.singlePhase.rawValue
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerVoltage) private var savedVoltage: String = "220"
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerPowerFactor) private var savedPowerFactor: String = "0.90"
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerDemandFactor) private var savedDemandFactor: String = "0.90"
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerBreakerFactor) private var savedBreakerFactor: String = "1.25"
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerWireFactor) private var savedWireFactor: String = "1.15"
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerMainBreakerLimitA) private var savedMainBreakerLimitA: String = "100"
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerImbalanceLimitPercent) private var savedImbalanceLimitPercent: String = "15"
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerIsCopper) private var savedIsCopper: Bool = true
    @AppStorage(UserPreferenceKeys.Calculator.lightingPlannerRows) private var savedRowsJSON: String = ""

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

    @State private var rows: [LightingCircuitLoad] = [LightingCircuitLoad(name: String(localized: "lighting_planner_default_circuit_name"), powerKW: "3.0")]
    @State private var resultText = ""
    @State private var resultModel: CalculationResult?
    @State private var exportFormat: CircuitPlanExportFormat = .pdf
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var didRestorePersistedInputs = false
    @State private var isRestoringPersistedInputs = false
    @FocusState private var isInputFocused: Bool

    init(initialProjectId: UUID? = nil) {
        _selectedProjectId = State(initialValue: initialProjectId)
    }

    var body: some View {
        Form {
            Section(String(localized: "lighting_planner_plan_archive_section")) {
                Picker(String(localized: "lighting_planner_project_picker"), selection: $selectedProjectId) {
                    Text(String(localized: "lighting_planner_generic_unbound_project")).tag(Optional<UUID>.none)
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

                LabeledContent(String(localized: "lighting_planner_plan_name_label")) {
                    TextField(String(localized: "lighting_planner_plan_name_placeholder"), text: $planName)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }

                Picker(String(localized: "lighting_planner_saved_plan_picker"), selection: $selectedPlanId) {
                    Text(String(localized: "lighting_planner_unselected_option")).tag(Optional<UUID>.none)
                    ForEach(availablePlans) { plan in
                        Text(plan.name).tag(Optional(plan.id))
                    }
                }

                Button(String(localized: "lighting_planner_load_selected_plan_button")) { loadSelectedPlan() }
                    .disabled(selectedPlan == nil)
                Button(String(localized: "lighting_planner_overwrite_selected_plan_button")) { savePlan(overwrite: true) }
                    .disabled(selectedPlan == nil)
                Button(String(localized: "lighting_planner_save_as_new_plan_button")) { savePlan(overwrite: false) }
                Button(String(localized: "lighting_planner_delete_selected_plan_button"), role: .destructive) { deleteSelectedPlan() }
                    .disabled(selectedPlan == nil)

                Picker(String(localized: "lighting_planner_export_format_picker"), selection: $exportFormat) {
                    ForEach(CircuitPlanExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Button(String(localized: "lighting_planner_export_current_project_button")) { exportCurrentProjectPlans() }
                    .disabled(currentProject == nil || currentProjectPlans.isEmpty)
            }

            Section(String(localized: "lighting_planner_supply_params_section")) {
                Picker(String(localized: "lighting_planner_supply_type_picker"), selection: $supplyType) {
                    ForEach(CircuitSupplyType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: supplyType) { _, newType in
                    if !isRestoringPersistedInputs {
                        voltage = newType.defaultVoltage
                    }
                    persistInputs()
                }
                LabeledContent(String(localized: "lighting_planner_voltage_label")) {
                    TextField(String(localized: "lighting_planner_voltage_placeholder"), text: $voltage.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                LabeledContent(String(localized: "lighting_planner_power_factor_label")) {
                    TextField("0.90", text: $powerFactor.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                LabeledContent(String(localized: "lighting_planner_demand_factor_label")) {
                    TextField("0.90", text: $demandFactor.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                LabeledContent(String(localized: "lighting_planner_breaker_factor_label")) {
                    TextField("1.25", text: $breakerFactor.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                LabeledContent(String(localized: "lighting_planner_wire_factor_label")) {
                    TextField("1.15", text: $wireFactor.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                Toggle(String(localized: "lighting_planner_copper_wire_toggle"), isOn: $isCopper)
            }

            Section(String(localized: "lighting_planner_warning_threshold_section")) {
                LabeledContent(String(localized: "lighting_planner_main_breaker_limit_label")) {
                    TextField("100", text: $mainBreakerLimitA.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                LabeledContent(String(localized: "lighting_planner_imbalance_limit_label")) {
                    TextField("15", text: $imbalanceLimitPercent.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
            }

            Section(String(localized: "lighting_planner_circuit_load_section")) {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "lighting_planner_circuit_name_field"), text: $row.name)
                            .focused($isInputFocused)
                        LabeledContent(String(localized: "lighting_planner_installed_power_label")) {
                            TextField("0", text: $row.powerKW.numericInput(.quantity))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($isInputFocused)
                        }
                        if rows.count > 1 {
                            Button(String(localized: "lighting_planner_delete_circuit_button"), role: .destructive) {
                                rows.removeAll { $0.id == row.id }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    rows.append(
                        LightingCircuitLoad(
                            name: String(format: String(localized: "lighting_planner_circuit_name_increment_format"), rows.count + 1),
                            powerKW: ""
                        )
                    )
                } label: {
                    Label(String(localized: "lighting_planner_add_circuit_button"), systemImage: "plus.circle.fill")
                }
            }

            Section {
                Button(String(localized: "lighting_planner_generate_button")) {
                    isInputFocused = false
                    evaluate()
                }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if let resultModel {
                Section(String(localized: "lighting_planner_result_section")) {
                    CalculatorResultCard(
                        title: String(localized: "lighting_planner_result_title"),
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle(String(localized: "lighting_planner_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
        .onAppear(perform: restorePersistedInputsIfNeeded)
        .onChange(of: planName) { _, _ in persistInputs() }
        .onChange(of: voltage) { _, _ in persistInputs() }
        .onChange(of: powerFactor) { _, _ in persistInputs() }
        .onChange(of: demandFactor) { _, _ in persistInputs() }
        .onChange(of: breakerFactor) { _, _ in persistInputs() }
        .onChange(of: wireFactor) { _, _ in persistInputs() }
        .onChange(of: mainBreakerLimitA) { _, _ in persistInputs() }
        .onChange(of: imbalanceLimitPercent) { _, _ in persistInputs() }
        .onChange(of: isCopper) { _, _ in persistInputs() }
        .onChange(of: rowDraftSignature) { _, _ in persistInputs() }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .data,
            defaultFilename: exportPayload?.defaultFilename ?? String(localized: "lighting_planner_export_default_filename")
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
        guard let v = CalculatorInputParser.double(voltage),
              let pf = CalculatorInputParser.double(powerFactor),
              let demand = CalculatorInputParser.double(demandFactor),
              let bFactor = CalculatorInputParser.double(breakerFactor),
              let wFactor = CalculatorInputParser.double(wireFactor),
              let mainBreakerLimit = CalculatorInputParser.double(mainBreakerLimitA),
              let imbalanceLimit = CalculatorInputParser.double(imbalanceLimitPercent),
              v > 0,
              pf > 0, pf <= 1,
              demand > 0,
              bFactor > 0,
              wFactor > 0,
              mainBreakerLimit > 0,
              imbalanceLimit > 0 else {
            presentError(String(localized: "lighting_planner_invalid_input_error"))
            return
        }

        var rowValidationError: String?
        let validRows = rows.compactMap { row -> CircuitEvalRow? in
            guard let power = CalculatorInputParser.double(row.powerKW),
                  power > 0 else { return nil }
            let demandPower = power * demand
            let current: Double
            switch EngineeringCalculations.circuitCurrentValidated(
                powerKW: demandPower,
                voltage: v,
                powerFactor: pf,
                isThreePhase: supplyType == .threePhase
            ) {
            case .success(let value):
                current = value
            case .failure(let error):
                if rowValidationError == nil {
                    let displayName = row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "lighting_planner_unnamed_circuit") : row.name
                    rowValidationError = String(
                        format: String(localized: "lighting_planner_row_validation_error_format"),
                        displayName,
                        error.userMessage
                    )
                }
                return nil
            }
            let breaker = EngineeringCalculations.recommendedBreaker(current: current, safetyFactor: bFactor)
            let wire = EngineeringCalculations.recommendedWireSectionByAmpacity(current: current, isCopper: isCopper, safetyFactor: wFactor)
            return CircuitEvalRow(
                name: row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "lighting_planner_unnamed_circuit") : row.name,
                installedPowerKW: power,
                demandPowerKW: demandPower,
                currentA: current,
                breakerA: breaker,
                wireSection: wire
            )
        }

        if let rowValidationError {
            presentError(rowValidationError)
            return
        }

        guard !validRows.isEmpty else {
            presentError(String(localized: "lighting_planner_no_valid_circuit_power_error"))
            return
        }

        var lines: [String] = []
        lines.append(
            String(format: String(localized: "lighting_planner_supply_line_format"), supplyType.displayName, Int(v))
        )
        lines.append(
            String(
                format: String(localized: "lighting_planner_pf_demand_line_format"),
                String(format: "%.2f", pf),
                String(format: "%.2f", demand)
            )
        )
        lines.append(
            String(
                format: String(localized: "lighting_planner_breaker_wire_factor_line_format"),
                String(format: "%.2f", bFactor),
                String(format: "%.2f", wFactor)
            )
        )
        lines.append("")
        lines.append(String(localized: "lighting_planner_circuit_detail_header"))

        let phaseAssignments: [Int]
        if supplyType == .threePhase {
            let currents = validRows.map(\.currentA)
            phaseAssignments = EngineeringCalculations.assignThreePhases(currents: currents)
        } else {
            phaseAssignments = Array(repeating: 0, count: validRows.count)
        }

        for (index, row) in validRows.enumerated() {
            let phaseLabel = supplyType == .threePhase
                ? String(format: String(localized: "lighting_planner_phase_label_format"), phaseName(phaseAssignments[index]))
                : ""
            lines.append(
                String(
                    format: String(localized: "lighting_planner_row_line_format"),
                    row.name,
                    fmt(row.installedPowerKW),
                    fmt(row.demandPowerKW),
                    fmt(row.currentA),
                    row.breakerA,
                    row.wireSection.map { fmtSection($0) + "mm²" } ?? String(localized: "lighting_planner_wire_over_spec"),
                    phaseLabel
                )
            )
        }

        let totalInstalled = validRows.reduce(0) { $0 + $1.installedPowerKW }
        let totalDemand = validRows.reduce(0) { $0 + $1.demandPowerKW }
        let totalCurrent = validRows.reduce(0) { $0 + $1.currentA }

        lines.append("")
        lines.append(String(localized: "lighting_planner_summary_header"))
        lines.append(String(format: String(localized: "lighting_planner_summary_circuit_count_format"), validRows.count))
        lines.append(String(format: String(localized: "lighting_planner_summary_total_installed_format"), fmt(totalInstalled)))
        lines.append(String(format: String(localized: "lighting_planner_summary_total_demand_format"), fmt(totalDemand)))
        lines.append(String(format: String(localized: "lighting_planner_summary_total_current_format"), fmt(totalCurrent)))

        var warnings: [String] = []
        var currentForMainBreaker = totalCurrent
        var phaseSummary: String?

        if supplyType == .threePhase {
            let totals = EngineeringCalculations.phaseTotals(currents: validRows.map(\.currentA), assignments: phaseAssignments)
            let imbalance = EngineeringCalculations.threePhaseImbalancePercent(phaseTotals: totals)
            currentForMainBreaker = totals.max() ?? totalCurrent
            if totals.count >= 3 {
                lines.append(
                    String(
                        format: String(localized: "lighting_planner_summary_abc_current_format"),
                        fmt(totals[0]),
                        fmt(totals[1]),
                        fmt(totals[2])
                    )
                )
            }
            lines.append(String(format: String(localized: "lighting_planner_summary_imbalance_format"), fmt(imbalance)))
            phaseSummary = totals.count >= 3
                ? String(
                    format: String(localized: "lighting_planner_phase_summary_format"),
                    fmt(totals[0]),
                    fmt(totals[1]),
                    fmt(totals[2])
                )
                : nil
            if imbalance > imbalanceLimit {
                warnings.append(
                    String(
                        format: String(localized: "lighting_planner_imbalance_warning_format"),
                        fmt(imbalance),
                        fmt(imbalanceLimit)
                    )
                )
            }
        }

        if currentForMainBreaker > mainBreakerLimit {
            warnings.append(
                String(
                    format: String(localized: "lighting_planner_main_breaker_warning_format"),
                    fmt(currentForMainBreaker),
                    fmt(mainBreakerLimit)
                )
            )
        }
        let mainBreakerRecommend = EngineeringCalculations.recommendedBreaker(current: currentForMainBreaker, safetyFactor: bFactor)
        lines.append(String(format: String(localized: "lighting_planner_main_breaker_recommend_format"), mainBreakerRecommend))

        lines.append("")
        if warnings.isEmpty {
            lines.append(String(localized: "lighting_planner_no_warning_line"))
        } else {
            lines.append(String(localized: "lighting_planner_warning_header"))
            lines += warnings.map { "- \($0)" }
        }

        var summaryItems: [CalculationResult.ResultItem] = [
            CalculationResult.item(String(localized: "lighting_planner_item_supply"), "\(supplyType.displayName) \(Int(v))V"),
            CalculationResult.item(String(localized: "lighting_planner_item_circuit_count"), "\(validRows.count)"),
            CalculationResult.item(String(localized: "lighting_planner_item_total_installed"), "\(fmt(totalInstalled)) kW"),
            CalculationResult.item(String(localized: "lighting_planner_item_total_demand"), "\(fmt(totalDemand)) kW"),
            CalculationResult.item(String(localized: "lighting_planner_item_total_current"), "\(fmt(totalCurrent)) A"),
            CalculationResult.item(String(localized: "lighting_planner_item_main_breaker"), "\(mainBreakerRecommend)A", status: warnings.isEmpty ? .pass : .warning),
        ]
        if let phaseSummary {
            summaryItems.append(CalculationResult.item(String(localized: "lighting_planner_item_three_phase_distribution"), phaseSummary))
        }
        if warnings.isEmpty {
            summaryItems.append(
                CalculationResult.item(
                    String(localized: "lighting_planner_item_warning_status"),
                    String(localized: "lighting_planner_item_no_warning"),
                    status: .pass
                )
            )
        } else {
            for warning in warnings {
                summaryItems.append(CalculationResult.item(String(localized: "lighting_planner_item_warning"), warning, status: .warning))
            }
        }

        let rowItems = validRows.map { row -> CalculationResult.ResultItem in
            let wireText = row.wireSection.map { "\(fmtSection($0))mm²" } ?? String(localized: "lighting_planner_wire_over_spec")
            let status: CalculationResult.ResultStatus = row.wireSection == nil ? .warning : .normal
            return CalculationResult.item(
                row.name,
                String(
                    format: String(localized: "lighting_planner_row_item_detail_format"),
                    fmt(row.currentA),
                    row.breakerA,
                    wireText
                ),
                status: status
            )
        }
        resultModel = CalculationResult(
            headline: warnings.isEmpty
                ? String(localized: "lighting_planner_headline_no_warning")
                : String(format: String(localized: "lighting_planner_headline_warning_count_format"), warnings.count),
            formula: String(localized: "lighting_planner_formula"),
            sections: [
                .init(title: String(localized: "lighting_planner_section_summary"), items: summaryItems),
                .init(title: String(localized: "lighting_planner_section_circuit_detail"), items: rowItems),
            ]
        )
        resultText = lines.joined(separator: "\n")
        store.appendCalculationHistory(
            tool: String(localized: "lighting_planner_nav_title"),
            input: String(format: String(localized: "lighting_planner_history_input_format"), validRows.count, Int(v)),
            result: String(format: String(localized: "lighting_planner_history_result_format"), fmt(totalCurrent))
        )
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
                defaultFilename: String(format: String(localized: "lighting_planner_export_pdf_filename_format"), project.name)
            )
        case .excel:
            exportPayload = ExportPayload(
                data: ReportBuilder.makeLightingCircuitPlansExcelHTML(projectName: project.name, plans: plans),
                contentType: .excelHTML,
                defaultFilename: String(format: String(localized: "lighting_planner_export_excel_filename_format"), project.name)
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
        rows = plan.loads.isEmpty ? [LightingCircuitLoad(name: String(localized: "lighting_planner_default_circuit_name"), powerKW: "")] : plan.loads
        resultText = ""
        resultModel = nil
        persistInputs()
    }

    private func savePlan(overwrite: Bool) {
        let trimmedName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? defaultPlanName : trimmedName
        let normalizedRows = rows.map { load in
            LightingCircuitLoad(
                id: load.id,
                name: load.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "lighting_planner_unnamed_circuit") : load.name,
                powerKW: load.powerKW
            )
        }

        if overwrite, let selected = selectedPlan,
           store.lightingCircuitPlans.contains(where: { $0.id == selected.id }) {
            store.updateLightingCircuitPlan(LightingCircuitPlan(
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
            ))
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
            store.insertLightingCircuitPlanAtTop(plan)
            selectedPlanId = plan.id
        }
        planName = finalName
        store.scheduleSave()
        persistInputs()
    }

    private func deleteSelectedPlan() {
        guard let selected = selectedPlan else { return }
        store.removeLightingCircuitPlans(ids: Set([selected.id]))
        selectedPlanId = nil
        store.scheduleSave()
        persistInputs()
    }

    private var defaultPlanName: String {
        if let pid = selectedProjectId,
           let project = store.projects.first(where: { $0.id == pid }) {
            return String(format: String(localized: "lighting_planner_default_plan_name_project_format"), project.name)
        }
        return String(localized: "lighting_planner_default_plan_name_generic")
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

    private func presentError(_ message: String) {
        resultText = message
        resultModel = .error(message)
    }

    private func restorePersistedInputsIfNeeded() {
        guard !didRestorePersistedInputs else { return }
        didRestorePersistedInputs = true
        isRestoringPersistedInputs = true

        planName = savedPlanName
        supplyType = StringEnumFallback.value(savedSupplyTypeRawValue, default: CircuitSupplyType.singlePhase)
        voltage = savedVoltage
        powerFactor = savedPowerFactor
        demandFactor = savedDemandFactor
        breakerFactor = savedBreakerFactor
        wireFactor = savedWireFactor
        mainBreakerLimitA = savedMainBreakerLimitA
        imbalanceLimitPercent = savedImbalanceLimitPercent
        isCopper = savedIsCopper
        if let data = savedRowsJSON.data(using: .utf8) {
            do {
                let decodedRows = try JSONDecoder().decode([LightingCircuitLoad].self, from: data)
                if !decodedRows.isEmpty {
                    rows = decodedRows
                }
            } catch {
                StorageIssueLog.record(
                    String(
                        format: String(localized: "lighting_planner_draft_decode_failed_format"),
                        error.localizedDescription
                    )
                )
            }
        }

        isRestoringPersistedInputs = false
    }

    private func persistInputs() {
        guard !isRestoringPersistedInputs else { return }
        savedPlanName = planName
        savedSupplyTypeRawValue = supplyType.rawValue
        savedVoltage = voltage
        savedPowerFactor = powerFactor
        savedDemandFactor = demandFactor
        savedBreakerFactor = breakerFactor
        savedWireFactor = wireFactor
        savedMainBreakerLimitA = mainBreakerLimitA
        savedImbalanceLimitPercent = imbalanceLimitPercent
        savedIsCopper = isCopper
        do {
            let data = try JSONEncoder().encode(rows)
            if let encodedRows = String(data: data, encoding: .utf8) {
                savedRowsJSON = encodedRows
            } else {
                StorageIssueLog.record(String(localized: "lighting_planner_draft_utf8_convert_failed"))
            }
        } catch {
            StorageIssueLog.record(
                String(
                    format: String(localized: "lighting_planner_draft_encode_failed_format"),
                    error.localizedDescription
                )
            )
        }
    }

    private var rowDraftSignature: String {
        rows.map { "\($0.id.uuidString)|\($0.name)|\($0.powerKW)" }
            .joined(separator: "\n")
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
