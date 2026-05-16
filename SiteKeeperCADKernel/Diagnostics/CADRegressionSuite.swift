import Foundation

extension SiteKeeperCADKernel {
    struct CADRegressionSuite: Equatable, Codable {
        struct Case: Identifiable, Equatable, Codable {
            var id: String
            var fileName: String
            var expectedDiagnostics: [String]

            init(
                id: String,
                fileName: String,
                expectedDiagnostics: [String] = []
            ) {
                self.id = id
                self.fileName = fileName
                self.expectedDiagnostics = expectedDiagnostics
            }
        }

        struct SampleResult: Identifiable, Equatable, Codable {
            var id: String
            var fileName: String
            var openSucceeded: Bool
            var isBlank: Bool
            var chineseReadable: Bool?
            var missingFonts: [String]
            var missingBigFonts: [String]
            var missingXrefs: [String]
            var unsupportedEntityRatio: Double
            var firstFrameMs: Double
            var renderMs: Double
            var qualityScore: Int
            var launchReady: Bool

            init(
                id: String = UUID().uuidString,
                fileName: String,
                openSucceeded: Bool,
                isBlank: Bool,
                chineseReadable: Bool?,
                missingFonts: [String] = [],
                missingBigFonts: [String] = [],
                missingXrefs: [String] = [],
                unsupportedEntityRatio: Double,
                firstFrameMs: Double,
                renderMs: Double,
                qualityScore: Int,
                launchReady: Bool
            ) {
                self.id = id
                self.fileName = fileName
                self.openSucceeded = openSucceeded
                self.isBlank = isBlank
                self.chineseReadable = chineseReadable
                self.missingFonts = missingFonts
                self.missingBigFonts = missingBigFonts
                self.missingXrefs = missingXrefs
                self.unsupportedEntityRatio = unsupportedEntityRatio
                self.firstFrameMs = firstFrameMs
                self.renderMs = renderMs
                self.qualityScore = qualityScore
                self.launchReady = launchReady
            }

            var hasMissingFonts: Bool {
                !missingFonts.isEmpty || !missingBigFonts.isEmpty
            }
        }

        struct AcceptancePolicy: Equatable, Codable {
            var requiredSampleCount: Int
            var requiredMajorContentCount: Int
            var maximumMojibakeRatio: Double
            var maximumUnsupportedEntityRatio: Double
            var smallFileSecondOpenTargetMs: Double

            init(
                requiredSampleCount: Int = 30,
                requiredMajorContentCount: Int = 27,
                maximumMojibakeRatio: Double = 0.03,
                maximumUnsupportedEntityRatio: Double = 0.10,
                smallFileSecondOpenTargetMs: Double = 3_000
            ) {
                self.requiredSampleCount = requiredSampleCount
                self.requiredMajorContentCount = requiredMajorContentCount
                self.maximumMojibakeRatio = maximumMojibakeRatio
                self.maximumUnsupportedEntityRatio = maximumUnsupportedEntityRatio
                self.smallFileSecondOpenTargetMs = smallFileSecondOpenTargetMs
            }
        }

        struct AcceptanceSummary: Equatable, Codable {
            var sampleCount: Int
            var majorContentDisplayableCount: Int
            var blankCount: Int
            var missingFontCount: Int
            var missingXrefCount: Int
            var averageQualityScore: Double
            var launchReady: Bool
        }

        var cases: [Case]
        var results: [SampleResult]
        var acceptancePolicy: AcceptancePolicy

        init(
            cases: [Case] = [],
            results: [SampleResult] = [],
            acceptancePolicy: AcceptancePolicy = AcceptancePolicy()
        ) {
            self.cases = cases
            self.results = results
            self.acceptancePolicy = acceptancePolicy
        }

        func summarize() -> AcceptanceSummary {
            let majorContentCount = results.filter {
                $0.openSucceeded &&
                !$0.isBlank &&
                $0.unsupportedEntityRatio <= acceptancePolicy.maximumUnsupportedEntityRatio
            }.count
            let blankCount = results.filter(\.isBlank).count
            let missingFontCount = results.filter(\.hasMissingFonts).count
            let missingXrefCount = results.filter { !$0.missingXrefs.isEmpty }.count
            let averageQuality = results.isEmpty
                ? 0
                : Double(results.reduce(0) { $0 + $1.qualityScore }) / Double(results.count)
            let launchReady = results.count >= acceptancePolicy.requiredSampleCount &&
                majorContentCount >= acceptancePolicy.requiredMajorContentCount &&
                blankCount == 0

            return AcceptanceSummary(
                sampleCount: results.count,
                majorContentDisplayableCount: majorContentCount,
                blankCount: blankCount,
                missingFontCount: missingFontCount,
                missingXrefCount: missingXrefCount,
                averageQualityScore: averageQuality,
                launchReady: launchReady
            )
        }
    }
}
