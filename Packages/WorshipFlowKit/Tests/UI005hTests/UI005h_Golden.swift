// UI-005h: digests of pictures recorded with the code of commit 38ca00d (the commit before this slice), on the Mac the slice was built on.
// They are a regression guard, not a portable truth: a different macOS or GPU could draw an antialiased edge differently, and the
// structural checks in the same tests (stored definitions byte for byte, decoded values, defaults) do not depend on the machine.
enum UI005h_Golden {
    /// Audience digest of each user theme in `UI005hFixtures.userThemes` (the broadcast picture is the same for these themes).
    static let userThemeAudience: [String: String] = [
        // re-recorded 2026-11-26 (FIX-Z): sample text changed, rendering code unchanged; the old value passed on the same code with the old text (old 4b4c3a53290c2341)
        "Sunday blue": "9e3bcc63af339e8",
        // re-recorded 2026-11-26 (FIX-Z): sample text changed, rendering code unchanged; the old value passed on the same code with the old text (old 6bcb221942b17552)
        "Loop with shadow": "a7a2c2380d372bb4",
        // re-recorded 2026-11-26 (FIX-Z): sample text changed, rendering code unchanged; the old value passed on the same code with the old text (old c8ced4111be51bda)
        "Keyed plain": "d1b59a5f17665f6",
        // re-recorded 2026-11-26 (FIX-Z): sample text changed, rendering code unchanged; the old value passed on the same code with the old text (old a3840e37db4abbb1)
        "Missing picture": "ec347864d30cdb0b",
    ]
    /// The two built-in looks before this slice (what the Classic themes must draw), audience and broadcast pictures.
    // re-recorded 2026-11-26 (FIX-Z): sample text changed, rendering code unchanged; the old value passed on the same code with the old text (old 1faed9c1e1957c85)
    static let oldFullScreenAudience = "52aacad6b54cf85c"
    // re-recorded 2026-11-26 (FIX-Z): sample text changed, rendering code unchanged; the old value passed on the same code with the old text (old a98ec309ef8a1e43)
    static let oldLowerThirdBroadcast = "4f6644d5b62a49e5"
}
