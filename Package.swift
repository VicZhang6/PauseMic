// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PauseMic",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "PauseMic", targets: ["PauseMic"])],
    targets: [
        .target(name: "PauseMicCore"),
        .executableTarget(name: "PauseMic", dependencies: ["PauseMicCore"]),
        .testTarget(name: "PauseMicCoreTests", dependencies: ["PauseMicCore"]),
        .testTarget(name: "PauseMicNativeTests", dependencies: ["PauseMic", "PauseMicCore"])
    ]
)
