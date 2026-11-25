// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no UI: safe to unit test.
        .target(name: "SwitchboardCore"),
        // The menu bar app.
        .executableTarget(name: "Switchboard", dependencies: ["SwitchboardCore"]),
        .testTarget(name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore"],
                    path: "tests/SwitchboardCoreTests"),
    ]
)
