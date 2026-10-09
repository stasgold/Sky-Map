// swift-tools-version:5.9
//
// SkyCore: the platform-independent heart of the iOS port of Sky Map v2 — math, ephemerides,
// the bundled catalog, the renderer contract and the layer producers. It has no UIKit/CoreMotion
// dependency, so it builds and tests on Linux as well as Apple platforms.

import PackageDescription

let package = Package(
    name: "SkyCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SkyCore", targets: ["SkyCore"]),
    ],
    targets: [
        .target(
            name: "SkyCore",
            resources: [.copy("Resources/catalog")]
        ),
        .testTarget(
            name: "SkyCoreTests",
            dependencies: ["SkyCore"]
        ),
    ]
)
