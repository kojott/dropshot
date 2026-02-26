// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DropShot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DropShot", targets: ["DropShot"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DropShot",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "DropShot",
            resources: [
                .process("Resources"),
                .copy("App/Info.plist")
            ]
        ),
        .testTarget(
            name: "DropShotTests",
            dependencies: ["DropShot"],
            path: "DropShotTests"
        )
    ]
)
