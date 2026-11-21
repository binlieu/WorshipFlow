// HWTEST-001 / FIX-D S1, S4: which connector each step uses, chosen from what the card says about itself NOW, never from
// fixed numbers. A card in a keying profile cannot send plain output on its first connector of a pair, and a card whose
// profile is not known to this kit can be treated as "every connector does everything" only when it reports no layout.
// Pure functions of `SDIDeviceInfo`, so every decision is tested without a card.
import Foundation
import SDIEngine

/// Where a keyed output goes and where its two pictures are read back.
struct HardwareKeyedPlan: Equatable {
    /// The connector a keyed port is opened on (1 or 3 on a four-connector card); the pair is `first` and `first + 1`.
    var first: Int
    /// Connectors that carry the two pictures, as the card reports them (or the old convention when it reports none).
    var fillConnector: Int
    var keyConnector: Int
    /// The input that reads what `first` carries, and the input that reads what `first + 1` carries.
    var inputA: Int
    var inputB: Int

    var cables: [HardwareCable] { [HardwareCable(output: first, input: inputA), HardwareCable(output: first + 1, input: inputB)] }
}

enum HardwareTestLayout {
    /// What the card says one connector can do. A card that reports no connector list is taken to allow everything.
    static func canOutput(_ info: SDIDeviceInfo, _ connector: Int) -> Bool {
        guard connector >= 1, connector <= info.connectorCount else { return false }
        return info.connectors.first { $0.connector == connector }?.canOutput ?? true
    }

    static func canInput(_ info: SDIDeviceInfo, _ connector: Int) -> Bool {
        guard connector >= 1, connector <= info.connectorCount else { return false }
        return info.connectors.first { $0.connector == connector }?.canInput ?? true
    }

    /// Every connector that can send plain output now, in order.
    static func outputs(_ info: SDIDeviceInfo) -> [Int] { (1...max(1, info.connectorCount)).filter { canOutput(info, $0) } }

    /// The connector for a plain output: `prefer` when it can output, otherwise the first one that can. Nil when none can.
    static func plainOutput(_ info: SDIDeviceInfo, prefer: Int) -> Int? {
        canOutput(info, prefer) ? prefer : outputs(info).first
    }

    /// An output and an input for the one-cable loopback. `preferOutput` and `preferInput` are kept when the layout allows
    /// them; otherwise the first connector that can do the job, an input in another pair when there is one.
    static func loopback(_ info: SDIDeviceInfo, preferOutput: Int, preferInput: Int) -> (output: Int, input: Int)? {
        guard let out = plainOutput(info, prefer: preferOutput) else { return nil }
        let inputs = (1...max(1, info.connectorCount)).filter { $0 != out && canInput(info, $0) }
        if canInput(info, preferInput), preferInput != out { return (out, preferInput) }
        let otherPair = inputs.first { ($0 - 1) / 2 != (out - 1) / 2 }
        guard let input = otherPair ?? inputs.first else { return nil }
        return (out, input)
    }

    /// The pairs (by first connector) the card could send fill and key on, preferred one first.
    static func keyablePairs(_ info: SDIDeviceInfo, prefer: Int) -> [Int] {
        guard info.supportsExternalKeying, info.connectorCount >= 2 else { return [] }
        var firsts: [Int] = []
        var c = 1
        while c + 1 <= info.connectorCount {
            // A pair whose state is reported must be keying now or have a profile that offers it.
            if let state = info.profileState(forPair: c) {
                if state.keyingAvailableNow || state.keyingChange != nil { firsts.append(c) }
            } else { firsts.append(c) }
            c += 2
        }
        return firsts.sorted { ($0 == prefer ? 0 : 1, $0) < ($1 == prefer ? 0 : 1, $1) }
    }

    /// The route of a pair as the card reports it, or the old convention (fill on the first connector).
    static func route(_ info: SDIDeviceInfo, first: Int) -> (fill: Int, key: Int) {
        info.keyRoute(firstConnector: first).map { ($0.fillConnector, $0.keyConnector) } ?? (first, first + 1)
    }

    /// Why no keyed loopback can be wired in the card's layout as it is now, or the plan. The inputs are connectors outside
    /// the pair that can receive; `preferA` and `preferB` are kept when they can.
    static func keyed(_ info: SDIDeviceInfo, first: Int, preferA: Int, preferB: Int) -> Result<HardwareKeyedPlan, HardwareLayoutProblem> {
        let r = route(info, first: first)
        let candidates = (1...max(1, info.connectorCount)).filter { $0 != first && $0 != first + 1 && canInput(info, $0) }
        func pick(_ prefer: Int, not taken: Int?) -> Int? {
            if candidates.contains(prefer), prefer != taken { return prefer }
            return candidates.first { $0 != taken }
        }
        guard let a = pick(preferA, not: nil), let b = pick(preferB, not: a) else {
            let listed = candidates.map(String.init).joined(separator: ", ")
            return .failure(HardwareLayoutProblem(
                text: "In the card's profile as it is now, " + (candidates.isEmpty ? "no connector outside SDI \(first) and \(first + 1) can receive a signal"
                                                                                    : "only SDI \(listed) can receive a signal outside SDI \(first) and \(first + 1)")
                    + ", and a fill and key loopback needs two."))
        }
        return .success(HardwareKeyedPlan(first: first, fillConnector: r.fill, keyConnector: r.key, inputA: a, inputB: b))
    }

    /// The two halves of a four-connector card for the loopback of every output: A is the lower half, B the upper.
    static func halves(_ info: SDIDeviceInfo) -> (lower: [Int], upper: [Int])? {
        guard info.connectorCount >= 4, info.connectorCount % 2 == 0 else { return nil }
        let all = Array(1...info.connectorCount)
        let half = all.count / 2
        return (Array(all.prefix(half)), Array(all.suffix(half)))
    }

    /// A short description of the layout for a report: "SDI 1 in/key, SDI 2 out/fill, ...". Nil when the card reports none.
    static func describe(_ info: SDIDeviceInfo) -> String? {
        guard !info.connectors.isEmpty else { return nil }
        return info.connectors.sorted { $0.connector < $1.connector }.map { c in
            let what = [c.canOutput ? "out" : nil, c.canInput ? "in" : nil].compactMap { $0 }.joined(separator: "/")
            let role = c.keyRole.map { $0 == .fill ? " (fill)" : " (key)" } ?? ""
            return "SDI \(c.connector): \(what.isEmpty ? "neither" : what)\(role)"
        }.joined(separator: "; ")
    }
}

struct HardwareLayoutProblem: Error, Equatable {
    var text: String
}

extension Result {
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
}
