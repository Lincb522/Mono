// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShibaWelcome",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ShibaWelcome", targets: ["ShibaWelcome"])],
    targets: [
        .target(
            name: "ShibaWelcome",
            resources: [.process("Resources"), .process("Shaders")]
        ),
        .testTarget(name: "ShibaWelcomeTests", dependencies: ["ShibaWelcome"])
    ]
)
