// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VcovenApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VcovenApp", targets: ["VcovenApp"]),
    ],
    targets: [
        .executableTarget(
            name: "VcovenApp",
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "VcovenAppTests", dependencies: ["VcovenApp"]),
    ]
)
