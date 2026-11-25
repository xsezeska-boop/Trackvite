// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Trackvite",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Trackvite", targets: ["Tracker"])],
    targets: [.executableTarget(name: "Tracker")]
)
