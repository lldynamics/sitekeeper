import Foundation
import Testing
@testable import sitekeeper

struct TransferLimitPolicyTests {
    @Test func resolveProfileUsesOverrideThenEnvironment() {
        #expect(TransferLimitPolicy.resolveProfile(userDefaultRaw: "dev", environmentRaw: "prod") == .development)
        #expect(TransferLimitPolicy.resolveProfile(userDefaultRaw: nil, environmentRaw: "staging") == .staging)
        #expect(TransferLimitPolicy.resolveProfile(userDefaultRaw: "unknown", environmentRaw: "release") == .production)
        #expect(TransferLimitPolicy.resolveProfile(userDefaultRaw: nil, environmentRaw: nil) == .production)
    }

    @Test func productionAndDevelopmentProfilesCoverImportAndExportLimits() {
        let production = TransferLimitPolicy.limits(for: .production)
        let development = TransferLimitPolicy.limits(for: .development)

        #expect(production.maxImportBytes == 500 * 1024 * 1024)
        #expect(production.backupArchiveWarningBytes == 1024 * 1024 * 1024)
        #expect(production.projectPackageWarningBytes == 1024 * 1024 * 1024)

        #expect(development.maxImportBytes > production.maxImportBytes)
        #expect(development.backupArchiveWarningBytes == production.backupArchiveWarningBytes)
        #expect(development.projectPackageWarningBytes == production.projectPackageWarningBytes)
    }

    @Test func sampleImportGateUsesEnvironmentProfile() {
        #expect(TransferLimitPolicy.allowsSampleDataImport(for: .production) == false)
        #expect(TransferLimitPolicy.allowsSampleDataImport(for: .staging))
        #expect(TransferLimitPolicy.allowsSampleDataImport(for: .development))
    }
}
