import SwiftUI

extension LaborRecordView {
    // MARK: - 工种选择（带工价记忆）

    @ViewBuilder
    var workTypePickerSection: some View {
        if !savedWorkTypes.isEmpty {
            LabeledContent(AppLocalization.string("工种")) {
                HStack(spacing: 8) {
                    TextField(AppLocalization.string("工种（例如电工）"), text: $newWorkType)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("labor-work-type-input")
                        .onChange(of: newWorkType) { _, newVal in
                            autoFillRate(for: newVal)
                        }
                    Menu {
                        ForEach(savedWorkTypes, id: \.self) { type in
                            Button(type) {
                                selectWorkType(type)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .accessibilityLabel(AppLocalization.string("选择工种"))
                }
            }
        } else {
            TextField(AppLocalization.string("工种（例如电工）"), text: $newWorkType)
                .accessibilityIdentifier("labor-work-type-input")
                .onChange(of: newWorkType) { _, newVal in
                    autoFillRate(for: newVal)
                }
        }
    }

    // MARK: - 班组选择

    @ViewBuilder
    var teamPickerSection: some View {
        if !savedTeams.isEmpty {
            LabeledContent(AppLocalization.string("班组")) {
                HStack(spacing: 8) {
                    TextField(AppLocalization.string("班组（例如A组）"), text: $newTeamName)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("labor-team-input")
                    Menu {
                        ForEach(savedTeams, id: \.self) { team in
                            Button(team) { newTeamName = team }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .accessibilityLabel(AppLocalization.string("选择班组"))
                }
            }
        } else {
            TextField(AppLocalization.string("班组（例如A组）"), text: $newTeamName)
                .accessibilityIdentifier("labor-team-input")
        }
    }

    private func selectWorkType(_ type: String) {
        newWorkType = type
        autoFillRate(for: type)
    }

    private func autoFillRate(for workType: String) {
        let cleaned = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let pairs = savedRatePairs()
        if let rate = pairs[cleaned], newUnitRate.isEmpty {
            newUnitRate = rate
        }
    }

    private var rateStorageKey: String {
        if let pid = newProjectId { return "\(UserPreferenceKeys.laborRatePrefix)\(pid.uuidString)" }
        return "\(UserPreferenceKeys.laborRatePrefix)_global"
    }

    private func savedRatePairs() -> [String: String] {
        let raw = UserPreferencesStore.shared.string(
            rateStorageKey,
            default: "",
            trimWhitespace: false
        )
        var result = [String: String]()
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && !val.isEmpty { result[key] = val }
            }
        }
        return result
    }

    private func saveRatePair(workType: String, rate: String) {
        let cleanedType = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRate = rate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedType.isEmpty, !cleanedRate.isEmpty else { return }
        var pairs = savedRatePairs()
        pairs[cleanedType] = cleanedRate
        let raw = pairs.map { "\($0):\($1)" }.joined(separator: ",")
        UserPreferencesStore.shared.set(raw, for: rateStorageKey)
    }

    private func saveTeamName(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !savedTeams.contains(cleaned) else { return }
        var teams = savedTeams
        teams.append(cleaned)
        savedTeamsRaw = teams.joined(separator: ",")
    }

    private func saveWorkType(_ type: String) {
        let cleaned = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !savedWorkTypes.contains(cleaned) else { return }
        var types = savedWorkTypes
        types.append(cleaned)
        savedWorkTypesRaw = types.joined(separator: ",")
    }

    func laborRow(_ r: LaborRecord) -> some View {
        let projectText = r.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? AppLocalization.string("未归属")
        let workersText = r.workers.isEmpty ? "" : String(format: AppLocalization.string("%@人"), r.workers.wireText)
        let workloadText = r.hours.isEmpty ? "" : "\(r.hours)\(r.workloadUnit.displayName)"
        let meta = [r.workType, r.teamName, workersText, workloadText, r.date.storageText].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: AppSpacing.normal) {
            RoundedRectangle(cornerRadius: 2)
                .fill(r.isSettled ? Color.appSuccess : Color.appFinance)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.625) {
                HStack {
                    Text(projectText)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.tight)
                    Text(ReportBuilder.money(ReportBuilder.laborLineTotal(r)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appFinance)
                        .monospacedDigit()
                }
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !r.note.isEmpty {
                    Text(r.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    func save() {
        guard canSave else { return }
        store.appendLaborRecord(LaborRecord(
            date: .day(CalendarDay(date: newDate)),
            workers: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(newWorkers, kind: .quantity)),
            hours: NumericInputSupport.quantity(NumericInputSupport.normalizedStorageText(newDays, kind: .days)),
            workloadUnit: .workday,
            unitRate: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(newUnitRate, kind: .laborRate)),
            workType: newWorkType,
            teamName: newTeamName,
            isSettled: newIsSettled,
            note: newNote,
            projectId: newProjectId
        ))
        saveTeamName(newTeamName)
        saveWorkType(newWorkType)
        if !newWorkType.isEmpty && !newUnitRate.isEmpty {
            saveRatePair(workType: newWorkType, rate: newUnitRate)
        }
        store.scheduleSave()
        operationNotice = .info(AppLocalization.string("已新增人工记录"))
        newWorkers = ""
        newDays = ""
        newUnitRate = ""
        newWorkType = ""
        newTeamName = ""
        newIsSettled = false
        newNote = ""
        newProjectId = nil
    }

    var canSave: Bool {
        InputValidator.validate(newWorkers, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(newDays, kind: .days, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(newUnitRate, kind: .laborRate, requirement: .optionalNonNegative).isValid
    }

    var newLaborTotal: MoneyValue {
        let totalDays = NumericInputSupport.quantity(newDays)
        let workers = NumericInputSupport.quantity(newWorkers)
        let totalWorkDays = workers * totalDays
        return totalWorkDays * NumericInputSupport.money(newUnitRate)
    }

    func deleteLaborRecordsWithUndo(ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        let targets = store.laborRecords.filter { idSet.contains($0.id) }
        guard !targets.isEmpty else { return }
        let deletion = store.removeLaborRecords(
            ids: idSet,
            audit: DataStoreDeletionAuditContext(
                summary: AppLocalization.string("删除人工记录"),
                detail: targets.map { [$0.teamName, $0.workType].filter { !$0.isEmpty }.joined(separator: " / ") }.joined(separator: "、"),
                source: "LaborRecordView"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: AppLocalization.string("已删除 %lld 条人工记录"), Int64(deletion.deletedCount)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreLaborRecords(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    func flushPendingLaborDeletionIfNeeded() {
        undoableDeletion.flushPendingCommit()
    }
}
