import Foundation
import Observation
import PDFKit
import SwiftUI
import Testing
@testable import sitekeeper

@Suite(.serialized)
@MainActor
struct AppPresentationTests {
    @Test func languageChangesResolveStringsAndStaticCalculatorCopyWithoutRestart() {
        let preferences = UserPreferencesStore.shared
        let previous = preferences.string(UserPreferenceKeys.languageCode)
        defer { restore(previous, key: UserPreferenceKeys.languageCode) }

        preferences.set(AppLanguage.chinese.rawValue, for: UserPreferenceKeys.languageCode)
        #expect(AppLocalization.string("项目") == "项目")
        #expect(CalculatorResultLabel.input == "输入")
        #expect(ToolboxCatalog.practicalTools.first?.title == "水印相机")
        let tutorialIDs = ConstructionMethodTutorialBlockCatalog.quickTools.map(\.id)
        let changed = PresentationObservationFlag()
        withObservationTracking {
            _ = AppLocalization.string("项目")
        } onChange: { changed.set() }

        preferences.set(AppLanguage.english.rawValue, for: UserPreferenceKeys.languageCode)
        #expect(changed.isSet)
        #expect(AppLocalization.string("项目") == "Projects")
        #expect(CalculatorResultLabel.input == "Input")
        #expect(ToolboxCatalog.practicalTools.first?.title == "Watermark Camera")
        #expect(ConstructionMethodTutorialBlockCatalog.quickTools.map(\.id) == tutorialIDs)
        #expect(Tab.dashboard.title == "Dashboard")
        #expect(PaymentStatus.partial.displayName == "Partially Paid")
        #expect(ProjectFinancialStatus.active.displayName == "Active")
        #expect(AppTheme.dropboxBlue.displayName == "Sky Blue")
        #expect(String(format: AppLocalization.string("%lld 天"), Int64(12)) == "12 days")

        preferences.set(AppLanguage.chinese.rawValue, for: UserPreferenceKeys.languageCode)
        #expect(AppLocalization.string("项目") == "项目")
        #expect(CalculatorResultLabel.input == "输入")
    }

    @Test func themeColorReadsParticipateInObservation() {
        let preferences = UserPreferencesStore.shared
        let previous = preferences.string(UserPreferenceKeys.appTheme)
        defer { restore(previous, key: UserPreferenceKeys.appTheme) }
        preferences.set(AppTheme.dropboxBlue.rawValue, for: UserPreferenceKeys.appTheme)
        let blue = UIColor(Color.appPrimaryAction).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let changed = PresentationObservationFlag()
        withObservationTracking {
            _ = Color.appPrimaryAction
            _ = Color.appFinanceSurface
        } onChange: { changed.set() }

        AppTheme.warmAmber.apply()
        #expect(changed.isSet)
        #expect(AppTheme.current == .warmAmber)
        let amber = UIColor(Color.appPrimaryAction).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(!blue.isEqual(amber))
    }

    @Test func resourceBundlesAndUnknownKeysHavePredictableFallbacks() {
        #expect(AppLocalization.localizedBundle(language: .english).bundleURL.lastPathComponent == "en.lproj")
        #expect(AppLocalization.localizedBundle(language: .chinese).bundleURL.lastPathComponent == "zh-Hans.lproj")
        #expect(AppLocalization.string("uiux-missing-key") == "uiux-missing-key")
        #expect(["zh-Hans", "en"].contains(AppLanguage.system.resourceLanguageCode))
    }

    @Test func generalPDFTemplatesFollowSelectedLanguageAndPreserveUserContent() throws {
        let preferences = UserPreferencesStore.shared
        let previous = preferences.string(UserPreferenceKeys.languageCode)
        defer { restore(previous, key: UserPreferenceKeys.languageCode) }
        let snapshot = pdfLocalizationSnapshot()
        var options = ExportContentOptions()
        options.currencyDisplayMode = .numberOnly

        // Switch both ways in one process, independently of the device language.
        for language in [AppLanguage.chinese, .english, .chinese] {
            preferences.set(language.rawValue, for: UserPreferenceKeys.languageCode)
            var lines: [String] = []
            ReportBuilderPDFSections.appendSections(snapshot: snapshot, options: options, lines: &lines)
            let isEnglish = language == .english
            let material = isEnglish
                ? "- 材料 50% %@  2.5 千克  Unit Price 1.24  Amount 3.09"
                : "- 材料 50% %@  2.5 千克  单价1.24  金额3.09"
            let quote = isEnglish ? "Quotation Details  Total 21.26" : "报价明细  合计 21.26"
            let labor = isEnglish
                ? "- 2026-10-30  2 people × 1.5 Work Hours  Unit Price 3.34/Work Hours  Amount 10.01  备注 50% %@"
                : "- 2026-10-30  2人 × 1.5工时  单价3.34/工时  金额10.01  备注 50% %@"
            let expected = [material, quote, labor]
            for line in expected { #expect(lines.contains(line)) }
            #expect(lines.contains { $0.contains(isEnglish ? "  Due 2026-11-01 " : "  到期2026-11-01 ") })
            #expect(lines.contains { $0.contains(isEnglish ? "对方 50% %@  Receipts: 2" : "对方 50% %@  票据2份") })
            #expect(lines.contains { $0.contains(isEnglish ? "资料 50% %@  Pages: 3  7.13" : "资料 50% %@  3页  7.13") })
            #expect(lines.contains { $0.contains(isEnglish ? "  Attachments: 1" : "  附件1个") })
            #expect(lines.contains { $0.contains("工程 原样 50%") })

            let document = try #require(PDFDocument(data: ReportBuilder.makePDF(snapshot: snapshot, options: options)))
            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
            #expect(text.contains(isEnglish ? "Data Export" : "数据导出"))
            #expect(text.contains(isEnglish ? "Generated at:" : "生成时间:"))
            #expect(text.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}"#, options: .regularExpression) != nil)
            let compactText = text.filter { !$0.isWhitespace }
            for line in expected {
                #expect(compactText.contains(line.filter { !$0.isWhitespace }))
            }
            for content in ["备注 50% %@", "对方 50% %@", "资料 50% %@", "笔记 50% %@", "工程 原样 50%", "千克", "米"] {
                #expect(compactText.contains(content.filter { !$0.isWhitespace }))
            }
            if isEnglish {
                for label in ["单价", "金额", "合计", "到期", "票据2份", "3页", "附件1个"] {
                    #expect(!text.contains(label))
                }
            }
        }
    }

    @Test func generalPDFKeepsCustomTitleAndCurrencySelection() throws {
        let preferences = UserPreferencesStore.shared
        let previous = preferences.string(UserPreferenceKeys.languageCode)
        defer { restore(previous, key: UserPreferenceKeys.languageCode) }
        preferences.set(AppLanguage.english.rawValue, for: UserPreferenceKeys.languageCode)
        let snapshot = pdfLocalizationSnapshot()
        let title = "自定标题 50% %@"
        for (mode, amount) in [(ExportCurrencyDisplayMode.cny, "¥3.09"), (.usd, "$3.09"), (.eur, "€3.09"), (.numberOnly, "3.09")] {
            var options = ExportContentOptions()
            options.currencyDisplayMode = mode
            let document = try #require(PDFDocument(data: ReportBuilder.makePDF(snapshot: snapshot, options: options, title: title)))
            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
            #expect(text.hasPrefix(title))
            #expect(text.contains("Amount \(amount)"))
        }
    }

    private func pdfLocalizationSnapshot() -> BackupSnapshot {
        let project = Project(name: "工程 原样 50%", location: "")
        let document = ProjectDocument(projectId: project.id, title: "资料 50% %@", fileName: "synthetic.pdf", pageCount: 3,
                                       amount: NumericInputSupport.money("7.125"))
        return BackupSnapshot(
            materialItems: [MaterialItem(name: "材料 50% %@", quantity: NumericInputSupport.quantity("2.5"), unit: "千克",
                                         unitPrice: NumericInputSupport.money("1.235"))],
            quoteItems: [QuoteItem(name: "报价 原样", unitPrice: NumericInputSupport.money("10.125"), quantity: 2, unit: "米", notes: "", taxRate: 10, discountRate: 5)],
            laborRecords: [LaborRecord(date: BusinessDateValue(legacyText: "2026-10-30"), workers: 2, hours: NumericInputSupport.quantity("1.5"),
                                       unitRate: NumericInputSupport.money("3.335"), note: "备注 50% %@")],
            projects: [project], dailyLogs: [], historyRecords: [],
            projectFinancialRecords: [ProjectFinancialRecord(projectId: project.id, amount: NumericInputSupport.money("7.125"), counterparty: "对方 50% %@",
                                                             linkedDocumentIds: [document.id, UUID()], dueDate: BusinessDateValue(legacyText: "2026-11-01"), reminderStatus: .pending)],
            projectDocuments: [document],
            quickNotes: [QuickNote(title: "笔记 50% %@", attachments: [QuickNoteAttachment(kind: .file, fileName: "synthetic.txt", originalName: "原样.txt")])],
            templates: []
        )
    }

    private func restore(_ value: String, key: String) {
        if value.isEmpty {
            UserPreferencesStore.shared.removeObject(for: key)
        } else {
            UserPreferencesStore.shared.set(value, for: key)
        }
    }
}

private final class PresentationObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }
}
