// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "NultraProtocol",
    products: [.library(name: "NultraProtocol", targets: ["NultraProtocol"])],
    targets: [
        .target(name: "NultraProtocol", path: "Nultra/Models"),
        .testTarget(name: "NultraProtocolTests", dependencies: ["NultraProtocol"])
    ]
)
