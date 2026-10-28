// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CameraCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CameraCore", targets: ["CameraCore"])],
    dependencies: [
        .package(url: "https://github.com/hmlongco/Factory.git", exact: "2.5.3"),
        .package(url: "https://github.com/Moya/Moya.git", exact: "15.0.3"),
        .package(
            url: "https://github.com/Miles-Matheson/HandyJSON.git",
            revision: "de8a7126d2270da55cea3cb45dadffcfd002dbbe"
        ),
    ],
    targets: [
        .target(
            name: "Localization",
            path: "Services/Localization"
        ),
        .target(
            name: "FNNetwork",
            dependencies: ["Moya", "HandyJSON", "Factory"],
            path: "Modules/FNNetwork"
        ),
        .target(
            name: "Storage",
            dependencies: ["Factory"],
            path: "Services/Storage"
        ),
        .target(
            name: "CameraCore",
            dependencies: ["Localization"],
            path: "Services",
            exclude: ["Storage", "UI", "Localization"]
        ),
        .target(
            name: "FNUser",
            dependencies: ["FNNetwork", "Storage", "Factory", "Localization"],
            path: "Modules/FNUser",
            exclude: ["MVVM/View", "Resources"]
        ),
        .target(
            name: "FNGenerationModels",
            dependencies: ["Localization"],
            path: "Modules/FNGeneration/MVVM/Model"
        ),
        .target(
            name: "FNOnboarding",
            dependencies: ["Storage", "Factory", "Localization"],
            path: "Modules/FNOnboarding",
            exclude: ["MVVM/View", "MVVM/ViewModel", "MVVM/Model/CameraNoticePresentation.swift", "Resources", "OnboardingViewController.swift"]
        ),
        .target(
            name: "FNVirtualCameraCore",
            dependencies: ["CameraCore", "Localization"],
            path: "Modules/FNVirtualCamera/Camera",
            exclude: ["Output"]
        ),
        .testTarget(
            name: "CameraCoreTests",
            dependencies: ["CameraCore", "FNVirtualCameraCore"],
            path: "Tests",
            exclude: ["Modules", "Network", "Localization"]
        ),
        .testTarget(
            name: "LocalizationTests",
            dependencies: ["Localization"],
            path: "Tests/Localization"
        ),
        .testTarget(
            name: "NetworkTests",
            dependencies: ["FNNetwork", "Moya"],
            path: "Tests/Network"
        ),
        .testTarget(
            name: "ModuleTests",
            dependencies: ["FNUser", "FNGenerationModels", "FNOnboarding", "FNNetwork", "Storage", "Moya", "Factory"],
            path: "Tests/Modules"
        ),
    ]
)
