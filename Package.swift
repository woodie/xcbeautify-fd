// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "xctidy",
    products: [
        .executable(name: "xctidy", targets: ["xctidy"])
    ],
    dependencies: [
        // Test-only. Lets one spec in XctidyKitTests be a *real*
        // Quick describe/context/it spec, so `swift test` produces a
        // genuine comma-flattened name for xctidy to disambiguate --
        // not just a hand-built fixture string.
        .package(url: "https://github.com/Quick/Quick.git", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.0.0"),
    ],
    targets: [
        // Core engine: parsing + rendering. Lives in its own target so the
        // test target can `@testable import` it without the executable
        // testability caveats that come with testing a target of type
        // .executableTarget directly.
        .target(name: "XctidyKit"),

        .executableTarget(
            name: "xctidy",
            dependencies: ["XctidyKit"]
        ),

        .testTarget(
            name: "XctidyKitTests",
            dependencies: [
                "XctidyKit",
                .product(name: "Quick", package: "Quick"),
                .product(name: "Nimble", package: "Nimble"),
            ]
        ),
    ]
)
