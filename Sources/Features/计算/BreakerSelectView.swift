import SwiftUI

struct BreakerSelectView: View {
    @Environment(DataStore.self) private var store
    @State private var calcCurrent = ""; @State private var loadType: LoadType = .lighting
    @State private var result = ""

    var body: some View {
        Form {
            Section("负载参数") {
                LabeledContent("计算电流 (A)") { TextField("例如 32", text: $calcCurrent).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("负载类型", selection: $loadType) {
                    ForEach(LoadType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("选型参考") {
                Text("• 照明回路: 额定电流 × 1.0\n• 插座回路: 额定电流 × 1.25\n• 动力回路: 额定电流 × 1.5")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("选型") { select() }.frame(maxWidth: .infinity).fontWeight(.semibold) }
            if !result.isEmpty {
                Section("推荐") { Text(result).font(.system(.body, design: .monospaced)) }
            }
        }
        .navigationTitle("空开/漏保选型").navigationBarTitleDisplayMode(.inline)
    }

    private func select() {
        guard let i = Double(calcCurrent), i > 0 else { result = "请输入计算电流"; return }
        let rated = i * loadType.factor
        let standardBreakers = [6, 10, 16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250]
        let breaker = standardBreakers.first { Double($0) >= rated } ?? 250
        let rcdRecommended = loadType == .socket
        result = """
        计算电流: \(fmt(i)) A
        推荐整定值: \(fmt(rated)) A
        断路器规格: \(breaker)A / \(loadType.poles)
        \(rcdRecommended ? "建议配置 30mA 漏电保护" : "")
        """
        store.historyRecords.insert(HistoryRecord(tool: "空开选型", input: "\(fmt(i))A, \(loadType.displayName)", result: "\(breaker)A", date: now()), at: 0)
        store.scheduleSave()
    }

    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}

enum LoadType: String, CaseIterable {
    case lighting
    case socket
    case power

    var displayName: String {
        switch self {
        case .lighting: "照明"
        case .socket: "插座"
        case .power: "动力"
        }
    }
    var factor: Double { switch self { case .lighting: 1.0; case .socket: 1.25; case .power: 1.5 } }
    var poles: String { switch self { case .lighting, .socket: "1P+N"; case .power: "3P" } }
}
