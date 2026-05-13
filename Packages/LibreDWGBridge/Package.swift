// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LibreDWGBridge",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "LibreDWGBridge",
            targets: ["LibreDWGBridge"]
        ),
    ],
    targets: [
        .target(
            name: "LibreDWGBridge"
        ),
    ]
)
