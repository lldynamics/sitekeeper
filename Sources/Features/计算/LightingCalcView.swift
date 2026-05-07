import SwiftUI

struct LightingCalcView: View {
    @Environment(DataStore.self) private var store
    @State private var roomLength: String = "6"
    @State private var roomWidth: String = "4"
    @State private var targetLux: String = "300"
    @State private var lumensPerFixture: String = "2400"
    @State private var utilizationFactor: String = "0.6"
    @State private var maintenanceFactor: String = "0.8"

    @State private var resultText: String = ""

    var body: some View {
        Form {
            Section("房间参数") {
                LabeledContent("长度 (m)") {
                    TextField("6", text: $roomLength)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("宽度 (m)") {
                    TextField("4", text: $roomWidth)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("照明要求") {
                LabeledContent("目标照度 (lux)") {
                    TextField("300", text: $targetLux)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RoomType.presets) { preset in
                            Button(preset.name) {
                                targetLux = String(preset.lux)
                            }
                            .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(targetLux == String(preset.lux) ? Color.orange : Color.gray.opacity(0.15))
                            .foregroundStyle(targetLux == String(preset.lux) ? .white : .primary)
                            .clipShape(Capsule())
                        }
                    }
                }
                LabeledContent("单灯光通量 (lm)") {
                    TextField("2400", text: $lumensPerFixture)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("利用系数") {
                    TextField("0.6", text: $utilizationFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("维护系数") {
                    TextField("0.8", text: $maintenanceFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Button("估算") { calc() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if !resultText.isEmpty {
                Section("估算结果") {
                    Text(resultText)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle("照明估算")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let l = Double(roomLength), l > 0,
              let w = Double(roomWidth), w > 0,
              let lux = Double(targetLux), lux > 0,
              let lumen = Double(lumensPerFixture), lumen > 0,
              let uf = Double(utilizationFactor), uf > 0, uf <= 1,
              let mf = Double(maintenanceFactor), mf > 0, mf <= 1 else {
            resultText = "请输入有效数值"
            return
        }
        let area = l * w
        let totalLumens = area * lux / (uf * mf)
        let count = Int(ceil(totalLumens / lumen))
        let perArea = Double(count) / area

        resultText = """
        房间面积: \(String(format: "%.2f", area)) m²
        总光通量需求: \(String(format: "%.0f", totalLumens)) lm
        需要灯具: \(count) 盏
        每平米: \(String(format: "%.1f", perArea)) 盏
        """
        saveHistory("\(count) 盏")
    }

    private func saveHistory(_ r: String) {
        store.historyRecords.insert(HistoryRecord(tool: "照明估算", input: "\(roomLength)×\(roomWidth)m, \(targetLux)lux", result: r, date: now()), at: 0)
        store.scheduleSave()
    }
    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }
}

struct RoomType: Identifiable {
    let id = UUID()
    let name: String
    let lux: Int

    static let presets: [RoomType] = [
        RoomType(name: "办公室", lux: 300),
        RoomType(name: "教室", lux: 300),
        RoomType(name: "车间", lux: 200),
        RoomType(name: "仓库", lux: 150),
        RoomType(name: "走廊", lux: 100),
        RoomType(name: "商场", lux: 500),
    ]
}
