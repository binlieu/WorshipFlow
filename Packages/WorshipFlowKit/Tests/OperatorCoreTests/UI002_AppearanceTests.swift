// UI-002 Part 4: the appearance setting (System, Dark, Light; default Dark) stored with the library, and the contrast of
// the token pairs the design README names, computed from docs/UI/design-tokens.json for both appearances.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct UI002_AppearanceChoiceTests {
    @Test func threeChoicesInOrderWithDarkTheDefault() {
        #expect(AppearanceChoice.allCases.map(\.title) == ["System", "Dark", "Light"])
        #expect(AppearanceChoice.default == .dark)
    }
    @Test func aStoredValueIsRestoredAndAnythingElseIsDark() {
        #expect(AppearanceChoice.restored(from: "light") == .light)
        #expect(AppearanceChoice.restored(from: "system") == .system)
        #expect(AppearanceChoice.restored(from: nil) == .dark)
        #expect(AppearanceChoice.restored(from: "purple") == .dark)
    }
    @Test func theViewAsksForAnExplicitSchemeExceptForSystem() {
        #expect(AppearanceChoice.system.forcedScheme == nil)
        #expect(AppearanceChoice.dark.forcedScheme == .dark && AppearanceChoice.light.forcedScheme == .light)
    }
}

@MainActor
@Suite struct UI002_AppearanceSettingTests {
    func model(_ store: LibraryStore) -> SettingsModel {
        SettingsModel(store: store, legacy: nil, defaultProfiles: { [ScreenProfile(name: "A", role: .audience, destination: .window)] })
    }
    @Test func darkByDefaultAndTheChoiceSurvivesARelaunch() async throws {
        let store = try LibraryStore.inMemory()
        let first = model(store)
        await first.load()
        #expect(first.appearance == .dark)
        first.setAppearance(.light)
        #expect(first.appearance == .light)
        await first.flush()
        let second = model(store)
        await second.load()
        #expect(second.appearance == .light)
    }
}

@Suite struct UI002_ContrastTests {
    static func luminance(_ hex: String) -> Double {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        func channel(_ shift: Int) -> Double {
            let x = Double((v >> shift) & 255) / 255.0
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
    static func ratio(_ a: String, _ b: String) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    func color(_ name: String, _ mode: Int, _ all: [String: (dark: String, light: String)]) throws -> String {
        let t = try #require(all[name])
        return DesignTokenParityTests.resolve(mode == 0 ? t.dark : t.light, mode: mode, all)
    }

    @Test func theRatioFunctionIsRight() {
        #expect(abs(Self.ratio("#000000", "#ffffff") - 21) < 0.01)
        #expect(abs(Self.ratio("#777777", "#777777") - 1) < 0.001)
    }

    /// Text colours on the surfaces they sit on, at least 4.5:1, in both appearances. The two exceptions are the pairs the
    /// design README names itself: light `cyan` (and the two tokens with its value) on `surface-2` is 4.4:1.
    @Test func textTokensReachFourPointFiveOnTheirSurfaces() throws {
        let all = try DesignTokenParityTests.tokens()
        let texts = ["text", "muted", "cyan", "blue", "warning", "status-ok", "section-verse", "section-chorus", "section-bridge",
                     "role-audience", "role-stage", "role-broadcast"]
        let surfaces = ["bg", "surface", "surface-2"]
        let readmeExceptions: Set<String> = ["light|cyan|surface-2", "light|status-ok|surface-2", "light|section-chorus|surface-2"]
        var failures: [String] = []
        for mode in 0...1 {
            let name = mode == 0 ? "dark" : "light"
            for t in texts { for s in surfaces {
                if readmeExceptions.contains("\(name)|\(t)|\(s)") { continue }
                let r = Self.ratio(try color(t, mode, all), try color(s, mode, all))
                if r < 4.5 { failures.append("\(name) \(t) on \(s): \(String(format: "%.2f", r))") }
            } }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func theReadmesNamedPairsHold() throws {
        let all = try DesignTokenParityTests.tokens()
        func r(_ fg: String, _ bg: String, _ mode: Int) throws -> Double { Self.ratio(try color(fg, mode, all), try color(bg, mode, all)) }
        for s in ["bg", "surface", "surface-2", "surface-3"] {
            #expect(try r("text", s, 0) >= 10, "dark text on \(s)")
            #expect(try r("text", s, 1) >= 12, "light text on \(s)")
        }
        for s in ["bg", "surface", "surface-2"] {
            #expect(try r("muted", s, 0) >= 5.5, "dark muted on \(s)")
            #expect(try r("muted", s, 1) >= 4.5, "light muted on \(s)")
            #expect(try r("border-strong", s, 0) >= 3.1, "dark border-strong on \(s)")
            #expect(try r("border-strong", s, 1) >= 3.4, "light border-strong on \(s)")
        }
        #expect(try r("on-live", "live-fill", 0) >= 5.0)
        #expect(try r("on-live", "live-fill", 1) >= 5.0)
    }
}
