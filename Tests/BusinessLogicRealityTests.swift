import Foundation
import Testing
@testable import sitekeeper

struct BusinessLogicRealityTests {
    @MainActor
    @Test func dailyWeatherRequiresObservationAndSurvivesDraftRecovery() throws {
        let store = BusinessDraftStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("weather-test-\(UUID().uuidString)"))
        defer { try? store.removeAll() }
        let dates = ["2026-10-24", "2026-01-02"].compactMap(Formatters.date.date(from:))
        #expect(DailyLogEditorState().weather.isEmpty)
        for date in dates {
            var composer = DailyLogComposerState(initialDate: date)
            #expect(composer.weather.isEmpty)
            let key = BusinessDraftStore.Key.daily(projectID: UUID())
            for observation in ["", "大雨", "Rain"] {
                composer.weather = observation
                let draft = DailyLogFormDraft(composer: composer, recordID: UUID())
                try store.save(draft, key: key)
                let restarted = BusinessDraftStore(root: store.root)
                let loaded = try #require(try restarted.load(DailyLogFormDraft.self, key: key))
                let restored = try loaded.composer(store: restarted, key: key)
                #expect(restored.weather == observation)
                #expect(restored.date.date() == date)
            }
        }
    }

    @MainActor
    @Test func logCalendarFindsNativeAndLegacyRepresentationsOfTheSameDay() throws {
        let day = try #require(CalendarDay("2026-10-24"))
        let date = try #require(Formatters.date.date(from: day.storageText))
        let native = DailyLog(date: .day(day), weather: "", content: "待补天气", workers: .empty)
        let restored = DailyLog(date: BusinessDateValue(legacyText: day.storageText), weather: "大雨", content: "人工实况", workers: .empty)
        let alternateDates = ["2026/10/24", " 2026-10-24 ", "2026-10-24 12:00:00"]
        let legacyLogs = alternateDates.map {
            DailyLog(date: BusinessDateValue(legacyText: $0), weather: "大雨", content: "历史记录", workers: .empty)
        }
        let invalid = DailyLog(date: .unresolved("未知日期"), weather: "", content: "待核实", workers: .empty)
        let otherDay = DailyLog(date: BusinessDateValue(legacyText: "2026-10-25"), weather: "", content: "次日", workers: .empty)
        let expected = [native, restored] + legacyLogs
        let logs = DailyLogCalendarIndex(logs: expected + [invalid, otherDay]).logs(on: date)
        #expect(Set(logs.map(\.id)) == Set(expected.map(\.id)))
        #expect(logs.first(where: { $0.id == restored.id })?.weather == "大雨")
        #expect(logs.first(where: { $0.id == native.id })?.weather == "")
    }

    @Test func csvForSpreadsheetsPreservesChineseQuotesCommasAndMultilineCells() throws {
        let row = ReportBuilder.csv(["现场实况", "大雨,停工", "备注：\"核实\"", "第一行\n第二行"])
        let data = ReportBuilder.csvData(rows: [ReportBuilder.csv(["天气", "工况", "确认", "记录"]), row])
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = try #require(String(data: data.dropFirst(3), encoding: .utf8))
        #expect(text == "\"天气\",\"工况\",\"确认\",\"记录\"\r\n\"现场实况\",\"大雨,停工\",\"备注：\"\"核实\"\"\",\"第一行\n第二行\"\r\n")
        #expect(!text.contains("<html"))
    }
}
