// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clementine",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Clementine",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            // The Makefile embeds Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
