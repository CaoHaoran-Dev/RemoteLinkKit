// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteLinkKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "RemoteLinkKit",
            targets: ["RemoteLinkKit"]
        )
    ],
    targets: [
        .target(name: "RemoteLinkKit"),
        .testTarget(
            name: "RemoteLinkKitTests",
            dependencies: ["RemoteLinkKit"]
        )
    ]
)
