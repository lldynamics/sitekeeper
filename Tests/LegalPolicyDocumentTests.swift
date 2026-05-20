import Testing
@testable import sitekeeper

struct LegalPolicyDocumentTests {
    @Test func privacyPolicyLoadsVersionedChineseSource() {
        let document = AppPolicy.privacyPolicyDocument(preferredLanguages: ["zh-Hans"])

        #expect(document.policyId == "sitekeeper.privacy")
        #expect(document.version == "2026-05-15")
        #expect(document.localeIdentifier == "zh-Hans")
        #expect(document.lastUpdatedDisplay == "2026年5月15日")
        #expect(document.body.contains(AppBrand.displayName))
        #expect(document.body.contains(AppContact.supportEmail))
        #expect(!document.body.contains("{APP_NAME}"))
        #expect(!document.body.contains("{SUPPORT_EMAIL}"))
    }

    @Test func privacyPolicyFallsBackToEnglishBaseLanguage() {
        let document = AppPolicy.privacyPolicyDocument(preferredLanguages: ["en-US"])

        #expect(document.localeIdentifier == "en")
        #expect(document.lastUpdatedDisplay == "May 15, 2026")
        #expect(document.body.contains(AppContact.supportEmail))
        #expect(document.body.contains("Drawing Originals"))
    }
}
