import Foundation

enum AppContact {
    static let supportEmail = "support@chengjinfang.com"
}

enum AppBrand {
    static var displayName: String {
        let info = Bundle.main.infoDictionary
        if let name = info?["CFBundleDisplayName"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let name = info?[kCFBundleNameKey as String] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "工地掌柜"
    }

    static var exportFilePrefix: String {
        displayName
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
    }
}

enum AppPolicy {
    static let privacyPolicyFallbackLastUpdated = "2026-05-24"

    static var privacyPolicyLastUpdated: String {
        privacyPolicyDocument().lastUpdatedDisplay
    }

    static func privacyPolicyDocument(
        bundle: Bundle = .main,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> LegalPolicyDocument {
        LegalPolicyResourceLoader.privacyPolicy(
            bundle: bundle,
            preferredLanguages: preferredLanguages
        )
    }
}

enum AppFeatureFlags {
    static var allowsSampleDataImport: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

    static var allowsConstructionMethodPackEndpointOverride: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }
}
