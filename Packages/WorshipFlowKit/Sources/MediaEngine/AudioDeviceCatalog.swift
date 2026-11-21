// MEDIA-006: the sound output devices the system offers, behind a protocol so the audio model and the cue player can
// be tested with a fake list. The real one asks Core Audio (APIs checked against the SDK headers, see the feature doc).
import Foundation
import CoreAudio
import os
import Domain

public protocol AudioDeviceCatalog: Sendable {
    /// Every device that has at least one output channel, in the order the system lists them.
    func outputDevices() -> [AudioOutputDevice]
    /// The Core Audio object for a device UID, or nil when no such device is connected.
    func deviceID(forUID uid: String) -> UInt32?
    /// Calls `handler`, on an arbitrary queue, when a device appears or disappears or the default output changes.
    /// Returns a function that stops the calls; it may be called more than once.
    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> @Sendable () -> Void
}

public struct CoreAudioDeviceCatalog: AudioDeviceCatalog {
    public init() {}

    public func outputDevices() -> [AudioOutputDevice] {
        let defaultID = Self.defaultOutputDevice()
        return Self.allDevices().compactMap { id in
            let channels = Self.outputChannels(of: id)
            guard channels > 0, let uid = Self.string(id, kAudioDevicePropertyDeviceUID), !uid.isEmpty else { return nil }
            let name = Self.string(id, kAudioObjectPropertyName).flatMap { $0.isEmpty ? nil : $0 } ?? uid
            return AudioOutputDevice(uid: uid, name: name, channelCount: channels, isDefault: id == defaultID)
        }
    }

    public func deviceID(forUID uid: String) -> UInt32? {
        Self.allDevices().first { id in
            Self.outputChannels(of: id) > 0 && Self.string(id, kAudioDevicePropertyDeviceUID) == uid
        }
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let listener = Listener(handler)
        listener.install()
        return { listener.remove() }
    }

    // MARK: Core Audio plumbing

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDevices() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr,
              id != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return id
    }

    private static func outputChannels(of id: AudioObjectID) -> Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = address(selector)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return status == noErr ? value as String : nil
    }

    /// Owns one Core Audio property listener block, so it can be removed with the very same block and queue.
    // @unchecked Sendable: `block` is created once in init and only read afterwards; `installed` is lock-guarded.
    private final class Listener: @unchecked Sendable {
        private let queue = DispatchQueue(label: "WorshipFlow.audio.devices")
        private let installed = OSAllocatedUnfairLock(initialState: false)
        private let block: AudioObjectPropertyListenerBlock
        private let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice]

        init(_ handler: @escaping @Sendable () -> Void) {
            block = { _, _ in handler() }
        }

        func install() {
            let first = installed.withLock { was -> Bool in let r = !was; was = true; return r }
            guard first else { return }
            for s in selectors {
                var a = CoreAudioDeviceCatalog.address(s)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, block)
            }
        }

        func remove() {
            let was = installed.withLock { was -> Bool in let r = was; was = false; return r }
            guard was else { return }
            for s in selectors {
                var a = CoreAudioDeviceCatalog.address(s)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, block)
            }
        }
    }
}
