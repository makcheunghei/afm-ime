// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "afm-ime",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "IMECore", path: "Sources/IMECore"),
        .executableTarget(name: "dictcompiler", dependencies: ["IMECore"], path: "Sources/DictCompiler"),
        .executableTarget(name: "dictbench", dependencies: ["IMECore"], path: "Sources/DictBench"),
        .executableTarget(name: "fmstructbench", path: "Sources/FMStructBench"),
        .executableTarget(name: "cloudmodelbench", path: "Sources/CloudModelBench"),
        .executableTarget(name: "providerbench", path: "Sources/ProviderBench"),
        .executableTarget(name: "dbg", dependencies: ["IMECore"], path: "Sources/Debug"),
        .executableTarget(name: "afm-input", dependencies: ["IMECore"], path: "Sources/AFMInput"),
        .executableTarget(name: "afm-app", dependencies: ["IMECore"], path: "Sources/AFMApp"),
        .testTarget(name: "IMECoreTests", dependencies: ["IMECore"], path: "Tests/IMECoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
