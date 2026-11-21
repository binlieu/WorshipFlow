// HW-003 / SCRN-11: SDIVideoMode <-> DeckLink display mode, matched on exact timing, never on a rounded frame rate.
// Status: Unit Tested. The SDK confirms each pairing at enable time (the bridge compares the SDK's own size and frame
// duration with the expected ones), so a wrong row here fails loudly instead of playing at the wrong rate.
import SDIEngine

public enum DeckLinkModeMapping {
    /// A BMDDisplayMode four-character code from its four ASCII characters.
    static func fourCC(_ text: StaticString) -> UInt32 {
        var value: UInt32 = 0
        text.withUTF8Buffer { bytes in
            for byte in bytes.prefix(4) { value = (value << 8) | UInt32(byte) }
        }
        return value
    }

    /// One row per `SDIVideoMode.allKnown` mode. 59.94 and 60 are different rows (HW-09), and 1080p29.97 and
    /// 1080i59.94 share a frame duration but are different rows because one is interlaced.
    static let table: [(mode: SDIVideoMode, displayMode: UInt32)] = [
        (.hd1080p5994, fourCC("Hp59")),   // bmdModeHD1080p5994
        (.hd1080p60, fourCC("Hp60")),     // bmdModeHD1080p6000, really 60.00 Hz
        (.hd1080p50, fourCC("Hp50")),     // bmdModeHD1080p50
        (.hd1080p2997, fourCC("Hp29")),   // bmdModeHD1080p2997
        (.hd1080p30, fourCC("Hp30")),     // bmdModeHD1080p30
        (.hd1080p25, fourCC("Hp25")),     // bmdModeHD1080p25
        (.hd1080i5994, fourCC("Hi59")),   // bmdModeHD1080i5994
        (.hd720p5994, fourCC("hp59")),    // bmdModeHD720p5994
        (.hd720p60, fourCC("hp60")),      // bmdModeHD720p60
        (.hd720p50, fourCC("hp50")),      // bmdModeHD720p50
    ]

    private static func sameTiming(_ a: SDIVideoMode, _ b: SDIVideoMode) -> Bool {
        a.width == b.width && a.height == b.height && a.isInterlaced == b.isInterlaced
            && a.frameDurationValue == b.frameDurationValue && a.timeScale == b.timeScale
    }

    /// The BMDDisplayMode code for a mode, or nil if the mode has no DeckLink equivalent.
    public static func displayMode(for mode: SDIVideoMode) -> UInt32? {
        table.first { sameTiming($0.mode, mode) }?.displayMode
    }

    /// The SDIVideoMode for a BMDDisplayMode code, or nil for modes the app does not offer (including everything above HD).
    public static func videoMode(forDisplayMode code: UInt32) -> SDIVideoMode? {
        table.first { $0.displayMode == code }?.mode
    }

    /// A BMDDisplayMode code as four characters, for logs ("Hp59"), or hexadecimal if it is not printable.
    public static func text(forFourCC code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return "0x" + String(code, radix: 16, uppercase: true) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
