// FIX-H item 10 (UI-005b): a role pill on a prop is a toggle (off is drawn dimmed and stays; on again with another click), a new text
// prop is saved switched off with the sheet saying so, and a text prop with no screen chosen is refused with a line saying why.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXH_PropPillsTests {
    func loaded() async throws -> (SettingsModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let settings = SettingsModel(store: store, legacy: nil, defaultProfiles: SettingsModelTests.defaults)
        await settings.load()
        return (settings, store)
    }
    let logo = Prop(name: "Church logo bug", imagePath: "/p/logo.png", frame: NormalizedRect(x: 0.85, y: 0.05, width: 0.1, height: 0.1))

    @Test func everyRoleHasAPillAndOffOnesStayInTheRow() {
        let pills = PropPills.pills(for: logo)
        #expect(pills.map(\.role) == [.audience, .stage, .broadcast])
        #expect(pills.map(\.isOn) == [true, false, true])
        #expect(pills.map(\.label) == ["AUD", "STG", "BRD"])
        #expect(pills.map(\.isDimmed) == [false, true, false])
    }

    @Test func aClickTurnsTheRoleOffAndAnotherClickTurnsItBackOn() async throws {
        let (settings, store) = try await loaded()
        settings.addProp(logo, bookmark: nil)
        settings.togglePropTarget(logo.id, role: .audience)
        #expect(settings.props.first?.targets == [.broadcast])
        #expect(PropPills.pills(for: settings.props[0]).first?.isDimmed == true)             // still in the row, dimmed
        settings.togglePropTarget(logo.id, role: .audience)
        #expect(settings.props.first?.targets == [.audience, .broadcast])
        settings.togglePropTarget(logo.id, role: .stage)                                       // a dimmed pill turns on too
        #expect(settings.props.first?.targets == [.audience, .stage, .broadcast])
        await settings.flush()
        #expect(try await store.props().first?.targets == [.audience, .stage, .broadcast])
    }

    @Test func aNewTextPropIsSavedSwitchedOff() async throws {
        let (settings, store) = try await loaded()
        let prop = try #require(settings.addTextProp(name: "Strap", spec: TextPropSpec(text: "Sunday"), targets: [.broadcast]))
        #expect(!prop.isOn && settings.props.first?.isOn == false)
        await settings.flush()
        #expect(try await store.props().first?.isOn == false)
        #expect(TextPropRules.savedOffNote == "Saved off. Switch it on when you want it shown.")
        // A picture prop added the old way is still on.
        settings.addProp(logo, bookmark: nil)
        #expect(settings.props.last?.isOn == true)
    }

    @Test func aTextPropWithNoScreenIsRefusedWithAReason() async throws {
        let (settings, _) = try await loaded()
        #expect(settings.addTextProp(name: "Strap", spec: TextPropSpec(text: "Sunday"), targets: []) == nil)
        #expect(settings.props.isEmpty)
        #expect(settings.lastError?.contains("Choose at least one screen") == true)
        #expect(TextPropRules.problem(name: "Strap", targets: []) == "Choose at least one screen to show it on. Nothing was saved.")
        #expect(TextPropRules.problem(name: "  ", targets: [.audience])?.contains("name") == true)
        #expect(TextPropRules.problem(name: "Strap", targets: [.audience]) == nil)
    }

    @Test func savingAnEditWithNoScreenChangesNothing() async throws {
        let (settings, _) = try await loaded()
        let prop = try #require(settings.addTextProp(name: "Strap", spec: TextPropSpec(text: "Sunday"), targets: [.broadcast]))
        let saved = settings.saveTextProp(prop.id, name: "Renamed", spec: TextPropSpec(text: "Monday"), targets: [])
        #expect(!saved && settings.props.first?.name == "Strap" && settings.props.first?.targets == [.broadcast])
        #expect(settings.lastError?.contains("Choose at least one screen") == true)
        #expect(settings.saveTextProp(prop.id, name: "Renamed", spec: TextPropSpec(text: "Monday"), targets: [.audience, .stage]))
        #expect(settings.props.first?.name == "Renamed" && settings.props.first?.targets == [.audience, .stage] && settings.props.first?.text?.text == "Monday")
    }
}
