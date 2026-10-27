import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    var addLogForm: some View {
        AppBusinessFormSheet(
            title: AppLocalization.string("写日志"),
            isPrimaryActionDisabled: !canSaveLog,
            onCancel: {
                persistComposerDraft()
                if draftError == nil || !draftLoaded { closeComposer() }
            },
            onPrimaryAction: {
                save()
            }
        ) {
                draftStatusSection
                Button(AppLocalization.string("丢弃草稿"), role: .destructive) { showDiscardLogDraft = true }
                    .accessibilityIdentifier("daily-log-discard-draft")
                Section(AppLocalization.string("基础信息")) {
                    DatePicker(AppLocalization.string("日期"), selection: $composer.date.daySelection, displayedComponents: .date)
                    weatherField(selection: $composer.weather)
                    TextField(AppLocalization.string("人数"), text: $composer.workers)
                    Picker(AppLocalization.string("选择工程"), selection: $composer.projectId) {
                        Text(AppLocalization.string("无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section(AppLocalization.string("施工内容")) {
                    Menu(AppLocalization.string("套用内容模板")) {
                        ForEach(contentTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.content = tpl }
                        }
                    }
                    if !store.templates.filter({ $0.category == .dailyLog }).isEmpty {
                        Menu(AppLocalization.string("套用我的日志模板")) {
                            ForEach(store.templates.filter { $0.category == .dailyLog }) { template in
                                Button(template.name) { applyDailyLogTemplate(template) }
                            }
                        }
                    }
                    TextField(AppLocalization.string("内容"), text: $composer.content, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("daily-log-compose-content")
                }
                Section(AppLocalization.string("安全与材料")) {
                    Menu(AppLocalization.string("套用安全模板")) {
                        ForEach(safetyTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.safety = tpl }
                        }
                    }
                    TextField(AppLocalization.string("安全事项"), text: $composer.safety, axis: .vertical)
                        .lineLimit(2...4)
                    Menu(AppLocalization.string("套用材料模板")) {
                        ForEach(materialTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.materials = tpl }
                        }
                    }
                    TextField(AppLocalization.string("材料进场"), text: $composer.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(AppLocalization.string("计划与质量")) {
                    Button {
                        composer.tomorrowPlan = generateTomorrowPlanFromTodos(for: composer.projectId)
                    } label: {
                        Label(AppLocalization.string("从今日待办生成明日计划"), systemImage: "wand.and.stars")
                    }
                    TextField(AppLocalization.string("明日计划"), text: $composer.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(AppLocalization.string("质量问题"), text: $composer.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(AppLocalization.string("整改记录"), text: $composer.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(AppLocalization.string("现场确认人"), text: $composer.confirmer)
                }
                constructionMethodLinkSection(selection: $composer.linkedMethodIDs)
                DailyLogWatermarkPhotoSection(
                    cameraPhotoTag: $composer.cameraPhotoTag,
                    selectedPhotos: $composer.selectedPhotos,
                    photoDrafts: $composer.photoDrafts,
                    isImporting: photoImportSession.isImporting,
                    onOpenCamera: { composer.showLogCamera = true }
                )
        }
        .disabled(isSavingLog)
        .interactiveDismissDisabled(isSavingLog || draftError != nil)
        .confirmationDialog(AppLocalization.string("丢弃草稿？"), isPresented: $showDiscardLogDraft, titleVisibility: .visible) {
            Button(AppLocalization.string("丢弃草稿"), role: .destructive) { discardComposerDraft() }
        }
        .onChange(of: composer.selectedPhotos) { _, newItems in
            importSelectedPhotos(newItems)
        }
        .sheet(isPresented: $composer.showLogCamera) {
            ImagePickerView(
                sourceType: .camera,
                onPickedWithTimestamp: { image, capturedAt in
                    appendCameraPhoto(image, capturedAt: capturedAt)
                },
                onPicked: { image in
                    appendCameraPhoto(image, capturedAt: Date())
                }
            )
        }
    }

    var editLogForm: some View {
        AppBusinessFormSheet(
            title: AppLocalization.string("编辑日志"),
            isPrimaryActionDisabled: isSavingLog || pendingEditorDraft != nil || editor.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCancel: {
                persistEditorDraft()
                if draftError == nil || !editorDraftReady { showEdit = false }
            },
            onPrimaryAction: {
                saveEditedLog()
            }
        ) {
                draftStatusSection
                if let pendingEditorDraft {
                    Section(AppLocalization.string("发现未完成的编辑草稿")) {
                        Text(AppLocalization.string("恢复草稿只会填入表单；请核对当前记录后再保存。"))
                        Button(AppLocalization.string("恢复草稿")) {
                            editor = pendingEditorDraft
                            if let text = pendingEditorDraft.dateText { editor.date = BusinessDateValue(legacyText: text) }
                            editor.baseRecord = store.dailyLogs.first(where: { $0.id == editor.logId }).flatMap { BusinessDraftStore.fingerprint($0) }
                            self.pendingEditorDraft = nil
                            editorDraftReady = true
                        }
                        Button(AppLocalization.string("丢弃草稿"), role: .destructive) {
                            do {
                                if let id = editor.logId { try businessDraftStore.discard(key: .dailyEdit(id)) }
                                self.pendingEditorDraft = nil
                                editorDraftReady = true
                            } catch { draftError = error.localizedDescription }
                        }
                    }
                }
                Section(AppLocalization.string("基础信息")) {
                    DatePicker(AppLocalization.string("日期"), selection: $editor.date.daySelection, displayedComponents: .date)
                    weatherField(selection: $editor.weather)
                    TextField(AppLocalization.string("人数"), text: $editor.workers)
                    Picker(AppLocalization.string("选择工程"), selection: $editor.projectId) {
                        Text(AppLocalization.string("无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section(AppLocalization.string("施工内容")) {
                    TextField(AppLocalization.string("内容"), text: $editor.content, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section(AppLocalization.string("安全与材料")) {
                    TextField(AppLocalization.string("安全事项"), text: $editor.safety, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(AppLocalization.string("材料进场"), text: $editor.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(AppLocalization.string("计划与质量")) {
                    Button {
                        editor.tomorrowPlan = generateTomorrowPlanFromTodos(for: editor.projectId)
                    } label: {
                        Label(AppLocalization.string("从今日待办生成明日计划"), systemImage: "wand.and.stars")
                    }
                    TextField(AppLocalization.string("明日计划"), text: $editor.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(AppLocalization.string("质量问题"), text: $editor.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(AppLocalization.string("整改记录"), text: $editor.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(AppLocalization.string("现场确认人"), text: $editor.confirmer)
                }
                constructionMethodLinkSection(selection: $editor.linkedMethodIDs)
        }
        .disabled(isSavingLog)
        .interactiveDismissDisabled(isSavingLog || draftError != nil)
    }

    @ViewBuilder
    func weatherField(selection: Binding<String>) -> some View {
        Picker(AppLocalization.string("天气"), selection: selection) {
            Text(AppLocalization.string("待填写")).tag("")
            ForEach(weatherOptions, id: \.self) { option in
                Text(AppLocalization.string(String.LocalizationValue(option))).tag(option)
            }
            if !selection.wrappedValue.isEmpty, !weatherOptions.contains(selection.wrappedValue) {
                Text(selection.wrappedValue).tag(selection.wrappedValue)
            }
        }
        .accessibilityIdentifier("daily-log-weather-picker")
        .accessibilityValue(selection.wrappedValue.isEmpty ? AppLocalization.string("待填写") : AppLocalization.string(String.LocalizationValue(selection.wrappedValue)))
        if selection.wrappedValue.isEmpty {
            Text(AppLocalization.string("请按日志日期的现场实况选择天气；未选择时将留空保存。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func constructionMethodLinkSection(selection: Binding<Set<UUID>>) -> some View {
        Section(AppLocalization.string("关联施工工艺")) {
            if store.constructionMethods.isEmpty {
                Text(AppLocalization.string("暂无工艺条目，可先在工具箱-施工工艺库新增"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.constructionMethods) { method in
                    Toggle(isOn: methodSelectionBinding(method.id, selection: selection)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(constructionMethodTitle(method))
                            HStack(spacing: 6) {
                                if !method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(method.trade)
                                }
                                Text(method.versionName.isEmpty ? "V1" : method.versionName)
                                Text(method.publishStatus.displayName)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    func methodSelectionBinding(_ id: UUID, selection: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(id) },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.insert(id)
                } else {
                    selection.wrappedValue.remove(id)
                }
            }
        )
    }

    var canSaveLog: Bool {
        let contentReady = !composer.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let workersReady = composer.workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || InputValidator.nonNegativeNumber(composer.workers)
        return contentReady && workersReady && !photoImportSession.isImporting && !isSavingLog && draftLoaded && !store.dailyLogs.contains(where: { $0.id == draftRecordID })
    }
}
