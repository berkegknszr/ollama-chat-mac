// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "OllamaSohbet",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "OllamaSohbet", path: "Sources")]
)
