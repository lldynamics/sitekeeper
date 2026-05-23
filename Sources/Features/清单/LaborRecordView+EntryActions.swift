import SwiftUI

extension LaborRecordView {
    // MARK: - 工种选择（带工价记忆）

    @ViewBuilder
    var workTypePickerSection: some View {
        if !savedWorkTypes.isEmpty {
            LabeledContent(String(localized: "工种")) {
                Menu {
                    ForEach(savedWorkTypes, id: \.self) { type in
                        Button(type) {
                            selectWorkType(type)
                        }
                    }
                    Divider()
                    Button(String(localized: "自定义")) {
                        newWorkType = ""
                    }
                } label: {
                    Text(newWorkType.isEmpty ? String(localized: "选择工种") : newWorkType)
                        .foregroundStyle(newWorkType.isEmpty ? .secondary : .primary)
                }
            }
        } else {
            TextField(String(localized: "工种（例如电工）"), text: $newWorkType)
                .onChange(of: newWorkType) { _, newVal in
                    autoFillRate(for: newVal)
                }
        }
    }

    // MARK: - 班组选择

    @ViewBuilder
    var teamPickerSection: some View {
        if !savedTeams.isEmpty {
            LabeledContent(String(localized: "班组")) {
                Menu {
                    ForEach(savedTeams, id: \.self) { team in
                        Button(team) { newTeamName = team }
                    }
                    Divider()
                    Button(String(localized: "自定义")) { newTeamName = "" }
                } label: {
                    Text(newTeamName.isEmpty ? String(localized: "选择班组") : newTeamName)
                        .foregroundStyle(newTeamName.isEmpty ? .secondary : .primary)
                }
            }
        } else {
            TextField(String(localized: "班组（例如A组）"), text: $newTeamName)
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
        let projectText = r.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? String(localized: "未归属")
        let workersText = r.workers.isEmpty ? "" : String(format: String(localized: "%@人"), r.workers)
        let daysText = r.days.isEmpty ? "" : String(format: String(localized: "%@天"), r.days)
        let meta = [r.workType, r.teamName, workersText, daysText, r.date].filter { !$0.isEmpty }.joined(separator: " · ")
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
            date: Formatters.date.string(from: newDate),
            workers: NumericInputSupport.normalizedStorageText(newWorkers, kind: .quantity),
            hours: NumericInputSupport.normalizedStorageText(newDays, kind: .days),
            unitRate: NumericInputSupport.normalizedStorageText(newUnitRate, kind: .laborRate),
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
        operationNotice = .info(String(localized: "已新增人工记录"))
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
        let totalDays = QuantityValue(text: newDays)
        let workers = QuantityValue(text: newWorkers)
        return workers * totalDays * MoneyValue(text: newUnitRate)
    }

    func deleteLaborRecordsWithUndo(ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        let targets = store.laborRecords.filter { idSet.contains($0.id) }
        guard !targets.isEmpty else { return }
        let deletion = store.removeLaborRecords(
            ids: idSet,
            audit: DataStoreDeletionAuditContext(
                summary: String(localized: "删除人工记录"),
                detail: targets.map { [$0.teamName, $0.workType].filter { !$0.isEmpty }.joined(separator: " / ") }.joined(separator: "、"),
                source: "LaborRecordView"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条人工记录"), Int64(deletion.deletedCount)),
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
