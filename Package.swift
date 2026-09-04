// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopBinsWidget",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DesktopBinsWidget",
            path: "Sources/DesktopBinsWidget"
        )
    ]
)
