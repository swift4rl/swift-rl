// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
import Foundation
import PackageDescription

let package = Package(
    name: "ReinforcementLearning",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(
            name: "ReinforcementLearning",
            targets: ["ReinforcementLearning"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "ReinforcementLearning",
            path: "Sources/ReinforcementLearning")
    ]
)
