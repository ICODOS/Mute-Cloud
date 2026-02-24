// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Mute",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Mute", targets: ["Mute"])
    ],
    dependencies: [
        // Global hotkey support with customizable UI
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Mute",
            dependencies: [
                "KeyboardShortcuts",
            ],
            path: "Mute"
        ),
    ]
)
