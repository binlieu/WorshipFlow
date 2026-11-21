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
        .library(name: "DeckLinkSDI", targets: ["DeckLinkSDI"]),
        .library(name: "CueEngine", targets: ["CueEngine"]),
        .library(name: "ScriptureEngine", targets: ["ScriptureEngine"]),
        .library(name: "ScriptureStore", targets: ["ScriptureStore"]),
        .library(name: "CueStore", targets: ["CueStore"]),
        .executable(name: "wf-bible-import", targets: ["BibleImportTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0"),
    ],
    targets: [
        // Platform-independent rules. Must not import AppKit, SwiftUI, Metal, AVFoundation.
        .target(name: "Domain"),
        .target(name: "RenderEngine", dependencies: ["Domain"]),
        .target(name: "MediaEngine", dependencies: ["Domain"]),
        .target(name: "OutputEngine", dependencies: ["Domain", "RenderEngine", "SDIEngine"]),
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
        // HW-003: Blackmagic DeckLink bridge. DeckLinkC is Objective-C++ around the vendor headers in sdk/
        // (ADR-0006); its public header is plain Objective-C. DeckLinkSDI adapts it to the SDIEngine protocols.
        .target(name: "DeckLinkC",
                exclude: ["sdk/README.md"],
                cxxSettings: [.headerSearchPath("sdk")],
                linkerSettings: [.linkedFramework("CoreFoundation"), .linkedFramework("Foundation"), .linkedFramework("CoreVideo")]),
        .target(name: "DeckLinkSDI", dependencies: ["DeckLinkC", "SDIEngine", "Domain"]),
        .testTarget(name: "DeckLinkSDITests", dependencies: ["DeckLinkSDI", "DeckLinkC", "SDIEngine"]),
        // CUE-001: show-control rules (actions, macros, schedule, playback markers, MIDI mapping). Pure Swift.
        .target(name: "CueEngine", dependencies: ["Domain"]),
        .testTarget(name: "CueEngineTests", dependencies: ["CueEngine", "Domain"]),
        // LIB-004: scripture references, verse splitting into slides, translation file format. Pure Swift.
        .target(name: "ScriptureEngine", dependencies: ["Domain"]),
        .testTarget(name: "ScriptureEngineTests", dependencies: ["ScriptureEngine", "Domain"]),
        // LIB-004b: translations stored in the church library, and the command-line importer (ADR-0008).
        .target(name: "ScriptureStore", dependencies: ["ScriptureEngine", "Persistence", "Domain", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ScriptureStoreTests", dependencies: ["ScriptureStore", "ScriptureEngine", "Persistence"]),
        .executableTarget(name: "BibleImportTool", dependencies: ["ScriptureStore", "ScriptureEngine", "Persistence"]),
        // CUE-002a: storage of macros, slide actions, schedule and MIDI bindings in the church library.
        .target(name: "CueStore", dependencies: ["CueEngine", "Persistence", "Domain", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "CueStoreTests", dependencies: ["CueStore", "CueEngine", "Persistence"]),
        // Operator workspace logic (view models). SwiftUI views stay in the app target.
        .target(name: "OperatorCore", dependencies: ["Domain", "Persistence"]),
        .testTarget(name: "OperatorCoreTests", dependencies: ["OperatorCore", "Domain", "Persistence"]),
        // Themes, Looks and props. Separate from DomainTests so slices built in parallel do not block each other.
        .testTarget(name: "CompositionTests", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "RenderEngineTests", dependencies: ["RenderEngine", "Domain"]),
        .testTarget(name: "OutputEngineTests", dependencies: ["OutputEngine"]),
    ],
    cxxLanguageStandard: .cxx17
)
