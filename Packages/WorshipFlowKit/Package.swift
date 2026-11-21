// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorshipFlowKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "RenderEngine", targets: ["RenderEngine"]),
        .library(name: "MediaEngine", targets: ["MediaEngine"]),
        .library(name: "OutputEngine", targets: ["OutputEngine"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "OperatorCore", targets: ["OperatorCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0"),
    ],
    targets: [
        // Platform-independent rules. Must not import AppKit, SwiftUI, Metal, AVFoundation.
        .target(name: "Domain"),
        .target(name: "RenderEngine", dependencies: ["Domain"]),
        .target(name: "MediaEngine", dependencies: ["Domain"]),
        .target(name: "OutputEngine", dependencies: ["Domain", "RenderEngine"]),
        .target(name: "Persistence", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Domain"]),
        // SYS-002 settings storage tests, separate so parallel slices do not block each other.
        .testTarget(name: "SettingsStoreTests", dependencies: ["Persistence", "Domain"]),
        // Operator workspace logic (view models). SwiftUI views stay in the app target.
        .target(name: "OperatorCore", dependencies: ["Domain", "Persistence"]),
        .testTarget(name: "OperatorCoreTests", dependencies: ["OperatorCore", "Domain", "Persistence"]),
        // Themes, Looks and props. Separate from DomainTests so slices built in parallel do not block each other.
        .testTarget(name: "CompositionTests", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "RenderEngineTests", dependencies: ["RenderEngine", "Domain"]),
        .testTarget(name: "OutputEngineTests", dependencies: ["OutputEngine"]),
    ]
)
