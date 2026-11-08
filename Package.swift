// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowRail",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WindowRail", targets: ["WindowRail"])],
    targets: [
        .executableTarget(name: "WindowRail", resources: [.process("Resources")], linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
            .linkedFramework("ApplicationServices"), .linkedFramework("ServiceManagement"),
            .linkedFramework("QuartzCore")
        ])
    ]
)
