// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ValheimServerMonitor", platforms: [.macOS(.v13)],
    products: [.executable(name: "ValheimServerMonitor", targets: ["ValheimServerMonitor"])],
    targets: [.target(name: "ServerCore"), .executableTarget(name: "ValheimServerMonitor", dependencies: ["ServerCore"]),
              .testTarget(name: "ServerCoreTests", dependencies: ["ServerCore"])])
