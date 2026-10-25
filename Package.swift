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
        ),
        .library(
            name: "RemoteProcessProtocol",
            targets: ["RemoteProcessProtocol"]
        )
    ],
    targets: [
        .target(
            name: "RemoteLinkKit"
        ),
        .target(
            name: "RemoteProcessProtocol",
            dependencies: ["RemoteLinkKit"]
        ),
        .testTarget(
            name: "RemoteLinkKitTests",
            dependencies: ["RemoteLinkKit"]
        ),
        .testTarget(
            name: "RemoteProcessProtocolTests",
            dependencies: ["RemoteProcessProtocol"]
        )
    ]
)
