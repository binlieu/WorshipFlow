// MEDIA-005 / MEDIA-006: the app's side of the audio slice. The operator model asks for devices and players through
// protocols; the engine's real ones already have the right shape, so the adoption is empty (the same pattern as
// `MediaRegistry: MediaFrameSource` in MediaSupport.swift).
import MediaEngine
import OperatorCore

extension CoreAudioDeviceCatalog: @retroactive AudioDeviceListing {}
extension AudioCuePlayer: @retroactive AudioCueEngine {}
