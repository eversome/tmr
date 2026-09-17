// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tmr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "tmr", targets: ["tmr"]),
        .library(name: "TimerCore", targets: ["TimerCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Pure logic. No AppKit, no terminal, no I/O of any kind.
        // Everything else in this package is a renderer on top of it.
        .target(name: "TimerCore"),

        // Output backends. Today: terminal. v0.2: a floating HUD. v0.4: BUSY Bar.
        .target(name: "Renderers", dependencies: ["TimerCore"]),

        .executableTarget(
            name: "tmr",
            dependencies: [
                "TimerCore",
                "Renderers",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        .testTarget(name: "TimerCoreTests", dependencies: ["TimerCore"]),
    ]
)
