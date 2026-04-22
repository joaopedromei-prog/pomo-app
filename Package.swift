// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pomo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pomo",
            path: "Sources/Pomo"
        )
    ]
)
