// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-screenshot-mcp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mac-screenshot-mcp", targets: ["MacScreenshotMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")
    ],
    targets: [
        .executableTarget(
            name: "MacScreenshotMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacScreenshotMCPTests",
            dependencies: ["MacScreenshotMCP"]
        ),
    ]
)
