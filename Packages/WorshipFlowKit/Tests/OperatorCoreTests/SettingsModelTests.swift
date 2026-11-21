// APP-001 / KI-025: screen profiles, Looks, props and themes in SQLite instead of JSON files.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct SettingsModelTests {
    static let defaults: @MainActor () -> [ScreenProfile] = {
        [ScreenProfile(name: "Audience", role: .audience, destination: .window),
         ScreenProfile(name: "Stage", role: .stage, destination: .window),
         ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window, isEnabled: false)]
    }

    func model(_ store: LibraryStore, legacy: LegacySettingsFiles? = nil) -> SettingsModel {
        SettingsModel(store: store, legacy: legacy, defaultProfiles: Self.defaults)
    }

    func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Load

    @Test func firstLaunchGetsDefaultScreensAndAStandardLookAndStoresThem() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        await settings.flush()
        #expect(settings.profiles.map(\.name) == ["Audience", "Stage", "Broadcast"])
        #expect(settings.looks.map(\.name) == ["Standard"])
        #expect(settings.selectedLookID == settings.looks.first?.id)
        #expect(settings.props.isEmpty && settings.customThemes.isEmpty && settings.lastError == nil)
        #expect(try await store.screenProfiles().map(\.name) == ["Audience", "Stage", "Broadcast"])
        #expect(try await store.looks().map(\.name) == ["Standard"])
        // A second launch reads what the first stored; it does not make new ids.
        let again = model(store)
        await again.load()
        #expect(again.profiles.map(\.id) == settings.profiles.map(\.id))
        #expect(again.looks.map(\.id) == settings.looks.map(\.id))
    }

    @Test func changesAreWrittenAndReadBackAfterARelaunch() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        var audience = try #require(settings.profiles.first)
        audience.name = "Main hall"
        audience.destination = .display(77)
        settings.updateProfile(audience)
        let look = settings.addLook()
        settings.renameLook(look.id, to: "Christmas")
        settings.setTheme(Theme.lowerThirdID, forScreen: audience.id)
        settings.setLayer(.props, visible: false, forScreen: audience.id)
        let prop = Prop(name: "Logo", imagePath: "/tmp/logo.png", frame: NormalizedRect(x: 0.8, y: 0.05, width: 0.1, height: 0.1))
        settings.addProp(prop, bookmark: Data([1, 2, 3]))
        settings.setProp(prop.id, isOn: false)
        await settings.flush()
        #expect(settings.lastError == nil)

        let again = model(store)
        await again.load()
        #expect(again.profiles.first?.name == "Main hall")
        #expect(again.profiles.first?.destination == .display(77))
        #expect(again.looks.map(\.name) == ["Standard", "Christmas"])
        #expect(again.selectedLookID == look.id)                                   // the selection is remembered
        #expect(again.screenLook(for: audience.id).themeID == Theme.lowerThirdID)
        #expect(again.screenLook(for: audience.id).visibleLayers == [.background, .slide])
        #expect(again.props.map(\.name) == ["Logo"] && again.props.first?.isOn == false)
        #expect(await again.bookmark(forProp: prop.id) == Data([1, 2, 3]))
    }

    @Test func lookDeleteKeepsTheLastOneAndMovesTheSelection() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        let only = try #require(settings.looks.first)
        settings.deleteLook(only.id)
        #expect(settings.looks.count == 1)
        let second = settings.addLook()
        settings.deleteLook(second.id)
        #expect(settings.selectedLookID == only.id)
        await settings.flush()
        #expect(try await store.looks().map(\.id) == [only.id])
        settings.removeProp(UUID())                                                 // unknown ids are ignored
        #expect(settings.lastError == nil)
    }

    @Test func writesReachTheFileInTheOrderTheyWereMade() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        let id = try #require(settings.profiles.first).id
        for n in 1...20 {
            var p = try #require(settings.profiles.first { $0.id == id })
            p.name = "Screen \(n)"
            settings.updateProfile(p)
        }
        await settings.flush()
        #expect(try await store.screenProfiles().first?.name == "Screen 20")
    }

    // MARK: Failure

    @Test func aFailedSaveSetsAnOperatorMessageAndDoesNotThrow() async throws {
        let store = try LibraryStore.inMemory()
        let settings = model(store)
        await settings.load()
        await settings.flush()
        try store.close()
        var p = try #require(settings.profiles.first)
        p.name = "After close"
        settings.updateProfile(p)
        await settings.flush()
        let message = try #require(settings.lastError)
        #expect(message.hasPrefix("Could not save the screen settings"))
        #expect(message.contains("restart the app"))
        #expect(settings.profiles.first?.name == "After close")                    // the screens still follow the operator
        settings.dismissError()
        #expect(settings.lastError == nil)
    }

    @Test func aBlankLookNameIsRefusedWithAMessage() async throws {
        let settings = model(try LibraryStore.inMemory())
        await settings.load()
        let id = try #require(settings.looks.first).id
        settings.renameLook(id, to: "   ")
        #expect(settings.looks.first?.name == "Standard")
        #expect(settings.lastError?.contains("a name is needed") == true)
    }

    // MARK: One-time import of the old JSON files (KI-025)

    func writeLegacy(into folder: URL, profileID: UUID, lookID: UUID, propID: UUID) throws -> (profiles: Data, looks: Data) {
        let profiles = [ScreenProfile(id: profileID, name: "Old audience", role: .audience, destination: .display(5)),
                        ScreenProfile(name: "Old stage", role: .stage, destination: .window)]
        let look = Look(id: lookID, name: "Easter", screens: [profileID: ScreenLook(themeID: Theme.lowerThirdID, visibleLayers: [.slide])])
        let prop = Prop(id: propID, name: "Cross", imagePath: "/tmp/cross.png", frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1))
        let library = LegacyLookLibrary(looks: [Look(id: UUID(), name: "Standard"), look], selectedLookID: lookID,
                                        props: [LegacyStoredProp(prop: prop, bookmark: Data([9, 9]))])
        let files = LegacySettingsFiles(folder: folder)
        let profileData = try JSONEncoder().encode(profiles)
        let lookData = try JSONEncoder().encode(library)
        try profileData.write(to: files.screenProfilesURL)
        try lookData.write(to: files.looksURL)
        return (profileData, lookData)
    }

    @Test func oldJSONFilesAreImportedOnceAndLeftUntouched() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (profileID, lookID, propID) = (UUID(), UUID(), UUID())
        let original = try writeLegacy(into: folder, profileID: profileID, lookID: lookID, propID: propID)
        let files = LegacySettingsFiles(folder: folder)
        let store = try LibraryStore.inMemory()

        let first = model(store, legacy: files)
        await first.load()
        await first.flush()
        #expect(first.profiles.map(\.name) == ["Old audience", "Old stage"])
        #expect(first.profiles.first?.id == profileID && first.profiles.first?.destination == .display(5))
        #expect(first.looks.map(\.name) == ["Standard", "Easter"])
        #expect(first.selectedLookID == lookID)
        #expect(first.screenLook(for: profileID) == ScreenLook(themeID: Theme.lowerThirdID, visibleLayers: [.slide]))
        #expect(first.props.map(\.name) == ["Cross"])
        #expect(await first.bookmark(forProp: propID) == Data([9, 9]))
        #expect(first.lastError == nil && first.notices.isEmpty)

        // The files are still there, byte for byte.
        #expect(try Data(contentsOf: files.screenProfilesURL) == original.profiles)
        #expect(try Data(contentsOf: files.looksURL) == original.looks)

        // The operator deletes what was imported; a later launch must not bring it back.
        first.deleteLook(lookID)
        first.removeProp(propID)
        await first.flush()
        let second = model(store, legacy: files)
        await second.load()
        #expect(second.looks.map(\.name) == ["Standard"])
        #expect(second.props.isEmpty)
        #expect(second.profiles.map(\.name) == ["Old audience", "Old stage"])
    }

    @Test func oldFilesAreIgnoredWhenTheTablesAlreadyHaveRows() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try writeLegacy(into: folder, profileID: UUID(), lookID: UUID(), propID: UUID())
        let store = try LibraryStore.inMemory()
        try await store.saveScreenProfiles([ScreenProfile(name: "Existing", role: .audience, destination: .window)])
        try await store.saveLook(Look(id: UUID(), name: "Mine"))
        let settings = model(store, legacy: LegacySettingsFiles(folder: folder))
        await settings.load()
        #expect(settings.profiles.map(\.name) == ["Existing"])
        #expect(settings.looks.map(\.name) == ["Mine"])
        #expect(settings.props.isEmpty)
    }

    @Test func anUnreadableOldFileIsReportedLeftAloneAndDefaultsAreUsed() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = LegacySettingsFiles(folder: folder)
        let garbage = Data("this is not json".utf8)
        try garbage.write(to: files.screenProfilesURL)
        try garbage.write(to: files.looksURL)
        let settings = model(try LibraryStore.inMemory(), legacy: files)
        await settings.load()
        #expect(settings.notices.count == 2)
        #expect(settings.profiles.map(\.name) == ["Audience", "Stage", "Broadcast"])
        #expect(settings.looks.map(\.name) == ["Standard"])
        #expect(try Data(contentsOf: files.screenProfilesURL) == garbage)
        #expect(try Data(contentsOf: files.looksURL) == garbage)
    }

    @Test func missingOldFilesAreFine() async throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = model(try LibraryStore.inMemory(), legacy: LegacySettingsFiles(folder: folder))
        await settings.load()
        #expect(settings.notices.isEmpty && settings.lastError == nil && settings.profiles.count == 3)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == [])   // nothing is created beside the library
    }

    @Test func legacyFilesLiveBesideTheLibraryFile() {
        let files = LegacySettingsFiles(libraryURL: URL(fileURLWithPath: "/tmp/run-1/Library.sqlite"))
        #expect(files.screenProfilesURL.path == "/tmp/run-1/screen-profiles.json")
        #expect(files.looksURL.path == "/tmp/run-1/looks.json")
    }
}
