// UI-007f (SC-25, SC-31): editing the signal chain the operator types for a destination, as pure functions on the list of boxes. The chain is the
// operator's own note about what a signal passes through (enclosure, converter, other); WorshipFlow cannot see any of it. Foundation and Domain only.
import Foundation
import Domain

public enum SignalChainEditing {
    public static let maxLength = ScreenProfile.maxChainLength

    public static func canAdd(to chain: [ChainNode]) -> Bool { chain.count < maxLength }

    /// A new box at the end, with no words yet (the operator types them). Unchanged when the chain is full.
    public static func adding(_ kind: ChainNode.Kind, to chain: [ChainNode]) -> [ChainNode] {
        canAdd(to: chain) ? chain + [ChainNode(kind: kind, label: "")] : chain
    }

    public static func removing(at index: Int, from chain: [ChainNode]) -> [ChainNode] {
        guard chain.indices.contains(index) else { return chain }
        var result = chain
        result.remove(at: index)
        return result
    }

    public static func setting(label: String, at index: Int, in chain: [ChainNode]) -> [ChainNode] {
        guard chain.indices.contains(index) else { return chain }
        var result = chain
        result[index] = ChainNode(kind: chain[index].kind, label: label)
        return result
    }

    public static func setting(kind: ChainNode.Kind, at index: Int, in chain: [ChainNode]) -> [ChainNode] {
        guard chain.indices.contains(index) else { return chain }
        var result = chain
        result[index] = ChainNode(kind: kind, label: chain[index].label)
        return result
    }

    /// Moves a box one place earlier (`by: -1`) or later (`by: 1`); the order is the order the signal travels, from the card to the screen.
    public static func moving(_ index: Int, by step: Int, in chain: [ChainNode]) -> [ChainNode] {
        let target = index + step
        guard chain.indices.contains(index), chain.indices.contains(target), step != 0 else { return chain }
        var result = chain
        result.swapAt(index, target)
        return result
    }

    /// What a box is called in the list and on the map: the typed words, else the kind alone ("Converter").
    public static func title(_ node: ChainNode) -> String {
        node.label.isEmpty ? kindName(node.kind) : node.label
    }

    public static func kindName(_ kind: ChainNode.Kind) -> String {
        switch kind {
        case .enclosure: "Enclosure"
        case .converter: "Converter"
        case .other: "Other"
        }
    }
}
