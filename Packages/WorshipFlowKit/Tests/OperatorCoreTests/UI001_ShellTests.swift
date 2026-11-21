// UI-001 Part 3/4: the decisions behind the six-mode shell: modes, role pills, output health, section runs, live line,
// library overview and filter. Views only draw what these return.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct UI001_ModeTests {
    @Test func sixModesInOrderWithCommandDigitsOneToSix() {
        #expect(WorkspaceMode.allCases.map(\.title) == ["Show", "Edit", "Media", "Stage", "Cues", "Screens"])
        #expect(WorkspaceMode.allCases.map(\.commandDigit) == [1, 2, 3, 4, 5, 6])
        for mode in WorkspaceMode.allCases { #expect(WorkspaceMode(commandDigit: mode.commandDigit) == mode) }
        #expect(WorkspaceMode(commandDigit: 0) == nil && WorkspaceMode(commandDigit: 7) == nil)
        #expect(WorkspaceMode(shortcutCharacter: "4") == .stage && WorkspaceMode(shortcutCharacter: "x") == nil)
    }

    @Test func aStoredValueIsRestoredAndAnythingElseIsShow() {
        #expect(WorkspaceMode.restored(from: "media") == .media)
        #expect(WorkspaceMode.restored(from: nil) == .show)
        #expect(WorkspaceMode.restored(from: "garbage") == .show)
        #expect(WorkspaceMode.restored(from: "") == .show)
    }
}

@MainActor
@Suite struct UI001_ModeRestoreTests {
    @Test func firstRunIsShowAndTheChoiceSurvivesARelaunch() async throws {
        let store = try LibraryStore.inMemory()
        let first = WorkspaceModel(store: store)
        await first.load()
        #expect(first.mode == .show)
        first.setMode(.screens)
        #expect(first.mode == .screens)
        await first.flush()
        let second = WorkspaceModel(store: store)
        await second.load()
        #expect(second.mode == .screens)
    }

    @Test func aDamagedStoredModeFallsBackToShow() async throws {
        let store = try LibraryStore.inMemory()
        try await store.setState("not-a-mode", for: WorkspaceModel.modeKey)
        let model = WorkspaceModel(store: store)
        await model.load()
        #expect(model.mode == .show)
    }

    @Test func changingModeNeverTouchesTheShow() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let p = try #require(await model.importLyrics(title: "S", primaryText: "a\n\nb", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        await model.goLive()
        let before = model.show
        for mode in WorkspaceMode.allCases { model.setMode(mode) }
        #expect(model.show == before)
    }
}

@Suite struct UI001_RolePillTests {
    typealias S = ScreenStatusInput

    @Test func alwaysThreePillsAudStgBrdInThatOrder() {
        let pills = RolePills.pills(from: [])
        #expect(pills.map(\.abbreviation) == ["AUD", "STG", "BRD"])
        #expect(pills.map(\.role) == [.audience, .stage, .broadcast])
        #expect(pills.allSatisfy { $0.status == .off })
    }

    @Test func runningIsOnDisabledAndStoppedAreOff() {
        let pills = RolePills.pills(from: [
            S(role: .audience, isEnabled: true, run: .running),
            S(role: .stage, isEnabled: false, run: .running),
            S(role: .broadcast, isEnabled: true, run: .stopped),
        ])
        #expect(pills.map(\.status) == [.on, .off, .off])
    }

    @Test func aFaultOnAnyEnabledScreenOfTheRoleWinsOverARunningOne() {
        let pills = RolePills.pills(from: [
            S(role: .audience, isEnabled: true, run: .running),
            S(role: .audience, isEnabled: true, run: .faulted),
        ])
        #expect(pills[0].status == .fault)
    }

    @Test func aHiddenScreenCountsAsOnButSaysItIsCovered() {
        let pill = RolePills.pills(from: [S(role: .stage, isEnabled: true, run: .hidden)])[1]
        #expect(pill.status == .on && pill.accessibilityText.contains("covered"))
    }

    @Test func everyPillHasWordsForVoiceOver() {
        let pills = RolePills.pills(from: [S(role: .broadcast, isEnabled: true, run: .faulted)])
        #expect(pills[0].accessibilityText == "Audience screens: off")
        #expect(pills[2].accessibilityText == "Broadcast screens: fault")
        #expect(pills.map(\.statusWord) == ["off", "off", "fault"])
    }
}

@Suite struct UI001_OutputHealthTests {
    typealias S = OutputHealthSample

    @Test func nothingRunningMeansNoReadout() {
        #expect(OutputHealth.summary(from: []) == nil)
        #expect(OutputHealth.summary(from: [S(role: .audience, run: .stopped, refreshRate: 60, dropped: 3, late: 1)]) == nil)
    }

    @Test func rateComesFromTheAudienceScreenAndCountsAreSummedOverRunningScreens() throws {
        let h = try #require(OutputHealth.summary(from: [
            S(role: .stage, run: .running, refreshRate: 30, dropped: 2, late: 1),
            S(role: .audience, run: .running, refreshRate: 59.94, dropped: 1, late: 4),
            S(role: .broadcast, run: .stopped, refreshRate: 0, dropped: 9, late: 9),
        ]))
        #expect(h.framesPerSecond == 59.94 && h.dropped == 3 && h.late == 5)
        #expect(h.rateText == "59.94 fps" && h.countsText == "dropped 3 · late 5")
    }

    @Test func wholeRatesHaveNoDecimals() throws {
        let h = try #require(OutputHealth.summary(from: [S(role: .audience, run: .running, refreshRate: 60, dropped: 0, late: 0)]))
        #expect(h.rateText == "60 fps")
    }

    @Test func aFaultedScreenIsReportedAsNeedingAttention() throws {
        let h = try #require(OutputHealth.summary(from: [
            S(role: .audience, run: .running, refreshRate: 60, dropped: 0, late: 0),
            S(role: .stage, run: .faulted, refreshRate: 0, dropped: 0, late: 0),
        ]))
        #expect(h.needsAttention)
    }
}

@Suite struct UI001_SectionRunTests {
    func group(_ name: String) -> SlideGroup { SlideGroup(presentationID: UUID(), name: name) }

    @Test func consecutiveSlidesOfOneSectionFormARun() {
        let v = group("Verse 1"), c = group("Chorus")
        let runs = SectionRuns.runs(slideGroupIDs: [v.id, v.id, c.id, c.id, nil], groups: [v, c],
                                    groupSlideCounts: [v.id: 2, c.id: 2])
        #expect(runs.map(\.name) == ["Verse 1", "Chorus", nil])
        #expect(runs.map(\.indices) == [[0, 1], [2, 3], [4]])
        #expect(runs.map(\.repeatCount) == [1, 1, 1])
    }

    @Test func aSectionPlayedTwiceInARowShowsItsRepeatCount() {
        let c = group("Chorus")
        let twice = SectionRuns.runs(slideGroupIDs: [c.id, c.id, c.id, c.id], groups: [c], groupSlideCounts: [c.id: 2])
        #expect(twice.count == 1 && twice[0].repeatCount == 2 && twice[0].indices == [0, 1, 2, 3])
        // A count that is not a whole number of plays (slides were added or removed) shows no repeat.
        let odd = SectionRuns.runs(slideGroupIDs: [c.id, c.id, c.id], groups: [c], groupSlideCounts: [c.id: 2])
        #expect(odd[0].repeatCount == 1)
    }

    @Test func separatedPlaysOfTheSameSectionAreSeparateRuns() {
        let v = group("Verse 1"), c = group("Chorus")
        let runs = SectionRuns.runs(slideGroupIDs: [c.id, v.id, c.id], groups: [v, c], groupSlideCounts: [v.id: 1, c.id: 1])
        #expect(runs.map(\.name) == ["Chorus", "Verse 1", "Chorus"])
    }

    @Test func toneFollowsTheSectionName() {
        #expect(SectionTone(sectionName: "Verse 2") == .verse)
        #expect(SectionTone(sectionName: "CHORUS") == .chorus)
        #expect(SectionTone(sectionName: "Pre-chorus") == .chorus)
        #expect(SectionTone(sectionName: "Bridge") == .bridge)
        #expect(SectionTone(sectionName: "Ending") == .ending)
        #expect(SectionTone(sectionName: "Outro") == .ending)
        #expect(SectionTone(sectionName: "Intro") == .other)
        #expect(SectionTone(sectionName: nil) == .other)
    }
}

@Suite struct UI001_LiveLineTests {
    @Test func positionLineHasTitleSectionAndSlideNumbers() {
        #expect(LiveSummary.positionLine(title: "Amazing Grace", section: "Chorus", index: 2, count: 9) == "Amazing Grace · Chorus · slide 3 of 9")
        #expect(LiveSummary.positionLine(title: "Amazing Grace", section: nil, index: 0, count: 4) == "Amazing Grace · slide 1 of 4")
        #expect(LiveSummary.positionLine(title: nil, section: nil, index: 0, count: 4) == "slide 1 of 4")
        #expect(LiveSummary.positionLine(title: "  ", section: "", index: 3, count: 4) == "slide 4 of 4")
    }

    @Test func theLiveLineJoinsTheLinesOfTheFirstLanguage() {
        #expect(LiveSummary.line(for: SlideContent(primary: "My chains are gone\nI've been set free")) == "My chains are gone I've been set free")
        #expect(LiveSummary.line(for: SlideContent(primary: "")) == "(blank slide)")
    }

    @MainActor @Test func theModelRemembersTitleAndSectionOfTheLiveSlide() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Amazing Grace", primaryText: "Verse 1:\none\n\nChorus:\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        #expect(model.livePositionLine == nil)
        await model.goLive()
        let first = try #require(model.livePositionLine)
        #expect(first.hasPrefix("Amazing Grace") && first.hasSuffix("slide 1 of 3"))
        #expect(first == "Amazing Grace · Verse 1 · slide 1 of 3")
        await model.next()
        #expect(model.livePositionLine == "Amazing Grace · Chorus · slide 2 of 3")
        model.stop()
        #expect(model.livePositionLine == nil)
    }
}

@MainActor
@Suite struct UI001_LibraryOverviewTests {
    @Test func countsPerLibraryAndTheBilingualMarker() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let one = try #require(await model.importLyrics(title: "Plain", primaryText: "a\n\nb", secondaryText: nil, maxLines: 1))
        let two = try #require(await model.importLyrics(title: "Both", primaryText: "a\n\nb", secondaryText: "x\n\ny", maxLines: 1))
        let library = try #require(model.selectedLibraryID)
        #expect(model.libraryCounts[library] == 2)
        #expect(model.bilingualPresentationIDs.contains(two.id))
        #expect(model.bilingualPresentationIDs.contains(one.id) == false)
        await model.createLibrary(name: "Other")
        let other = try #require(model.selectedLibraryID)
        #expect(other != library && model.libraryCounts[other] == 0 && model.libraryCounts[library] == 2)
    }

    @Test func filterIgnoresCaseAndAccentsAndKeepsOrder() {
        let titles = ["10,000 Reasons", "Amazing Grace", "Ân điển lạ lùng", "Be Thou My Vision"]
        #expect(LibraryFilter.apply("", to: titles, title: { $0 }) == titles)
        #expect(LibraryFilter.apply("GRACE", to: titles, title: { $0 }) == ["Amazing Grace"])
        #expect(LibraryFilter.apply("an dien", to: titles, title: { $0 }) == ["Ân điển lạ lùng"])
        #expect(LibraryFilter.apply("zzz", to: titles, title: { $0 }).isEmpty)
    }
}
