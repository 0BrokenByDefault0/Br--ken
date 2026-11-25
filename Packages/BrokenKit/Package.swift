// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrokenKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MusicCore", targets: ["MusicCore"]),
        .library(name: "SoundEngine", targets: ["SoundEngine"]),
    ],
    targets: [
        .target(name: "MusicCore"),
        .target(name: "SoundEngine", dependencies: ["MusicCore"]),
        .testTarget(name: "MusicCoreTests", dependencies: ["MusicCore"], exclude: ["Fixtures"]),
        .testTarget(name: "SoundEngineTests", dependencies: ["SoundEngine"]),
    ],
    swiftLanguageModes: [.v6]
)
