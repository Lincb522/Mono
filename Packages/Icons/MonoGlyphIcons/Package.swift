// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonoGlyphIcons",
    platforms: [.iOS(.v16)],
    products: [.library(name: "MonoGlyphIcons", targets: ["MonoGlyphIcons"])],
    targets: [
        .target(
            name: "MonoGlyphIcons",
            resources: [.process("icons.xcassets"), .process("expressiveOutline.xcassets")]
        )
    ]
)
