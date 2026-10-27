import SwiftUI
import Foundation

struct ConstructionMethodPackImportSheet: View {
    enum PayloadSource {
        case website
        case offlineCache

        var displayName: String {
            switch self {
            case .website:
                return AppLocalization.string("网站实时")
            case .offlineCache:
                return AppLocalization.string("离线缓存")
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
                Section(AppLocalization.string("同步概览")) {
                    LabeledContent(AppLocalization.string("当前来源"), value: payloadSource.displayName)
                    LabeledContent(AppLocalization.string("可用包数量"), value: "\(availablePackCount)")
                    LabeledContent(AppLocalization.string("网站更新时间"), value: websiteGeneratedAtDisplayText)
                    LabeledContent(AppLocalization.string("本地版本"), value: localVersionDisplayText)
                    LabeledContent(AppLocalization.string("离线缓存"), value: offlineCacheDisplayText)
                    LabeledContent(AppLocalization.string("本次变更"), value: selectedDiffSummaryText)
                    LabeledContent(AppLocalization.string("上次导入状态"), value: lastImportStatusDisplayText)
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

                Section(AppLocalization.string("同步操作")) {
                    Button {
                        Task { await load(allowOfflineFallback: true) }
                    } label: {
                        Label(AppLocalization.string("从网站同步"), systemImage: "arrow.clockwise.circle.fill")
                    }
                    .disabled(isLoading)

                    if shouldShowRetryButton {
                        Button {
                            Task { await load(allowOfflineFallback: true) }
                        } label: {
                            Label(AppLocalization.string("失败重试"), systemImage: "arrow.trianglehead.clockwise")
                        }
                        .disabled(isLoading)
                    }

                    Button {
                        applyOfflineCache(manual: true)
                    } label: {
                        Label(AppLocalization.string("使用离线缓存"), systemImage: "internaldrive.fill")
                    }
                    .disabled(cachedSnapshot == nil)

                    if cachedSnapshot != nil {
                        Button(role: .destructive) {
                            clearOfflineCache()
                        } label: {
                            Label(AppLocalization.string("清除离线缓存"), systemImage: "trash")
                        }
                    }
                }

                if isLoading {
                    Section {
                        ProgressView(AppLocalization.string("正在同步工程知识网站工艺包..."))
                    }
                }

                if let payload {
                    Section(AppLocalization.string("数据源")) {
                        LabeledContent(AppLocalization.string("端点"), value: sourceDisplayText)
                        LabeledContent(AppLocalization.string("已选择"), value: "\(selectedPackIDs.count)")
                    }

                    Section(AppLocalization.string("选择导入")) {
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
                                    Text(pack.trade.isEmpty ? AppLocalization.string("未分类") : pack.trade)
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
                                        Text(AppLocalization.string("与当前版本一致，可按需跳过导入"))
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
                        Section(AppLocalization.string("导入差异预览")) {
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
                                                Text(String(format: AppLocalization.string("当前：%@"), change.before))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                Text(String(format: AppLocalization.string("同步：%@"), change.after))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        if preview.changes.count > 3 {
                                            Text(String(format: AppLocalization.string("另有 %lld 项字段变化"), Int64(preview.changes.count - 3)))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if preview.kind == .unchanged {
                                        Text(AppLocalization.string("已与当前库内版本一致，导入时将自动跳过。"))
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
                            AppLocalization.string("读取失败"),
                            systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage)
                        )
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            AppLocalization.string("暂无工艺包"),
                            systemImage: "tray",
                            description: Text(AppLocalization.string("请稍后重试。"))
                        )
                    }
                }
            }
            .navigationTitle(AppLocalization.string("工艺包同步中心"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("导入")) {
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
