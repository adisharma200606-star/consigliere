// swift-tools-version:5.9
import PackageDescription

// ConsigliereCore is the brain: matching, the stash, the line picker, config.
// It uses Foundation only, so it builds and tests on macOS and on Linux.
// The notch app (App/) depends on it; nothing here depends on the app.
let package = Package(
    name: "ConsigliereCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ConsigliereCore", targets: ["ConsigliereCore"])
    ],
    targets: [
        .target(name: "ConsigliereCore", path: "Sources/ConsigliereCore"),
        .testTarget(name: "ConsigliereCoreTests", dependencies: ["ConsigliereCore"], path: "Tests/ConsigliereCoreTests")
    ]
)
