// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GnoshbotData",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GnoshbotData", targets: ["GnoshbotData"]),
    ],
    targets: [
        .target(
            name: "GnoshbotData",
            path: ".",
            exclude: [
                "Gnoshbot",
                "Gnoshbot.xcodeproj",
                "Tests",
                "project.yml",
            ],
            sources: [
                "ActiveOrderCache.swift",
                "RestaurantCache.swift",
                "MenuCache.swift",
                "ProfileBlob.swift",
                "GnoshbotStore.swift",
                "DeliveryLocationEntity.swift",
                "DeliveryLocationQuery.swift",
                "LaunchCopy.swift",
                "LunchRange.swift",
                "OrderLunchLaunch.swift",
            ]
        ),
        .testTarget(
            name: "GnoshbotDataTests",
            dependencies: ["GnoshbotData"],
            path: "Tests/GnoshbotDataTests"
        ),
    ]
)
