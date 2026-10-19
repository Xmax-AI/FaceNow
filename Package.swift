// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CameraCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CameraCore", targets: ["CameraCore"])],
    targets: [
        .target(name: "CameraCore", path: "Shared", resources: [.copy("Assets.xcassets")]),
        .testTarget(name: "CameraCoreTests", dependencies: ["CameraCore"], path: "Tests")
    ]
)
