// UI-001 / ADR-0007: the Edit, Media, Stage, Cues and Screens modes. Each re-homes panels that already worked; none
// of them carries new logic.
import SwiftUI
import Domain
import OperatorCore

// MARK: Edit

struct EditModeView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        if workspace.openPresentationID == nil {
            VStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard").font(.largeTitle).foregroundStyle(Tok.muted)
                Text("Open a song to edit it").font(.title3)
                Text("Choose one in Show (Command-1), or press Command-N for a new presentation.")
                    .font(.caption).foregroundStyle(Tok.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                filmstrip.frame(width: 232)
                Divider()
                VStack(spacing: 0) {
                    header
                    Divider()
                    status
                    Divider()
                    SlideEditor(app: app, workspace: workspace)
                }
            }
        }
    }

    // MARK: Filmstrip

    private var filmstrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(workspace.presentations.first { $0.id == workspace.openPresentationID }?.title ?? "Slides")
                    .lineLimit(1)
                Spacer()
                Button { Task { await workspace.addSlide(SlideContent(primary: "")) } } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("Add slide").accessibilityLabel("Add slide")
            }
            .padding(Space.s4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(Array(workspace.slides.enumerated()), id: \.element.id) { i, slide in
                        let selected = workspace.show.selectedIndex == i
                        let live = app.show.liveDeck?.presentationID == workspace.openPresentationID && app.show.liveIndex == i
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(i + 1)").font(.system(size: 12, weight: .bold).monospacedDigit())
                            SlideThumbnail(app: app, slide: slide.content)
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(selected ? Tok.blue : .clear, lineWidth: 2))
                                .padding(live ? 4 : 0)
                                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(live ? (app.mode == .live ? Tok.liveFill : Tok.warning) : .clear, lineWidth: 3))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { workspace.selectSlide(i) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Slide \(i + 1): \(slide.content.primary)")
                        .accessibilityValue(live ? "live" : "")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
            }
        }
        .background(Tok.surface)
    }

    // MARK: Header: theme, section orders, re-flow

    private var header: some View {
        HStack(spacing: Space.s3) {
            Picker("Theme", selection: Binding(get: { workspace.openThemeID },
                                               set: { id in if let open = workspace.openPresentationID { app.setPresentationTheme(id, forPresentation: open) } })) {
                Text("Default").tag(UUID?.none)
                ForEach(app.themes) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .frame(maxWidth: 260).help("The look of this song on the audience screen")
            Button { app.ui.showThemeEditor = true } label: { Label("Themes…", systemImage: "paintpalette") }
                .buttonStyle(HeaderButtonStyle()).help("Create and edit themes")
            if let itemID = workspace.selectedPlaylistItemID, let item = workspace.playlistItems.first(where: { $0.id == itemID }) {
                Picker("Section order", selection: Binding(get: { item.arrangementID },
                                                           set: { id in Task { await workspace.setArrangement(id, forPlaylistItem: itemID) } })) {
                    Text("Natural order").tag(UUID?.none)
                    ForEach(workspace.arrangements) { Text($0.name).tag(UUID?.some($0.id)) }
                }.frame(maxWidth: 260)
            }
            Button { app.ui.showSectionOrders = true } label: { Label("Section orders…", systemImage: "list.number") }
                .buttonStyle(HeaderButtonStyle()).help("Section orders of the open song")
            Spacer()
            Button { if let id = workspace.openPresentationID { app.openImport(existing: id) } } label: {
                Label("Re-flow lyrics…", systemImage: "text.alignleft")
            }
            .buttonStyle(HeaderButtonStyle())
        }
        .padding(.horizontal, Space.s5).padding(.vertical, Space.s3)
    }

    private var status: some View {
        let editing = workspace.show.selectedIndex + 1
        let liveSame = app.show.liveDeck?.presentationID == workspace.openPresentationID
        return HStack(spacing: 6) {
            Image(systemName: "lock").foregroundStyle(Tok.muted)
            if liveSame, let live = app.show.liveIndex {
                Text("Slide \(live + 1) is live.").fontWeight(.semibold)
                Text("You are editing slide \(editing). Nothing on the screens changes until it is triggered again.").foregroundStyle(Tok.muted)
            } else {
                Text("Nothing from this song is live.").fontWeight(.semibold)
                Text("Editing changes the preview only.").foregroundStyle(Tok.muted)
            }
            Spacer()
        }
        .font(.system(size: 12)).lineLimit(1)
        .padding(.horizontal, Space.s5).frame(height: 30)
        .background(Tok.surface2)
    }
}

// MARK: Media

struct MediaModeView: View {
    let app: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                if let media = app.media {
                    MediaBinPanel(app: app, media: media).padding(Space.s5)
                } else {
                    Text("The media bin is not available.").foregroundStyle(Tok.muted).padding(Space.s5)
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                if let audio = app.audio { AudioPanel(audio: audio).padding(Space.s5) }
            }
            .frame(width: 380)
            .background(Tok.surface)
        }
    }
}

// MARK: Stage

struct StageModeView: View {
    let app: AppModel

    var body: some View {
        if let stage = app.stage {
            HStack(alignment: .top, spacing: 0) {
                StageEditorView(app: app, stage: stage)
                Divider()
                ScrollView { TimersPanel(app: app, stage: stage).padding(Space.s5) }
                    .frame(width: 330).background(Tok.surface)
            }
        } else {
            Text("Stage layouts are not available.").foregroundStyle(Tok.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Cues

struct CuesModeView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt").font(.system(size: 28)).foregroundStyle(Tok.muted)
            Text("Macros, slide actions and control surfaces arrive in a later version.")
                .font(.system(size: 15)).foregroundStyle(Tok.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Screens

struct ScreensModeView: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView { ScreensPanel(model: app).padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    LookPanel(model: app)
                    Divider()
                    PropsPanel(model: app)
                    Divider()
                    verification
                }
                .padding(Space.s5)
            }
            .frame(width: 380).background(Tok.surface)
        }
    }

    private var verification: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel("Verification")
            Text("Checks how your Blackmagic DeckLink card works with WORSHIPFLOW and makes one file to send back. Nothing here is Hardware Verified until the test has run on the real card.")
                .font(.caption).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            Button { openWindow(id: "hardware-test") } label: { Label("Run signal test…", systemImage: "waveform.path.ecg") }
                .buttonStyle(HeaderButtonStyle())
        }
    }
}
