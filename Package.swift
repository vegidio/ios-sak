// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "iOS-SAK",
    platforms: [
        .iOS(.v18),
        .macOS(.v12),
    ],
    products: [
        .library(name: "REST", targets: ["REST"]),
        .library(name: "GraphQL", targets: ["GraphQL"]),
        .library(name: "Components", targets: ["Components"]),
    ],
    targets: [
        .target(name: "REST", path: "Sources/REST"),
        .target(name: "GraphQL", path: "Sources/GraphQL"),
        .target(name: "Components", path: "Sources/Components"),
        .testTarget(name: "RESTTests", dependencies: ["REST"], path: "Tests/RESTTests"),
        .testTarget(name: "GraphQLTests", dependencies: ["GraphQL"], path: "Tests/GraphQLTests"),
        .testTarget(name: "ComponentsTests", dependencies: ["Components"], path: "Tests/ComponentsTests"),
    ]
)
