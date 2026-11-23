// STAGE-001b (LIVE-01, LIVE-02, LIVE-04, SCRN-03): stage layouts, timers and the stage clock. Layouts and timers
// live in the library (schema v4); the layout chosen for each stage screen and the clock style are app-state keys.
// Changes take effect in memory at once and are written in order on one queue; a failed write sets `lastError` with
// a message a volunteer can act on. Nothing here throws at the interface. Foundation and Observation only.
import Foundation
import Observation
import Domain
import Persistence

/// One line of the timers panel.
public struct TimerRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kindLabel: String
    public var text: String
    public var isRunning: Bool
    /// A countdown that has passed zero; shown in the warning colour.
    public var isOverrun: Bool
    /// A countdown to a time of day: it follows the clock and has no start, pause or reset.
    public var followsClock: Bool
}

@MainActor
@Observable
public final class StageModel {
    // MARK: State the interface reads

    /// The operator's own layouts, in creation order. The built-in one is not in this list.
    public internal(set) var customLayouts: [StageLayout] = []
    public internal(set) var timers: [ShowTimer] = []
    public internal(set) var clockStyle = ClockStyle()
    public internal(set) var lastError: String?
    public internal(set) var isLoaded = false
    /// Which layout each stage screen shows. A screen that is not here shows the built-in layout.
    public internal(set) var layoutChoices: [UUID: UUID] = [:]
    /// UI-003 (LIVE-03): the message on the stage screens now, nil when none. Never stored: a relaunch starts without one.
    public internal(set) var stageMessage: String?
    /// The last few messages sent, newest first, for reuse.
    public internal(set) var recentMessages: [String] = []
    /// UI-003: the timers the operator marked for the toolbar; nil means the defaults (first elapsed, first countdown).
    @ObservationIgnored var toolbarMarks: [UUID]?
    /// Read by the toolbar: bumped when the choice changes.
    public internal(set) var toolbarRevision = 0
    @ObservationIgnored var showWasStopped = true

    /// The built-in layout first, then the operator's own.
    public var layouts: [StageLayout] { [StageLayout.standard] + customLayouts }

    /// Called on the main actor after any change that can alter a stage picture, so the app can publish again.
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    // MARK: Internals

    @ObservationIgnored let store: LibraryStore
    @ObservationIgnored private let nowProvider: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var queue: [Write] = []
    @ObservationIgnored private var drain: Task<Void, Never>?

    static let choicesKey = "stage.layoutChoices"
    static let clockKey = "stage.clockStyle"
    static let messagesKey = "stage.recentMessages"
    static let toolbarKey = "stage.toolbarTimers"
    public static let recentMessageLimit = 5
    public static let readOnlyMessage = "The built-in layout cannot be changed. Choose Duplicate to make your own copy, then edit that."

    enum Write: Equatable {
        case layout(UUID), timer(UUID), deleteLayout(UUID), deleteTimer(UUID), choices, clock, messages, toolbar
    }

    /// - Parameters:
    ///   - now: the current time; injected so timers and the clock can be tested.
    ///   - calendar: decides the hour shown on the clock and what "today" means for a countdown to a time.
    public init(store: LibraryStore, now: @escaping @MainActor () -> Date = { Date() }, calendar: Calendar = .current) {
        self.store = store
        self.nowProvider = now
        self.calendar = calendar
    }

    // MARK: Loading

    /// Reads layouts, timers, the screens' choices and the clock style. A failure is reported and the rest still loads.
    public func load() async {
        // FIX-J item 4: a layout that cannot be decoded is skipped (and named once); the others load.
        let loaded = await attempt("read the stage layouts") { try await self.store.stageLayoutsAndSkipped() }
        customLayouts = loaded?.layouts ?? []
        if let notice = loaded?.skipped.operatorNotice { lastError = notice }
        timers = await attempt("read the timers") { try await self.store.timers() } ?? []
        // A damaged or missing value is ignored: the built-in layout and a 12-hour clock are always safe.
        if let text = try? await store.state(for: Self.choicesKey), let data = text.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            var choices: [UUID: UUID] = [:]
            for (screen, layout) in stored {
                if let s = UUID(uuidString: screen), let l = UUID(uuidString: layout), layoutExists(l) { choices[s] = l }
            }
            layoutChoices = choices
        }
        if let text = try? await store.state(for: Self.clockKey), let data = text.data(using: .utf8),
           let style = try? JSONDecoder().decode(ClockStyle.self, from: data) {
            clockStyle = style
        }
        if let text = try? await store.state(for: Self.messagesKey), let data = text.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String].self, from: data) {
            recentMessages = Array(stored.prefix(Self.recentMessageLimit))
        }
        if let text = try? await store.state(for: Self.toolbarKey), let data = text.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String].self, from: data) {
            toolbarMarks = stored.compactMap(UUID.init(uuidString:))
        }
        isLoaded = true
    }

    /// Waits until every change made so far has been written (or has failed and been reported).
    public func flush() async {
        while let task = drain { await task.value }
    }

    public func dismissError() { lastError = nil }

    // MARK: Time

    public var now: Date { nowProvider() }

    /// Seconds since the reference date: what the timers are measured in.
    public var nowSeconds: TimeInterval { now.timeIntervalSinceReferenceDate }

    public func timeOfDayText(at date: Date) -> String {
        TimeFormat.timeOfDay(date, calendar: calendar, twentyFourHour: clockStyle.twentyFourHour,
                             showSeconds: clockStyle.showsSeconds)
    }

    // MARK: Clock style (LIVE-04)

    public func setClockStyle(twentyFourHour: Bool? = nil, showsSeconds: Bool? = nil) {
        var style = clockStyle
        if let twentyFourHour { style.twentyFourHour = twentyFourHour }
        if let showsSeconds { style.showsSeconds = showsSeconds }
        guard style != clockStyle else { return }
        clockStyle = style
        enqueue(.clock)
        onChange?()
    }

    // MARK: Layouts (LIVE-01)

    public func layoutExists(_ id: UUID) -> Bool { id == StageLayout.standardID || customLayouts.contains { $0.id == id } }

    public func layout(withID id: UUID) -> StageLayout? { layouts.first { $0.id == id } }

    /// Only the operator's own layouts can be changed.
    public func isEditable(_ id: UUID) -> Bool { customLayouts.contains { $0.id == id } }

    /// A new layout that starts as a copy of the built-in one, so it is never empty. Nil (with `lastError`) if the name is blank.
    @discardableResult
    public func createLayout(name: String) -> StageLayout? { copy(of: StageLayout.standard, named: name, doing: "create the layout") }

    /// A copy of any layout, built-in or not, named "<name> copy" unless a name is given.
    @discardableResult
    public func duplicateLayout(_ id: UUID, name: String? = nil) -> StageLayout? {
        guard let source = layout(withID: id) else { return missingLayout("duplicate the layout") }
        return copy(of: source, named: name ?? source.name + " copy", doing: "duplicate the layout")
    }

    private func copy(of source: StageLayout, named name: String, doing what: String) -> StageLayout? {
        guard let name = Self.validName(name) else { return blankName(what) }
        var layout = source
        layout.id = UUID()
        layout.name = name
        layout.elements = source.elements.map { element in
            var e = element
            e.id = UUID()
            return e
        }
        customLayouts.append(layout)
        enqueue(.layout(layout.id))
        onChange?()
        return layout
    }

    public func renameLayout(_ id: UUID, to name: String) {
        guard let i = customLayouts.firstIndex(where: { $0.id == id }) else { refuse(id, "rename the layout"); return }
        guard let name = Self.validName(name) else { _ = blankName("rename the layout"); return }
        guard customLayouts[i].name != name else { return }
        customLayouts[i].name = name
        enqueue(.layout(id))
        onChange?()
    }

    /// Screens that showed the deleted layout go back to the built-in one.
    public func deleteLayout(_ id: UUID) {
        guard let i = customLayouts.firstIndex(where: { $0.id == id }) else { refuse(id, "delete the layout"); return }
        customLayouts.remove(at: i)
        queue.removeAll { $0 == .layout(id) }
        enqueue(.deleteLayout(id))
        let before = layoutChoices
        layoutChoices = layoutChoices.filter { $0.value != id }
        if layoutChoices != before { enqueue(.choices) }
        onChange?()
    }

    // MARK: Layout of each stage screen

    /// The layout a screen shows: its choice, or the built-in layout.
    public func layout(forScreen screenID: UUID) -> StageLayout {
        layoutChoices[screenID].flatMap { layout(withID: $0) } ?? StageLayout.standard
    }

    public func layoutID(forScreen screenID: UUID) -> UUID { layout(forScreen: screenID).id }

    /// Chooses the layout of a stage screen; nil, or the built-in id, returns it to the built-in layout.
    public func setLayout(_ layoutID: UUID?, forScreen screenID: UUID) {
        if let layoutID, layoutID != StageLayout.standardID {
            guard isEditable(layoutID) else { _ = missingLayout("choose the layout"); return }
            guard layoutChoices[screenID] != layoutID else { return }
            layoutChoices[screenID] = layoutID
        } else {
            guard layoutChoices[screenID] != nil else { return }
            layoutChoices[screenID] = nil
        }
        enqueue(.choices)
        onChange?()
    }

    // MARK: Elements (LIVE-01)

    /// Adds an element to one of the operator's layouts and returns its id. A timer element uses `timerID`, or the
    /// first timer; with no timer there is nothing to show and `lastError` says so.
    @discardableResult
    public func addElement(_ template: NewStageElement, to layoutID: UUID, timerID: UUID? = nil) -> UUID? {
        guard isEditable(layoutID) else { refuse(layoutID, "add the element"); return nil }
        if template == .timer, (timerID ?? timers.first?.id) == nil {
            lastError = "Could not add the timer: there are no timers yet. Add a timer in the Timers panel first."
            return nil
        }
        if let timerID, template == .timer, !timers.contains(where: { $0.id == timerID }) {
            lastError = "Could not add the timer: that timer no longer exists. Choose another timer."
            return nil
        }
        guard let element = StageEditing.newElement(template, timerID: timerID ?? timers.first?.id) else { return nil }
        var clean = StageEditing.sanitized(element)
        // SLIDE-001b: in free space where there is any, not on top of the elements already there.
        if let existing = layout(withID: layoutID)?.elements {
            let free = FreeSpace.place(width: clean.frame.width, height: clean.frame.height, avoiding: existing.map(\.frame),
                                       preferred: (clean.frame.x, clean.frame.y))
            clean = StageEditing.framed(clean, x: free.x, y: free.y, width: free.width, height: free.height)
        }
        let placed = clean
        edit(layoutID) { $0.elements.append(placed) }
        return placed.id
    }

    public func removeElement(_ elementID: UUID, from layoutID: UUID) {
        edit(layoutID) { $0.elements.removeAll { $0.id == elementID } }
    }

    /// Changes one element and keeps every value inside what the compositor can draw. The id never changes.
    public func updateElement(_ elementID: UUID, in layoutID: UUID, _ change: (inout StageElement) -> Void) {
        edit(layoutID) { layout in
            guard let i = layout.elements.firstIndex(where: { $0.id == elementID }) else { return }
            var e = layout.elements[i]
            change(&e)
            e.id = elementID
            layout.elements[i] = StageEditing.sanitized(e)
        }
    }

    /// Moves an element by a fraction of the screen from where it was when the drag began. The frame stays on screen.
    public func moveElement(_ elementID: UUID, in layoutID: UUID, from start: NormalizedRect, dx: Double, dy: Double) {
        updateElement(elementID, in: layoutID) { e in
            e.frame = start
            e.move(dx: dx, dy: dy)
        }
    }

    /// Resizes from the drag's start frame by a fraction of the screen. Not smaller than the minimum, not off screen.
    public func resizeElement(_ elementID: UUID, in layoutID: UUID, from start: NormalizedRect, dWidth: Double, dHeight: Double) {
        updateElement(elementID, in: layoutID) { e in
            e.frame = start
            e.resize(width: start.width + dWidth, height: start.height + dHeight)
        }
    }

    /// Sets the frame from typed numbers (fractions of the screen), clamped the same way.
    public func setFrame(_ elementID: UUID, in layoutID: UUID, x: Double, y: Double, width: Double, height: Double) {
        updateElement(elementID, in: layoutID) { e in e = StageEditing.framed(e, x: x, y: y, width: width, height: height) }
    }

    public func setFontSize(_ size: Double, for elementID: UUID, in layoutID: UUID) {
        updateElement(elementID, in: layoutID) { $0.style.fontSize = size }
    }

    public func setColor(_ color: ColorRGBA, for elementID: UUID, in layoutID: UUID) {
        updateElement(elementID, in: layoutID) { $0.style.color = color }
    }

    public func setAlignment(_ alignment: Domain.TextAlignment, for elementID: UUID, in layoutID: UUID) {
        updateElement(elementID, in: layoutID) { $0.alignment = alignment }
    }

    public func setShowsSecondLanguage(_ on: Bool, for elementID: UUID, in layoutID: UUID) {
        updateElement(elementID, in: layoutID) { $0.showsSecondLanguage = on }
    }

    /// Points a timer element at another timer. Other kinds are left as they are.
    public func setTimer(_ timerID: UUID, for elementID: UUID, in layoutID: UUID) {
        guard timers.contains(where: { $0.id == timerID }) else {
            lastError = "Could not choose the timer: that timer no longer exists. Choose another timer."
            return
        }
        updateElement(elementID, in: layoutID) { e in if case .timer = e.kind { e.kind = .timer(timerID) } }
    }

    /// Applies a change to one of the operator's layouts: in memory now, written soon. Built-in or unknown ids are refused.
    private func edit(_ layoutID: UUID, _ change: (inout StageLayout) -> Void) {
        guard let i = customLayouts.firstIndex(where: { $0.id == layoutID }) else { refuse(layoutID, "change the layout"); return }
        var layout = customLayouts[i]
        change(&layout)
        guard layout != customLayouts[i] else { return }
        customLayouts[i] = layout
        enqueue(.layout(layoutID))
        onChange?()
    }

    // MARK: Timers (LIVE-02, LIVE-04)

    /// The longest countdown: 99:59:59, the most `TimeFormat` can show.
    public static let longestCountdown = 99 * 3600 + 3599

    @discardableResult
    public func addCountdown(name: String?, minutes: Int, seconds: Int) -> ShowTimer? {
        let total = minutes * 60 + seconds
        guard minutes >= 0, seconds >= 0, total > 0, total <= Self.longestCountdown else {
            lastError = "Could not add the countdown: choose a length longer than zero seconds and no more than 99 hours."
            return nil
        }
        return add(name: name, fallback: "Countdown", kind: .countdown(seconds: TimeInterval(total)))
    }

    @discardableResult
    public func addElapsed(name: String?) -> ShowTimer? { add(name: name, fallback: "Elapsed", kind: .elapsed) }

    /// A countdown to a time of day today. If that time has passed it is already over and shows in the warning colour.
    @discardableResult
    public func addCountdown(name: String?, toHour hour: Int, minute: Int) -> ShowTimer? {
        guard (0...23).contains(hour), (0...59).contains(minute),
              let target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
            lastError = "Could not add the countdown: choose an hour from 0 to 23 and a minute from 0 to 59."
            return nil
        }
        return add(name: name, fallback: "Countdown to time", kind: .countdownTo(target))
    }

    private func add(name: String?, fallback: String, kind: ShowTimer.Kind) -> ShowTimer? {
        var label = fallback
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let valid = Self.validName(name) else { return nil }
            label = valid
        }
        let timer = ShowTimer(id: UUID(), name: label, kind: kind)
        timers.append(timer)
        enqueue(.timer(timer.id))
        onChange?()
        return timer
    }

    public func renameTimer(_ id: UUID, to name: String) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { missingTimer("rename the timer"); return }
        guard let name = Self.validName(name) else { _ = blankName("rename the timer"); return }
        guard timers[i].name != name else { return }
        timers[i].name = name
        enqueue(.timer(id))
        onChange?()
    }

    /// Layout elements that showed the timer stay in their layouts and draw nothing until pointed at another timer.
    public func deleteTimer(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { missingTimer("delete the timer"); return }
        timers.remove(at: i)
        queue.removeAll { $0 == .timer(id) }
        enqueue(.deleteTimer(id))
        if let marks = toolbarMarks, marks.contains(id) {
            toolbarMarks = marks.filter { $0 != id }
            toolbarRevision &+= 1
            enqueue(.toolbar)
        }
        onChange?()
    }

    public func startTimer(_ id: UUID) { changeTimer(id, "start the timer") { $0.start(at: $1) } }
    public func pauseTimer(_ id: UUID) { changeTimer(id, "pause the timer") { $0.pause(at: $1) } }
    public func resetTimer(_ id: UUID) { changeTimer(id, "reset the timer") { t, _ in t.reset() } }

    private func changeTimer(_ id: UUID, _ what: String, _ change: (inout ShowTimer, TimeInterval) -> Void) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { missingTimer(what); return }
        var timer = timers[i]
        change(&timer, nowSeconds)
        guard timer != timers[i] else { return }
        timers[i] = timer
        enqueue(.timer(id))
        onChange?()
    }

    /// What the timers panel shows at the given instant.
    public func timerRows(at seconds: TimeInterval) -> [TimerRow] {
        timers.map { timer in
            let label: String
            let follows: Bool
            switch timer.kind {
            case .countdown(let length): label = "Countdown from \(TimeFormat.clock(seconds: length))"; follows = false
            case .elapsed: label = "Elapsed"; follows = false
            case .countdownTo(let date):
                label = "Countdown to \(TimeFormat.timeOfDay(date, calendar: calendar, twentyFourHour: clockStyle.twentyFourHour, showSeconds: false))"
                follows = true
            }
            return TimerRow(id: timer.id, name: timer.name, kindLabel: label,
                            text: TimeFormat.clock(seconds: timer.value(at: seconds)), isRunning: timer.isRunning,
                            isOverrun: timer.isOverrun(at: seconds), followsClock: follows)
        }
    }

    // MARK: Scenes (LIVE-02, SCRN-03)

    /// The scene of one stage screen. `notes` are the live slide's speaker notes; the stage message is the one sent from the Show inspector.
    public func stageScene(forScreen screenID: UUID, state: ShowState, notes: String?) -> SceneDescription {
        scene(layout: layout(forScreen: screenID), state: state, notes: notes)
    }

    public func scene(layout: StageLayout, state: ShowState, notes: String?) -> SceneDescription {
        let date = now
        let context = StageContext(state: state, now: date.timeIntervalSinceReferenceDate,
                                   timeOfDayText: timeOfDayText(at: date), timers: timers, message: stageMessage, notes: notes)
        return StageComposer.scene(layout: layout, context: context)
    }

    /// Scenes for every given stage screen, from one reading of the clock.
    public func stageScenes(forScreens ids: [UUID], state: ShowState, notes: String?) -> [UUID: SceneDescription] {
        var scenes: [UUID: SceneDescription] = [:]
        for id in ids { scenes[id] = stageScene(forScreen: id, state: state, notes: notes) }
        return scenes
    }

    /// True when any of these screens shows a clock or a timer, so the app must republish every second.
    public func needsPerSecondRefresh(forScreens ids: [UUID]) -> Bool {
        ids.contains { StageEditing.needsPerSecondRefresh(layout(forScreen: $0)) }
    }

    /// The layout with sample slides, clock, message and notes, for the editor's canvas.
    public func sampleScene(for layout: StageLayout) -> SceneDescription {
        let date = now
        return StageEditing.sampleScene(layout: layout, timers: timers, now: date.timeIntervalSinceReferenceDate,
                                        timeOfDayText: timeOfDayText(at: date))
    }

    // MARK: Writing

    func enqueueWrite(_ write: Write) { enqueue(write) }

    private func enqueue(_ write: Write) {
        if !queue.contains(write) { queue.append(write) }
        guard drain == nil else { return }
        drain = Task { [weak self] in await self?.drainQueue() }
    }

    private func drainQueue() async {
        while !queue.isEmpty {
            let write = queue.removeFirst()
            await perform(write)
        }
        drain = nil
    }

    private func perform(_ write: Write) async {
        switch write {
        case .layout(let id):
            guard let layout = customLayouts.first(where: { $0.id == id }) else { return }
            _ = await attempt("save the layout") { try await self.store.saveStageLayout(layout) }
        case .timer(let id):
            guard let timer = timers.first(where: { $0.id == id }) else { return }
            _ = await attempt("save the timer") { try await self.store.saveTimer(timer) }
        case .deleteLayout(let id):
            do { try await store.deleteStageLayout(id: id) } catch StoreError.notFound { /* never reached the file */ } catch {
                lastError = Self.message(for: error, doing: "delete the layout")
            }
        case .deleteTimer(let id):
            do { try await store.deleteTimer(id: id) } catch StoreError.notFound { /* never reached the file */ } catch {
                lastError = Self.message(for: error, doing: "delete the timer")
            }
        case .choices:
            let stored = Dictionary(uniqueKeysWithValues: layoutChoices.map { ($0.key.uuidString, $0.value.uuidString) })
            guard let data = try? JSONEncoder().encode(stored), let text = String(data: data, encoding: .utf8) else { return }
            _ = await attempt("remember the stage layouts") { try await self.store.setState(text, for: Self.choicesKey) }
        case .messages:
            guard let data = try? JSONEncoder().encode(recentMessages), let text = String(data: data, encoding: .utf8) else { return }
            _ = await attempt("remember the stage messages") { try await self.store.setState(text, for: Self.messagesKey) }
        case .toolbar:
            guard let marks = toolbarMarks, let data = try? JSONEncoder().encode(marks.map(\.uuidString)),
                  let text = String(data: data, encoding: .utf8) else { return }
            _ = await attempt("remember the toolbar timers") { try await self.store.setState(text, for: Self.toolbarKey) }
        case .clock:
            guard let data = try? JSONEncoder().encode(clockStyle), let text = String(data: data, encoding: .utf8) else { return }
            _ = await attempt("remember the clock style") { try await self.store.setState(text, for: Self.clockKey) }
        }
    }

    // MARK: Errors

    private func attempt<T>(_ what: String, _ body: () async throws -> T) async -> T? {
        do { return try await body() } catch {
            lastError = Self.message(for: error, doing: what)
            return nil
        }
    }

    private func refuse(_ layoutID: UUID, _ what: String) {
        lastError = layoutID == StageLayout.standardID ? Self.readOnlyMessage : Self.missingLayoutMessage(what)
    }

    private func missingLayout(_ what: String) -> StageLayout? {
        lastError = Self.missingLayoutMessage(what)
        return nil
    }

    private static func missingLayoutMessage(_ what: String) -> String {
        "Could not \(what): that layout no longer exists. Choose another layout from the list."
    }

    private func missingTimer(_ what: String) {
        lastError = "Could not \(what): that timer no longer exists. Choose another timer from the list."
    }

    private func blankName(_ what: String) -> StageLayout? {
        lastError = "Could not \(what): a name is needed. Type at least one letter and try again."
        return nil
    }

    private static func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func message(for error: Error, doing what: String) -> String {
        if let store = error as? StoreError {
            switch store {
            case .invalidName: return "Could not \(what): a name is needed. Type at least one letter and try again."
            case .notFound: return "Could not \(what): that item no longer exists. Choose it again from the list."
            case .invalidReference: return "Could not \(what): the built-in layout cannot be changed."
            case .unknownMigration: return "Could not \(what): the library file is from a different version of the app."
            case .invalidValue: return "Could not \(what): that value is not allowed (a time outside the clip, or a number that is not real). Change it and try again."
            }
        }
        return "Could not \(what): \(error.localizedDescription) The change is in effect now but may be lost when the app quits. Try again; if it keeps failing, restart the app."
    }
}
