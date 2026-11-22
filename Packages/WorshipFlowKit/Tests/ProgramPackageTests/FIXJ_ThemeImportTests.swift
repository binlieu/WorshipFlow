// FIX-J items 3 and 4 (UI-005h): a theme in a program package that carries hostile values is clamped when the package is read and when it is
// imported; every number the compositor divides by or sizes a bitmap from comes out sane.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXJ_ThemeImportTests {
    private let white: [String: Any] = ["red": 1, "green": 1, "blue": 1, "alpha": 1]

    @Test func aHostileThemeInAPackageIsClampedWhenReadAndWhenImported() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editManifest(package) { root in
            var themes = root["themes"] as? [[String: Any]] ?? []
            var primary = themes[0]["primary"] as? [String: Any] ?? [:]
            var style = primary["style"] as? [String: Any] ?? [:]
            style["weight"] = 99999
            style["lineHeight"] = 1e9
            style["opticalSize"] = -4
            primary["style"] = style
            themes[0]["primary"] = primary
            themes[0]["background"] = ["gradient": ["_0": ["stops": [["position": 9, "color": white]], "centerX": 0.5, "centerY": 0.5, "radiusX": 0, "radiusY": -2]]]
            themes[0]["plate"] = ["x": -5, "width": 40, "bottomMargin": -9, "fill": ["red": 0, "green": 0, "blue": 0, "alpha": 12],
                                  "cornerRadius": -1, "paddingX": 1e12, "paddingY": -3,
                                  "bar": ["width": -4, "gap": 1e12, "top": white, "bottom": white]]
            root["themes"] = themes
        }
        func check(_ t: Theme, _ where_: String) {
            #expect(t.primary.style.weight == 900, "\(where_)")
            #expect((t.primary.style.lineHeight ?? 0) <= 4 && t.primary.style.opticalSize == nil, "\(where_)")
            if case .gradient(let g) = t.background {
                #expect(g.stops.count >= 2 && g.stops.map(\.position) == g.stops.map(\.position).sorted() && g.radiusX > 0 && g.radiusY > 0, "\(where_)")
            } else { Issue.record("\(where_): background \(t.background)") }
            let p = t.plate
            #expect(p?.x == 0 && p?.width == 1 && p?.bottomMargin == 0 && p?.fill.alpha == 1 && p?.cornerRadius == 0 && p?.paddingY == 0, "\(where_)")
            #expect((p?.paddingX ?? 9999) <= 1000 && p?.bar?.width == 0 && (p?.bar?.gap ?? 9999) <= 1000, "\(where_)")
        }
        let contents = try ProgramPackageContents.open(package)
        check(try #require(contents.document.themes.first { $0.id == home.themeID }), "read")
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        check(try #require(try await church.themes().first { $0.id == home.themeID }), "imported")
    }
}
