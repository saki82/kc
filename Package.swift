// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "kc",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "kc",
            path: "Sources/kc"
        )
    ]
)
