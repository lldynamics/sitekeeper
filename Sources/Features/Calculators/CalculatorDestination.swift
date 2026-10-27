import SwiftUI

enum CalculatorDestination: CaseIterable {
    case current, voltageDrop, conduitFill, trayFill, breakerSelect, concrete, rebar, tile, wallArea, unitConverter
    case materialUsage, slopeHeight
    case measurementCheck, linearCutting, circuitPhaseRecord

    var icon: String {
        switch self {
        case .current: "bolt.fill"
        case .voltageDrop: "arrow.triangle.swap"
        case .conduitFill: "circle.grid.cross"
        case .trayFill: "rectangle.grid.1x2"
        case .breakerSelect: "switch.2"
        case .concrete: "cube.fill"
        case .rebar: "ruler.fill"
        case .tile: "square.grid.3x3"
        case .wallArea: "square.split.2x2"
        case .unitConverter: "arrow.left.arrow.right"
        case .materialUsage: "paintbrush.fill"
        case .slopeHeight: "angle"
        case .measurementCheck: "ruler.fill"
        case .linearCutting: "scissors"
        case .circuitPhaseRecord: "list.bullet.rectangle"
        }
    }

    var title: String {
        switch self {
        case .current: "电流计算"
        case .voltageDrop: "电缆压降"
        case .conduitFill: "线管穿线率"
        case .trayFill: "桥架填充率"
        case .breakerSelect: "空开/漏保选型"
        case .concrete: "混凝土算量"
        case .rebar: "钢筋重量"
        case .tile: "地砖排料"
        case .wallArea: "墙面面积"
        case .unitConverter: "单位换算"
        case .materialUsage: "材料用量与损耗"
        case .slopeHeight: "坡度与高差"
        case .measurementCheck: "实测实量验收表"
        case .linearCutting: "定尺下料"
        case .circuitPhaseRecord: "回路负荷分相记录"
        }
    }

    var desc: String {
        switch self {
        case .current: "功率 / 电压 → 电流"
        case .voltageDrop: "线路压降及线径推荐"
        case .conduitFill: "管内导线截面积占比"
        case .trayFill: "桥架内电缆总截面积"
        case .breakerSelect: "按电流选断路器规格"
        case .concrete: "方量 + 水泥砂石估算"
        case .rebar: "每米重 / 总重 / 吨位"
        case .tile: "片数 / 箱数 / 胶粘剂"
        case .wallArea: "扣除门窗后净面积"
        case .unitConverter: "长度、面积、重量"
        case .materialUsage: "面积、单耗、遍数 → 用量与采购量"
        case .slopeHeight: "百分比、千分比、坡比与高差互算"
        case .measurementCheck: "自设目标与偏差 → 测点检查记录"
        case .linearCutting: "段长、数量、切缝 → 建议组合与余料"
        case .circuitPhaseRecord: "回路电流、相别 → 分相汇总与记录"
        }
    }

    var section: String {
        switch self {
        case .current, .voltageDrop, .conduitFill, .trayFill, .breakerSelect, .circuitPhaseRecord: "电气"
        case .concrete, .rebar, .tile, .wallArea, .materialUsage, .linearCutting: "土建"
        case .unitConverter, .slopeHeight, .measurementCheck: "通用"
        }
    }

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .current: CurrentCalcView()
        case .voltageDrop: VoltageDropView()
        case .conduitFill: ConduitFillView()
        case .trayFill: TrayFillView()
        case .breakerSelect: BreakerSelectView()
        case .concrete: ConcreteCalcView()
        case .rebar: RebarCalcView()
        case .tile: TileCalcView()
        case .wallArea: WallAreaView()
        case .unitConverter: UnitConverterView()
        case .materialUsage: MaterialUsageCalcView()
        case .slopeHeight: SlopeHeightCalcView()
        case .measurementCheck: MeasurementCheckView()
        case .linearCutting: LinearCuttingView()
        case .circuitPhaseRecord: CircuitPhaseRecordView()
        }
    }
}
