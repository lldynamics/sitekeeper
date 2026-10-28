// swift-tools-version: 6.0
import Foundation
import PackageDescription

// A host-only validation package. The iOS app continues compiling these same
// complete files through project.yml; no production code is copied or rewritten.
let calculationSources = ["EngineeringCalculations.swift", "CalculationValidator.swift", "SlopeHeightCalculation.swift"]
let existingUnitTests = ["UnitConverterTests.swift"]

func otherEntries(in directory: String, keeping names: [String]) throws -> [String] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)
        .filter { !names.contains($0) }
        .sorted()
}

let package = Package(
    name: "SitekeeperCalculationValidation",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ThumbnailCacheCore",
            path: "Sources/Shared/Services/Storage/CacheCore"
        ),
        .target(
            name: "BackupWorkflowCore",
            path: "Sources/Features/Profile/Backups",
            exclude: try otherEntries(in: "Sources/Features/Profile/Backups", keeping: ["BackupImportWorkflow.swift"]),
            sources: ["BackupImportWorkflow.swift"]
        ),
        .target(
            name: "sitekeeper",
            path: "Sources/Shared/Helpers",
            exclude: try otherEntries(in: "Sources/Shared/Helpers", keeping: calculationSources),
            sources: calculationSources
        ),
        .testTarget(
            name: "ExistingUnitConverterTests",
            dependencies: ["sitekeeper"],
            path: "Tests",
            exclude: try otherEntries(in: "Tests", keeping: existingUnitTests),
            sources: existingUnitTests
        ),
        .testTarget(
            name: "UnitConversionContractTests",
            dependencies: ["sitekeeper"],
            path: "HostTests/UnitConversion"
        ),
        .testTarget(
            name: "SlopeHeightContractTests",
            dependencies: ["sitekeeper"],
            path: "HostTests/SlopeHeight"
        ),
        .testTarget(
            name: "BackupImportWorkflowTests",
            dependencies: ["BackupWorkflowCore"],
            path: "HostTests/BackupWorkflow"
        ),
        .testTarget(
            name: "ThumbnailCacheTests",
            dependencies: ["ThumbnailCacheCore"],
            path: "HostTests/ThumbnailCache"
        ),
        .testTarget(
            name: "ThumbnailImageBenchmarks",
            dependencies: ["ThumbnailCacheCore"],
            path: "HostTests/ThumbnailBenchmarks"
        )
    ],
    swiftLanguageModes: [.v5]
)
