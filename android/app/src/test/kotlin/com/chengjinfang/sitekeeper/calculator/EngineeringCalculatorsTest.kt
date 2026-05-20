package com.chengjinfang.sitekeeper.calculator

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class EngineeringCalculatorsTest {
    @Test
    fun concreteCalculatorIncludesWasteAndMaterialEstimate() {
        val result = assertNotNull(
            calculateConcrete(
                lengthM = 10.0,
                widthM = 8.0,
                thicknessCm = 12.0,
                wastePercent = 5.0,
                grade = ConcreteGrade.C25
            )
        )

        assertEquals("含损耗 10.08 m³", result.headline)
        assertTrue(result.metrics.any { it.label == "水泥" && it.value.contains("3528 kg") })
    }

    @Test
    fun wallAreaCalculatorDeductsOpenings() {
        val result = assertNotNull(
            calculateWallArea(
                wallLengthsM = listOf(6.0, 4.0, 6.0, 4.0),
                heightM = 2.8,
                doorAreaM2 = 2.0,
                windowAreaM2 = 3.0
            )
        )

        assertEquals("净面积 51 m²", result.headline)
    }

    @Test
    fun tileCalculatorRoundsPiecesAndBoxesUp() {
        val result = assertNotNull(
            calculateTile(
                roomLengthM = 6.0,
                roomWidthM = 4.0,
                tileLengthMm = 600.0,
                tileWidthMm = 600.0,
                wastePercent = 8.0,
                piecesPerBox = 4.0
            )
        )

        assertEquals("需 72 片 / 18 箱", result.headline)
    }

    @Test
    fun currentCalculatorHandlesSingleAndThreePhase() {
        val single = assertNotNull(
            calculateCurrent(
                powerKw = 10.0,
                voltage = 220.0,
                powerFactor = 0.85,
                isThreePhase = false
            )
        )
        val three = assertNotNull(
            calculateCurrent(
                powerKw = 10.0,
                voltage = 380.0,
                powerFactor = 0.85,
                isThreePhase = true
            )
        )

        assertEquals("电流 53.48 A", single.headline)
        assertEquals("电流 17.87 A", three.headline)
    }

    @Test
    fun voltageDropCalculatorFlagsHighDrop() {
        val result = assertNotNull(
            calculateVoltageDrop(
                currentA = 20.0,
                lengthM = 100.0,
                sectionMm2 = 2.5,
                voltage = 220.0,
                isLoopLength = false,
                material = WireMaterial.Copper
            )
        )

        assertEquals("压降 12.73%", result.headline)
        assertTrue(result.metrics.any { it.label == "电压降" && it.warning })
    }

    @Test
    fun unitConverterUsesCategoryFactors() {
        val result = assertNotNull(
            calculateUnitConversion(
                value = 1.0,
                from = UnitCategory.Length.units.first { it.title == "米" },
                to = UnitCategory.Length.units.first { it.title == "厘米" }
            )
        )

        assertEquals("100 厘米", result.headline)
    }
}
