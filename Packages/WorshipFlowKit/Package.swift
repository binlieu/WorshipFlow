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
        .library(name: "SDIEngine", targets: ["SDIEngine"]),
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
        // STAGE-001a: stage layouts and timers, separate targets so parallel slices do not block each other.
        .testTarget(name: "StageTests", dependencies: ["Domain"]),
        .testTarget(name: "StageStoreTests", dependencies: ["Persistence", "Domain"]),
        // MEDIA-002: media transport rules.
        .testTarget(name: "MediaRulesTests", dependencies: ["Domain"]),
        .testTarget(name: "MediaEngineTests", dependencies: ["MediaEngine", "Domain"]),
        // SLIDE-001a: slide objects (shapes, images, text boxes) across model, compositor and storage.
        .testTarget(name: "SlideObjectTests", dependencies: ["Domain", "RenderEngine", "Persistence"]),
        // HW-001: SDI device abstraction, scheduler, connector planning and simulator. No vendor SDK here.
        .target(name: "SDIEngine", dependencies: ["Domain"]),
        .testTarget(name: "SDIEngineTests", dependencies: ["SDIEngine", "Domain"]),
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
