// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "NultraProtocol",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "NultraProtocol", targets: ["NultraProtocol"])],
    targets: [
        .target(name: "NultraProtocol", path: "Nultra/Models"),
        .testTarget(name: "NultraProtocolTests", dependencies: ["NultraProtocol"])
    ]
)
