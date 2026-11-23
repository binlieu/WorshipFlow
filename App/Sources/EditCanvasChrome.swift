// UI-006c: the small pieces the Edit mode gained: the strip's "Saved ... ago" words and the app side of the preview-as-screen scene.
// The rules (what counts as saved, which screen supplies the theme, the zoom sizes) are in `UI006c_EditFeatures.swift` with tests.
import SwiftUI
import Domain
import MediaEngine
import OperatorCore

/// E19: "Saved 2 s ago", at the right of the live strip. It looks once a second at whether typed or edited text is still waiting to be
/// written (`hasUnsavedDrafts`, the same state the quit and mode-switch flushes use) and at the save problem the workspace reports. It says
/// "All changes saved" until it has seen a save itself, and never invents a time.
struct EditSaveText: View {
    let workspace: WorkspaceModel
    @State private var status = EditSaveStatus()
    @State private var now: TimeInterval = ProcessInfo.processInfo.systemUptime

    var body: some View {
        Text(status.text(now: now))
            .foregroundStyle(status.isProblem ? Tok.warning : Tok.muted)
            .wfLine()
            .wfRect("ed.strip.saved", size: 12, weight: 400)
            .help(status.isProblem ? "The last write failed; the text is kept and will be written again." : "Whether your changes have reached the library")
            .accessibilityLabel("Save status")
            .accessibilityValue(status.text(now: now))
            .task {
                while !Task.isCancelled {
                    let t = ProcessInfo.processInfo.systemUptime
                    status.observe(hasUnsaved: workspace.hasUnsavedDrafts, problem: workspace.draftSaveProblem, now: t)
                    now = t
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

extension AppModel {
    /// E16: how `slide` is composed for one screen role, by the same composer the outputs use (the audience case is `thumbnailScene`).
    /// A preview only: the live show, the screens and the saved slide are not touched. FIX-V item 5: the stage preview is the stage screen's
    /// own scene (its chosen layout, Hide, Auto-fit, the next slide and, if the layout has a notes element, this slide's speaker notes). Broadcast
    /// and audience previews never get notes.
    func editPreviewScene(role: EditPreviewRole, for slide: SlideContent, slideID: UUID? = nil) -> SceneDescription {
        let slides = workspace?.slides ?? []
        let index = slideID.flatMap { id in slides.firstIndex { $0.id == id } }
        let notes = index.flatMap { slides[$0].notes }.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return EditPreviewScene.scene(role: role, slide: slide, profiles: profiles, themes: themes, look: currentLook, props: props,
                                      presentationThemeID: workspace?.openThemeID,
                                      media: LiveMedia.preview(slide: slide, at: MediaClock.now()),
                                      deck: index == nil ? nil : slides.map(\.content), index: index, stage: stage, notes: notes)
    }
}
