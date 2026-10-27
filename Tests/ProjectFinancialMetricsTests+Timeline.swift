import Testing
import Foundation
@testable import sitekeeper

extension ProjectFinancialMetricsTests {
    @Test func constructionMethodVersionAndPublishStatusCodable() throws {
        let method = ConstructionMethod(
            title: "墙面找平",
            trade: "泥工",
            versionName: "V2",
            publishStatus: .published,
            tutorialBody: "基层处理",
            procedureSteps: ["放线", "打点"],
            qualityChecklist: ["平整度检查"],
            safetyChecklist: ["高处作业佩戴安全带"]
        )

        let data = try JSONEncoder().encode(method)
        let decoded = try JSONDecoder().decode(ConstructionMethod.self, from: data)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let legacy = try JSONDecoder().decode(
            ConstructionMethod.self,
            from: #"{"title":"旧工艺","trade":"水电","steps":"放线\n开槽"}"#.data(using: .utf8)!
        )

        #expect(encodedObject["steps"] == nil)
        #expect(encodedObject["qualityStandard"] == nil)
        #expect(encodedObject["safetyNotes"] == nil)
        #expect((encodedObject["procedureSteps"] as? [String]) == ["放线", "打点"])
        #expect((encodedObject["qualityChecklist"] as? [String]) == ["平整度检查"])
        #expect((encodedObject["safetyChecklist"] as? [String]) == ["高处作业佩戴安全带"])
        #expect(decoded.versionName == "V2")
        #expect(decoded.publishStatus == .published)
        #expect(decoded.procedureSteps == ["放线", "打点"])
        #expect(decoded.qualityChecklist == ["平整度检查"])
        #expect(decoded.safetyChecklist == ["高处作业佩戴安全带"])
        #expect(legacy.versionName == "V1")
        #expect(legacy.publishStatus == .draft)
        #expect(legacy.procedureSteps == ["放线", "开槽"])
    }

    @Test func projectTimelineSortsMixedItemsByDate() {
        let projectId = UUID()
        let log = DailyLog(
            date: BusinessDateValue(legacyText: "2026-05-08"),
            weather: "晴",
            content: "安装桥架",
            workers: NumericInputSupport.quantity("3"),
            projectId: projectId
        )
        let finance = ProjectFinancialRecord(
            projectId: projectId,
            date: BusinessDateValue(legacyText: "2026-05-09 10:30"),
            direction: .expense,
            category: .material,
            amount: NumericInputSupport.money("100")
        )
        let material = MaterialItem(
            name: "桥架",
            quantity: NumericInputSupport.quantity("10"),
            unit: "米",
            arrivalDate: BusinessDateValue(legacyText: "2026-05-07"),
            projectId: projectId
        )

        let items = ProjectTimelineBuilder.makeItems(
            logs: [log],
            progress: [],
            materials: [material],
            quotes: [],
            labor: [],
            financialRecords: [finance],
            documents: [],
            warehouseMovements: [],
            quickNotes: [],
            siteTodos: [],
            drawings: []
        )

        #expect(items.first?.type == "记账")
        #expect(items.map(\.type) == ["记账", "日志", "材料"])
    }
}
