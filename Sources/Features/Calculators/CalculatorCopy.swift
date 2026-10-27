import Foundation

enum CalculatorResultCopy {
    static func breakerFormula() -> String {
        calculatorLoc("整定值 = 计算电流 × 负载系数；断路器规格取不小于整定值的最小标准档。")
    }

    static func breakerReference(loadType: String, factor: Double) -> String {
        calculatorLocFormat("%@回路按计算电流 × %@ 估算整定值，正式选型仍需结合线路保护和上级配合。", loadType, CalculatorFormatting.fixed(factor, digits: 2))
    }

    static func breakerRcdAdvice(recommended: Bool) -> String {
        recommended
            ? calculatorLoc("建议配置 30mA 漏电保护。")
            : calculatorLoc("按现场方案和保护分级要求选配。")
    }

    static func currentFormula(isThreePhase: Bool) -> String {
        isThreePhase
            ? "I = P×1000 ÷ (√3×U×cosφ)"
            : "I = P×1000 ÷ (U×cosφ)"
    }

    static func currentFormulaNote(isThreePhase: Bool) -> String {
        isThreePhase
            ? calculatorLoc("三相按 I = P ÷ (√3 × U × cosφ) 估算，功率输入单位为 kW。")
            : calculatorLoc("单相按 I = P ÷ (U × cosφ) 估算，功率输入单位为 kW。")
    }

    static func currentHeadline(_ current: Double) -> String {
        calculatorLocFormat("电流 %@", CalculatorFormatting.amperes(current, digits: 2))
    }

    static func currentPhaseLabel(isThreePhase: Bool) -> String {
        isThreePhase ? calculatorLoc("三相") : calculatorLoc("单相")
    }

    static func currentVoltageDisplay(voltage: Double, isThreePhase: Bool) -> String {
        calculatorLocFormat(
            "%@ (%@)",
            CalculatorFormatting.volts(voltage, digits: 0),
            currentPhaseLabel(isThreePhase: isThreePhase)
        )
    }

    static func ampacityCheck(ampacity: Double, loadCurrent: Double) -> String {
        let ampacityText = CalculatorFormatting.amperes(ampacity, digits: 0)
        if loadCurrent <= ampacity {
            return calculatorLocFormat("载流量 %@，满足校核。", ampacityText)
        }
        return calculatorLocFormat("载流量 %@，当前电流已偏大。", ampacityText)
    }

    static func voltageDropFormula() -> String {
        calculatorLoc("ΔU = I × (ρ × 有效长度 ÷ 截面积)；压降率 = (ΔU ÷ 额定电压) × 100%。")
    }

    static func voltageDropHeadline(percent: Double) -> String {
        calculatorLocFormat("压降 %@%%", CalculatorFormatting.fixed(percent, digits: 2))
    }

    static func conduitFillFormula() -> String {
        calculatorLoc("穿线率 = 导线总截面积 ÷ 线管截面积 × 100%。")
    }

    static func conduitFillHeadline(rate: Double) -> String {
        calculatorLocFormat("穿线率 %@", CalculatorFormatting.percent(rate))
    }

    static func conduitComplianceText(pass: Bool) -> String {
        passFail(
            pass: pass,
            passText: calculatorLoc("符合规范（≤40%）"),
            failText: calculatorLoc("已超出规范（>40%）")
        )
    }

    static func trayFillFormula() -> String {
        calculatorLoc("填充率 = 电缆总截面积 ÷ 桥架截面积 × 100%。")
    }

    static func trayCableItemError(index: Int, message: String) -> String {
        calculatorLocFormat("第 %lld 项电缆：%@", Int64(index), message)
    }

    static func trayFillHeadline(rate: Double) -> String {
        calculatorLocFormat("填充率 %@", CalculatorFormatting.percent(rate))
    }

    static func trayComplianceText(pass: Bool) -> String {
        passFail(
            pass: pass,
            passText: calculatorLoc("符合规范（≤40%）"),
            failText: calculatorLoc("超出规范（>40%）")
        )
    }

    static func trayDraftDecodeFailed(_ message: String) -> String {
        calculatorLocFormat("桥架填充草稿解析失败：%@", message)
    }

    static func trayDraftEncodeFailed(_ message: String) -> String {
        calculatorLocFormat("桥架填充草稿编码失败：%@", message)
    }

    static func rebarFormula() -> String {
        calculatorLoc("单位重 = d² ÷ 162；总重 = 单位重 × 单根长度 × 根数。")
    }

    static func concreteFormula() -> String {
        calculatorLoc("净方量 = 长 × 宽 × 厚(cm) ÷ 100；含损耗方量 = 净方量 × (1 + 损耗%)。")
    }

    static func concreteHeadline(total: Double) -> String {
        calculatorLocFormat("含损耗 %@", CalculatorFormatting.cubicMeters(total))
    }

    static func concreteCementWithBags(cement: Double) -> String {
        calculatorLocFormat(
            "%@ (%@)",
            CalculatorFormatting.kilograms(cement),
            CalculatorFormatting.bags(Int(ceil(cement / 50)))
        )
    }

    static func tileFormula() -> String {
        calculatorLoc("片数 = ceil(含损耗面积 ÷ 单片面积)；箱数 = ceil(片数 ÷ 每箱片数)。")
    }

    static func wallAreaFormula() -> String {
        calculatorLoc("净面积 = 墙体总周长 × 层高 - 门窗总面积。")
    }

    static func unitConvertFormula() -> String {
        calculatorLoc("输出值 = 输入值 × 源单位系数 ÷ 目标单位系数。")
    }

    static func breakerHeadline(breaker: Int, poles: String) -> String {
        calculatorLocFormat("推荐 %lldA / %@", Int64(breaker), poles)
    }

    static func recommendedSection(_ value: Double?) -> String {
        guard let value else {
            return calculatorLoc("超出常用规格，请复核设计。")
        }
        return CalculatorFormatting.squareMillimeters(
            value,
            minFractionDigits: 0,
            maxFractionDigits: value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        )
    }

    static func passFail(pass: Bool, passText: String, failText: String) -> String {
        pass ? passText : failText
    }
}

enum CalculatorResultLabel {
    static var input: String { AppLocalization.string("输入") }
    static var output: String { AppLocalization.string("输出") }
    static var category: String { AppLocalization.string("类别") }
    static var power: String { AppLocalization.string("功率") }
    static var voltage: String { AppLocalization.string("电压") }
    static var powerFactor: String { AppLocalization.string("功率因数") }
    static var current: String { AppLocalization.string("计算电流") }
    static var currentResult: String { AppLocalization.string("电流结果") }
    static var currentRating: String { AppLocalization.string("推荐整定值") }
    static var rcdAdvice: String { AppLocalization.string("漏保建议") }
    static var material: String { AppLocalization.string("材质") }
    static var effectiveLength: String { AppLocalization.string("有效长度") }
    static var lineResistance: String { AppLocalization.string("线路电阻") }
    static var voltageDrop: String { AppLocalization.string("电压降") }
    static var ampacityCheck: String { AppLocalization.string("载流量校核") }
    static var recommendedSection: String { AppLocalization.string("推荐截面") }
    static var conduitArea: String { AppLocalization.string("线管截面积") }
    static var wireArea: String { AppLocalization.string("导线总截面积") }
    static var trayArea: String { AppLocalization.string("桥架截面积") }
    static var cableArea: String { AppLocalization.string("电缆总截面积") }
    static var complianceCheck: String { AppLocalization.string("规范校核") }
    static var recommendedConduit: String { AppLocalization.string("推荐管内径") }
    static var recommendedTray: String { AppLocalization.string("推荐桥架") }
    static var floorArea: String { AppLocalization.string("地面面积") }
    static var adjustedArea: String { AppLocalization.string("含损耗面积") }
    static var adhesive: String { AppLocalization.string("胶粘剂") }
    static var packageCount: String { AppLocalization.string("箱数") }
    static var perimeter: String { AppLocalization.string("周长") }
    static var grossArea: String { AppLocalization.string("毛面积") }
    static var deductionArea: String { AppLocalization.string("扣除门窗") }
    static var netArea: String { AppLocalization.string("净面积") }
    static var netVolume: String { AppLocalization.string("净方量") }
    static var cement: String { AppLocalization.string("水泥") }
    static var sand: String { AppLocalization.string("砂") }
    static var gravel: String { AppLocalization.string("碎石") }
    static var unitWeight: String { AppLocalization.string("单位重") }
    static var totalWeight: String { AppLocalization.string("总重") }
    static var tonnage: String { AppLocalization.string("吨位") }
    static var estimatedCost: String { AppLocalization.string("造价") }
}

enum CalculatorCopy {
    static var actionCalculate: String { AppLocalization.string("计算") }
    static var actionEstimate: String { AppLocalization.string("估算") }
    static var actionSelect: String { AppLocalization.string("选型") }
    static var actionConvert: String { AppLocalization.string("换算") }
    static var actionAdd: String { AppLocalization.string("添加") }
    static var actionCancel: String { AppLocalization.string("取消") }
    static var resultSection: String { AppLocalization.string("计算结果") }

    static var historySection: String { AppLocalization.string("记录") }
    static var historyTitle: String { AppLocalization.string("计算历史") }
    static var historyDescription: String { AppLocalization.string("查看、删除历史计算结果") }

    static var currentTool: String { AppLocalization.string("电流计算") }
    static var currentInputSection: String { AppLocalization.string("输入参数") }
    static var currentFormulaSection: String { AppLocalization.string("公式") }
    static var currentResultTitle: String { AppLocalization.string("电流计算结果") }
    static var currentPower: String { AppLocalization.string("功率") }
    static var currentPowerPlaceholder: String { AppLocalization.string("例如 10") }
    static var currentCommonPower: String { AppLocalization.string("常用功率") }
    static var currentVoltage: String { AppLocalization.string("电压") }
    static var currentVoltagePreset: String { AppLocalization.string("电压预设") }
    static var currentPowerFactor: String { AppLocalization.string("功率因数") }
    static var currentPowerFactorPreset: String { AppLocalization.string("功率因数") }
    static var currentThreePhase: String { AppLocalization.string("三相电") }
    static var currentInvalidNumber: String { AppLocalization.string("请输入有效数值") }
    static var currentPowerRange: String { AppLocalization.string("请输入 0.1–5000000") }
    static var currentVoltageRange: String { AppLocalization.string("请输入 12–100000") }
    static var currentPowerFactorRange: String { AppLocalization.string("请输入 0.01–1") }

    static var voltageDropTool: String { AppLocalization.string("电缆压降") }
    static var voltageDropLineSection: String { AppLocalization.string("线路参数") }
    static var voltageDropAmpacitySection: String { AppLocalization.string("载流量参考") }
    static var voltageDropResultTitle: String { AppLocalization.string("压降评估") }
    static var voltageDropCurrent: String { AppLocalization.string("电流") }
    static var voltageDropCurrentPlaceholder: String { AppLocalization.string("例如 20") }
    static var voltageDropCommonCurrent: String { AppLocalization.string("常用电流") }
    static var voltageDropLength: String { AppLocalization.string("长度") }
    static var voltageDropLengthPlaceholder: String { AppLocalization.string("例如 100") }
    static var voltageDropCommonLength: String { AppLocalization.string("常用长度") }
    static var voltageDropLoopLength: String { AppLocalization.string("回路长度（已含来/回）") }
    static var voltageDropMaterial: String { AppLocalization.string("材质") }
    static var voltageDropCopper: String { AppLocalization.string("铜") }
    static var voltageDropAluminum: String { AppLocalization.string("铝") }
    static var voltageDropSectionArea: String { AppLocalization.string("截面积") }
    static var voltageDropRatedVoltage: String { AppLocalization.string("额定电压") }
    static var voltageDropVoltagePreset: String { AppLocalization.string("电压预设") }
    static var voltageDropAmpacityNotice: String { AppLocalization.string("以下载流量仅作现场估算参考，正式选型仍以设计和敷设条件校核为准") }
    static var voltageDropCurrentRange: String { AppLocalization.string("请输入 0.1–100000") }
    static var voltageDropLengthRange: String { AppLocalization.string("请输入 1–1000000") }
    static var voltageDropSectionRange: String { AppLocalization.string("请输入 1–20000") }
    static var voltageDropVoltageRange: String { AppLocalization.string("请输入 12–100000") }

    static var conduitTool: String { AppLocalization.string("线管穿线率") }
    static var conduitParameterSection: String { AppLocalization.string("参数") }
    static var conduitReferenceSection: String { AppLocalization.string("参考") }
    static var conduitResultTitle: String { AppLocalization.string("线管穿线率") }
    static var conduitInnerDiameter: String { AppLocalization.string("线管内径") }
    static var conduitCommonDiameter: String { AppLocalization.string("常用管径") }
    static var conduitWireDiameter: String { AppLocalization.string("单根导线外径") }
    static var conduitCommonWireDiameter: String { AppLocalization.string("常用线径") }
    static var conduitWireCount: String { AppLocalization.string("导线根数") }
    static var conduitCommonWireCount: String { AppLocalization.string("常用根数") }
    static var conduitFillNotice: String { AppLocalization.string("规范要求穿线率 ≤ 40%") }
    static var conduitInnerDiameterRange: String { AppLocalization.string("请输入 6–10000") }
    static var conduitWireDiameterRange: String { AppLocalization.string("请输入 0.5–100") }
    static var conduitWireCountRange: String { AppLocalization.string("请输入 1–500") }
    static var integerRequired: String { AppLocalization.string("请输入整数") }
    static var conduitUnsupportedSize: String { AppLocalization.string("超出常用规格") }

    static var trayTool: String { AppLocalization.string("桥架填充率") }
    static var trayDimensionSection: String { AppLocalization.string("桥架尺寸 (mm)") }
    static var trayCableSection: String { AppLocalization.string("电缆列表") }
    static var trayResultTitle: String { AppLocalization.string("桥架填充率") }

    static var breakerTool: String { AppLocalization.string("空开/漏保选型") }
    static var breakerLoadSection: String { AppLocalization.string("负载参数") }
    static var breakerReferenceSection: String { AppLocalization.string("选型参考") }
    static var breakerResultSection: String { AppLocalization.string("推荐") }
    static var breakerResultTitle: String { AppLocalization.string("断路器推荐") }
    static var breakerCurrent: String { AppLocalization.string("计算电流") }
    static var breakerCurrentPlaceholder: String { AppLocalization.string("例如 32") }
    static var breakerCommonCurrent: String { AppLocalization.string("常用电流") }
    static var breakerLoadType: String { AppLocalization.string("负载类型") }
    static var breakerCurrentRequired: String { AppLocalization.string("请输入计算电流") }
    static var breakerCurrentRange: String { AppLocalization.string("请输入 0.1–100000") }
    static var breakerSocketLoad: String { AppLocalization.string("插座") }
    static var breakerPowerLoad: String { AppLocalization.string("动力") }

    static var concreteTool: String { AppLocalization.string("混凝土算量") }
    static var concreteDimensionSection: String { AppLocalization.string("板面尺寸") }
    static var concreteResultTitle: String { AppLocalization.string("混凝土估算") }
    static var concreteLength: String { AppLocalization.string("长度") }
    static var concreteWidth: String { AppLocalization.string("宽度") }
    static var concreteThickness: String { AppLocalization.string("厚度") }
    static var concreteWaste: String { AppLocalization.string("损耗") }
    static var concreteThicknessPreset: String { AppLocalization.string("厚度预设") }
    static var concreteGrade: String { AppLocalization.string("标号") }
    static var concreteMixNotice: String { AppLocalization.string("配比为估算值，现场下单前请以搅拌站或配合比通知单复核。") }
    static var concreteLengthRange: String { AppLocalization.string("请输入 0.1–10000") }
    static var concreteThicknessRange: String { AppLocalization.string("请输入 1–200") }
    static var concreteWasteRange: String { AppLocalization.string("请输入 0–40") }

    static var unitConverterTool: String { AppLocalization.string("单位换算") }
    static var unitConverterSection: String { AppLocalization.string("换算") }
    static var unitConverterResultTitle: String { AppLocalization.string("单位换算") }
    static var unitCategory: String { AppLocalization.string("类别") }
    static var unitValue: String { AppLocalization.string("数值") }
    static var unitQuickValue: String { AppLocalization.string("快捷值") }
    static var unitFrom: String { AppLocalization.string("从") }
    static var unitTo: String { AppLocalization.string("到") }
    static var unitNotice: String { AppLocalization.string("换算只做单位制切换，不替代材料规格、配比和损耗计算。") }
    static var unitSelectUnit: String { AppLocalization.string("请选择单位") }
    static var unitInputRange: String { AppLocalization.string("请输入 0–1000000000") }
    static var unitLengthCategory: String { AppLocalization.string("长度") }
    static var unitAreaCategory: String { AppLocalization.string("面积") }
    static var unitWeightCategory: String { AppLocalization.string("重量") }
    static var unitMeter: String { AppLocalization.string("米") }
    static var unitKilometer: String { AppLocalization.string("千米") }
    static var unitCentimeter: String { AppLocalization.string("厘米") }
    static var unitMillimeter: String { AppLocalization.string("毫米") }
    static var unitFoot: String { AppLocalization.string("英尺") }
    static var unitInch: String { AppLocalization.string("英寸") }
    static var unitYard: String { AppLocalization.string("码") }
    static var unitSquareMeter: String { AppLocalization.string("平方米") }
    static var unitSquareKilometer: String { AppLocalization.string("平方千米") }
    static var unitHectare: String { AppLocalization.string("公顷") }
    static var unitMu: String { AppLocalization.string("亩") }
    static var unitSquareFoot: String { AppLocalization.string("平方英尺") }
    static var unitKilogram: String { AppLocalization.string("千克") }
    static var unitTon: String { AppLocalization.string("吨") }
    static var unitGram: String { AppLocalization.string("克") }
    static var unitPound: String { AppLocalization.string("磅") }
    static var unitOunce: String { AppLocalization.string("盎司") }

    static var tileTool: String { AppLocalization.string("地砖排料") }
    static var tileRoomSection: String { AppLocalization.string("房间") }
    static var tileMaterialSection: String { AppLocalization.string("瓷砖") }
    static var tileResultTitle: String { AppLocalization.string("地砖排料结果") }
    static var tileHeadlinePrefix: String { AppLocalization.string("需瓷砖") }
    static var tileRoomLength: String { AppLocalization.string("房间长度") }
    static var tileRoomWidth: String { AppLocalization.string("房间宽度") }
    static var tileLength: String { AppLocalization.string("瓷砖长度") }
    static var tileWidth: String { AppLocalization.string("瓷砖宽度") }
    static var tileWaste: String { AppLocalization.string("损耗") }
    static var tileBoxPieces: String { AppLocalization.string("每箱片数") }
    static var lengthPreset: String { AppLocalization.string("长度预设") }
    static var widthPreset: String { AppLocalization.string("宽度预设") }
    static var commonLength: String { AppLocalization.string("常用长度") }
    static var commonWidth: String { AppLocalization.string("常用宽度") }
    static var wastePreset: String { AppLocalization.string("损耗预设") }

    static var rebarTool: String { AppLocalization.string("钢筋重量") }
    static var rebarSpecSection: String { AppLocalization.string("钢筋规格") }
    static var rebarResultTitle: String { AppLocalization.string("钢筋重量估算") }
    static var totalWeightPrefix: String { AppLocalization.string("总重") }
    static var rebarDiameter: String { AppLocalization.string("直径") }
    static var rebarCommonDiameter: String { AppLocalization.string("常用直径") }
    static var rebarLengthEach: String { AppLocalization.string("每根长") }
    static var rebarCommonLength: String { AppLocalization.string("常用长度") }
    static var rebarQuantity: String { AppLocalization.string("根数") }
    static var rebarCommonQuantity: String { AppLocalization.string("常用根数") }
    static var unitPrice: String { AppLocalization.string("单价") }
    static var optionalPlaceholder: String { AppLocalization.string("选填") }

    static var wallTool: String { AppLocalization.string("墙面面积") }
    static var wallDimensionSection: String { AppLocalization.string("墙面尺寸 (m)") }
    static var wallOpeningSection: String { AppLocalization.string("扣除面积 (m²)") }
    static var wallResultTitle: String { AppLocalization.string("墙面面积结果") }
    static var wallLength1: String { AppLocalization.string("墙 1 长") }
    static var wallLength2: String { AppLocalization.string("墙 2 长") }
    static var wallLength3: String { AppLocalization.string("墙 3 长") }
    static var wallLength4: String { AppLocalization.string("墙 4 长") }
    static var wallHeight: String { AppLocalization.string("层高") }
    static var wallHeightPreset: String { AppLocalization.string("层高预设") }
    static var wallDoorArea: String { AppLocalization.string("门总面积") }
    static var wallWindowArea: String { AppLocalization.string("窗总面积") }
    static var wallLengthRequired: String { AppLocalization.string("请至少输入一面墙长度") }
    static var wallLengthRequiredHint: String { AppLocalization.string("请至少输入一面墙长度（>0）") }
    static var wallLengthRange: String { AppLocalization.string("请输入 0–10000") }
    static var wallHeightRange: String { AppLocalization.string("请输入 1.8–20") }
    static var wallOpeningRange: String { AppLocalization.string("请输入 0–5000") }

    static var trayWidth: String { AppLocalization.string("宽度") }
    static var trayCommonWidth: String { AppLocalization.string("常用宽度") }
    static var trayHeight: String { AppLocalization.string("高度") }
    static var trayCommonHeight: String { AppLocalization.string("常用高度") }
    static var trayDeleteCable: String { AppLocalization.string("删除此电缆") }
    static var trayAddCable: String { AppLocalization.string("添加电缆") }
    static var trayCableOuterDiameter: String { AppLocalization.string("外径 (mm)") }
    static var trayCableCount: String { AppLocalization.string("根数 (根)") }
    static var trayFillNotice: String { AppLocalization.string("桥架穿线率按截面积估算，常用控制目标不高于 40%。") }
    static var trayWidthRange: String { AppLocalization.string("请输入 50–10000") }
    static var trayHeightRange: String { AppLocalization.string("请输入 30–2000") }
    static var trayUnsupportedSize: String { AppLocalization.string("超出常用规格") }
    static var trayDraftUTF8EncodeFailed: String { AppLocalization.string("桥架填充草稿编码后 UTF8 转换失败") }

    static var unitPieces: String { AppLocalization.string("片") }
    static var unitRoots: String { AppLocalization.string("根") }
    static var unitYuanPerKilogram: String { AppLocalization.string("元/kg") }
}

enum CalculatorHistoryCopy {
    static func tileInput(
        roomLength: String,
        roomWidth: String,
        tileLength: String,
        tileWidth: String
    ) -> String {
        calculatorLocFormat("%@×%@ m, %@×%@ mm", roomLength, roomWidth, tileLength, tileWidth)
    }

    static func tileResult(pieceCount: Int, packageCount: Int) -> String {
        "\(CalculatorFormatting.pieces(pieceCount)) / \(CalculatorFormatting.packages(packageCount))"
    }

    static func concreteInput(
        length: String,
        width: String,
        thickness: String,
        grade: String
    ) -> String {
        calculatorLocFormat("%@×%@ m, %@ cm, %@", length, width, thickness, grade)
    }

    static func volumeResult(prefix: String, value: Double) -> String {
        calculatorLocFormat("%@ %@", prefix, CalculatorFormatting.cubicMeters(value))
    }

    static func wallHeightInput(_ height: String) -> String {
        calculatorLocFormat("层高 %@", CalculatorFormatting.valueWithUnitString(height, unit: "m"))
    }

    static func areaResult(prefix: String, value: Double) -> String {
        calculatorLocFormat("%@ %@", prefix, CalculatorFormatting.squareMeters(value))
    }

    static func currentInput(power: String, voltage: String) -> String {
        calculatorLocFormat(
            "%@ / %@",
            CalculatorFormatting.valueWithUnitString(power, unit: "kW"),
            CalculatorFormatting.valueWithUnitString(voltage, unit: "V")
        )
    }

    static func voltageDropInput(current: String, length: String, section: String) -> String {
        calculatorLocFormat(
            "%@, %@, %@",
            CalculatorFormatting.valueWithUnitString(current, unit: "A"),
            CalculatorFormatting.valueWithUnitString(length, unit: "m"),
            CalculatorFormatting.valueWithUnitString(section, unit: "mm²")
        )
    }

    static func breakerInput(current: Double, loadType: String) -> String {
        calculatorLocFormat("%@, %@", CalculatorFormatting.amperes(current, digits: 1), loadType)
    }

    static func breakerResult(_ amperes: Int) -> String {
        CalculatorFormatting.amperes(Double(amperes), digits: 0)
    }

    static func weightResult(prefix: String, value: Double) -> String {
        calculatorLocFormat("%@ %@", prefix, CalculatorFormatting.kilograms(value))
    }
}

enum CalculatorPlainTextExport {
    static func text(from result: CalculationResult?, title: String) -> String {
        guard let result else { return "" }
        return result.plainText(title: title)
    }

    static func headline(from result: CalculationResult?, title: String) -> String {
        text(from: result, title: title)
            .components(separatedBy: "\n")
            .first ?? ""
    }

    static func dailyLogBlock(title: String, copyText: String) -> String {
        [
            calculatorLocFormat("【计算结果】%@", title),
            copyText,
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }
}

enum CalculatorInputParser {
    static func double(_ value: String) -> Double? {
        guard let decimal = DataValueParser.decimalValueIfPresent(
            from: value,
            requiresEntireString: true
        ) else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    static func int(_ value: String) -> Int? {
        guard let decimal = DataValueParser.decimalValueIfPresent(
            from: value,
            requiresEntireString: true
        ) else {
            return nil
        }
        let doubleValue = NSDecimalNumber(decimal: decimal).doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= Double(Int.min),
              doubleValue <= Double(Int.max) else {
            return nil
        }
        return Int(doubleValue)
    }
}
