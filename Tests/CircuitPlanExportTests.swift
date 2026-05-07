import Testing
import Foundation
@testable import sitekeeper

struct CircuitPlanExportTests {
    @Test func exportLightingPlansPDF() {
        let plans = [samplePlan(name: "一层照明")]
        let data = ReportBuilder.makeLightingCircuitPlansPDF(projectName: "测试项目", plans: plans)
        #expect(data.count > 0)
    }

    @Test func exportLightingPlansExcel() {
        let plans = [samplePlan(name: "一层照明"), samplePlan(name: "二层照明")]
        let data = ReportBuilder.makeLightingCircuitPlansExcelHTML(projectName: "测试项目", plans: plans)
        let html = String(data: data, encoding: .utf8) ?? ""
        #expect(html.contains("测试项目"))
        #expect(html.contains("一层照明"))
        #expect(html.contains("二层照明"))
    }

    private func samplePlan(name: String) -> LightingCircuitPlan {
        LightingCircuitPlan(
            name: name,
            projectId: nil,
            supplyType: .singlePhase,
            voltage: "220",
            powerFactor: "0.9",
            demandFactor: "0.9",
            breakerFactor: "1.25",
            wireFactor: "1.15",
            isCopper: true,
            loads: [
                LightingCircuitLoad(name: "走廊", powerKW: "2.5"),
                LightingCircuitLoad(name: "楼梯间", powerKW: "1.2"),
            ],
            updatedAt: "2026-05-02 15:10"
        )
    }
}
