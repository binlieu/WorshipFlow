// FIX-G item 2 (MEDIA-010): where a bin item is used as a slide's own background, and what the operator is told before it goes.
import Foundation

/// One slide that has a bin item as its own background.
public struct SlideBackgroundUse: Sendable, Equatable {
    public var presentationID: UUID
    public var presentationTitle: String
    /// 1-based place in the presentation.
    public var slideNumber: Int
    /// The first line of the slide's words, so the operator can tell which slide it is.
    public var words: String

    public init(presentationID: UUID, presentationTitle: String, slideNumber: Int, words: String) {
        self.presentationID = presentationID
        self.presentationTitle = presentationTitle
        self.slideNumber = slideNumber
        self.words = words
    }
}

/// The slides a removal would leave without their background, and the sentence that says so. No uses, no message.
public struct SlideBackgroundRemovalImpact: Sendable, Equatable {
    public var itemName: String
    public var uses: [SlideBackgroundUse]

    public init(itemName: String, uses: [SlideBackgroundUse]) {
        self.itemName = itemName
        self.uses = uses
    }

    /// At most this many slides are named; the rest are counted.
    public static let namedLimit = 8

    public var message: String? {
        guard !uses.isEmpty else { return nil }
        let named = uses.prefix(Self.namedLimit).map { "\"\($0.presentationTitle)\" slide \($0.slideNumber)" }
        let rest = uses.count > Self.namedLimit ? " and \(uses.count - Self.namedLimit) more" : ""
        let count = uses.count == 1 ? "1 slide" : "\(uses.count) slides"
        return "\"\(itemName)\" is the own background of \(count): \(named.joined(separator: ", "))\(rest). "
            + "After it is removed those slides keep their choice and show their words on the theme's own background, marked as missing, until you choose another item for them."
    }
}
