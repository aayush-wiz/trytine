// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClickyMine",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClickyMine",
            path: "Sources/ClickyMine"
        )
    ]
)
