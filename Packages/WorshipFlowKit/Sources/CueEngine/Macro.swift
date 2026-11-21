// CUE-001 (AUTO-02): macros and the library that validates them. Foundation only.
import Foundation

public struct Macro: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var steps: [CueAction]

    public init(id: UUID = UUID(), name: String, steps: [CueAction]) {
        self.id = id
        self.name = name
        self.steps = steps
    }

    var calledMacroIDs: [UUID] {
        steps.compactMap { if case .runMacro(let id) = $0 { return id } else { return nil } }
    }
}

public enum MacroLibraryError: Error, Sendable, Equatable {
    case emptyName
    /// Macro names along the cycle, first and last equal.
    case cycle([String])
    case tooDeep(macro: String, depth: Int, limit: Int)

    public var message: String {
        switch self {
        case .emptyName: return "A macro needs a name"
        case .cycle(let names): return "Macro cycle: " + names.joined(separator: " \u{2192} ")
        case .tooDeep(let name, let depth, let limit):
            return "Macro \u{201C}\(name)\u{201D} would nest \(depth) levels deep; the limit is \(limit)"
        }
    }
}

/// Saved macros. `save` refuses a macro that would create a cycle or nest more than `maxDepth` levels. A macro may call a
/// macro id that does not exist (yet); that is reported and skipped when it runs.
public struct MacroLibrary: Sendable, Equatable, Codable {
    public static let maxDepth = 8
    public static let currentVersion = 1

    public private(set) var macros: [Macro]

    public init() { macros = [] }

    /// For data read from storage that may be damaged. Use `issues()` to look for problems.
    public init(unvalidated macros: [Macro]) { self.macros = macros }

    public func macro(id: UUID) -> Macro? { macros.first { $0.id == id } }

    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        guard let i = macros.firstIndex(where: { $0.id == id }) else { return false }
        macros.remove(at: i)
        return true
    }

    public mutating func save(_ macro: Macro) throws {
        guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MacroLibraryError.emptyName }
        var candidate = self
        if let i = candidate.macros.firstIndex(where: { $0.id == macro.id }) {
            candidate.macros[i] = macro
        } else {
            candidate.macros.append(macro)
        }
        if let path = candidate.cycle(from: macro.id) { throw MacroLibraryError.cycle(path.map(\.name)) }
        for m in candidate.macros {
            let now = candidate.depth(of: m.id)
            if now > Self.maxDepth, depth(of: m.id) <= Self.maxDepth {
                throw MacroLibraryError.tooDeep(macro: m.name, depth: now, limit: Self.maxDepth)
            }
        }
        self = candidate
    }

    /// Levels of macros from this one down: 1 for a macro that calls none, 0 for an unknown id. Safe on cycles.
    public func depth(of id: UUID) -> Int {
        var memo: [UUID: Int] = [:]
        var visiting: Set<UUID> = []
        func walk(_ id: UUID) -> Int {
            if let d = memo[id] { return d }
            guard let m = macro(id: id), !visiting.contains(id) else { return 0 }
            visiting.insert(id)
            let d = 1 + (m.calledMacroIDs.map(walk).max() ?? 0)
            visiting.remove(id)
            memo[id] = d
            return d
        }
        return walk(id)
    }

    /// Names along a call path that leads from the macro back to itself, if there is one.
    private func cycle(from start: UUID) -> [Macro]? {
        guard let first = macro(id: start) else { return nil }
        var path: [Macro] = [first]
        var onPath: Set<UUID> = [start]
        var dead: Set<UUID> = []
        func walk(_ m: Macro) -> Bool {
            for callee in m.calledMacroIDs {
                if callee == start { return true }
                guard let next = macro(id: callee), !onPath.contains(callee), !dead.contains(callee) else { continue }
                path.append(next); onPath.insert(callee)
                if walk(next) { return true }
                path.removeLast(); onPath.remove(callee); dead.insert(callee)
            }
            return false
        }
        return walk(first) ? path + [first] : nil
    }

    /// Problems in the stored data: cycles (each reported once, starting at the first member in list order) and macros
    /// that nest too deep.
    public func issues() -> [MacroLibraryError] {
        var out: [MacroLibraryError] = []
        var seenCycles: [Set<UUID>] = []
        for m in macros {
            if let path = cycle(from: m.id) {
                let members = Set(path.map(\.id))
                if !seenCycles.contains(members) { seenCycles.append(members); out.append(.cycle(path.map(\.name))) }
            }
        }
        for m in macros {
            let d = depth(of: m.id)
            if d > Self.maxDepth { out.append(.tooDeep(macro: m.name, depth: d, limit: Self.maxDepth)) }
        }
        return out
    }

    /// The first transport command found in the macro or in any macro it calls, in written order. Safe on cycles.
    public func firstTransport(in id: UUID) -> CueTransport? {
        var seen: Set<UUID> = []
        func walk(_ id: UUID) -> CueTransport? {
            guard let m = macro(id: id), seen.insert(id).inserted else { return nil }
            for step in m.steps {
                switch step {
                case .transport(let t): return t
                case .runMacro(let callee): if let t = walk(callee) { return t }
                default: continue
                }
            }
            return nil
        }
        return walk(id)
    }

    private enum CodingKeys: String, CodingKey { case version, macros }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        macros = try c.decode([Macro].self, forKey: .macros)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(macros, forKey: .macros)
    }
}
