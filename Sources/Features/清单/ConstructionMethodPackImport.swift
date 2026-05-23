import SwiftUI
import Foundation

struct ConstructionMethodPackImportSheet: View {
    enum PayloadSource {
        case website
        case offlineCache

        var displayName: String {
            switch self {
            case .website:
                return String(localized: "网站实时")
            case .offlineCache:
                return String(localized: "离线缓存")
            }
        }
    }

    struct ImportFieldChange: Identifiable {
        let key: String
        let label: String
        let before: String
        let after: String

        var id: String { key }
    }

    struct ImportDiffPreview: Identifiable {
        enum Kind {
            case new
            case updated
            case unchanged
        }

        let pack: RemoteConstructionMethodPack
        let kind: Kind
        let changes: [ImportFieldChange]

        var id: String { pack.id }
    }

    @Environment(\.dismiss) var dismiss
    let existingMethods: [ConstructionMethod]
    let onImport: ([ConstructionMethod], Int, Int) -> Void

    @State var payload: RemoteConstructionMethodPackPayload?
    @State var selectedPackIDs: Set<String> = []
    @State var isLoading = false
    @State var errorMessage: String?
    @State var loadedEndpoint: URL?
    @State var payloadSource: PayloadSource = .website
    @State var operationNotice: OperationToastNotice?
    @State var lastImportStatus: ConstructionMethodPackImportStatus? = ConstructionMethodPackImportStatusStore.load()
    @State var cachedSnapshot: ConstructionMethodPackOfflineCacheSnapshot? = ConstructionMethodPackOfflineCacheStore.load()

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "同步概览")) {
                    LabeledContent(String(localized: "当前来源"), value: payloadSource.displayName)
                    LabeledContent(String(localized: "可用包数量"), value: "\(availablePackCount)")
                    LabeledContent(String(localized: "网站更新时间"), value: websiteGeneratedAtDisplayText)
                    LabeledContent(String(localized: "本地版本"), value: localVersionDisplayText)
                    LabeledContent(String(localized: "离线缓存"), value: offlineCacheDisplayText)
                    LabeledContent(String(localized: "本次变更"), value: selectedDiffSummaryText)
                    LabeledContent(String(localized: "上次导入状态"), value: lastImportStatusDisplayText)
                    if let statusDetail = lastImportStatusDetailText {
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage, payloadSource == .offlineCache {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.appWarning)
                    }
                }

                Section(String(localized: "同步操作")) {
                    Button {
                        Task { await load(allowOfflineFallback: true) }
                    } label: {
                        Label(String(localized: "从网站同步"), systemImage: "arrow.clockwise.circle.fill")
                    }
                    .disabled(isLoading)

                    if shouldShowRetryButton {
                        Button {
                            Task { await load(allowOfflineFallback: true) }
                        } label: {
                            Label(String(localized: "失败重试"), systemImage: "arrow.trianglehead.clockwise")
                        }
                        .disabled(isLoading)
                    }

                    Button {
                        applyOfflineCache(manual: true)
                    } label: {
                        Label(String(localized: "使用离线缓存"), systemImage: "internaldrive.fill")
                    }
                    .disabled(cachedSnapshot == nil)

                    if cachedSnapshot != nil {
                        Button(role: .destructive) {
                            clearOfflineCache()
                        } label: {
                            Label(String(localized: "清除离线缓存"), systemImage: "trash")
                        }
                    }
                }

                if isLoading {
                    Section {
                        ProgressView(String(localized: "正在同步工程知识网站工艺包..."))
                    }
                }

                if let payload {
                    Section(String(localized: "数据源")) {
                        LabeledContent(String(localized: "端点"), value: sourceDisplayText)
                        LabeledContent(String(localized: "已选择"), value: "\(selectedPackIDs.count)")
                    }

                    Section(String(localized: "选择导入")) {
                        ForEach(payload.packs) { pack in
                            Toggle(isOn: selectedBinding(for: pack.id)) {
                                VStack(alignment: .leading, spacing: 5) {
                                    let preview = importDiff(for: pack)
                                    HStack(spacing: 8) {
                                        Text(pack.title)
                                            .font(.body.weight(.semibold))
                                        Spacer(minLength: 8)
                                        Text(importStateText(preview))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(importStateColor(preview))
                                    }
                                    Text(pack.trade.isEmpty ? String(localized: "未分类") : pack.trade)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.appDoc)
                                    Text(pack.procedureSteps.prefix(2).joined(separator: "；"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if preview.kind == .updated, !preview.changes.isEmpty {
                                        Text(preview.changes.map(\.label).joined(separator: "、"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    } else if preview.kind == .unchanged {
                                        Text(String(localized: "与当前版本一致，可按需跳过导入"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }

                    if !selectedImportDiffs.isEmpty {
                        Section(String(localized: "导入差异预览")) {
                            ForEach(selectedImportDiffs) { preview in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(preview.pack.title)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer(minLength: 8)
                                        Text(importStateText(preview))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(importStateColor(preview))
                                    }

                                    if preview.kind == .updated, !preview.changes.isEmpty {
                                        ForEach(Array(preview.changes.prefix(3))) { change in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(change.label)
                                                    .font(.caption.weight(.semibold))
                                                Text(String(format: String(localized: "当前：%@"), change.before))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                Text(String(format: String(localized: "同步：%@"), change.after))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        if preview.changes.count > 3 {
                                            Text(String(format: String(localized: "另有 %lld 项字段变化"), Int64(preview.changes.count - 3)))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if preview.kind == .unchanged {
                                        Text(String(localized: "已与当前库内版本一致，导入时将自动跳过。"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } else if let errorMessage {
                    Section {
                        ContentUnavailableView(
                            String(localized: "读取失败"),
                            systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage)
                        )
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            String(localized: "暂无工艺包"),
                            systemImage: "tray",
                            description: Text(String(localized: "请稍后重试。"))
                        )
                    }
                }
            }
            .navigationTitle(String(localized: "工艺包同步中心"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "导入")) {
                        importSelected()
                    }
                    .disabled(selectedPackIDs.isEmpty || payload == nil)
                }
            }
            .task {
                if payload == nil {
                    await load(allowOfflineFallback: true)
                }
            }
            .operationToast(notice: $operationNotice)
        }
    }
}
