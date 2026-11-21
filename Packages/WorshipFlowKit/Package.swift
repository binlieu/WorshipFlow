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
    ],
    targets: [
        // Platform-independent rules. Must not import AppKit, SwiftUI, Metal, AVFoundation.
        .target(name: "Domain"),
        .target(name: "RenderEngine", dependencies: ["Domain"]),
        .target(name: "MediaEngine", dependencies: ["Domain"]),
        .target(name: "OutputEngine", dependencies: ["Domain", "RenderEngine"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "RenderEngineTests", dependencies: ["RenderEngine", "Domain"]),
        .testTarget(name: "OutputEngineTests", dependencies: ["OutputEngine"]),
    ]
)
