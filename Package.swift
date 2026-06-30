// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "iOS-SAK",
    platforms: [
        .iOS(.v18),
        .macOS(.v12),
    ],
    products: [
        .library(name: "REST", targets: ["REST"]),
        .library(name: "Components", targets: ["Components"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.11.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
    ],
    targets: [
        .macro(
            name: "RESTMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftBasicFormat", package: "swift-syntax"),
            ],
            path: "Sources/REST/Macros"
        ),
        .target(
            name: "REST",
            dependencies: ["Alamofire", "RESTMacros"],
            path: "Sources/REST",
            exclude: ["Macros", "README.md"]
        ),
        .target(name: "Components", path: "Sources/Components"),
        .testTarget(name: "RESTTests", dependencies: ["REST"], path: "Tests/RESTTests"),
        .testTarget(
            name: "RESTMacrosTests",
            dependencies: [
                "RESTMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/RESTMacrosTests"
        ),
        .testTarget(
            name: "ComponentsTests", dependencies: ["Components"], path: "Tests/ComponentsTests"),
    ]
)
