// FIX-J item 9 (UI-005h): the golden digests in `UI005h_Golden` were recorded on one Mac and one macOS. An antialiased edge can be drawn
// differently on another GPU or another macOS, so the digest tests that compare against them run only on a machine with the recording
// machine's identity, and say so when they do not. The identity is the macOS version and the GPU's name, hashed (nothing personal: no host
// name, no user name).
import Foundation
import Metal

enum MachineIdentity {
    /// What identifies the rendering stack: the macOS version string and the default GPU's name.
    static var description: String {
        "\(ProcessInfo.processInfo.operatingSystemVersionString)|\(MTLCreateSystemDefaultDevice()?.name ?? "no GPU")"
    }

    /// FNV-1a over `description`, in hex.
    static func hash(_ text: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    static var current: String { hash(description) }

    /// The identity of the machine the digests were recorded on (UI-005h, re-recorded by FIX-J on the same code).
    static let recording = "d662dd81dec66f04"

    static var matchesRecording: Bool { current == recording }

    static var skipReason: String {
        "Golden digests were recorded on a machine with identity \(recording) (macOS and GPU, hashed); this one is \(current). The structural checks still run."
    }
}
