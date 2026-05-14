import Foundation
import SwiftUI

struct DXFLayerSheet: View {
    @Binding var layerSearchText: String
    @Binding var visibleLayers: Set<String>
    @Binding var lockedLayers: Set<String>
    let layerStats: [DXFLayerStat]
    let filteredLayerStats: [DXFLayerStat]
    let onIsolate: (String) -> Void
    let onFocus: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索图层名称", text: $layerSearchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !layerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("清除搜索") {
                            layerSearchText = ""
                        }
                    }
                }
                Section("图层开关") {
                    LabeledContent("当前显示", value: "\(visibleLayers.count)/\(max(layerStats.count, 1))")
                    LabeledContent("已锁定", value: "\(lockedLayers.count)")
                    Button("显示全部") {
                        visibleLayers = Set(layerStats.map(\.name))
                    }
                    Button("隐藏未锁定图层", role: .destructive) {
                        visibleLayers = visibleLayers.intersection(lockedLayers)
                    }
                    .disabled(visibleLayers.subtracting(lockedLayers).isEmpty)
                    Button("锁定当前可见图层") {
                        lockedLayers.formUnion(visibleLayers)
                    }
                    .disabled(visibleLayers.isEmpty)
                    Button("全部解锁") {
                        lockedLayers.removeAll()
                    }
                    .disabled(lockedLayers.isEmpty)

                    if filteredLayerStats.isEmpty {
                        ContentUnavailableView(
                            "没有匹配图层",
                            systemImage: "square.3.layers.3d.down.right.slash",
                            description: Text("换个关键词继续搜索")
                        )
                    }

                    ForEach(filteredLayerStats) { layer in
                        let isLocked = lockedLayers.contains(layer.name)
                        HStack(spacing: 10) {
                            Toggle(isOn: Binding(
                                get: { visibleLayers.contains(layer.name) },
                                set: { newValue in
                                    setLayer(layer.name, visible: newValue)
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(layer.name)
                                    Text(layer.kindSummaryText.isEmpty ? "\(layer.count) 个对象" : "\(layer.count) 个对象 · \(layer.kindSummaryText)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(isLocked)

                            Button("只看") {
                                onIsolate(layer.name)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLocked)

                            Button {
                                setLayer(layer.name, locked: !isLocked)
                            } label: {
                                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                            }
                            .buttonStyle(.bordered)
                            .tint(isLocked ? Color.orange : .secondary)
                            .accessibilityLabel(isLocked ? "解锁图层 \(layer.name)" : "锁定图层 \(layer.name)")

                            Button {
                                onFocus(layer.name)
                            } label: {
                                Image(systemName: "scope")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("定位图层 \(layer.name)")
                        }
                    }
                }
            }
            .navigationTitle("图层")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onDone()
                    }
                }
            }
        }
    }

    private func setLayer(_ layerName: String, visible: Bool) {
        guard !lockedLayers.contains(layerName) else { return }
        if visible {
            visibleLayers.insert(layerName)
        } else {
            visibleLayers.remove(layerName)
        }
    }

    private func setLayer(_ layerName: String, locked: Bool) {
        if locked {
            lockedLayers.insert(layerName)
        } else {
            lockedLayers.remove(layerName)
        }
    }
}

struct DXFSearchResultsSheet: View {
    let matchedTexts: [DXFPreviewModel.TextEntity]
    let onSelect: (DXFPreviewModel.TextEntity) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if matchedTexts.isEmpty {
                    ContentUnavailableView(
                        "没有匹配文字",
                        systemImage: "text.magnifyingglass",
                        description: Text("输入图纸文字后再查看结果")
                    )
                } else {
                    Section("文字搜索结果") {
                        ForEach(matchedTexts) { text in
                            Button {
                                onSelect(text)
                            } label: {
                                textResultRow(for: text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("搜索结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onDone()
                    }
                }
            }
        }
    }

    private func textResultRow(for text: DXFPreviewModel.TextEntity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text.value)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let rawValue = text.rawValue, rawValue != text.value {
                Text("原始文本：\(rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(text.layer)
                Text(text.kind.rawValue)
                Text("X:\(DXFCanvasRenderer.formatCoordinate(text.point.x)) Y:\(DXFCanvasRenderer.formatCoordinate(text.point.y))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("解码：\(text.chosenCodepage.map(DXFCanvasRenderer.codePageDisplayName) ?? "自动/未知")")
                if let styleName = text.styleName {
                    Text("样式：\(styleName)")
                }
                if let fontFile = text.fontFile {
                    Text("字体：\(fontFile)")
                }
                if let bigFontFile = text.bigFontFile {
                    Text("大字体：\(bigFontFile)")
                }
                if let rawTextBytesHex = text.rawTextBytesHex {
                    Text("原始字节：\(rawTextBytesHex)")
                        .textSelection(.enabled)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct DWGLightweightDiagnosticSheet: View {
    let diagnostic: DWGLightweightDiagnostic?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let diagnostic {
                    Section("解析概况") {
                        row("DWG 版本", diagnostic.dwgVersion)
                        row("对象总数", "\(diagnostic.totalObjectCount)")
                        row("可绘制对象数", "\(diagnostic.drawableObjectCount)")
                        row("未支持对象类型", diagnostic.unsupportedObjectTypes)
                    }
                    Section("文字与样式") {
                        row("文字编码", diagnostic.textEncoding)
                        row("STYLE 字体", diagnostic.styleFonts)
                        row("大字体", diagnostic.bigFonts)
                    }
                    Section("性能估计") {
                        row("解析耗时", "\(diagnostic.parseDurationMilliseconds) ms")
                        row("内存估计", String(format: "%.2f MB", diagnostic.estimatedMemoryMB))
                    }
                    if let failureReason = diagnostic.failureReason,
                       !failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section("打不开原因") {
                            Text(failureReason)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "暂无诊断数据",
                        systemImage: "stethoscope",
                        description: Text("当前图纸没有可用的轻量诊断。")
                    )
                }
            }
            .navigationTitle("DWG 轻量诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onDone()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.subheadline)
    }
}
