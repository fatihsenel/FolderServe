// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FolderServeCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FolderServeCore", targets: ["FolderServeCore"])],
    targets: [
        .target(name: "FolderServeCore"),
        .testTarget(name: "FolderServeCoreTests", dependencies: ["FolderServeCore"]),
    ]
)
