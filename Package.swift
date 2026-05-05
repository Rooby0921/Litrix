// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Litrix",
    defaultLocalization: "en",
    platforms: [
        .macOS("14.4")
    ],
    products: [
        .executable(
            name: "Litrix",
            targets: ["PaperDockApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PaperDockApp",
            path: "Sources/PaperDockApp",
            resources: [
                .process("Resources/zh-Hans.lproj"),
                .copy("Resources/Plugins")
            ]
        )
    ]
)
