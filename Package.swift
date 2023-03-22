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
        .library(name: "Test", targets: ["SAKTest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios", branch: "4.1.3"),
        .package(url: "https://github.com/Alamofire/Alamofire", branch: "5.6.4"),
        .package(url: "https://github.com/apollographql/apollo-ios", branch: "1.0.6"),
    ],
    targets: [
        // Network
        .target(
            name: "SAKNetwork",
            dependencies: [
                .product(name: "Apollo", package: "apollo-ios"),
                "Alamofire",
                "SAKUtil"
            ],
            path: "Source/Network"
        ),
        .testTarget(
            name: "SAKNetworkTest",
            dependencies: ["SAKNetwork"],
            path: "Tests/Network"
        ),

        // Util
        .target(
            name: "SAKUtil",
            dependencies: [],
            path: "Source/Util"
        ),
        .testTarget(
            name: "SAKUtilTest",
            dependencies: ["SAKUtil"],
            path: "Tests/Util"
        ),

        // View
        .target(
            name: "SAKView",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios")
            ],
            path: "Source/View"
        ),
        .testTarget(
            name: "SAKViewTest",
            dependencies: ["SAKView"],
            path: "Tests/View"
        ),

        // Test
        .target(
            name: "SAKTest",
            dependencies: [],
            path: "Source/Test"
        ),
    ]
)
