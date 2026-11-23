// UI-006c (Edit): the model logic of the Edit mode's new controls, all pure and testable. Foundation and Domain only; the views are in
// the app target (`EditMode.swift`, `EditCanvasChrome.swift`). Nothing here changes a stored field or a shared type.
import Foundation
import Domain

// MARK: Align (design E13 / E14)

/// Where an object goes when it is aligned to the slide.
public enum ObjectAlignment: String, Sendable, CaseIterable, Equatable {
    case left, centerHorizontally, right, top, centerVertically, bottom, center

    public var title: String {
        switch self {
        case .left: "Align left"
        case .centerHorizontally: "Align horizontal centres"
        case .right: "Align right"
        case .top: "Align top"
        case .centerVertically: "Align vertical middles"
        case .bottom: "Align bottom"
        case .center: "Centre on slide"
        }
    }

    /// The frame after the alignment: the object keeps its size and moves only along the axis named (`center` moves along both).
    /// A frame that is larger than the slide is aligned by its own origin so it never leaves the slide on the near side.
    public func aligned(_ frame: NormalizedRect) -> NormalizedRect {
        var f = frame
        func middle(_ size: Double) -> Double { size >= 1 ? 0 : (1 - size) / 2 }
        func far(_ size: Double) -> Double { size >= 1 ? 0 : 1 - size }
        switch self {
        case .left: f.x = 0
        case .centerHorizontally: f.x = middle(f.width)
        case .right: f.x = far(f.width)
        case .top: f.y = 0
        case .centerVertically: f.y = middle(f.height)
        case .bottom: f.y = far(f.height)
        case .center: f.x = middle(f.width); f.y = middle(f.height)
        }
        return f
    }
}

extension SlideEditorModel {
    /// Aligns one object to the slide. One undo step, nothing changes on the live output, and nothing is written when the object is already there.
    /// Returns whether the object moved.
    @discardableResult
    public func align(_ id: UUID, _ alignment: ObjectAlignment) -> Bool {
        guard let object = objects.first(where: { $0.id == id }) else { return false }
        guard !refusesBecauseLocked(id) else { return false }          // UI-007c
        let target = alignment.aligned(object.frame)
        guard target != object.frame else { return false }
        edit(id) { $0.frame = target }
        return true
    }

    /// Aligns the selected object. False when nothing is selected or it is already aligned.
    @discardableResult
    public func alignSelected(_ alignment: ObjectAlignment) -> Bool {
        guard let id = selectedObjectID else { return false }
        return align(id, alignment)
    }
}

// MARK: "Saved ... ago" (design E19)

/// What the Edit strip says about saving, from what the model can be asked: whether typed or edited text is still waiting to be written,
/// and whether a write failed. A save is "observed" when the view sees the waiting text go away; the time is the moment of that look
/// (the view looks about once a second), never an assumed one. Before any save this session the strip says only that nothing is waiting.
public struct EditSaveStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case allSaved
        case saved(at: TimeInterval)
        case waiting
        case failed(String)
    }

    public private(set) var state: State = .allSaved
    private var wasWaiting = false

    public init() {}

    /// Feed one look. `now` is any monotonic seconds value.
    public mutating func observe(hasUnsaved: Bool, problem: String?, now: TimeInterval) {
        if let problem, !problem.isEmpty { state = .failed(problem); wasWaiting = true; return }
        if hasUnsaved { state = .waiting; wasWaiting = true; return }
        if wasWaiting { state = .saved(at: now); wasWaiting = false }
    }

    /// The words for the strip.
    public func text(now: TimeInterval) -> String {
        switch state {
        case .allSaved: return "All changes saved"
        case .waiting: return "Saving…"
        case .failed: return "Not saved"
        case .saved(let at):
            let seconds = max(0, Int((now - at).rounded(.down)))
            if seconds < 2 { return "Saved just now" }
            if seconds < 60 { return "Saved \(seconds) s ago" }
            if seconds < 3600 { return "Saved \(seconds / 60) min ago" }
            return "Saved \(seconds / 3600) h ago"
        }
    }

    public var isProblem: Bool { if case .failed = state { true } else { false } }
}

// MARK: Audience / Stage / Broadcast preview (design E16)

/// Which screen's composition the Edit canvas draws. Only the Audience view is the one the operator edits on; the others are read-only looks.
public enum EditPreviewRole: String, Sendable, CaseIterable, Equatable {
    case audience, stage, broadcast

    public var title: String {
        switch self { case .audience: "Audience"; case .stage: "Stage"; case .broadcast: "Broadcast" }
    }
    public var screenRole: ScreenRole {
        switch self { case .audience: .audience; case .stage: .stage; case .broadcast: .broadcast }
    }
    /// Objects can be selected and moved only on the Audience view: the other compositions do not place them where the boxes would be.
    public var isEditable: Bool { self == .audience }
}

public enum EditPreviewScene {
    /// How `slide` is composed for one role, by the same composer the outputs use. The first enabled screen of that role supplies its Look
    /// and theme (a role with no screen is drawn with the built-in defaults). No speaker notes are passed, so none can appear in any role.
    /// The slide is drawn as a triggered preview; nothing here touches the live show.
    public static func scene(role: EditPreviewRole, slide: SlideContent, profiles: [ScreenProfile], themes: [Theme], look: Look?,
                             props: [Prop], presentationThemeID: UUID?, media: MediaLayers?,
                             deck: [SlideContent]? = nil, index: Int? = nil, stageScene: SceneDescription? = nil,
                             screenLooks: [UUID: Look] = [:], sectionNames: [String?] = []) -> SceneDescription {
        let state = previewState(slide: slide, deck: deck, index: index, sectionNames: sectionNames)
        let profile = profile(for: role, in: profiles)
        // The Look is resolved against the real profile list, so a profile that is not in it still gets the standard look.
        let all = profiles.contains { $0.id == profile.id } ? profiles : profiles + [profile]
        // FIX-V item 5 (REVIEW-4 M1): a stage screen is drawn from its own layout, as the real screen is, when the caller supplies that scene.
        let stageScenes: [UUID: SceneDescription] = role == .stage ? (stageScene.map { [profile.id: $0] } ?? [:]) : [:]
        return PublishedScenes(state: state, clockText: nil, profiles: all, themes: themes, look: look, props: props,
                               presentationThemeID: presentationThemeID, stageScenes: stageScenes, media: media, screenLooks: screenLooks)
            .scene(forScreen: profile.id)
    }

    /// FIX-V item 5: the stage preview, composed from the stage screen's own layout (`StageModel`, the same call the real screen's scene comes
    /// from) with the open deck, this slide's position in it and its speaker notes. Other roles are composed as before, with no notes.
    @MainActor
    public static func scene(role: EditPreviewRole, slide: SlideContent, profiles: [ScreenProfile], themes: [Theme], look: Look?,
                             props: [Prop], presentationThemeID: UUID?, media: MediaLayers?,
                             deck: [SlideContent]?, index: Int?, stage: StageModel?, notes: String?,
                             screenLooks: [UUID: Look] = [:], sectionNames: [String?] = []) -> SceneDescription {
        var stageScene: SceneDescription?
        if role == .stage, let stage {
            let state = previewState(slide: slide, deck: deck, index: index, sectionNames: sectionNames)
            stageScene = stage.stageScene(forScreen: profile(for: role, in: profiles).id, state: state, notes: notes)
        }
        return scene(role: role, slide: slide, profiles: profiles, themes: themes, look: look, props: props, presentationThemeID: presentationThemeID,
                     media: media, deck: deck, index: index, stageScene: stageScene, screenLooks: screenLooks, sectionNames: sectionNames)
    }

    /// FIX-V item 5: the state the preview is composed from. With the open deck and the slide's position in it, the stage preview has the same
    /// current and next slide the stage screen would have if this slide were live; without them it is a one-slide deck. Never the live state.
    /// FIX-W (L12): `sectionNames` are the deck's section names in the deck's order (the live deck's own), so a stage Section element draws.
    public static func previewState(slide: SlideContent, deck: [SlideContent]?, index: Int?, sectionNames: [String?] = []) -> ShowState {
        var slides = [slide]
        var at = 0
        var names: [String?] = []                 // the names belong to the open deck, not to a one-slide stand-in
        if let deck, let index, deck.indices.contains(index) {
            slides = deck
            slides[index] = slide
            at = index
            names = sectionNames
        }
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: slides, sectionNames: names)))
        state.apply(.trigger(index: at))
        return state
    }

    /// The first enabled screen of the role, else the first of it, else a stand-in with built-in defaults.
    public static func profile(for role: EditPreviewRole, in profiles: [ScreenProfile]) -> ScreenProfile {
        let wanted = role.screenRole
        return profiles.first { $0.role == wanted && $0.isEnabled }
            ?? profiles.first { $0.role == wanted }
            ?? ScreenProfile(name: role.title, role: wanted, destination: .window)
    }
}

// MARK: Zoom (design E17)

/// The canvas zoom. A percentage is a fraction of the 1920-point-wide output; "Fit" is whatever fills the area up to the design's 800 points.
public enum EditZoom: Hashable, Sendable, CaseIterable {
    case fit, p25, p50, p75, p100

    public var title: String {
        switch self { case .fit: "Fit"; case .p25: "25%"; case .p50: "50%"; case .p75: "75%"; case .p100: "100%" }
    }
    public var fixedScale: Double? {
        switch self { case .fit: nil; case .p25: 0.25; case .p50: 0.5; case .p75: 0.75; case .p100: 1 }
    }
    public static let outputWidth = 1920.0

    /// The canvas width in points: the fixed scale of the output, or (for Fit) the largest 16:9 that fits the area, never wider than the
    /// design's 800 and never narrower than 220.
    public func canvasWidth(areaWidth: Double, areaHeight: Double) -> Double {
        if let scale = fixedScale { return Self.outputWidth * scale }
        return max(220, min(800, areaWidth - 80, (areaHeight - 120) * 16 / 9))
    }

    /// The percentage of the 1920-point output that a canvas of `width` points shows, as the field reads it.
    public static func percent(forCanvasWidth width: Double) -> Int { Int((width / outputWidth * 100).rounded()) }
}
