// UI-006e (STAGE): the stage features the design draws and the app lacked. Hiding an element (the eye), Auto-fit, the second-language colour
// and the Band / Speaker / Clock only presets. All of them go through `StageModel`'s own change path (refused for the built-in layout,
// kept inside what the compositor can draw, saved in order, `onChange` so the stage screens are republished). Foundation and Domain only.
import Foundation
import Domain

/// The design's three layout presets (04-stage.png, the list's cards "Band", "Speaker" and "Clock only").
public enum StagePreset: String, Sendable, CaseIterable, Identifiable {
    case band, speaker, clockOnly
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .band: "Band"
        case .speaker: "Speaker"
        case .clockOnly: "Clock only"
        }
    }

    /// The card's second word in the design.
    public var summary: String {
        switch self {
        case .band: "current + next"
        case .speaker: "notes + timer"
        case .clockOnly: "time of day"
        }
    }

    /// The elements of the preset, each with a new id. Styles and frames come from the built-in layout, so a preset reads like it.
    func elements() -> [StageElement] {
        let standard = StageLayout.standard.elements
        func copy(_ kind: StageElement.Kind) -> StageElement? {
            guard var e = standard.first(where: { $0.kind == kind }) else { return nil }
            e.id = UUID()
            return e
        }
        switch self {
        case .band:
            return [copy(.currentSlide), copy(.nextSlide)].compactMap { $0 }
        case .speaker:
            // Notes large in the upper part of the screen, the first countdown big underneath in the warm colour.
            guard let current = copy(.currentSlide), var timer = copy(.firstCountdown) else { return [] }
            var notes = StageElement(id: UUID(), kind: .notes, frame: NormalizedRect(x: 0.04, y: 0.07, width: 0.92, height: 0.5),
                                     style: current.style, alignment: .leading)
            notes.style.fontSize = 84
            notes.style.weight = 500
            timer.frame = NormalizedRect(x: 0.04, y: 0.62, width: 0.5, height: 0.3)
            timer.style.fontSize = 170
            timer.style.color = ColorRGBA(red: 1, green: 0.82, blue: 0.48)      // the design's warm yellow (#FFD17B)
            timer.alignment = .leading
            return [notes, timer]
        case .clockOnly:
            guard var clock = copy(.timeOfDay) else { return [] }
            clock.frame = NormalizedRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
            clock.style.fontSize = 400
            clock.alignment = .center
            clock.verticalAlignment = .center
            return [clock]
        }
    }
}

extension StageModel {
    // MARK: Hide, Auto-fit, second-language colour

    /// Hides an element on the stage screens without removing it (the eye in the element list). The element, its frame and its style stay.
    /// FIX-Y: hiding the Current slide is refused, with the reason in `lastError`, when it would leave nothing from the show on the stage screen.
    public func setHidden(_ hidden: Bool, for elementID: UUID, in layoutID: UUID) {
        if hidden, let layout = customLayouts.first(where: { $0.id == layoutID }), let why = StageEditing.hideRefusal(hiding: elementID, in: layout) {
            lastError = why
            return
        }
        updateElement(elementID, in: layoutID) { $0.isHidden = hidden }
    }

    /// Switches Auto-fit on or off: the text is shrunk until it fits the element's frame, never below `StageAutoFit.floor(for:)`.
    public func setAutoFit(_ on: Bool, for elementID: UUID, in layoutID: UUID) {
        updateElement(elementID, in: layoutID) { $0.autoFit = on }
    }

    /// The colour of the second-language line of a current-slide element that has its own line. An element without one has nothing to colour:
    /// its second language is drawn in the first language's colour, and nothing changes.
    public func setSecondLanguageColor(_ color: ColorRGBA, for elementID: UUID, in layoutID: UUID) {
        updateElement(elementID, in: layoutID) { e in e.secondLanguage?.style.color = color }
    }

    // MARK: Presets

    /// A new layout of the operator's own, made from a preset. Nil (with `lastError`) if the name is blank.
    @discardableResult
    public func addPreset(_ preset: StagePreset, named name: String) -> StageLayout? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Could not create the layout: a name is needed. Type at least one letter and try again."
            return nil
        }
        let standard = StageLayout.standard
        let layout = StageLayout(id: UUID(), name: trimmed, background: standard.background, warningColor: standard.warningColor,
                                 elements: preset.elements().map { StageEditing.sanitized($0) }, messageBand: standard.messageBand)
        customLayouts.append(layout)
        enqueueWrite(.layout(layout.id))
        onChange?()
        return layout
    }
}
