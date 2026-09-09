import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    var addLogForm: some View {
        AppBusinessFormSheet(
            title: String(localized: "写日志"),
            isPrimaryActionDisabled: !canSaveLog,
            onCancel: {
                showAdd = false
                clearDraft()
            },
            onPrimaryAction: {
                if save() {
                    showAdd = false
                }
            }
        ) {
                Section(String(localized: "基础信息")) {
                    DatePicker(String(localized: "日期"), selection: $composer.date, displayedComponents: .date)
                    Picker(String(localized: "天气"), selection: $composer.weather) {
                        ForEach(weatherOptions, id: \.self) { Text(String(localized: String.LocalizationValue($0))).tag($0) }
                    }
                    TextField(String(localized: "人数"), text: $composer.workers)
                    Picker(String(localized: "选择工程"), selection: $composer.projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section(String(localized: "施工内容")) {
                    Menu(String(localized: "套用内容模板")) {
                        ForEach(contentTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.content = tpl }
                        }
                    }
                    if !store.templates.filter({ $0.category == .dailyLog }).isEmpty {
                        Menu(String(localized: "套用我的日志模板")) {
                            ForEach(store.templates.filter { $0.category == .dailyLog }) { template in
                                Button(template.name) { applyDailyLogTemplate(template) }
                            }
                        }
                    }
                    TextField(String(localized: "内容"), text: $composer.content, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("daily-log-compose-content")
                }
                Section(String(localized: "安全与材料")) {
                    Menu(String(localized: "套用安全模板")) {
                        ForEach(safetyTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.safety = tpl }
                        }
                    }
                    TextField(String(localized: "安全事项"), text: $composer.safety, axis: .vertical)
                        .lineLimit(2...4)
                    Menu(String(localized: "套用材料模板")) {
                        ForEach(materialTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.materials = tpl }
                        }
                    }
                    TextField(String(localized: "材料进场"), text: $composer.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(String(localized: "计划与质量")) {
                    Button {
                        composer.tomorrowPlan = generateTomorrowPlanFromTodos(for: composer.projectId)
                    } label: {
                        Label(String(localized: "从今日待办生成明日计划"), systemImage: "wand.and.stars")
                    }
                    TextField(String(localized: "明日计划"), text: $composer.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "质量问题"), text: $composer.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "整改记录"), text: $composer.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "现场确认人"), text: $composer.confirmer)
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
            title: String(localized: "编辑日志"),
            isPrimaryActionDisabled: editor.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCancel: {
                showEdit = false
            },
            onPrimaryAction: {
                saveEditedLog()
                showEdit = false
            }
        ) {
                Section(String(localized: "基础信息")) {
                    DatePicker(String(localized: "日期"), selection: $editor.date, displayedComponents: .date)
                    Picker(String(localized: "天气"), selection: $editor.weather) {
                        ForEach(weatherOptions, id: \.self) { Text(String(localized: String.LocalizationValue($0))).tag($0) }
                    }
                    TextField(String(localized: "人数"), text: $editor.workers)
                    Picker(String(localized: "选择工程"), selection: $editor.projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section(String(localized: "施工内容")) {
                    TextField(String(localized: "内容"), text: $editor.content, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section(String(localized: "安全与材料")) {
                    TextField(String(localized: "安全事项"), text: $editor.safety, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "材料进场"), text: $editor.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(String(localized: "计划与质量")) {
                    Button {
                        editor.tomorrowPlan = generateTomorrowPlanFromTodos(for: editor.projectId)
                    } label: {
                        Label(String(localized: "从今日待办生成明日计划"), systemImage: "wand.and.stars")
                    }
                    TextField(String(localized: "明日计划"), text: $editor.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "质量问题"), text: $editor.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "整改记录"), text: $editor.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "现场确认人"), text: $editor.confirmer)
                }
                constructionMethodLinkSection(selection: $editor.linkedMethodIDs)
        }
    }

    @ViewBuilder
    func constructionMethodLinkSection(selection: Binding<Set<UUID>>) -> some View {
        Section(String(localized: "关联施工工艺")) {
            if store.constructionMethods.isEmpty {
                Text(String(localized: "暂无工艺条目，可先在工具箱-施工工艺库新增"))
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
        return contentReady && workersReady && !photoImportSession.isImporting
    }
}
