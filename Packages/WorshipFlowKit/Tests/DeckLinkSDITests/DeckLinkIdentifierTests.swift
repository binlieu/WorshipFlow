// HW-003: persistent-ID text, and the other plain-data types. Verification level: Unit Tested.
import Foundation
import Testing
@testable import DeckLinkSDI

@Suite struct HW003_IdentifierTests {
    @Test func aGroupIDRoundTrips() {
        let id = DeckLinkIdentifier.group(0x1234_5678_9ABC_DEF0)
        #expect(id.description == "decklink:group:123456789abcdef0")
        #expect(DeckLinkIdentifier(id.description) == id)
    }

    @Test func aDeviceIDRoundTripsIncludingNegativeValues() {
        for value: Int64 in [0, 1, 255, Int64.max, -1, Int64.min, 0x7000_0000_0000_0001] {
            let id = DeckLinkIdentifier.device(value)
            #expect(DeckLinkIdentifier(id.description) == id, "\(value)")
        }
        #expect(DeckLinkIdentifier.device(-1).description == "decklink:device:ffffffffffffffff")
    }

    @Test func hexIsPaddedToSixteenDigits() {
        #expect(DeckLinkIdentifier.device(1).description == "decklink:device:0000000000000001")
    }

    @Test func parsingAcceptsUppercaseShortFormsAndAZeroXPrefix() {
        #expect(DeckLinkIdentifier("decklink:device:ABCDEF") == .device(0xABCDEF))
        #expect(DeckLinkIdentifier("decklink:device:0xff") == .device(255))
        #expect(DeckLinkIdentifier("decklink:group:0X10") == .group(16))
        #expect(DeckLinkIdentifier("decklink:device:1") == .device(1))
    }

    @Test func parsingRejectsWhatIsNotAnIdentifier() {
        #expect(DeckLinkIdentifier("") == nil)
        #expect(DeckLinkIdentifier("decklink:device:") == nil)
        #expect(DeckLinkIdentifier("decklink:device:0x") == nil)
        #expect(DeckLinkIdentifier("decklink:device:xyz") == nil)
        #expect(DeckLinkIdentifier("decklink:device:12345678901234567") == nil, "17 digits do not fit 64 bits")
        #expect(DeckLinkIdentifier("decklink:device:-1") == nil)
        #expect(DeckLinkIdentifier("decklink:device: 1") == nil)
        #expect(DeckLinkIdentifier("device:1") == nil)
        #expect(DeckLinkIdentifier("decklink:card:1") == nil)
        #expect(DeckLinkIdentifier("decklink:name:") == nil)
        #expect(DeckLinkIdentifier("decklink:device:１２") == nil, "full-width digits are not hex")
    }

    @Test func aNamedIdentifierKeepsItsText() {
        let id = DeckLinkIdentifier.named("DeckLink Mini Monitor")
        #expect(DeckLinkIdentifier(id.description) == id)
    }

    @Test func groupAndDeviceWithTheSameNumberAreDifferent() {
        #expect(DeckLinkIdentifier.group(5) != DeckLinkIdentifier.device(5))
        #expect(DeckLinkIdentifier("decklink:group:5") != DeckLinkIdentifier("decklink:device:5"))
    }
}

@Suite struct HW003_SnapshotTests {
    @Test func foundationValuesConvertWithTheirKinds() {
        let raw: [String: Any] = [
            "flag": true, "count": 7, "ratio": 0.5, "text": "hello", "none": NSNull(),
            "list": [1, "two", false], "nested": ["a": 1],
        ]
        let value = DeckLinkSnapshotValue(foundation: raw)
        #expect(value["flag"] == .bool(true))
        #expect(value["count"] == .int(7))
        #expect(value["ratio"] == .double(0.5))
        #expect(value["text"] == .string("hello"))
        #expect(value["none"] == .null)
        #expect(value["list"] == .array([.int(1), .string("two"), .bool(false)]))
        #expect(value["nested"]?["a"] == .int(1))
    }

    @Test func renderingIsKeySortedAndStable() {
        let value = DeckLinkSnapshotValue.object(["b": .int(2), "a": .array([.bool(true), .null]), "c": .object([:])])
        #expect(value.rendered() == value.rendered())
        let text = value.rendered()
        #expect(text.range(of: "\"a\"")!.lowerBound < text.range(of: "\"b\"")!.lowerBound)
        #expect(text.contains("\"c\": {}"))
    }
}
