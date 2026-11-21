// OUT-001: command-line options for unattended soak runs.
import Foundation

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
