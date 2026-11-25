// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything both programs share: accounts on disk, telling Claude
        // copies apart, link routing. No user interface; unit tested.
        .target(name: "SwitchboardCore"),
        // The menu bar app.
        .executableTarget(name: "Switchboard", dependencies: ["SwitchboardCore"]),
        // The command-line tool.
        .executableTarget(name: "cprof", dependencies: ["SwitchboardCore"]),
        .testTarget(name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore"],
                    path: "tests/SwitchboardCoreTests"),
    ]
)
