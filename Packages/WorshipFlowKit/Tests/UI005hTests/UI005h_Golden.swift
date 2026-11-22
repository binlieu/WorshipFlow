// UI-005h: digests of pictures recorded with the code of commit 38ca00d (the commit before this slice), on the Mac the slice was built on.
// They are a regression guard, not a portable truth: a different macOS or GPU could draw an antialiased edge differently, and the
// structural checks in the same tests (stored definitions byte for byte, decoded values, defaults) do not depend on the machine.
enum UI005h_Golden {
    /// Audience digest of each user theme in `UI005hFixtures.userThemes` (the broadcast picture is the same for these themes).
    static let userThemeAudience: [String: String] = [
        "Sunday blue": "4b4c3a53290c2341",
        "Loop with shadow": "6bcb221942b17552",
        "Keyed plain": "c8ced4111be51bda",
        "Missing picture": "a3840e37db4abbb1",
    ]
    /// The two built-in looks before this slice (what the Classic themes must draw), audience and broadcast pictures.
    static let oldFullScreenAudience = "1faed9c1e1957c85"
    static let oldLowerThirdBroadcast = "a98ec309ef8a1e43"
}
