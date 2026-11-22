// FIX-O (KI-180): the two media layers, observable one at a time. `MediaModel.layers` was one observed value, so a change to the clip over
// the slide made every reader of the background draw again, and the other way round. The value and what changes it are unchanged.
import Foundation
import Observation
import Domain

@MainActor
public final class ObservedLayers: Observable {
    private let registrar = ObservationRegistrar()
    private var value = MediaLayers()

    public init() {}

    /// Both layers. Depends on both (the old behaviour); prefer a layer.
    public var layers: MediaLayers { registrar.access(self, keyPath: \.background); registrar.access(self, keyPath: \.foreground); return value }
    /// Without registering a dependency: for the model's own bookkeeping, never for a view.
    public var current: MediaLayers { value }
    public var background: MediaLayer? { registrar.access(self, keyPath: \.background); return value.background }
    public var foreground: MediaLayer? { registrar.access(self, keyPath: \.foreground); return value.foreground }

    public func set(_ new: MediaLayers) {
        let backgroundChanged = new.background != value.background, foregroundChanged = new.foreground != value.foreground
        if backgroundChanged { registrar.willSet(self, keyPath: \.background) }
        if foregroundChanged { registrar.willSet(self, keyPath: \.foreground) }
        value = new
        if backgroundChanged { registrar.didSet(self, keyPath: \.background) }
        if foregroundChanged { registrar.didSet(self, keyPath: \.foreground) }
    }
}
