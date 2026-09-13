// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Mono",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "Mono",
            targets: ["Mono"]),
    ],
    dependencies: [
        // NeteaseCloudMusicAPI - ncm API 封装库（对齐后端 4.40.1）
        .package(path: "Packages/MusicServices/NeteaseCloudMusicAPI-Swift"),
        // FFmpegSwiftSDK - Mono播放引擎底层 FFmpeg 8.0 解码与流媒体 SDK
        .package(path: "Packages/Audio/ffmpeg-swift"),
        // QQMusicKit - qcm API 封装库（对齐后端 0.7.2）
        .package(path: "Packages/MusicServices/QQMusicKit"),
        // HiconIcons - Hicon 图标库（本地包，从 Figma 导出）
        .package(path: "Packages/Icons/HiconIcons"),
        // ZappiconIcons - Zappicon (H173) 图标库（本地包，Light 风格）
        .package(path: "Packages/Icons/ZappiconIcons"),
        // LucideIcons - Lucide 图标库（本地包）
        .package(path: "Packages/Icons/LucideIcons"),
        // SolarIcons - Solar 图标库（本地包）
        .package(path: "Packages/Icons/SolarIcons"),
        // BlobIcons - Blob 风格 PNG 图标包
        .package(path: "Packages/Icons/BlobIcons"),
        // doodlePop - 配套 PNG 图标包
        .package(path: "Packages/Icons/doodlePop"),
        // PawPrintIcons - 猫狗扁平 PNG 图标包
        .package(path: "Packages/Icons/PawPrintIcons"),
        // DotDogSnakeIcons - 点狗蛇 PNG 图标包
        .package(path: "Packages/Icons/DotDogSnakeIcons"),
        // MinimalWhiteIcons - 纯白主题配套 PNG 图标包
        .package(path: "Packages/Icons/MinimalWhiteIcons"),
        // PulseBloomIcons - Pulse Bloom 图标包
        .package(path: "Packages/Icons/PulseBloomIcons"),
        // MonoGlyphIcons - MONO 原创图标包
        .package(path: "Packages/Icons/MonoGlyphIcons"),
        // ZIPFoundation - 用户字体 ZIP 压缩包导入
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
    ],
    targets: [
        .target(
            name: "Mono",
            dependencies: [
                .product(name: "NeteaseCloudMusicAPI", package: "NeteaseCloudMusicAPI-Swift"),
                .product(name: "FFmpegSwiftSDK", package: "ffmpeg-swift"),
                "QQMusicKit",
                "HiconIcons",
                "ZappiconIcons",
                "LucideIcons",
                "SolarIcons",
                "BlobIcons",
                "doodlePop",
                "PawPrintIcons",
                "DotDogSnakeIcons",
                "MinimalWhiteIcons",
                "PulseBloomIcons",
                "MonoGlyphIcons",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
                .process("Resources/SanJiPoMoTi.ttf"),
                .process("Resources/HYPixel11pxU.ttf"),
                .process("Resources/ZihunBantianyun.ttf"),
                .process("Resources/YeZiGongChangGangFengSong.ttf"),
                .process("Resources/WenDaoPaoPaoTi-2.ttf"),
                .process("Resources/k8x12S-4.ttf"),
                .process("Resources/eq_presets.json"),
                .process("Resources/eq_presets_32.json"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
            ]
        ),
        // MARK: - 测试 Target(material3-expressive-theme Task 15)
        // 单元测试 + Property-Based Testing(PBT)Target
        .testTarget(
            name: "MonoTests",
            dependencies: ["Mono"],
            path: "Tests/MonoTests"
        ),
    ]
)
