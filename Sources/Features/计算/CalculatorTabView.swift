import SwiftUI

enum CalculatorDestination: CaseIterable {
    case current, voltageDrop, conduitFill, trayFill, breakerSelect, lightingPlanner, lightingCalc, concrete, rebar, tile, wallArea, unitConverter, watermarkCamera

    var icon: String {
        switch self {
        case .current: "bolt.fill"
        case .voltageDrop: "arrow.triangle.swap"
        case .conduitFill: "circle.grid.cross"
        case .trayFill: "rectangle.grid.1x2"
        case .breakerSelect: "switch.2"
        case .lightingPlanner: "tablecells.fill"
        case .lightingCalc: "lightbulb.fill"
        case .concrete: "cube.fill"
        case .rebar: "ruler.fill"
        case .tile: "square.grid.3x3"
        case .wallArea: "square.split.2x2"
        case .unitConverter: "arrow.left.arrow.right"
        case .watermarkCamera: "camera.aperture"
        }
    }

    var title: String {
        switch self {
        case .current: "电流计算"
        case .voltageDrop: "电缆压降"
        case .conduitFill: "线管穿线率"
        case .trayFill: "桥架填充率"
        case .breakerSelect: "空开/漏保选型"
        case .lightingPlanner: "照明回路表"
        case .lightingCalc: "照明估算"
        case .concrete: "混凝土算量"
        case .rebar: "钢筋重量"
        case .tile: "地砖排料"
        case .wallArea: "墙面面积"
        case .unitConverter: "单位换算"
        case .watermarkCamera: "水印相机"
        }
    }

    var desc: String {
        switch self {
        case .current: "功率 / 电压 → 电流"
        case .voltageDrop: "线路压降及线径推荐"
        case .conduitFill: "管内导线截面积占比"
        case .trayFill: "桥架内电缆总截面积"
        case .breakerSelect: "按电流选断路器规格"
        case .lightingPlanner: "回路负荷、断路器与线径建议"
        case .lightingCalc: "房间面积 → 灯具数量"
        case .concrete: "方量 + 水泥砂石估算"
        case .rebar: "每米重 / 总重 / 吨位"
        case .tile: "片数 / 箱数 / 胶粘剂"
        case .wallArea: "扣除门窗后净面积"
        case .unitConverter: "长度、面积、重量"
        case .watermarkCamera: "独立拍照并导出带工程水印的现场图片"
        }
    }

    var section: String {
        switch self {
        case .current, .voltageDrop, .conduitFill, .trayFill, .breakerSelect, .lightingPlanner: "电气"
        case .lightingCalc: "照明"
        case .concrete, .rebar, .tile, .wallArea: "土建"
        case .unitConverter, .watermarkCamera: "通用"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .current: CurrentCalcView()
        case .voltageDrop: VoltageDropView()
        case .conduitFill: ConduitFillView()
        case .trayFill: TrayFillView()
        case .breakerSelect: BreakerSelectView()
        case .lightingPlanner: LightingCircuitPlannerView()
        case .lightingCalc: LightingCalcView()
        case .concrete: ConcreteCalcView()
        case .rebar: RebarCalcView()
        case .tile: TileCalcView()
        case .wallArea: WallAreaView()
        case .unitConverter: UnitConverterView()
        case .watermarkCamera: WatermarkCameraToolView()
        }
    }
}

struct CalculatorTabView: View {
    @AppStorage("favoriteCalculators") private var favData = ""

    private var favSet: Set<String> {
        Set(favData.split(separator: ",").map(String.init))
    }

    private var sortedDefs: [CalculatorDestination] {
        let defs = CalculatorDestination.allCases.filter { $0 != .watermarkCamera }
        let favs = defs.filter { favSet.contains($0.title) }
        let rest = defs.filter { !favSet.contains($0.title) }
        return favs + rest
    }

    var body: some View {
        NavigationStack {
            List {
                let grouped = Dictionary(grouping: sortedDefs, by: { $0.section })
                let order = ["电气", "照明", "土建", "通用"]
                ForEach(order, id: \.self) { section in
                    if let items = grouped[section], !items.isEmpty {
                        Section(section) {
                            ForEach(items.indices, id: \.self) { i in
                                let item = items[i]
                                NavigationLink { item.destination } label: {
                                    ToolRow(icon: item.icon, title: item.title, desc: item.desc, color: .orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("计算")
        }
    }
}
