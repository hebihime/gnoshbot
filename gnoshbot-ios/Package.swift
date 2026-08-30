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
            sources: ["ActiveOrderCache.swift"]
        ),
    ]
)
