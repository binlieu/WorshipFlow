// OUT-001: command-line options for unattended soak runs.
import Foundation
import Domain

struct SoakConfig: Sendable {
    var seconds: Double
    var screenIndex: Int?
    var videoPath: String?
    var reportPath: String?

    /// `--soak <seconds> [--screen <index>] [--video <path>] [--report <path>]`; nil when `--soak` is absent.
    static func parse(_ args: [String]) -> SoakConfig? {
        guard let i = args.firstIndex(of: "--soak"), i + 1 < args.count, let seconds = Double(args[i + 1]), seconds > 0 else { return nil }
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
            return args[j + 1]
        }
        return SoakConfig(seconds: seconds, screenIndex: value("--screen").flatMap { Int($0) },
                          videoPath: value("--video"), reportPath: value("--report"))
    }
}

/// The slides a soak run cycles through. Only used with `--soak`; the workspace and library are not opened then.
/// Original short lines; Amazing Grace is public domain. The stacked-mark line exercises Vietnamese diacritics.
enum SoakDeck {
    static let slides: [SlideContent] = [
        SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay, tiếng ca sao ngọt ngào"),
        SlideContent(primary: "That saved a wretch like me", secondary: "Đã cứu một người tội lỗi như tôi"),
        SlideContent(primary: "I once was lost, but now am found", secondary: "Xưa tôi lạc lối, nay được tìm thấy"),
        SlideContent(primary: "Was blind, but now I see", secondary: "Xưa tôi mù lòa, nay được thấy sáng"),
        SlideContent(primary: "Praise the Lord, all you nations", secondary: "Hãy ngợi khen Chúa, hỡi muôn dân"),
        SlideContent(primary: "Stacked marks: Ễ Ậ Ở Ỗ Ẵ ỷ ự", secondary: "Nguyện xin Chúa ban phước, ễ ậ ở ỗ ẵ"),
    ]

    static let deck = ShowDeck(presentationID: UUID(), slides: slides)
}
