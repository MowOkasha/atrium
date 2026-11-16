// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Atrium",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Atrium",
            path: "Sources/Atrium",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
