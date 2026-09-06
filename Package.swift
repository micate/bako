// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Bako",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "Bako", targets: ["BakoApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "BakoApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "BakoAppTests",
            dependencies: ["BakoApp"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
