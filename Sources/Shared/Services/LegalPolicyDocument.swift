import Foundation

struct LegalPolicyDocument: Equatable {
    let policyId: String
    let version: String
    let localeIdentifier: String
    let lastUpdatedDisplay: String
    let body: String
}

enum LegalPolicyResourceLoader {
    static func privacyPolicy(
        bundle: Bundle = .main,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> LegalPolicyDocument {
        loadPolicy(
            manifestResource: "privacy-policy",
            bundle: bundle,
            preferredLanguages: preferredLanguages
        )
    }

    private static func loadPolicy(
        manifestResource: String,
        bundle: Bundle,
        preferredLanguages: [String]
    ) -> LegalPolicyDocument {
        guard
            let manifestURL = bundle.url(forResource: manifestResource, withExtension: "json"),
            let manifestData = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(PolicyManifest.self, from: manifestData),
            let localeKey = selectedLocale(
                preferredLanguages: preferredLanguages,
                availableLocales: Array(manifest.locales.keys),
                defaultLocale: manifest.defaultLocale
            ),
            let locale = manifest.locales[localeKey],
            let body = loadBody(locale: locale, bundle: bundle)
        else {
            return fallbackPrivacyPolicy()
        }

        return LegalPolicyDocument(
            policyId: manifest.policyId,
            version: manifest.version,
            localeIdentifier: localeKey,
            lastUpdatedDisplay: locale.lastUpdatedDisplay,
            body: renderTemplate(body)
        )
    }

    private static func loadBody(locale: PolicyManifest.LocaleEntry, bundle: Bundle) -> String? {
        guard
            let url = bundle.url(forResource: locale.resource, withExtension: locale.fileExtension),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func selectedLocale(
        preferredLanguages: [String],
        availableLocales: [String],
        defaultLocale: String
    ) -> String? {
        let available = Set(availableLocales)
        for language in preferredLanguages {
            let normalized = language.replacingOccurrences(of: "_", with: "-")
            if available.contains(normalized) {
                return normalized
            }
            if normalized.hasPrefix("zh-Hans"), available.contains("zh-Hans") {
                return "zh-Hans"
            }
            if normalized.hasPrefix("zh-Hant"), available.contains("zh-Hans") {
                return "zh-Hans"
            }
            if let base = normalized.split(separator: "-").first.map(String.init),
               available.contains(base) {
                return base
            }
        }
        return available.contains(defaultLocale) ? defaultLocale : availableLocales.sorted().first
    }

    private static func renderTemplate(_ text: String) -> String {
        text
            .replacingOccurrences(of: "{APP_NAME}", with: AppBrand.displayName)
            .replacingOccurrences(of: "{SUPPORT_EMAIL}", with: AppContact.supportEmail)
    }

    private static func fallbackPrivacyPolicy() -> LegalPolicyDocument {
        LegalPolicyDocument(
            policyId: "sitekeeper.privacy",
            version: "unknown",
            localeIdentifier: "fallback",
            lastUpdatedDisplay: AppPolicy.privacyPolicyFallbackLastUpdated,
            body: String(localized: "privacy.policy.unavailable")
        )
    }
}

private struct PolicyManifest: Decodable {
    struct LocaleEntry: Decodable {
        let resource: String
        let fileExtension: String
        let lastUpdatedDisplay: String
    }

    let policyId: String
    let version: String
    let defaultLocale: String
    let locales: [String: LocaleEntry]
}
