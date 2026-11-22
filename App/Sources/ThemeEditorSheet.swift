// APP-001 / KI-023 / PRES-06: the theme editor. Built-in themes are read-only; duplicate one to change it.
// Every change is saved at once, and the thumbnail is drawn by the same compositor the screens use.
import SwiftUI
import AppKit
import Domain
import OperatorCore

struct ThemeEditorSheet: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var nameText = ""
    @State private var pendingDelete = false

    private var selected: Theme? { app.themes.first { $0.id == selectedID } }
    private var isCustom: Bool { app.customThemes.contains { $0.id == selectedID } }
    private var openTitle: String? {
        workspace.presentations.first { $0.id == workspace.openPresentationID }?.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = workspace.lastError ?? app.settingsError {
                ErrorBar(message: error) { workspace.dismissError(); app.dismissSettingsError() }
            }
            HStack {
                Text("Themes").font(.wf(15, .bold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 16) {
                themeList.frame(width: 220)
                Divider()
                if let theme = selected {
                    ScrollView { editor(theme).padding(.trailing, 8) }
                } else {
                    Text("Choose a theme, or make a new one.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(18)
        .frame(width: 900, height: 700)
        .onAppear {
            selectedID = workspace.openThemeID ?? selectedID ?? app.themes.first?.id
            nameText = selected?.name ?? ""
        }
        .onChange(of: selectedID) { _, _ in nameText = selected?.name ?? "" }
        .confirmationDialog("Delete the theme \"\(selected?.name ?? "")\"?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Delete theme", role: .destructive) {
                if let id = selectedID {
                    app.deleteTheme(id)
                    selectedID = Theme.fullScreenID
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Songs and screens that used it go back to the default theme.") }
    }

    // MARK: List

    private var themeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $selectedID) {
                Section("Built in") {
                    ForEach(Theme.builtIn) { Text($0.name).tag($0.id) }
                }
                Section("Yours") {
                    ForEach(app.customThemes) { Text($0.name).tag($0.id) }
                    if app.customThemes.isEmpty {
                        Text("None yet").font(.wfSmall).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityLabel("Themes")
            HStack {
                Button("New") { if let made = app.createTheme(name: nextName("My theme")) { selectedID = made.id } }
                    .help("A new theme that starts as a copy of Full screen")
                Button("Duplicate") {
                    if let id = selectedID, let made = app.duplicateTheme(id) { selectedID = made.id }
                }.disabled(selected == nil)
                Button("Delete…", role: .destructive) { pendingDelete = true }.disabled(!isCustom)
            }
        }
    }

    private func nextName(_ base: String) -> String {
        let used = Set(app.themes.map { $0.name.lowercased() })
        if !used.contains(base.lowercased()) { return base }
        var n = 2
        while used.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Editor

    @ViewBuilder private func editor(_ theme: Theme) -> some View {
        let id = theme.id
        VStack(alignment: .leading, spacing: 14) {
            ScenePreview(scene: ThemeEditing.previewScene(for: theme), width: 480, cached: false)
                .frame(maxWidth: 480)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                .accessibilityHidden(true)
            Text("Preview with sample words. A video background shows as its fallback colour here.")
                .font(.wfSmall).foregroundStyle(.secondary)

            if isCustom {
                HStack {
                    Text("Name").font(.wfSmall).foregroundStyle(.secondary)
                    TextField("Name", text: $nameText).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        .onSubmit { commitName(id) }
                    Button("Rename") { commitName(id) }.disabled(nameText == theme.name)
                }
                backgroundEditor(theme)
                BlockEditor(app: app, themeID: id, isPrimary: true, title: "First language", block: theme.primary)
                secondEditor(theme)
                Toggle("Shrink the words to fit their boxes", isOn: Binding(get: { theme.fitsText }, set: { on in app.updateTheme(id) { $0.fitsText = on } }))
                    .toggleStyle(.wfCheckbox)
                    .help("When the words of a slide are bigger than the boxes above, both languages get smaller together, down to 56 pixels on a 1080-line screen.")
            } else {
                Text("\"\(theme.name)\" is built in and cannot be changed. Duplicate it to make your own version.")
                    .font(.wfCallout)
            }
            if let title = openTitle {
                Button("Use for \"\(title)\"") { if let open = workspace.openPresentationID { app.setPresentationTheme(id, forPresentation: open) } }
                    .disabled(workspace.openThemeID == id)
                if workspace.openThemeID == id { Text("This song uses this theme.").font(.wfSmall).foregroundStyle(.secondary) }
            }
        }
    }

    private func commitName(_ id: UUID) {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        app.renameTheme(id, to: trimmed)
        nameText = app.themes.first { $0.id == id }?.name ?? nameText
    }

    // MARK: Background

    private enum BackgroundKind: String, CaseIterable, Identifiable {
        case media = "Background video", color = "Colour", image = "Image", gradient = "Gradient", transparent = "Transparent"
        var id: String { rawValue }
    }

    private func kind(of background: ThemeBackground) -> BackgroundKind {
        switch background {
        case .media: .media
        case .color: .color
        case .image: .image
        case .gradient: .gradient
        case .transparent: .transparent
        }
    }

    private func backgroundEditor(_ theme: Theme) -> some View {
        let id = theme.id
        return VStack(alignment: .leading, spacing: 8) {
            Text("Background").font(.wfHeadline)
            Picker("Background", selection: Binding(get: { kind(of: theme.background) }, set: { new in
                app.updateTheme(id) { t in
                    switch new {
                    case .media: t.background = .media
                    case .color:
                        if case .color = t.background {} else { t.background = .color(Theme.mediaFallbackColor) }
                    case .image:
                        if case .image = t.background {} else { t.background = .image(path: "") }
                    case .gradient:
                        if case .gradient = t.background {} else { t.background = .gradient(Theme.designGradient) }
                    case .transparent: t.background = .transparent
                    }
                }
            })) {
                ForEach(BackgroundKind.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().fixedSize()      // KI-028: sized to its labels, so "Background video" is not clipped
            switch theme.background {
            case .color(let c):
                ColorPicker("Colour", selection: Binding(get: { Color(c) }, set: { new in
                    app.updateTheme(id) { $0.background = .color(new.rgba) }
                })).frame(maxWidth: 240)
            case .image(let path):
                HStack {
                    TextField("Image file path", text: Binding(get: { path }, set: { new in
                        app.updateTheme(id) { $0.background = .image(path: new) }
                    })).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Button("Choose…") { chooseImage(for: id) }
                }
                if !path.isEmpty, !FileManager.default.isReadableFile(atPath: path) {
                    Text("That file cannot be read. The screen shows black behind the words.")
                        .font(.wfSmall).foregroundStyle(.orange)
                }
            case .gradient:
                Text("The design's radial gradient, teal into navy. A background chosen in the media bin or on a slide covers it. Its colours are not editable yet.")
                    .font(.wfSmall).foregroundStyle(.secondary)
            case .media:
                Text("The looping background video chosen in the Background video panel.").font(.wfSmall).foregroundStyle(.secondary)
            case .transparent:
                Text("Nothing behind the words. For a broadcast overlay.").font(.wfSmall).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseImage(for id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a background image for the theme"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { app.updateTheme(id) { $0.background = .image(path: url.path) } }
        }
    }

    // MARK: Second language

    @ViewBuilder private func secondEditor(_ theme: Theme) -> some View {
        let id = theme.id
        Toggle("Show a second language", isOn: Binding(get: { theme.secondary != nil }, set: { on in
            app.updateTheme(id) { t in
                if on { t.secondary = t.secondary ?? Theme.fullScreen.secondary ?? t.primary } else { t.secondary = nil }
            }
        })).toggleStyle(.wfCheckbox)
        if let second = theme.secondary {
            BlockEditor(app: app, themeID: id, isPrimary: false, title: "Second language", block: second)
        }
    }
}

/// Font, size, colour, outline, frame and alignment of one language's text.
private struct BlockEditor: View {
    let app: AppModel
    let themeID: UUID
    let isPrimary: Bool
    let title: String
    /// The block as it is now, so the controls redraw when it changes.
    let block: TextBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.wfHeadline)
            HStack {
                TextField("Font", text: binding(\.style.fontName)).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    .accessibilityLabel("\(title) font")
                number("Size", binding(\.style.fontSize), width: 64)
                ColorPicker("Text colour", selection: colorBinding(\.style.color)).labelsHidden()
                    .accessibilityLabel("\(title) text colour")
            }
            if NSFont(name: block.style.fontName, size: 12) == nil {
                Text("No font with that name is installed, so the default font is used. Use a name such as \"Helvetica Neue\" or \"Georgia-Bold\".")
                    .font(.wfSmall).foregroundStyle(.orange)
            }
            HStack {
                number("Outline", binding(\.style.outlineWidth), width: 56)
                ColorPicker("Outline colour", selection: colorBinding(\.style.outlineColor)).labelsHidden()
                    .accessibilityLabel("\(title) outline colour")
                Text("Size and outline are in points on a 1080-line screen.").font(.wfSmall).foregroundStyle(.secondary)
            }
            HStack {
                Text("Frame (0 to 1 of the screen)").font(.wfSmall).foregroundStyle(.secondary)
                number("Left", binding(\.frame.x), width: 56)
                number("Top", binding(\.frame.y), width: 56)
                number("Width", binding(\.frame.width), width: 56)
                number("Height", binding(\.frame.height), width: 56)
            }
            HStack {
                Picker("Across", selection: binding(\.alignment)) {
                    Text("Left").tag(OperatorCoreAlignment.leading)
                    Text("Centre").tag(OperatorCoreAlignment.center)
                    Text("Right").tag(OperatorCoreAlignment.trailing)
                }.frame(maxWidth: 200).accessibilityLabel("\(title) alignment")
                Picker("Down", selection: binding(\.verticalAlignment)) {
                    Text("Top").tag(VerticalAlignment.top)
                    Text("Middle").tag(VerticalAlignment.center)
                    Text("Bottom").tag(VerticalAlignment.bottom)
                }.frame(maxWidth: 200).accessibilityLabel("\(title) vertical alignment")
            }
        }
    }

    private func number(_ label: String, _ value: Binding<Double>, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.wfSmall)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder).frame(width: width)
                .accessibilityLabel("\(title) \(label.lowercased())")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TextBlock, T>) -> Binding<T> {
        Binding(get: { block[keyPath: keyPath] }, set: { new in
            app.updateTheme(themeID) { theme in
                if isPrimary { theme.primary[keyPath: keyPath] = new } else { theme.secondary?[keyPath: keyPath] = new }
            }
        })
    }

    private func colorBinding(_ keyPath: WritableKeyPath<TextBlock, ColorRGBA>) -> Binding<Color> {
        Binding(get: { Color(block[keyPath: keyPath]) }, set: { new in
            app.updateTheme(themeID) { theme in
                if isPrimary { theme.primary[keyPath: keyPath] = new.rgba } else { theme.secondary?[keyPath: keyPath] = new.rgba }
            }
        })
    }
}

private typealias OperatorCoreAlignment = Domain.TextAlignment

extension Color {
    init(_ c: ColorRGBA) { self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha) }

    /// The colour as non-premultiplied sRGB, as the compositor expects.
    var rgba: ColorRGBA {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return ColorRGBA(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                         blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }
}
