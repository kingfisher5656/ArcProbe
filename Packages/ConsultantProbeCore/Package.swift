// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ConsultantProbeCore", platforms: [.iOS(.v18), .macOS(.v13)],
    products: [.library(name: "ConsultantProbeCore", targets: ["ConsultantProbeCore"])],
    targets: [.target(name: "ConsultantProbeCore"), .testTarget(name: "ConsultantProbeCoreTests", dependencies: ["ConsultantProbeCore"])])
