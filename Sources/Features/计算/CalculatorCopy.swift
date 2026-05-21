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
    static let input = String(localized: "输入")
    static let output = String(localized: "输出")
    static let category = String(localized: "类别")
    static let power = String(localized: "功率")
    static let voltage = String(localized: "电压")
    static let powerFactor = String(localized: "功率因数")
    static let current = String(localized: "计算电流")
    static let currentResult = String(localized: "电流结果")
    static let currentRating = String(localized: "推荐整定值")
    static let rcdAdvice = String(localized: "漏保建议")
    static let material = String(localized: "材质")
    static let effectiveLength = String(localized: "有效长度")
    static let lineResistance = String(localized: "线路电阻")
    static let voltageDrop = String(localized: "电压降")
    static let ampacityCheck = String(localized: "载流量校核")
    static let recommendedSection = String(localized: "推荐截面")
    static let conduitArea = String(localized: "线管截面积")
    static let wireArea = String(localized: "导线总截面积")
    static let trayArea = String(localized: "桥架截面积")
    static let cableArea = String(localized: "电缆总截面积")
    static let complianceCheck = String(localized: "规范校核")
    static let recommendedConduit = String(localized: "推荐管内径")
    static let recommendedTray = String(localized: "推荐桥架")
    static let floorArea = String(localized: "地面面积")
    static let adjustedArea = String(localized: "含损耗面积")
    static let adhesive = String(localized: "胶粘剂")
    static let packageCount = String(localized: "箱数")
    static let perimeter = String(localized: "周长")
    static let grossArea = String(localized: "毛面积")
    static let deductionArea = String(localized: "扣除门窗")
    static let netArea = String(localized: "净面积")
    static let netVolume = String(localized: "净方量")
    static let cement = String(localized: "水泥")
    static let sand = String(localized: "砂")
    static let gravel = String(localized: "碎石")
    static let unitWeight = String(localized: "单位重")
    static let totalWeight = String(localized: "总重")
    static let tonnage = String(localized: "吨位")
    static let estimatedCost = String(localized: "造价")
}

enum CalculatorCopy {
    static let actionCalculate = String(localized: "计算")
    static let actionEstimate = String(localized: "估算")
    static let actionSelect = String(localized: "选型")
    static let actionConvert = String(localized: "换算")
    static let actionAdd = String(localized: "添加")
    static let actionCancel = String(localized: "取消")
    static let resultSection = String(localized: "计算结果")

    static let historySection = String(localized: "记录")
    static let historyTitle = String(localized: "计算历史")
    static let historyDescription = String(localized: "查看、删除历史计算结果")

    static let currentTool = String(localized: "电流计算")
    static let currentInputSection = String(localized: "输入参数")
    static let currentFormulaSection = String(localized: "公式")
    static let currentResultTitle = String(localized: "电流计算结果")
    static let currentPower = String(localized: "功率")
    static let currentPowerPlaceholder = String(localized: "例如 10")
    static let currentCommonPower = String(localized: "常用功率")
    static let currentVoltage = String(localized: "电压")
    static let currentVoltagePreset = String(localized: "电压预设")
    static let currentPowerFactor = String(localized: "功率因数")
    static let currentPowerFactorPreset = String(localized: "功率因数")
    static let currentThreePhase = String(localized: "三相电")
    static let currentInvalidNumber = String(localized: "请输入有效数值")
    static let currentPowerRange = String(localized: "请输入 0.1–5000000")
    static let currentVoltageRange = String(localized: "请输入 12–100000")
    static let currentPowerFactorRange = String(localized: "请输入 0.01–1")

    static let voltageDropTool = String(localized: "电缆压降")
    static let voltageDropLineSection = String(localized: "线路参数")
    static let voltageDropAmpacitySection = String(localized: "载流量参考")
    static let voltageDropResultTitle = String(localized: "压降评估")
    static let voltageDropCurrent = String(localized: "电流")
    static let voltageDropCurrentPlaceholder = String(localized: "例如 20")
    static let voltageDropCommonCurrent = String(localized: "常用电流")
    static let voltageDropLength = String(localized: "长度")
    static let voltageDropLengthPlaceholder = String(localized: "例如 100")
    static let voltageDropCommonLength = String(localized: "常用长度")
    static let voltageDropLoopLength = String(localized: "回路长度（已含来/回）")
    static let voltageDropMaterial = String(localized: "材质")
    static let voltageDropCopper = String(localized: "铜")
    static let voltageDropAluminum = String(localized: "铝")
    static let voltageDropSectionArea = String(localized: "截面积")
    static let voltageDropRatedVoltage = String(localized: "额定电压")
    static let voltageDropVoltagePreset = String(localized: "电压预设")
    static let voltageDropAmpacityNotice = String(localized: "以下载流量仅作现场估算参考，正式选型仍以设计和敷设条件校核为准")
    static let voltageDropCurrentRange = String(localized: "请输入 0.1–100000")
    static let voltageDropLengthRange = String(localized: "请输入 1–1000000")
    static let voltageDropSectionRange = String(localized: "请输入 1–20000")
    static let voltageDropVoltageRange = String(localized: "请输入 12–100000")

    static let conduitTool = String(localized: "线管穿线率")
    static let conduitParameterSection = String(localized: "参数")
    static let conduitReferenceSection = String(localized: "参考")
    static let conduitResultTitle = String(localized: "线管穿线率")
    static let conduitInnerDiameter = String(localized: "线管内径")
    static let conduitCommonDiameter = String(localized: "常用管径")
    static let conduitWireDiameter = String(localized: "单根导线外径")
    static let conduitCommonWireDiameter = String(localized: "常用线径")
    static let conduitWireCount = String(localized: "导线根数")
    static let conduitCommonWireCount = String(localized: "常用根数")
    static let conduitFillNotice = String(localized: "规范要求穿线率 ≤ 40%")
    static let conduitInnerDiameterRange = String(localized: "请输入 6–10000")
    static let conduitWireDiameterRange = String(localized: "请输入 0.5–100")
    static let conduitWireCountRange = String(localized: "请输入 1–500")
    static let integerRequired = String(localized: "请输入整数")
    static let conduitUnsupportedSize = String(localized: "超出常用规格")

    static let trayTool = String(localized: "桥架填充率")
    static let trayDimensionSection = String(localized: "桥架尺寸 (mm)")
    static let trayCableSection = String(localized: "电缆列表")
    static let trayResultTitle = String(localized: "桥架填充率")

    static let breakerTool = String(localized: "空开/漏保选型")
    static let breakerLoadSection = String(localized: "负载参数")
    static let breakerReferenceSection = String(localized: "选型参考")
    static let breakerResultSection = String(localized: "推荐")
    static let breakerResultTitle = String(localized: "断路器推荐")
    static let breakerCurrent = String(localized: "计算电流")
    static let breakerCurrentPlaceholder = String(localized: "例如 32")
    static let breakerCommonCurrent = String(localized: "常用电流")
    static let breakerLoadType = String(localized: "负载类型")
    static let breakerCurrentRequired = String(localized: "请输入计算电流")
    static let breakerCurrentRange = String(localized: "请输入 0.1–100000")
    static let breakerSocketLoad = String(localized: "插座")
    static let breakerPowerLoad = String(localized: "动力")

    static let concreteTool = String(localized: "混凝土算量")
    static let concreteDimensionSection = String(localized: "板面尺寸")
    static let concreteResultTitle = String(localized: "混凝土估算")
    static let concreteLength = String(localized: "长度")
    static let concreteWidth = String(localized: "宽度")
    static let concreteThickness = String(localized: "厚度")
    static let concreteWaste = String(localized: "损耗")
    static let concreteThicknessPreset = String(localized: "厚度预设")
    static let concreteGrade = String(localized: "标号")
    static let concreteMixNotice = String(localized: "配比为估算值，现场下单前请以搅拌站或配合比通知单复核。")
    static let concreteLengthRange = String(localized: "请输入 0.1–10000")
    static let concreteThicknessRange = String(localized: "请输入 1–200")
    static let concreteWasteRange = String(localized: "请输入 0–40")

    static let unitConverterTool = String(localized: "单位换算")
    static let unitConverterSection = String(localized: "换算")
    static let unitConverterResultTitle = String(localized: "单位换算")
    static let unitCategory = String(localized: "类别")
    static let unitValue = String(localized: "数值")
    static let unitQuickValue = String(localized: "快捷值")
    static let unitFrom = String(localized: "从")
    static let unitTo = String(localized: "到")
    static let unitNotice = String(localized: "换算只做单位制切换，不替代材料规格、配比和损耗计算。")
    static let unitSelectUnit = String(localized: "请选择单位")
    static let unitInputRange = String(localized: "请输入 0–1000000000")
    static let unitLengthCategory = String(localized: "长度")
    static let unitAreaCategory = String(localized: "面积")
    static let unitWeightCategory = String(localized: "重量")
    static let unitMeter = String(localized: "米")
    static let unitKilometer = String(localized: "千米")
    static let unitCentimeter = String(localized: "厘米")
    static let unitMillimeter = String(localized: "毫米")
    static let unitFoot = String(localized: "英尺")
    static let unitInch = String(localized: "英寸")
    static let unitYard = String(localized: "码")
    static let unitSquareMeter = String(localized: "平方米")
    static let unitSquareKilometer = String(localized: "平方千米")
    static let unitHectare = String(localized: "公顷")
    static let unitMu = String(localized: "亩")
    static let unitSquareFoot = String(localized: "平方英尺")
    static let unitKilogram = String(localized: "千克")
    static let unitTon = String(localized: "吨")
    static let unitGram = String(localized: "克")
    static let unitPound = String(localized: "磅")
    static let unitOunce = String(localized: "盎司")

    static let tileTool = String(localized: "地砖排料")
    static let tileRoomSection = String(localized: "房间")
    static let tileMaterialSection = String(localized: "瓷砖")
    static let tileResultTitle = String(localized: "地砖排料结果")
    static let tileHeadlinePrefix = String(localized: "需瓷砖")
    static let tileRoomLength = String(localized: "房间长度")
    static let tileRoomWidth = String(localized: "房间宽度")
    static let tileLength = String(localized: "瓷砖长度")
    static let tileWidth = String(localized: "瓷砖宽度")
    static let tileWaste = String(localized: "损耗")
    static let tileBoxPieces = String(localized: "每箱片数")
    static let lengthPreset = String(localized: "长度预设")
    static let widthPreset = String(localized: "宽度预设")
    static let commonLength = String(localized: "常用长度")
    static let commonWidth = String(localized: "常用宽度")
    static let wastePreset = String(localized: "损耗预设")

    static let rebarTool = String(localized: "钢筋重量")
    static let rebarSpecSection = String(localized: "钢筋规格")
    static let rebarResultTitle = String(localized: "钢筋重量估算")
    static let totalWeightPrefix = String(localized: "总重")
    static let rebarDiameter = String(localized: "直径")
    static let rebarCommonDiameter = String(localized: "常用直径")
    static let rebarLengthEach = String(localized: "每根长")
    static let rebarCommonLength = String(localized: "常用长度")
    static let rebarQuantity = String(localized: "根数")
    static let rebarCommonQuantity = String(localized: "常用根数")
    static let unitPrice = String(localized: "单价")
    static let optionalPlaceholder = String(localized: "选填")

    static let wallTool = String(localized: "墙面面积")
    static let wallDimensionSection = String(localized: "墙面尺寸 (m)")
    static let wallOpeningSection = String(localized: "扣除面积 (m²)")
    static let wallResultTitle = String(localized: "墙面面积结果")
    static let wallLength1 = String(localized: "墙 1 长")
    static let wallLength2 = String(localized: "墙 2 长")
    static let wallLength3 = String(localized: "墙 3 长")
    static let wallLength4 = String(localized: "墙 4 长")
    static let wallHeight = String(localized: "层高")
    static let wallHeightPreset = String(localized: "层高预设")
    static let wallDoorArea = String(localized: "门总面积")
    static let wallWindowArea = String(localized: "窗总面积")
    static let wallLengthRequired = String(localized: "请至少输入一面墙长度")
    static let wallLengthRequiredHint = String(localized: "请至少输入一面墙长度（>0）")
    static let wallLengthRange = String(localized: "请输入 0–10000")
    static let wallHeightRange = String(localized: "请输入 1.8–20")
    static let wallOpeningRange = String(localized: "请输入 0–5000")

    static let trayWidth = String(localized: "宽度")
    static let trayCommonWidth = String(localized: "常用宽度")
    static let trayHeight = String(localized: "高度")
    static let trayCommonHeight = String(localized: "常用高度")
    static let trayDeleteCable = String(localized: "删除此电缆")
    static let trayAddCable = String(localized: "添加电缆")
    static let trayCableOuterDiameter = String(localized: "外径 (mm)")
    static let trayCableCount = String(localized: "根数 (根)")
    static let trayFillNotice = String(localized: "桥架穿线率按截面积估算，常用控制目标不高于 40%。")
    static let trayWidthRange = String(localized: "请输入 50–10000")
    static let trayHeightRange = String(localized: "请输入 30–2000")
    static let trayUnsupportedSize = String(localized: "超出常用规格")
    static let trayDraftUTF8EncodeFailed = String(localized: "桥架填充草稿编码后 UTF8 转换失败")

    static let unitPieces = String(localized: "片")
    static let unitRoots = String(localized: "根")
    static let unitYuanPerKilogram = String(localized: "元/kg")
}

enum CalculatorHistorySupport {
    @MainActor
    static func record(
        store: DataStore,
        tool: String,
        input: String,
        result: String
    ) {
        store.appendCalculationHistory(
            tool: tool,
            input: input,
            result: result
        )
    }
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
