// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iOS-SAK",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "Network", targets: ["SAKNetwork"]),
        .library(name: "Util", targets: ["SAKUtil"]),
        .library(name: "View", targets: ["SAKView"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", branch: "5.6.4"),
        .package(url: "https://github.com/apollographql/apollo-ios", branch: "1.0.6"),
    ],
    targets: [
        // Network
        .target(
            name: "SAKNetwork",
            dependencies: [
                "Alamofire",
                .product(name: "Apollo", package: "apollo-ios"),
                "SAKUtil"
            ],
            path: "Source/Network"
        ),

        // Util
        .target(
            name: "SAKUtil",
            dependencies: [],
            path: "Source/Util"
        ),

        // View
        .target(
            name: "SAKView",
            dependencies: [],
            path: "Source/View"
        ),
    ]
)
