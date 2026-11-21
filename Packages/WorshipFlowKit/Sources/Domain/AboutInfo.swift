// UI-004: the words of the About window, kept here so a test can check them. The developer's name and e-mail address are the
// only personal details; the third-party notices repeat NOTICE and the README.
import Foundation

public enum AboutInfo {
    public static let summary = "WorshipFlow is a local-first Mac app for presenting worship lyrics, Scripture, slides, images and video on the audience screen, the stage monitors and the broadcast feed, each with its own look. It keeps working without the internet."
    public static let developerLine = "Developed by Simon Lieu"
    public static let developerEmail = "me@simonlieu.com"
    public static let developerMailURL = URL(string: "mailto:me@simonlieu.com")!
    public static let projectURL = URL(string: "https://github.com/binlieu/WorshipFlow")!
    public static let licenceLine = "Released under the Apache License 2.0."
    public static let thirdPartyNotices: [String] = [
        "Blackmagic DeckLink SDK include files: copyright Blackmagic Design, used unmodified under the licence notice in each file. The Desktop Video driver is not included. \"DeckLink\" and \"Blackmagic Design\" are trademarks of Blackmagic Design Pty. Ltd.; this app is not affiliated with or endorsed by Blackmagic Design.",
        "GRDB.swift: copyright Gwendal Roué, MIT License, used for SQLite access.",
        "No Bible translation text is included with the app.",
    ]
}
