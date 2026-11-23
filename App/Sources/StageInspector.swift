// UI-005e: the Stage mode's right column, as `04-stage.png` draws it: the selected element's settings (Shows, Size, Weight, Colour), the
// element list, and the stage screens that use the layout. UI-006e added Auto-fit, the second-language colour and the per-element eye; the
// Section element is still left out (no section name reaches the stage). The owner's extras that the design has no row for (alignment, position and size in percent,
// delete) follow the designed sections, so none of them moves. Every change goes through `StageModel` and is refused for the built-in layout.
import SwiftUI
import AppKit
import Domain
import OperatorCore

struct StageInspector: View {
    let app: AppModel
    @Bindable var stage: StageModel
    let layout: StageLayout
    let editable: Bool
    @Binding var elementID: UUID?
    let layoutID: UUID

    private var element: StageElement? { layout.elements.first { $0.id == elementID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                elementSection
                Rectangle().fill(Tok.border).frame(height: 1)
                elementsSection
                Rectangle().fill(Tok.border).frame(height: 1)
                assignedSection
                if let e = element {
                    Rectangle().fill(Tok.border).frame(height: 1)
                    extras(e)
                }
            }
        }
        .background(Tok.surface)
    }

    // MARK: Element

    private func row<Content: View>(_ label: String, rectID: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.wf(12)).foregroundStyle(Tok.muted).wfLine().frame(width: 70, alignment: .trailing).wfRect("\(rectID).label", size: 12, weight: 400)
            content()
        }
        .frame(minHeight: 30)
    }

    private var elementSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Element — \(element.map { StageElementNames.title(of: $0, in: stage).lowercased() } ?? "none")", rectID: "st.insp.h")
            if let e = element {
                VStack(spacing: 0) {
                    row("Shows", rectID: "st.insp.shows") { showsControl(e) }
                    row("Size", rectID: "st.insp.size") { sizeControl(e) }
                    row("Weight", rectID: "st.insp.weight") { weightControl(e) }
                    row("Colour", rectID: "st.insp.colour") { colourControl(e) }
                    row("2nd lang.", rectID: "st.insp.second") { secondLanguageControl(e) }      // UI-006e
                    if StageAutoFit.isBelowLyricMinimum(e) {
                        // UI-006e: the design's caption names a 64 px minimum lyric size; this says so only when the layout is below it.
                        Text("Below the \(Int(StageAutoFit.lyricMinimum)) px minimum for lyrics at 1080p: hard to read from the back of the room.")
                            .font(.wf(11)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                }
            } else {
                Text(editable ? "Choose an element on the canvas, or add one." : "Choose an element to see its settings.")
                    .font(.wf(12)).foregroundStyle(Tok.muted).frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .disabled(!editable)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func showsControl(_ e: StageElement) -> some View {
        switch e.kind {
        case .currentSlide, .nextSlide:
            WFPopup(title: e.showsSecondLanguage ? "Both languages" : "First language only", accessibilityName: "Languages shown", rectID: "st.insp.shows") {
                Button("Both languages") { stage.setShowsSecondLanguage(true, for: e.id, in: layoutID) }
                Button("First language only") { stage.setShowsSecondLanguage(false, for: e.id, in: layoutID) }
            }
        case .timer(let current):
            WFPopup(title: stage.timers.first { $0.id == current }?.name ?? "(deleted timer)", accessibilityName: "Timer shown", rectID: "st.insp.shows") {
                ForEach(stage.timers) { t in Button(t.name) { stage.setTimer(t.id, for: e.id, in: layoutID) } }
            }
        default:
            Text(Self.shown(by: e.kind)).font(.wf(12)).foregroundStyle(Tok.muted).wfLine().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func shown(by kind: StageElement.Kind) -> String {
        switch kind {
        case .timeOfDay: "Time of day"
        case .message: "The stage message"
        case .notes: "Speaker notes"
        case .firstCountdown: "First countdown timer"
        default: ""
        }
    }

    /// The design's Size row: the size field (its stepper sits inside the field, at the right) and the Auto-fit checkbox. UI-006e.
    private func sizeControl(_ e: StageElement) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                TextField("Font size", value: Binding(get: { e.style.fontSize }, set: { stage.setFontSize($0, for: e.id, in: layoutID) }),
                          format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.plain).font(.wfMono(11)).accessibilityLabel("Font size")
                Text("px").font(.wfMono(11)).foregroundStyle(Tok.muted)
                Stepper("Font size", value: Binding(get: { e.style.fontSize }, set: { stage.setFontSize($0, for: e.id, in: layoutID) }),
                        in: StageEditing.fontSizeRange, step: 4).labelsHidden().accessibilityLabel("Font size step")
                    .scaleEffect(0.8).frame(width: 14)
            }
            .wfField().frame(width: 120.5).wfRect("st.insp.size", size: 11, weight: 400, radius: Radius.md)
            Toggle(isOn: Binding(get: { e.autoFit }, set: { stage.setAutoFit($0, for: e.id, in: layoutID) })) {
                Text("Auto-fit").font(.wf(12)).foregroundStyle(Tok.text).wfLine()
            }
            .toggleStyle(.wfCheckbox).fixedSize()
            .help("Shrink the text until it fits the box. The lyric stops at \(Int(StageAutoFit.lyricMinimum)) px at 1080p; other text at half its size. Elements with Auto-fit shrink together.")
            .accessibilityLabel("Auto-fit")
            .wfRect("st.insp.autofit", size: 12, weight: 400)
            Spacer(minLength: 0)
        }
    }

    /// UI-006e: the colour of the second-language line, for an element that draws it as its own line.
    @ViewBuilder private func secondLanguageControl(_ e: StageElement) -> some View {
        if let second = e.secondLanguage {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(Color(second.style.color)).frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tok.borderStrong, lineWidth: 1))
                    .overlay {
                        ColorPicker("Second language colour", selection: Binding(get: { Color(second.style.color) },
                                                                                set: { stage.setSecondLanguageColor($0.rgba, for: e.id, in: layoutID) }))
                            .labelsHidden().opacity(0.015).accessibilityLabel("Second language colour")
                    }
                    .wfRect("st.insp.second.swatch", radius: 5)
                HexField(color: second.style.color, label: "Second language colour as hex") { stage.setSecondLanguageColor($0, for: e.id, in: layoutID) }
                    .wfRect("st.insp.second.hex", size: 11, weight: 400, radius: Radius.md)
            }
        } else if e.kind == .currentSlide {
            Text("Same colour as the first language").font(.wf(12)).foregroundStyle(Tok.muted).wfLine().frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: 30)
        }
    }

    private static let weights: [(String, Int)] = [("Regular", 400), ("Medium", 500), ("Semibold", 600), ("Bold", 700), ("Heavy", 800)]

    private func weightControl(_ e: StageElement) -> some View {
        let current = e.style.weight ?? 400
        let name = Self.weights.first { $0.1 == current }?.0 ?? "Weight \(current)"
        return WFPopup(title: name, accessibilityName: "Weight", rectID: "st.insp.weight") {
            ForEach(Self.weights, id: \.1) { item in
                Button(item.0) { stage.updateElement(e.id, in: layoutID) { $0.style.weight = item.1 } }
            }
        }
    }

    private func colourControl(_ e: StageElement) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5).fill(Color(e.style.color)).frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tok.borderStrong, lineWidth: 1))
                .overlay {
                    ColorPicker("Colour", selection: Binding(get: { Color(e.style.color) }, set: { stage.setColor($0.rgba, for: e.id, in: layoutID) }))
                        .labelsHidden().opacity(0.015).accessibilityLabel("Colour")
                }
                .wfRect("st.insp.colour.swatch", radius: 5)
            HexField(color: e.style.color) { stage.setColor($0, for: e.id, in: layoutID) }
                .wfRect("st.insp.colour.hex", size: 11, weight: 400, radius: Radius.md)
        }
    }

    // MARK: Elements

    private var elementsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Elements", rectID: "st.insp.elements.h")
            VStack(spacing: 0) {
                ForEach(Array(layout.elements.enumerated()), id: \.element.id) { index, e in
                    let selected = e.id == elementID
                    HStack(spacing: 0) {
                        Button { elementID = e.id } label: {
                            HStack(spacing: 8) {
                                Image(systemName: StageElementNames.symbol(of: e)).font(.wf(12)).foregroundStyle(Tok.text).frame(width: 15, height: 15)
                                Text(StageElementNames.title(of: e, in: stage)).font(.wf(13)).lineLimit(1).wfLine()
                                Spacer(minLength: 0)
                            }
                            .opacity(e.isHidden ? 0.45 : 1)
                            .padding(.leading, 8).frame(height: 26).frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(StageElementNames.title(of: e, in: stage) + (e.isHidden ? ", hidden" : ""))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        eyeButton(e, index: index)
                    }
                    .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                    .wfRect("st.insp.el.\(index)", size: 13, weight: 400, radius: Radius.md)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// UI-006e: the eye at the right of an element's row: hides the element on the stage screens without removing it. Not drawn as a button when the
    /// layout is the built-in one (nothing to change there); the row is still selectable.
    private func eyeButton(_ e: StageElement, index: Int) -> some View {
        Button { stage.setHidden(!e.isHidden, for: e.id, in: layoutID) } label: {
            Image(systemName: e.isHidden ? "eye.slash" : "eye").font(.wf(11)).foregroundStyle(e.isHidden ? Tok.muted : Tok.text)
                .frame(width: 26, height: 26).contentShape(Rectangle())
                .wfFocusReport(.button)
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .opacity(editable ? 1 : 0.5)
        .help(editable ? (e.isHidden ? "Show this element on the stage screens" : "Hide this element on the stage screens") : StageModel.readOnlyMessage)
        .accessibilityLabel(e.isHidden ? "Show \(StageElementNames.title(of: e, in: stage))" : "Hide \(StageElementNames.title(of: e, in: stage))")
        .wfRect("st.insp.el.\(index).eye")
    }

    // MARK: Assigned to

    private var assignedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Assigned to", rectID: "st.insp.assigned.h").padding(.bottom, 6)
            let screens = app.profiles.filter { $0.role == .stage }
            ForEach(Array(screens.enumerated()), id: \.element.id) { index, p in
                HStack(spacing: 8) {
                    Circle().fill(Tok.roleStage).frame(width: 8, height: 8).wfRect("st.insp.screen.\(index).dot")
                    Text("\(p.name) · \(app.destinationName(p.destination))").font(.wf(13)).lineLimit(1).wfLine()
                    Spacer(minLength: 0)
                    Toggle("Use this layout on \(p.name)", isOn: Binding(get: { stage.layoutID(forScreen: p.id) == layoutID },
                                                                         set: { stage.setLayout($0 ? layoutID : nil, forScreen: p.id) }))
                        .toggleStyle(.wfBare).labelsHidden().wfRect("st.insp.screen.\(index).toggle")
                }
                .frame(height: 26).wfRect("st.insp.screen.\(index)")
            }
            if screens.isEmpty {
                Text("There is no stage screen yet. Add one in Screens.").font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            }
            Text("Speaker notes and stage messages never appear on Audience or Broadcast screens. Themes, Looks and props do not apply to stage layouts.")
                .font(.wf(11)).foregroundStyle(Tok.muted).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                .wfRect("st.insp.note", size: 11, weight: 400).padding(.top, 8)
            if !editable {
                Text("This is the built-in layout. Duplicate it (left, under the list) to change it.")
                    .font(.wf(11)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Extras

    private func extras(_ e: StageElement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Position and size")
            Picker("Alignment", selection: Binding(get: { e.alignment }, set: { stage.setAlignment($0, for: e.id, in: layoutID) })) {
                Text("Left").tag(Domain.TextAlignment.leading)
                Text("Centre").tag(Domain.TextAlignment.center)
                Text("Right").tag(Domain.TextAlignment.trailing)
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Alignment")
            Text("In percent of the screen").font(.wf(11)).foregroundStyle(Tok.muted)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow { percent("Left", e, \.x); percent("Top", e, \.y) }
                GridRow { percent("Width", e, \.width); percent("Height", e, \.height) }
            }
            Button("Delete element") {      // FIX-V: not drawn red (red is only for on air)
                stage.removeElement(e.id, from: layoutID)
                elementID = nil
            }
            .buttonStyle(HeaderButtonStyle())
        }
        .disabled(!editable)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func percent(_ label: String, _ e: StageElement, _ keyPath: WritableKeyPath<NormalizedRect, Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.wf(11)).foregroundStyle(Tok.muted).frame(width: 40, alignment: .leading)
            TextField(label, value: Binding(get: { e.frame[keyPath: keyPath] * 100 }, set: { value in
                var f = e.frame
                f[keyPath: keyPath] = value / 100
                stage.setFrame(e.id, in: layoutID, x: f.x, y: f.y, width: f.width, height: f.height)
            }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.plain).font(.wfMono(11)).wfField(height: 22).frame(width: 58)
                .accessibilityLabel("\(label) percent")
        }
    }
}

/// A `#RRGGBB` field in the design's mono look; it applies when the text is a valid colour and goes back to the colour's own text otherwise.
private struct HexField: View {
    let color: ColorRGBA
    var label = "Colour as hex"
    let apply: (ColorRGBA) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var current: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }

    var body: some View {
        TextField("", text: $text).textFieldStyle(.plain).font(.wfMono(11)).focused($focused)
            .wfField()
            .onAppear { text = current }
            .onChange(of: color) { _, _ in if !focused { text = current } }
            .onSubmit(commit)
            .onChange(of: focused) { _, now in if !now { commit() } }
            .accessibilityLabel(label)
    }

    private func commit() {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6, let v = UInt32(s, radix: 16) {
            let new = ColorRGBA(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, alpha: color.alpha)
            if new != color { apply(new) }
        }
        text = current
    }
}
