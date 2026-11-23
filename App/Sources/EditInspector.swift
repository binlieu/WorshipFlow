// UI-005c: the Edit mode's inspector, 320 pt, drawn from docs/UI/mockups/02-editor.html: the tabs Object / Slide / Theme, then sections
// (`.sec`) of rows (`.fr`) in the design's fields. Object holds the selected object's controls; Slide holds the words fields and the slide
// actions the old header row had; Theme holds the presentation's theme control. Not built (feature missing, room kept): Fit, Background
// fill, the Layers list. See AI/reports/UI-005c-report.md.
import SwiftUI
import AppKit
import Domain
import OperatorCore

private typealias HorizontalAlign = Domain.TextAlignment

enum EditInspectorTab: Hashable { case object, slide, theme }

struct EditInspector: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @Bindable var editor: SlideEditorModel
    @State private var tab: EditInspectorTab = .object

    var body: some View {
        VStack(spacing: 0) {
            EditSection(first: true) {
                EditSegmented(items: [.init(value: .object, title: "Object", label: "Object"),
                                      .init(value: .slide, title: "Slide", label: "Slide"),
                                      .init(value: .theme, title: "Theme", label: "Theme")],
                              selection: $tab, accessibilityName: "Inspector tabs", rectID: "ed.insp.tabs", fill: true, sidePadding: 11)
            }
            ScrollView {
                VStack(spacing: 0) {
                    switch tab {
                    case .object: objectTab
                    case .slide: slideTab
                    case .theme: themeTab
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.leading, 1)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tok.surface)
        .overlay(alignment: .leading) { Rectangle().fill(Tok.border).frame(width: 1) }
        .wfRect("ed.insp")
        #if DEBUG || WF_MEASURE
        // The capture (EditDesignCapture.swift) switches tabs by notification; nothing else posts it.
        .onReceive(NotificationCenter.default.publisher(for: .init("wf.debug.editTab"))) { note in
            switch note.object as? String { case "slide": tab = .slide; case "theme": tab = .theme; default: tab = .object }
        }
        #endif
    }

    // MARK: Object tab

    @ViewBuilder private var objectTab: some View {
        if let box = editor.selectedLyricBox, let frame = editor.lyricFrame(box) {
            lyricSections(box, frame)
        } else if let o = editor.selectedObject {
            switch o.content {
            case .text(let t): textSections(o, t)
            case .shape(let s): shapeSections(o, s)
            case .image(let i): imageSections(o, i)
            case .video: EmptyView()        // SYS-015: stored only; the feature slice adds its sections
            }
            positionSection(o)
            EditSection {
                EditHeading(text: "Appearance")
                EditRow(label: "Opacity") {
                    WFSlider(value: Binding(get: { o.opacity }, set: { editor.setOpacity(o.id, $0) }), accessibilityName: "Opacity")
                    Text("\(Int((o.opacity * 100).rounded()))%").font(.wfMono(11)).foregroundStyle(Tok.muted).wfLine().frame(width: 36, alignment: .trailing)
                }
            }
        } else {
            EditSection {
                EditHeading(text: "No object selected")
                Text("Choose an object or a lyric box on the slide, or add an object with Text, Shape or Image in the bar above.")
                    .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Text object

    @ViewBuilder private func textSections(_ o: SlideObject, _ t: TextObject) -> some View {
        let id = o.id
        EditSection(rectID: "ed.insp.text") {
            EditHeading(text: "Text", rectID: "ed.insp.text.h")
            EditRow(label: "Font", rectID: "ed.insp.font") { fontField(id, t.style.fontName) }
            EditRow(label: "Style", rectID: "ed.insp.style") {
                EditPopup(title: Self.weightName(t.style.weight), accessibilityName: "Font style", rectID: "ed.insp.style.field") {
                    ForEach(Self.weights, id: \.value) { w in
                        Button(w.name) { editor.edit(id, key: "weight") { obj in if case .text(var tx) = obj.content { tx.style.weight = w.value; obj.content = .text(tx) } } }
                    }
                }
                EditNumberField(value: "\(Int(t.style.fontSize)) pt", label: "Font size", rectID: "ed.insp.size") { entry in
                    guard let v = Self.number(entry) else { return false }
                    editor.setFontSize(id, v); return true
                }
                .frame(width: 64)
            }
            EditRow(label: "Align", rectID: "ed.insp.alignrow") {
                EditSegmented(items: [.init(value: HorizontalAlign.leading, symbol: "text.alignleft", label: "Align left"),
                                      .init(value: .center, symbol: "text.aligncenter", label: "Align centre"),
                                      .init(value: .trailing, symbol: "text.alignright", label: "Align right")],
                              selection: Binding(get: { t.alignment }, set: { editor.setAlignment(id, $0) }),
                              accessibilityName: "Alignment", rectID: "ed.insp.align")
                EditSegmented(items: [.init(value: VerticalAlignment.top, title: "Top", label: "Align to the top"),
                                      .init(value: .center, title: "Mid", label: "Align to the middle"),
                                      .init(value: .bottom, title: "Bot", label: "Align to the bottom")],
                              selection: Binding(get: { t.verticalAlignment }, set: { editor.setVerticalAlignment(id, $0) }),
                              accessibilityName: "Vertical alignment", rectID: "ed.insp.valign", sidePadding: 6)
            }
            EditRow(label: "Colour", rectID: "ed.insp.colourrow") {
                EditSwatch(color: Color(t.style.color), label: "Text colour", rectID: "ed.insp.colour.sw") {
                    colourChoices(label: "Text colour", color: t.style.color) { editor.setTextColor(id, $0) }
                }
                EditNumberField(value: Self.hex(t.style.color), label: "Text colour, hex", rectID: "ed.insp.colour.hex") { entry in
                    guard let c = Self.colour(hex: entry) else { return false }
                    editor.setTextColor(id, c); return true
                }
            }
            EditRow { Color.clear }          // Fit (the design's "Shrink to fit box"): no fit mode in the model yet; its row is kept
        }
        EditSection(rectID: "ed.insp.effects") {
            EditHeading(text: "Effects", rectID: "ed.insp.effects.h")
            let shadow = t.style.shadow
            EditRow(rectID: "ed.insp.shadowrow") {
                EditCheckbox(isOn: Binding(get: { shadow != nil }, set: { on in editor.setShadow(id, on ? TextShadow(offsetX: 0, offsetY: 4, blur: 16) : nil) }),
                             title: "Shadow", rectID: "ed.insp.shadow.chk")
                Spacer(minLength: 0)
                let sh = shadow ?? TextShadow(offsetX: 0, offsetY: 4, blur: 16)
                EditSwatch(color: Color(sh.color), label: "Shadow colour", rectID: "ed.insp.shadow.sw") {
                    colourChoices(label: "Shadow colour", color: sh.color) { editor.setShadow(id, TextShadow(color: $0, offsetX: sh.offsetX, offsetY: sh.offsetY, blur: sh.blur)) }
                }
                .disabled(shadow == nil).opacity(shadow == nil ? 0.45 : 1)
                EditNumberField(value: "\(Self.trim(sh.offsetX)) · \(Self.trim(sh.offsetY)) · \(Self.trim(sh.blur))", label: "Shadow across, down and blur",
                                rectID: "ed.insp.shadow.field") { entry in
                    let parts = Self.numbers(entry)
                    guard parts.count == 3 else { return false }
                    editor.setShadow(id, TextShadow(color: sh.color, offsetX: parts[0], offsetY: parts[1], blur: parts[2])); return true
                }
                .frame(width: 96).disabled(shadow == nil).opacity(shadow == nil ? 0.45 : 1)
            }
            let outlined = t.style.outlineWidth > 0
            EditRow(rectID: "ed.insp.outlinerow") {
                EditCheckbox(isOn: Binding(get: { outlined }, set: { on in editor.setOutline(id, width: on ? 2 : 0) }), title: "Outline", rectID: "ed.insp.outline.chk")
                Spacer(minLength: 0)
                EditSwatch(color: Color(t.style.outlineColor), label: "Outline colour", rectID: "ed.insp.outline.sw") {
                    colourChoices(label: "Outline colour", color: t.style.outlineColor) { editor.setOutline(id, color: $0) }
                }
                .disabled(!outlined).opacity(outlined ? 1 : 0.45)
                EditNumberField(value: "\(Self.trim(t.style.outlineWidth > 0 ? t.style.outlineWidth : 2)) px", label: "Outline width", rectID: "ed.insp.outline.field") { entry in
                    guard let v = Self.number(entry) else { return false }
                    editor.setOutline(id, width: v); return true
                }
                .frame(width: 96).disabled(!outlined).opacity(outlined ? 1 : 0.45)
            }
            EditRow { Color.clear }          // Background fill: not in the model for text; its row is kept
        }
    }

    /// The font field: the family typed or chosen, in the design's field; a name that is not installed is drawn in the warning colour.
    private func fontField(_ id: UUID, _ name: String) -> some View {
        let installed = NSFont(name: name, size: 12) != nil
        return HStack(spacing: 6) {
            EditFontText(value: name, installed: installed) { editor.setFontName(id, $0) }
            Menu {
                ForEach(Self.families, id: \.self) { family in Button(family) { editor.setFontName(id, family) } }
            } label: {
                Image(systemName: "chevron.down").font(.wf(9, .semibold)).foregroundStyle(Tok.muted).frame(width: 12, height: 12)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Choose an installed font").accessibilityLabel("Installed fonts")
        }
        .wfField()
        .wfRect("ed.insp.font.field", size: 12, weight: 400, radius: Radius.md)
        .help(installed ? "" : "No font with that name is installed, so the default font is used.")
    }

    // MARK: Shape and image objects

    @ViewBuilder private func shapeSections(_ o: SlideObject, _ s: ShapeObject) -> some View {
        let id = o.id
        EditSection {
            EditHeading(text: "Shape")
            EditRow {
                EditCheckbox(isOn: Binding(get: { s.fill != nil }, set: { on in editor.setFill(id, on ? SlideEditing.defaultShapeFill : nil) }), title: "Fill")
                Spacer(minLength: 0)
                if let fill = s.fill {
                    EditSwatch(color: Color(fill), label: "Fill colour") { colourChoices(label: "Fill colour", color: fill) { editor.setFill(id, $0) } }
                }
            }
            let stroked = s.strokeColor != nil && s.strokeWidth > 0
            EditRow {
                EditCheckbox(isOn: Binding(get: { stroked }, set: { on in
                    if on { editor.setStrokeColor(id, s.strokeColor ?? .white); editor.setStrokeWidth(id, max(s.strokeWidth, 6)) } else { editor.setStrokeWidth(id, 0) }
                }), title: "Outline")
                Spacer(minLength: 0)
                if stroked {
                    EditSwatch(color: Color(s.strokeColor ?? .white), label: "Outline colour") {
                        colourChoices(label: "Outline colour", color: s.strokeColor ?? .white) { editor.setStrokeColor(id, $0) }
                    }
                    EditNumberField(value: "\(Self.trim(s.strokeWidth)) px", label: "Outline width") { entry in
                        guard let v = Self.number(entry) else { return false }
                        editor.setStrokeWidth(id, v); return true
                    }
                    .frame(width: 96)
                }
            }
            if case .roundedRectangle(let radius) = s.shape {
                EditRow(label: "Corners") {
                    WFSlider(value: Binding(get: { radius }, set: { editor.setCornerRadius(id, $0) }), range: 0...0.5, accessibilityName: "Corner radius")
                }
            }
        }
    }

    @ViewBuilder private func imageSections(_ o: SlideObject, _ i: ImageObject) -> some View {
        EditSection {
            EditHeading(text: "Image")
            Text(i.path).font(.wfMono(11)).foregroundStyle(Tok.muted).lineLimit(2).truncationMode(.middle).padding(.bottom, 6)
            if !FileManager.default.isReadableFile(atPath: i.path) {
                Text("That file cannot be read, so nothing is drawn. Delete this object and insert the image again.")
                    .font(.wf(12)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
            }
            EditRow(label: "Show") {
                EditPopup(title: i.contentMode == .fit ? "Fit (whole picture)" : "Fill (crop to the box)", accessibilityName: "Image mode") {
                    Button("Fit (whole picture)") { editor.setImageContentMode(o.id, .fit) }
                    Button("Fill (crop to the box)") { editor.setImageContentMode(o.id, .fill) }
                }
            }
        }
    }

    // MARK: Position (pixels of the 1920 x 1080 canvas)

    private func positionSection(_ o: SlideObject) -> some View {
        positionGrid(o.frame) { f in editor.setFrame(o.id, x: f.x, y: f.y, width: f.width, height: f.height) }
    }

    /// X, Y, W and H in pixels of the 1920 x 1080 frame; `commit` receives the whole new frame.
    private func positionGrid(_ frame: NormalizedRect, commit: @escaping (NormalizedRect) -> Void) -> some View {
        EditSection(rectID: "ed.insp.pos") {
            EditHeading(text: "Position", rectID: "ed.insp.pos.head")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                posField("X", frame, id: "x", label: "Left, in pixels", commit: commit) { Int(($0.x * 1920).rounded()) } set: { v, f in NormalizedRect(x: v / 1920, y: f.y, width: f.width, height: f.height) }
                posField("Y", frame, id: "y", label: "Top, in pixels", commit: commit) { Int(($0.y * 1080).rounded()) } set: { v, f in NormalizedRect(x: f.x, y: v / 1080, width: f.width, height: f.height) }
                posField("W", frame, id: "w", label: "Width, in pixels", commit: commit) { Int(($0.width * 1920).rounded()) } set: { v, f in NormalizedRect(x: f.x, y: f.y, width: v / 1920, height: f.height) }
                posField("H", frame, id: "h", label: "Height, in pixels", commit: commit) { Int(($0.height * 1080).rounded()) } set: { v, f in NormalizedRect(x: f.x, y: f.y, width: f.width, height: v / 1080) }
            }
            .wfRect("ed.insp.pos.grid")
        }
    }

    private func posField(_ prefix: String, _ frame: NormalizedRect, id: String, label: String, commit: @escaping (NormalizedRect) -> Void,
                          get: (NormalizedRect) -> Int, set: @escaping (Double, NormalizedRect) -> NormalizedRect) -> some View {
        EditNumberField(value: "\(get(frame))", prefix: prefix, label: label, rectID: "ed.insp.pos.\(id)") { entry in
            guard let v = Self.number(entry) else { return false }
            commit(set(v, frame))
            return true
        }
    }

    // MARK: A lyric box (FIX-K)

    @ViewBuilder private func lyricSections(_ box: LyricBox, _ frame: NormalizedRect) -> some View {
        EditSection {
            EditHeading(text: "Lyric box — \(box.title.lowercased())")
            Text(editor.hasOwnFrame(box)
                 ? "This slide has its own position for these words. Other slides still use the theme's."
                 : "These words use the theme's position. Moving or resizing the box gives this slide its own.")
                .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
        }
        positionGrid(frame) { f in editor.setLyricFrame(box, x: f.x, y: f.y, width: f.width, height: f.height) }
        EditSection {
            EditRow {
                Button("Reset to theme position") { editor.resetLyricFrame(box) }
                    .buttonStyle(HeaderButtonStyle()).disabled(!editor.hasOwnFrame(box))
                    .help("Give these words back the theme's place on this slide").accessibilityLabel("Reset to theme position")
            }
            EditRow {
                Button("Apply to all slides in this song") { app.ui.applyLyricToAll = box }      // FIX-N item 7: asks first
                    .buttonStyle(HeaderButtonStyle())
                    .help("Every slide of this song takes this position for \(box.title.lowercased()) words. One undo step").accessibilityLabel("Apply to all slides in this song")
            }
        }
    }

    // MARK: Slide tab: the words and the slide's actions

    @ViewBuilder private var slideTab: some View {
        let index = workspace.showParts.selectedIndex
        if workspace.slides.indices.contains(index) {
            let slide = workspace.slides[index]
            EditSection {
                EditHeading(text: "Words — slide \(index + 1) of \(workspace.slides.count)")
                VStack(alignment: .leading, spacing: 10) {
                    WordsEditorField(label: "First language", text: Binding(
                        get: { slide.content.primary },
                        set: { new in var c = slide.content; c.primary = new; workspace.editSlide(id: slide.id, content: c) }), minHeight: 64)
                    WordsEditorField(label: "Second language", text: Binding(
                        get: { slide.content.secondary ?? "" },
                        set: { new in var c = slide.content; c.secondary = new.isEmpty ? nil : new; workspace.editSlide(id: slide.id, content: c) }), minHeight: 64)
                    WordsEditorField(label: "Speaker notes — stage screens only", text: Binding(
                        get: { slide.notes },
                        set: { workspace.editSlide(id: slide.id, content: slide.content, notes: $0) }), minHeight: 64)
                }
                Text("Editing here changes the preview only. The audience sees the change when you go live again.")
                    .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }
        EditSection {
            EditHeading(text: "Slide")
            VStack(alignment: .leading, spacing: 8) {
                HeaderControlButton(control: .addSlide, symbol: "plus", compact: false) { Task { await workspace.addSlide(SlideContent(primary: "")) } }
                HeaderControlButton(control: .reflow, symbol: "text.alignleft", compact: false) {
                    if let id = workspace.openPresentationID { app.openImport(existing: id) }
                }
                HeaderControlButton(control: .editLiveSlide, symbol: "pencil.and.outline", compact: false) { app.requestLiveQuickEdit() }
                    .disabled(workspace.showParts.liveSlide == nil)
            }
        }
        if let itemID = workspace.selectedPlaylistItemID, let item = workspace.playlistItems.first(where: { $0.id == itemID }), item.kind.hasSlides {
            EditSection {
                EditHeading(text: "Section order")
                WFPopup(title: workspace.arrangements.first { $0.id == item.arrangementID }?.name ?? "Natural order", accessibilityName: "Section order") {
                    Button("Natural order") { Task { await workspace.setArrangement(nil, forPlaylistItem: itemID) } }
                    ForEach(workspace.arrangements) { a in Button(a.name) { Task { await workspace.setArrangement(a.id, forPlaylistItem: itemID) } } }
                }
                .padding(.bottom, 8)
                HeaderControlButton(control: .sectionOrders, symbol: "list.number", compact: false) { app.ui.showSectionOrders = true }
            }
        }
    }

    // MARK: Theme tab

    @ViewBuilder private var themeTab: some View {
        EditSection {
            EditHeading(text: "Theme of this song")
            WFPopup(title: workspace.openThemeID.flatMap { id in app.themes.first { $0.id == id }?.name } ?? "Default", accessibilityName: "Theme") {
                Button("Default") { setTheme(nil) }
                ForEach(app.themes) { theme in Button(theme.name) { setTheme(theme.id) } }
            }
            .help("The look of this song on the audience screen")
            .padding(.bottom, 8)
            HeaderControlButton(control: .themes, symbol: "paintpalette", compact: false) { app.ui.showThemeEditor = true }
        }
    }

    private func setTheme(_ id: UUID?) {
        if let open = workspace.openPresentationID { app.setPresentationTheme(id, forPresentation: open) }
    }

    // MARK: Colour choices (the popover of a swatch)

    /// The six preset colours the old inspector offered and the system colour panel, in one popover.
    private func colourChoices(label: String, color: ColorRGBA, set: @escaping (ColorRGBA) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Self.swatches, id: \.name) { swatch in
                    Button { set(swatch.color) } label: {
                        RoundedRectangle(cornerRadius: 5).fill(Color(swatch.color)).frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color == swatch.color ? Tok.blue : Tok.borderStrong, lineWidth: color == swatch.color ? 2 : 1))
                    }
                    .buttonStyle(.plain).help(swatch.name).accessibilityLabel("\(label) \(swatch.name)")
                }
            }
            ColorPicker("Custom", selection: Binding(get: { Color(color) }, set: { set($0.rgba) })).accessibilityLabel("\(label) custom")
        }
    }

    // MARK: Values

    private static let swatches: [(name: String, color: ColorRGBA)] = [
        ("Blue", ColorRGBA(red: 0.2, green: 0.5, blue: 0.95)), ("Red", ColorRGBA(red: 0.9, green: 0.2, blue: 0.2)),
        ("Green", ColorRGBA(red: 0.2, green: 0.7, blue: 0.3)), ("Gold", ColorRGBA(red: 0.95, green: 0.75, blue: 0.2)),
        ("White", .white), ("Black", .black),
    ]

    /// The faces of the Style pop-up: CSS weights. A text object with no weight is the font's regular face.
    static let weights: [(name: String, value: Int?)] = [("Light", 300), ("Regular", nil), ("Medium", 500), ("Semibold", 600), ("Bold", 700), ("Heavy", 800)]
    static func weightName(_ weight: Int?) -> String {
        guard let weight else { return "Regular" }
        return weights.min { abs(($0.value ?? 400) - weight) < abs(($1.value ?? 400) - weight) }?.name ?? "Regular"
    }

    static let families: [String] = NSFontManager.shared.availableFontFamilies

    static func hex(_ c: ColorRGBA) -> String {
        String(format: "#%02X%02X%02X", Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
    }
    static func colour(hex text: String) -> ColorRGBA? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return ColorRGBA(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    static func trim(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }
    /// The first number in `text` ("72 pt", "2 px", "230").
    static func number(_ text: String) -> Double? { numbers(text).first }
    /// Every number in `text`, however they are separated ("0 · 4 · 16", "0, 4, 16", "0 4 16").
    static func numbers(_ text: String) -> [Double] {
        text.split(whereSeparator: { !("0123456789.-".contains($0)) }).compactMap { Double($0) }
    }
}

/// The text of the font field: plain text in the field chrome that commits on Return or when it loses focus.
private struct EditFontText: View {
    let value: String
    let installed: Bool
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text).textFieldStyle(.plain).font(.wf(12))
            .foregroundStyle(installed ? Tok.text : Tok.warning)
            .focused($focused)
            .onSubmit { apply() }
            .onChange(of: focused) { _, now in if !now { apply() } }
            .onAppear { text = value }
            .onChange(of: value) { _, new in if !focused { text = new } }
            .accessibilityLabel("Font")
            .accessibilityValue(installed ? value : "\(value), not installed")
    }

    private func apply() { if text != value, !text.trimmingCharacters(in: .whitespaces).isEmpty { commit(text) } else { text = value } }
}
