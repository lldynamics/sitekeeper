package com.chengjinfang.sitekeeper.calculator

import java.util.Locale
import kotlin.math.ceil
import kotlin.math.sqrt

data class CalculatorMetric(
    val label: String,
    val value: String,
    val warning: Boolean = false
)

data class CalculatorResult(
    val title: String,
    val headline: String,
    val formula: String,
    val metrics: List<CalculatorMetric>
)

enum class ConcreteGrade(
    val title: String,
    val cementKgPerM3: Double,
    val sandM3PerM3: Double,
    val gravelM3PerM3: Double
) {
    C20("C20", 320.0, 0.53, 0.84),
    C25("C25", 350.0, 0.50, 0.80),
    C30("C30", 380.0, 0.47, 0.77)
}

enum class WireMaterial(
    val title: String,
    val resistivity: Double
) {
    Copper("铜", 0.0175),
    Aluminum("铝", 0.0283)
}

enum class UnitCategory(
    val title: String,
    val units: List<UnitDefinition>
) {
    Length(
        title = "长度",
        units = listOf(
            UnitDefinition("毫米", 0.001),
            UnitDefinition("厘米", 0.01),
            UnitDefinition("米", 1.0),
            UnitDefinition("千米", 1000.0),
            UnitDefinition("英寸", 0.0254),
            UnitDefinition("英尺", 0.3048)
        )
    ),
    Area(
        title = "面积",
        units = listOf(
            UnitDefinition("平方毫米", 0.000001),
            UnitDefinition("平方米", 1.0),
            UnitDefinition("亩", 666.6667),
            UnitDefinition("公顷", 10000.0)
        )
    ),
    Weight(
        title = "重量",
        units = listOf(
            UnitDefinition("克", 0.001),
            UnitDefinition("千克", 1.0),
            UnitDefinition("吨", 1000.0)
        )
    )
}

data class UnitDefinition(
    val title: String,
    val factorToBase: Double
)

fun parseCalculatorNumber(value: String): Double? =
    value
        .replace(",", "")
        .trim()
        .toDoubleOrNull()

fun calculateConcrete(
    lengthM: Double?,
    widthM: Double?,
    thicknessCm: Double?,
    wastePercent: Double?,
    grade: ConcreteGrade
): CalculatorResult? {
    val length = lengthM?.takeIf { it > 0.0 } ?: return null
    val width = widthM?.takeIf { it > 0.0 } ?: return null
    val thickness = thicknessCm?.takeIf { it > 0.0 } ?: return null
    val waste = wastePercent?.takeIf { it >= 0.0 } ?: return null
    val netVolume = length * width * thickness / 100.0
    val totalVolume = netVolume * (1.0 + waste / 100.0)
    val cementKg = totalVolume * grade.cementKgPerM3
    val cementBags = ceil(cementKg / 50.0).toInt()

    return CalculatorResult(
        title = "混凝土算量",
        headline = "含损耗 ${formatCalculatorNumber(totalVolume, 3)} m³",
        formula = "净方量 = 长×宽×厚(cm)÷100；含损耗 = 净方量×(1+损耗%)",
        metrics = listOf(
            CalculatorMetric("净方量", "${formatCalculatorNumber(netVolume, 3)} m³"),
            CalculatorMetric("水泥", "${formatCalculatorNumber(cementKg, 0)} kg / $cementBags 袋"),
            CalculatorMetric("砂", "${formatCalculatorNumber(totalVolume * grade.sandM3PerM3, 3)} m³"),
            CalculatorMetric("碎石", "${formatCalculatorNumber(totalVolume * grade.gravelM3PerM3, 3)} m³")
        )
    )
}

fun calculateWallArea(
    wallLengthsM: List<Double?>,
    heightM: Double?,
    doorAreaM2: Double?,
    windowAreaM2: Double?
): CalculatorResult? {
    val walls = wallLengthsM.mapNotNull { it?.takeIf { value -> value > 0.0 } }
    val height = heightM?.takeIf { it > 0.0 } ?: return null
    if (walls.isEmpty()) {
        return null
    }

    val perimeter = walls.sum()
    val grossArea = perimeter * height
    val deductArea = (doorAreaM2 ?: 0.0).coerceAtLeast(0.0) + (windowAreaM2 ?: 0.0).coerceAtLeast(0.0)
    val netArea = (grossArea - deductArea).coerceAtLeast(0.0)

    return CalculatorResult(
        title = "墙面面积",
        headline = "净面积 ${formatCalculatorNumber(netArea, 2)} m²",
        formula = "净面积 = 墙体总周长×层高 - 门窗总面积",
        metrics = listOf(
            CalculatorMetric("周长", "${formatCalculatorNumber(perimeter, 2)} m"),
            CalculatorMetric("毛面积", "${formatCalculatorNumber(grossArea, 2)} m²"),
            CalculatorMetric("扣除", "${formatCalculatorNumber(deductArea, 2)} m²"),
            CalculatorMetric("净面积", "${formatCalculatorNumber(netArea, 2)} m²")
        )
    )
}

fun calculateTile(
    roomLengthM: Double?,
    roomWidthM: Double?,
    tileLengthMm: Double?,
    tileWidthMm: Double?,
    wastePercent: Double?,
    piecesPerBox: Double?
): CalculatorResult? {
    val roomLength = roomLengthM?.takeIf { it > 0.0 } ?: return null
    val roomWidth = roomWidthM?.takeIf { it > 0.0 } ?: return null
    val tileLength = tileLengthMm?.takeIf { it > 0.0 } ?: return null
    val tileWidth = tileWidthMm?.takeIf { it > 0.0 } ?: return null
    val waste = wastePercent?.takeIf { it >= 0.0 } ?: return null
    val boxPieces = piecesPerBox?.takeIf { it > 0.0 } ?: return null

    val area = roomLength * roomWidth
    val areaWithWaste = area * (1.0 + waste / 100.0)
    val tileArea = (tileLength / 1000.0) * (tileWidth / 1000.0)
    val pieceCount = ceilStable(areaWithWaste / tileArea)
    val boxCount = ceilStable(pieceCount / boxPieces)

    return CalculatorResult(
        title = "地砖排料",
        headline = "需 $pieceCount 片 / $boxCount 箱",
        formula = "片数 = ceil(含损耗面积÷单片面积)；箱数 = ceil(片数÷每箱片数)",
        metrics = listOf(
            CalculatorMetric("地面面积", "${formatCalculatorNumber(area, 2)} m²"),
            CalculatorMetric("含损耗", "${formatCalculatorNumber(areaWithWaste, 2)} m²"),
            CalculatorMetric("胶粘剂", "${formatCalculatorNumber(areaWithWaste * 5.0, 1)} kg"),
            CalculatorMetric("箱数", "$boxCount 箱")
        )
    )
}

fun calculateCurrent(
    powerKw: Double?,
    voltage: Double?,
    powerFactor: Double?,
    isThreePhase: Boolean
): CalculatorResult? {
    val power = powerKw?.takeIf { it > 0.0 } ?: return null
    val ratedVoltage = voltage?.takeIf { it > 0.0 } ?: return null
    val factor = powerFactor?.takeIf { it > 0.0 && it <= 1.0 } ?: return null
    val denominator = if (isThreePhase) {
        sqrt(3.0) * ratedVoltage * factor
    } else {
        ratedVoltage * factor
    }
    val current = power * 1000.0 / denominator

    return CalculatorResult(
        title = "电流计算",
        headline = "电流 ${formatCalculatorNumber(current, 2)} A",
        formula = if (isThreePhase) {
            "I = P×1000 ÷ (√3×U×cosφ)"
        } else {
            "I = P×1000 ÷ (U×cosφ)"
        },
        metrics = listOf(
            CalculatorMetric("功率", "${formatCalculatorNumber(power, 2)} kW"),
            CalculatorMetric("电压", "${formatCalculatorNumber(ratedVoltage, 0)} V"),
            CalculatorMetric("功率因数", formatCalculatorNumber(factor, 2)),
            CalculatorMetric("电流", "${formatCalculatorNumber(current, 2)} A", warning = current > 100.0)
        )
    )
}

fun calculateVoltageDrop(
    currentA: Double?,
    lengthM: Double?,
    sectionMm2: Double?,
    voltage: Double?,
    isLoopLength: Boolean,
    material: WireMaterial
): CalculatorResult? {
    val current = currentA?.takeIf { it > 0.0 } ?: return null
    val length = lengthM?.takeIf { it > 0.0 } ?: return null
    val section = sectionMm2?.takeIf { it > 0.0 } ?: return null
    val ratedVoltage = voltage?.takeIf { it > 0.0 } ?: return null
    val effectiveLength = if (isLoopLength) length else length * 2.0
    val resistance = material.resistivity * effectiveLength / section
    val dropV = current * resistance
    val dropPercent = dropV / ratedVoltage * 100.0
    val ampacity = roughAmpacity(section, material == WireMaterial.Copper)
    val recommended = recommendedWireSection(
        current = current,
        length = length,
        voltage = ratedVoltage,
        isLoopLength = isLoopLength,
        material = material
    )

    return CalculatorResult(
        title = "电缆压降",
        headline = "压降 ${formatCalculatorNumber(dropPercent, 2)}%",
        formula = "ΔU = I×(ρ×L有效÷S)，压降% = ΔU÷U×100%",
        metrics = listOf(
            CalculatorMetric("材质", material.title),
            CalculatorMetric("有效长度", "${formatCalculatorNumber(effectiveLength, 1)} m"),
            CalculatorMetric("线路电阻", "${formatCalculatorNumber(resistance, 3)} Ω"),
            CalculatorMetric("电压降", "${formatCalculatorNumber(dropV, 2)} V", warning = dropPercent > 5.0),
            CalculatorMetric("载流量", "${formatCalculatorNumber(ampacity, 0)} A", warning = current > ampacity),
            CalculatorMetric("推荐截面", recommended?.let { "${formatCalculatorNumber(it, 1)} mm²" } ?: "需复核设计", warning = recommended == null)
        )
    )
}

fun calculateUnitConversion(
    value: Double?,
    from: UnitDefinition,
    to: UnitDefinition
): CalculatorResult? {
    val inputValue = value ?: return null
    val outputValue = inputValue * from.factorToBase / to.factorToBase
    return CalculatorResult(
        title = "单位换算",
        headline = "${formatCalculatorNumber(outputValue, 4)} ${to.title}",
        formula = "输出值 = 输入值×源单位系数÷目标单位系数",
        metrics = listOf(
            CalculatorMetric("输入", "${formatCalculatorNumber(inputValue, 4)} ${from.title}"),
            CalculatorMetric("输出", "${formatCalculatorNumber(outputValue, 4)} ${to.title}")
        )
    )
}

fun roughAmpacity(
    sectionMm2: Double,
    isCopper: Boolean
): Double {
    val base = when {
        sectionMm2 <= 1.5 -> 14.0
        sectionMm2 <= 2.5 -> 24.0
        sectionMm2 <= 4.0 -> 32.0
        sectionMm2 <= 6.0 -> 41.0
        sectionMm2 <= 10.0 -> 57.0
        sectionMm2 <= 16.0 -> 76.0
        sectionMm2 <= 25.0 -> 101.0
        sectionMm2 <= 35.0 -> 125.0
        sectionMm2 <= 50.0 -> 150.0
        sectionMm2 <= 70.0 -> 192.0
        sectionMm2 <= 95.0 -> 232.0
        else -> sectionMm2 * 2.1
    }
    return if (isCopper) base else base * 0.78
}

fun recommendedWireSection(
    current: Double,
    length: Double,
    voltage: Double,
    isLoopLength: Boolean,
    material: WireMaterial
): Double? =
    STANDARD_WIRE_SECTIONS.firstOrNull { section ->
        voltageDropPercent(
            current = current,
            length = length,
            section = section,
            voltage = voltage,
            isLoopLength = isLoopLength,
            material = material
        ) <= 5.0 && current <= roughAmpacity(section, material == WireMaterial.Copper)
    }

val STANDARD_WIRE_SECTIONS: List<Double> =
    listOf(1.5, 2.5, 4.0, 6.0, 10.0, 16.0, 25.0, 35.0, 50.0, 70.0, 95.0, 120.0, 150.0, 185.0, 240.0)

private fun ceilStable(value: Double): Int =
    ceil(value - 1e-9).toInt()

private fun voltageDropPercent(
    current: Double,
    length: Double,
    section: Double,
    voltage: Double,
    isLoopLength: Boolean,
    material: WireMaterial
): Double {
    val effectiveLength = if (isLoopLength) length else length * 2.0
    val resistance = material.resistivity * effectiveLength / section
    return current * resistance / voltage * 100.0
}

fun formatCalculatorNumber(
    value: Double,
    decimals: Int
): String =
    if (value % 1.0 == 0.0) {
        String.format(Locale.US, "%.0f", value)
    } else {
        String.format(Locale.US, "%.${decimals}f", value).trimEnd('0').trimEnd('.')
    }
