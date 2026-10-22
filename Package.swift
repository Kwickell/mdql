// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkdownQuickLook",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "MarkdownQuickLookCore", targets: ["MarkdownQuickLookCore"]),
        .executable(name: "mdql-render", targets: ["mdql-render"]),
        .executable(name: "mdql-probe", targets: ["mdql-probe"]),
        .executable(name: "mdql-qlcheck", targets: ["mdql-qlcheck"])
    ],
    targets: [
        .target(name: "MarkdownQuickLookCore", path: "Sources/MarkdownQuickLookCore"),
        .executableTarget(
            name: "mdql-render",
            dependencies: ["MarkdownQuickLookCore"],
            path: "CLI"
        ),
        .executableTarget(
            name: "mdql-probe",
            dependencies: ["MarkdownQuickLookCore"],
            path: "Probe"
        ),
        .executableTarget(name: "mdql-qlcheck", path: "QLCheck"),
        .testTarget(
            name: "MarkdownQuickLookCoreTests",
            dependencies: ["MarkdownQuickLookCore"],
            path: "Tests/MarkdownQuickLookCoreTests"
        )
    ]
)
