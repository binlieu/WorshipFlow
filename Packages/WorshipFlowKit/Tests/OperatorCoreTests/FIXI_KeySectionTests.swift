// FIX-I item 2: the keyboard has a section, the slide grid or the media bin (whichever was clicked last). Arrows move the selection and
// never the show; Return takes the selected slide, or sends the selected bin item, live; Space is "Next" from either section; Shift-Space
// is "Previous". The decision is a pure function of (section, key, what has focus, sheet open); the navigation helpers are pure too.
import Foundation
import Testing
@testable import OperatorCore

@Suite struct FIXI_KeySectionTests {
    static let sections: [KeySection] = [.slideGrid, .mediaBin]
    static let controls: [FocusedElement] = [.toggle, .checkbox, .segmented, .tab, .slider, .button, .popUp]
    static let arrows: [(KeyboardKey, SelectionMove)] = [(.leftArrow, .left), (.rightArrow, .right), (.upArrow, .up), (.downArrow, .down)]

    // MARK: the routing function, every (section, key, focus, sheet) case

    @Test func arrowsMoveTheSelectionInBothSectionsAndNeverReachTheTransport() {
        for section in Self.sections {
            for (key, move) in Self.arrows {
                for focus: FocusedElement in [.none, .slideGrid] {
                    #expect(KeyRouting.decision(for: key, focus: focus, section: section, sheetOpen: false) == .moveSelection(move), "\(section) \(key)")
                }
                #expect(KeyRouting.decision(for: key, textInputFocused: false, section: section, sheetOpen: false) == .moveSelection(move))
            }
        }
    }

    @Test func returnTakesTheSlideLiveFromTheGridAndSendsTheBinItemLiveFromTheBin() {
        for key: KeyboardKey in [.returnKey, .keypadEnter] {
            #expect(KeyRouting.decision(for: key, focus: .slideGrid, section: .slideGrid, sheetOpen: false) == .transport(.goLive))
            #expect(KeyRouting.decision(for: key, focus: .slideGrid, section: .mediaBin, sheetOpen: false) == .sendBinSelectionLive)
            #expect(KeyRouting.decision(for: key, focus: .none, section: .mediaBin, sheetOpen: false) == .sendBinSelectionLive)
        }
    }

    @Test func spaceIsNextFromEitherSectionAndShiftSpaceIsPrevious() {
        for section in Self.sections {
            #expect(KeyRouting.decision(for: .space, focus: .none, section: section, sheetOpen: false) == .transport(.next))
            #expect(KeyRouting.decision(for: .space, focus: .slideGrid, section: section, sheetOpen: false, shiftDown: true) == .transport(.previous))
        }
    }

    @Test func blackoutClearAndDeleteAreUnchangedAndWorkFromEitherSection() {
        for section in Self.sections {
            #expect(KeyRouting.decision(for: .b, focus: .none, section: section, sheetOpen: false) == .transport(.blackout))
            #expect(KeyRouting.decision(for: .escape, focus: .none, section: section, sheetOpen: false) == .transport(.clear))
            #expect(KeyRouting.decision(for: .escape, focus: .none, section: section, sheetOpen: false, shiftDown: true) == .transport(.clearAll))
            #expect(KeyRouting.decision(for: .deleteKey, focus: .none, section: section, sheetOpen: false) == .deleteSelectedObject)
        }
    }

    @Test func aFocusedControlKeepsEveryKeyInBothSectionsButEscape() {
        for section in Self.sections {
            for control in Self.controls {
                for key: KeyboardKey in [.returnKey, .space, .leftArrow, .rightArrow, .upArrow, .downArrow, .b] {
                    #expect(KeyRouting.decision(for: key, focus: control, section: section, sheetOpen: false) == .passThrough, "\(section) \(control) \(key)")
                }
                #expect(KeyRouting.decision(for: .escape, focus: control, section: section, sheetOpen: false) == .focusShow)
            }
        }
    }

    @Test func textFieldsKeepTypingSpaceReturnAndArrowsInBothSections() {
        for section in Self.sections {
            for focus: FocusedElement in [.textInput, .searchField] {
                for key: KeyboardKey in [.returnKey, .keypadEnter, .space, .leftArrow, .rightArrow, .upArrow, .downArrow, .b, .deleteKey] {
                    #expect(KeyRouting.decision(for: key, focus: focus, section: section, sheetOpen: false) == .passThrough, "\(section) \(focus) \(key)")
                    #expect(KeyRouting.decision(for: key, focus: focus, section: section, sheetOpen: false, shiftDown: true) == .passThrough)
                }
            }
        }
    }

    @Test func anOpenSheetOrAMenuShortcutNeverReachesTheShow() {
        for section in Self.sections {
            for key: KeyboardKey in [.returnKey, .space, .leftArrow, .rightArrow, .upArrow, .downArrow, .b, .escape] {
                #expect(KeyRouting.decision(for: key, focus: .none, section: section, sheetOpen: true) == .passThrough)
                #expect(KeyRouting.decision(for: key, focus: .none, section: section, sheetOpen: false, commandModifierDown: true) == .passThrough)
            }
        }
    }

    @Test func aHeldKeyIsIgnoredInBothSections() {
        for section in Self.sections {
            for key: KeyboardKey in [.returnKey, .space, .leftArrow, .rightArrow, .upArrow, .downArrow] {
                #expect(KeyRouting.decision(for: key, focus: .none, section: section, sheetOpen: false, isRepeat: true) == .ignore, "\(section) \(key)")
            }
        }
    }

    // MARK: which section has the arrows

    @Test func theSlideGridHasTheArrowsAtLaunchAndWhenAPresentationOpens() {
        #expect(KeySection.after(.launch, from: .mediaBin) == .slideGrid)
        #expect(KeySection.after(.presentationOpened, from: .mediaBin) == .slideGrid)
    }

    @Test func theLastClickedOfTheTwoSectionsHasTheArrows() {
        #expect(KeySection.after(.clickedMediaBin, from: .slideGrid) == .mediaBin)
        #expect(KeySection.after(.clickedSlideGrid, from: .mediaBin) == .slideGrid)
    }

    @Test func aClickInTheSidebarPlaylistOrInspectorDoesNotTakeTheArrowsAway() {
        #expect(KeySection.after(.clickedElsewhere, from: .mediaBin) == .mediaBin)
        #expect(KeySection.after(.clickedElsewhere, from: .slideGrid) == .slideGrid)
    }

    // MARK: moving the selection

    @Test func theBinMovesByItemAndByRowAndStopsAtTheEnds() {
        // 7 items, 3 across: rows 0 1 2 / 3 4 5 / 6
        #expect(BinNavigation.target(count: 7, current: 4, move: .right, columns: 3) == 5)
        #expect(BinNavigation.target(count: 7, current: 4, move: .left, columns: 3) == 3)
        #expect(BinNavigation.target(count: 7, current: 4, move: .down, columns: 3) == 6)       // the last row is short: its last item
        #expect(BinNavigation.target(count: 7, current: 4, move: .up, columns: 3) == 1)
        #expect(BinNavigation.target(count: 7, current: 0, move: .left, columns: 3) == 0)
        #expect(BinNavigation.target(count: 7, current: 6, move: .right, columns: 3) == 6)
        #expect(BinNavigation.target(count: 7, current: 6, move: .down, columns: 3) == 6)
        #expect(BinNavigation.target(count: 7, current: 1, move: .up, columns: 3) == 1)
    }

    @Test func aSingleRowBinIgnoresUpAndDown() {
        #expect(BinNavigation.target(count: 5, current: 2, move: .up, columns: 5) == 2)
        #expect(BinNavigation.target(count: 5, current: 2, move: .down, columns: 5) == 2)
    }

    @Test func nothingSelectedStartsAtTheFirstItemAndAnEmptyBinHasNoTarget() {
        #expect(BinNavigation.target(count: 4, current: nil, move: .right, columns: 4) == 0)
        #expect(BinNavigation.target(count: 4, current: nil, move: .down, columns: 4) == 0)
        #expect(BinNavigation.target(count: 0, current: nil, move: .right, columns: 1) == nil)
    }

    @Test func theSlideGridMovesByRowInsideASectionAndAcrossSections() {
        // Two sections, 3 across: A = 0 1 2 / 3 4 ; B = 5 6 7 / 8
        let runs: [[Int]] = [[0, 1, 2, 3, 4], [5, 6, 7, 8]]
        #expect(SlideGridNavigation.target(from: 1, move: .down, columns: 3, runs: runs) == 4)
        #expect(SlideGridNavigation.target(from: 2, move: .down, columns: 3, runs: runs) == 4)        // the short row: its last slide
        #expect(SlideGridNavigation.target(from: 4, move: .down, columns: 3, runs: runs) == 6)        // into the next section's first row, same column
        #expect(SlideGridNavigation.target(from: 3, move: .down, columns: 3, runs: runs) == 5)
        #expect(SlideGridNavigation.target(from: 6, move: .up, columns: 3, runs: runs) == 4)          // back into the previous section's last row
        #expect(SlideGridNavigation.target(from: 7, move: .up, columns: 3, runs: runs) == 4)
        #expect(SlideGridNavigation.target(from: 0, move: .up, columns: 3, runs: runs) == nil)
        #expect(SlideGridNavigation.target(from: 8, move: .down, columns: 3, runs: runs) == nil)
        #expect(SlideGridNavigation.target(from: 8, move: .right, columns: 3, runs: runs) == nil)      // past the last slide: the caller may cross items
        #expect(SlideGridNavigation.target(from: 0, move: .left, columns: 3, runs: runs) == nil)
        #expect(SlideGridNavigation.target(from: 2, move: .right, columns: 3, runs: runs) == 3)
        #expect(SlideGridNavigation.target(from: 4, move: .right, columns: 3, runs: runs) == 5)
    }

    @Test func aListMovesOneSlideForEveryArrow() {
        let runs: [[Int]] = [[0, 1], [2, 3]]
        #expect(SlideGridNavigation.target(from: 1, move: .down, columns: 1, runs: runs) == 2)
        #expect(SlideGridNavigation.target(from: 2, move: .up, columns: 1, runs: runs) == 1)
    }
}

@Suite struct FIXI_KeyTableTests {
    /// The keyboard table in the Cues mode and the transport bar's hints must name the keys that really do each thing.
    @Test func theKeyboardTableSaysWhatTheKeysNowDo() {
        let table = Dictionary(uniqueKeysWithValues: ShowShortcuts.all.map { ($0.key, $0.command) })
        #expect(table["Space"] == "Next slide")
        #expect(table["⇧ Space"] == "Previous slide")
        #expect(table["← → ↑ ↓"] == "Move the selection (Preview only)")
        #expect(table["↩"] == "Go live with the selected slide, or send the selected media item live")
        #expect(table["→ or Space"] == nil && table["←"] == nil, "the arrows no longer step the live slide")
        let keys = ShowShortcuts.all.map(\.key)
        #expect(Set(keys).count == keys.count, "no two commands share a key")
    }

    @Test func theTransportBarHintsAreTheRealKeys() {
        #expect(TransportKeyHints.previous == "⇧␣" && TransportKeyHints.next == "␣" && TransportKeyHints.goLive == "↩")
    }
}
