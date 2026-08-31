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
                "AddressDraft.swift",
                "BioShieldMatcher.swift",
                "CacheHydrator.swift",
                "ControlPlaneSettings.swift",
                "DeliveryLocationEntity.swift",
                "DeliveryLocationQuery.swift",
                "DeviceIdentity.swift",
                "GeoHash5.swift",
                "GnoshbotStore.swift",
                "LaunchCopy.swift",
                "LunchRange.swift",
                "LunchScorer.swift",
                "LaunchFollowThrough.swift",
                "MenuCache.swift",
                "MenuDocument.swift",
                "OrderLunchLaunch.swift",
                "ProfileBlob.swift",
                "PrototypeCatalog.swift",
                "PrototypeProfileStore.swift",
                "PushCopy.swift",
                "RegionBBox.swift",
                "RegionEnsureClient.swift",
                "RestaurantCache.swift",
                "SettlementError.swift",
                "SettlementSession.swift",
                "SettlementWorker.swift",
                "ShopPrefix.swift",
                "ShopRuntimeConfig.swift",
                "SpenderKey.swift",
                "X402Network.swift",
                "X402V1.swift",
                "FulfillmentPoller.swift",
                "InquirySpeech.swift",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "GnoshbotDataTests",
            dependencies: ["GnoshbotData"],
            path: "Tests/GnoshbotDataTests"
        ),
    ]
)
