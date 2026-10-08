// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArcaeaCore",
    platforms: [.iOS(.v18), .macOS(.v13)],
    products: [.library(name: "ArcaeaCore", targets: ["ArcaeaCore"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "ArcaeaCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .testTarget(name: "ArcaeaCoreTests", dependencies: ["ArcaeaCore"])
    ]
)
