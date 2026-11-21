// UI-001 Part 2: the design (docs/UI/design-tokens.json) and the app's asset catalog cannot drift silently: every
// colour token has a colour set of the same name with the same dark and light values, and every colour set has a token.
import Testing
import Foundation

@Suite struct DesignTokenParityTests {
    struct Rgba: Equatable { var r: Int, g: Int, b: Int, a: Int }

    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("docs/UI/design-tokens.json").path) { return url }
        }
        return url
    }()

    static func tokens() throws -> [String: (dark: String, light: String)] {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/UI/design-tokens.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let color = try #require(json["color"] as? [String: Any])
        let list = try #require(color["tokens"] as? [[String: Any]])
        var result: [String: (String, String)] = [:]
        for t in list {
            let value = try #require(t["value"] as? [String: String])
            result[try #require(t["name"] as? String)] = (try #require(value["dark"]), try #require(value["light"]))
        }
        return result
    }

    static func resolve(_ value: String, mode: Int, _ all: [String: (dark: String, light: String)]) -> String {
        if value.hasPrefix("{"), value.hasSuffix("}"), let t = all[String(value.dropFirst().dropLast())] {
            return resolve(mode == 0 ? t.dark : t.light, mode: mode, all)
        }
        return value
    }

    static func parse(_ text: String) -> Rgba? {
        if text.hasPrefix("#"), text.count == 7, let v = Int(text.dropFirst(), radix: 16) {
            return Rgba(r: v >> 16 & 255, g: v >> 8 & 255, b: v & 255, a: 1000)
        }
        let digits = text.replacingOccurrences(of: "rgba(", with: "").replacingOccurrences(of: ")", with: "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard digits.count == 4, let r = Int(digits[0]), let g = Int(digits[1]), let b = Int(digits[2]), let a = Double(digits[3]) else { return nil }
        return Rgba(r: r, g: g, b: b, a: Int((a * 1000).rounded()))
    }

    static func catalogNames() throws -> [String] {
        let dir = root.appendingPathComponent("App/Resources/Assets.xcassets")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".colorset") }.map { String($0.dropLast(".colorset".count)) }.sorted()
    }

    static func catalogValue(_ name: String, dark: Bool) throws -> Rgba? {
        let url = root.appendingPathComponent("App/Resources/Assets.xcassets/\(name).colorset/Contents.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let colors = try #require(json["colors"] as? [[String: Any]])
        for entry in colors {
            let isDark = (entry["appearances"] as? [[String: String]])?.contains { $0["value"] == "dark" } ?? false
            guard isDark == dark, let color = entry["color"] as? [String: Any], let c = color["components"] as? [String: String] else { continue }
            func channel(_ key: String) -> Int? {
                guard let s = c[key] else { return nil }
                return s.hasPrefix("0x") ? Int(s.dropFirst(2), radix: 16) : nil
            }
            guard let r = channel("red"), let g = channel("green"), let b = channel("blue"), let a = c["alpha"].flatMap(Double.init) else { return nil }
            return Rgba(r: r, g: g, b: b, a: Int((a * 1000).rounded()))
        }
        return nil
    }

    @Test func everyColourTokenHasAColourSetAndEveryColourSetHasAToken() throws {
        let tokens = Set(try Self.tokens().keys)
        let sets = Set(try Self.catalogNames())
        #expect(tokens.subtracting(sets).sorted().isEmpty, "tokens without a colour set")
        #expect(sets.subtracting(tokens).sorted().isEmpty, "colour sets without a token")
        #expect(tokens.count >= 25)
    }

    @Test func colourSetValuesMatchTheTokensInBothAppearances() throws {
        let all = try Self.tokens()
        for (name, value) in all {
            let dark = try #require(Self.parse(Self.resolve(value.dark, mode: 0, all)), "\(name) dark")
            let light = try #require(Self.parse(Self.resolve(value.light, mode: 1, all)), "\(name) light")
            #expect(try Self.catalogValue(name, dark: true) == dark, "\(name) dark")
            #expect(try Self.catalogValue(name, dark: false) == light, "\(name) light")
        }
    }

    @Test func theAppIconSetHasEveryMacSize() throws {
        let dir = Self.root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("Contents.json"))) as? [String: Any])
        let images = try #require(json["images"] as? [[String: String]])
        #expect(images.count == 10)
        for image in images {
            let file = try #require(image["filename"])
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(file).path), "\(file)")
        }
    }
}
