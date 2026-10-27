// swift-tools-version: 6.0
import Foundation
import PackageDescription

// A host-only validation package. The iOS app continues compiling these same
// complete files through project.yml; no production code is copied or rewritten.
let calculationSources = ["EngineeringCalculations.swift", "CalculationValidator.swift"]
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
        )
    ],
    swiftLanguageModes: [.v5]
)
