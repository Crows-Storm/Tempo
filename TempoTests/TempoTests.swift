import CoreGraphics
import Foundation
import Testing
@testable import Tempo

struct FocusClockTests {
    @Test func remainingUsesEndDate() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.start(at: start, durations: .standard)
        let later = start.addingTimeInterval(60)
        #expect(abs(clock.remaining(at: later, durations: .standard) - (25 * 60 - 60)) < 0.01)
    }

    @Test func pauseKeepsRemaining() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.start(at: start, durations: .standard)
        let pausedAt = start.addingTimeInterval(90)
        clock.pause(at: pausedAt, durations: .standard)
        let remaining = clock.remaining(at: pausedAt.addingTimeInterval(500), durations: .standard)
        #expect(abs(remaining - (25 * 60 - 90)) < 0.01)
        clock.resume(at: pausedAt.addingTimeInterval(500))
        #expect(clock.runState == .running)
    }

    @Test func naturalFocusStartsShortBreakAndCounts() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.start(at: start, durations: .standard)
        let event = clock.reconcile(at: start.addingTimeInterval(25 * 60), durations: .standard)
        guard case let .focusFinished(_, rotten, counts, _) = event else {
            Issue.record("expected focus finished")
            return
        }
        #expect(rotten == false)
        #expect(counts == true)
        #expect(clock.phase == .shortBreak)
        #expect(clock.runState == .idle)
        #expect(clock.completedFocusCount == 1)
    }

    @Test func fourthFocusLeadsToLongBreak() {
        var clock = FocusClock()
        clock.completedFocusCount = 3
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.start(at: start, durations: .standard)
        _ = clock.reconcile(at: start.addingTimeInterval(25 * 60), durations: .standard)
        #expect(clock.phase == .longBreak)
        #expect(clock.completedFocusCount == 4)
    }

    @Test func earlySkipIsRottenAndDoesNotCount() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.start(at: start, durations: .standard)
        let event = clock.skip(at: start.addingTimeInterval(120), durations: .standard)
        guard case let .focusFinished(elapsed, rotten, counts, _) = event else {
            Issue.record("expected focus finished")
            return
        }
        #expect(elapsed < 10 * 60)
        #expect(rotten == true)
        #expect(counts == false)
        #expect(clock.completedFocusCount == 0)
    }

    @Test func stopDiscardsSession() {
        var clock = FocusClock()
        clock.start(at: .now, durations: .standard)
        let id = clock.stop()
        #expect(id != nil)
        #expect(clock.runState == .idle)
        #expect(clock.phase == .focus)
        #expect(clock.activeSessionID == nil)
    }

    @Test func switchPhaseTogglesIdleFocusAndBreak() {
        var clock = FocusClock()
        clock.switchPhase(durations: .standard)
        #expect(clock.phase == .shortBreak)
        #expect(clock.runState == .idle)
        clock.switchPhase(durations: .standard)
        #expect(clock.phase == .focus)
    }

    @Test func completeAfterTenMinutesCountsAsPomodoro() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.start(at: start, durations: .standard)
        let event = clock.skip(at: start.addingTimeInterval(12 * 60), durations: .standard)
        guard case let .focusFinished(_, rotten, counts, _) = event else {
            Issue.record("expected focus finished")
            return
        }
        #expect(rotten == false)
        #expect(counts == true)
        #expect(clock.completedFocusCount == 1)
    }

    @Test func switchPhaseDoesNotResetARunningTimer() {
        var clock = FocusClock()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        clock.start(at: start, durations: .standard)
        clock.boardID = "board"
        clock.cardID = "card"
        clock.switchPhase(durations: .standard)
        #expect(clock.runState == .running)
        #expect(clock.phase == .focus)
        #expect(clock.boardID == "board")
        #expect(clock.cardID == "card")
    }
}

struct AnalyticsTests {
    @Test func efficiencyIgnoresMatchingApps() {
        let rules = [DistractionRule(id: "mail", app: "Mail", title: "")]
        let ratio = Analytics.efficiency(
            samples: [("Xcode", "File"), ("Mail", "Inbox"), ("Xcode", "File"), ("Xcode", "File")],
            rules: rules
        )
        #expect(ratio == 0.75)
    }

    @Test func streakCountsBackFromToday() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let sessions = (0..<3).map { offset in
            SessionFact(
                id: "\(offset)",
                start: calendar.date(byAdding: .day, value: -offset, to: today) ?? today,
                seconds: 25 * 60,
                boardID: nil,
                rotten: false,
                counts: true,
                efficiency: nil,
                primaryApp: nil,
                apps: [],
                titles: []
            )
        }
        #expect(Analytics.streak(sessions: sessions, today: today, calendar: calendar) == 3)
    }

    @Test func heatmapLevelIsNotColorOnly() {
        let day = HeatmapDay(day: .now, minutes: 80, sessions: 2, inRange: true)
        #expect(day.level == 3)
        #expect(day.sessions == 2)
    }

    @Test func xRuleDoesNotMatchXcode() {
        let rules = [DistractionRule(id: "x", app: "^X$|Twitter", title: "")]
        #expect(Analytics.efficiency(samples: [("Xcode", "File")], rules: rules) == 1)
        #expect(Analytics.efficiency(samples: [("X", "Home")], rules: rules) == 0)
        #expect(Analytics.efficiency(samples: [("Twitter", "Home")], rules: rules) == 0)
    }

    @Test func todaySecondsKeepsATenMinuteSession() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [
            SessionFact(
                id: "s",
                start: now,
                seconds: 10 * 60 + 5,
                boardID: nil,
                rotten: false,
                counts: true,
                efficiency: nil,
                primaryApp: nil,
                apps: [],
                titles: []
            )
        ]
        let today = Analytics.todaySeconds(sessions: sessions, now: now, calendar: calendar)
        #expect(abs(today - (10 * 60 + 5)) < 0.01)
        #expect(TempoFormat.minutesValue(today) != TempoFormat.minutesValue(10))
    }
}

struct CardOrderTests {
    @Test func insertBeforeLeavesAGap() {
        #expect(CardOrder.inserted(["c"], into: ["a", "b", "d"], before: "b") == ["a", "c", "b", "d"])
    }

    @Test func insertAtEndAppends() {
        #expect(CardOrder.inserted(["c"], into: ["a", "b"], before: nil) == ["a", "b", "c"])
    }

    @Test func movingWithinListDropsTheOldSlot() {
        #expect(CardOrder.inserted(["b"], into: ["a", "b", "c"], before: "a") == ["b", "a", "c"])
    }
}

struct CardDropTargetTests {
    @Test func midpointPicksTheCardBelow() {
        let frames = [
            CardFrame(id: "a", minY: 0, height: 80),
            CardFrame(id: "b", minY: 90, height: 80),
            CardFrame(id: "c", minY: 180, height: 80)
        ]
        #expect(CardDropTarget.beforeID(y: 20, frames: frames, draggingID: nil, holdingBefore: nil, holdingThisColumn: false, gap: 0) == "a")
        #expect(CardDropTarget.beforeID(y: 100, frames: frames, draggingID: nil, holdingBefore: nil, holdingThisColumn: false, gap: 0) == "b")
        #expect(CardDropTarget.beforeID(y: 250, frames: frames, draggingID: nil, holdingBefore: nil, holdingThisColumn: false, gap: 0) == nil)
    }

    @Test func openGapKeepsTheSameSlot() {
        let frames = [
            CardFrame(id: "a", minY: 0, height: 80),
            CardFrame(id: "b", minY: 170, height: 80),
            CardFrame(id: "c", minY: 260, height: 80)
        ]
        #expect(CardDropTarget.beforeID(y: 100, frames: frames, draggingID: nil, holdingBefore: "b", holdingThisColumn: true, gap: 80) == "b")
    }

    @Test func draggingCardIsIgnored() {
        let frames = [
            CardFrame(id: "a", minY: 0, height: 80),
            CardFrame(id: "b", minY: 90, height: 0),
            CardFrame(id: "c", minY: 100, height: 80)
        ]
        #expect(CardDropTarget.beforeID(y: 20, frames: frames, draggingID: "b", holdingBefore: nil, holdingThisColumn: false, gap: 0) == "a")
        #expect(CardDropTarget.beforeID(y: 50, frames: frames, draggingID: "b", holdingBefore: nil, holdingThisColumn: false, gap: 0) == "c")
    }

    @Test func placeholderStaysHiddenUntilACardIsDragging() {
        #expect(!CardDropTarget.showsPlaceholder(draggingID: nil, probeListID: "progress", columnID: "progress"))
        #expect(CardDropTarget.showsPlaceholder(draggingID: "card", probeListID: "progress", columnID: "progress"))
        #expect(!CardDropTarget.showsPlaceholder(draggingID: "card", probeListID: "progress", columnID: "todo"))
    }
}

struct CardEffortTests {
    @Test func hourEstimateRoundsToPomodoros() {
        #expect(CardEffort.plannedPomodoros(estimatedHours: 1, focusMinutes: 25) == 2)
        #expect(CardEffort.plannedPomodoros(estimatedHours: 25.0 / 60, focusMinutes: 25) == 1)
    }

    @Test func linkedSessionsWinOverHours() {
        let json = JSONBox.strings(["a", "b", "c"])
        #expect(CardEffort.donePomodoros(sessionIDsJSON: json, actualHours: 0.1, focusMinutes: 25) == 3)
        #expect(CardEffort.donePomodoros(sessionIDsJSON: "[]", actualHours: 50.0 / 60, focusMinutes: 25) == 2)
    }

    @Test func fractionClampsWhenOverEstimate() {
        #expect(CardEffort.fraction(actualHours: 0.5, estimatedHours: 1) == 0.5)
        #expect(CardEffort.fraction(actualHours: 2, estimatedHours: 1) == 1)
        #expect(CardEffort.isOverEstimate(actualHours: 2, estimatedHours: 1))
    }
}

struct BoardSeedTests {
    @Test func welcomeCardHasTryList() {
        #expect(BoardSeed.welcomeTitle == "Welcome✨")
        #expect(BoardSeed.welcomeNotes.contains("Draggable"))
        #expect(BoardSeed.welcomeNotes.contains("- [ ] Drag this card to In Progress"))
        #expect(BoardSeed.welcomeNotes.contains("- [ ] Edit me in Markdown"))
        #expect(BoardSeed.welcomeNotes.contains("- [ ] Set estimated time"))
    }
}

struct CardDraftSaveTests {
    @MainActor
    @Test func saveDraftInsertsCardInTheChosenList() throws {
        let model = AppModel(stack: try TempoStore.memory())
        model.createBoard(name: "Board")
        let list = try #require(model.fetchLists(boardID: model.selectedBoardID ?? "").first { $0.role == .todo })
        let before = model.fetchCards(listID: list.id).count
        model.cardDraft = CardDraft(
            id: "card-1",
            existingID: nil,
            listID: list.id,
            title: "Hello",
            notes: "body",
            estimatedHours: 2
        )
        model.saveDraft()
        let cards = model.fetchCards(listID: list.id)
        #expect(cards.count == before + 1)
        #expect(cards.contains { $0.id == "card-1" && $0.title == "Hello" && $0.notes == "body" })
        #expect(model.cardDraft == nil)
        #expect(model.revision >= 1)
    }

    @MainActor
    @Test func saveDraftKeepsDraftWhenTitleIsBlank() throws {
        let model = AppModel(stack: try TempoStore.memory())
        model.createBoard(name: "Board")
        let list = try #require(model.fetchLists(boardID: model.selectedBoardID ?? "").first)
        let before = model.fetchCards(listID: list.id).count
        model.cardDraft = CardDraft(id: "card-1", existingID: nil, listID: list.id, title: "   ", notes: "", estimatedHours: 1)
        model.saveDraft()
        #expect(model.fetchCards(listID: list.id).count == before)
        #expect(model.cardDraft != nil)
    }
}

struct ListRoleTests {
    @Test func presetColumnsCannotRenameOrDelete() {
        #expect(!ListRole.todo.canRename)
        #expect(!ListRole.inProgress.canRename)
        #expect(!ListRole.done.canRename)
        #expect(!ListRole.todo.canDelete)
        #expect(ListRole.custom.canRename)
        #expect(ListRole.custom.canDelete)
    }
}

struct DurationMarksTests {
    @Test func nearestPicksCommonFocusLength() {
        #expect(DurationMarks.nearest(27, in: DurationMarks.focus) == 25)
        #expect(DurationMarks.nearest(40, in: DurationMarks.focus) == 45)
        #expect(DurationMarks.index(of: 25, in: DurationMarks.focus) == 2)
    }
}

struct DistractionPresetTests {
    @Test func resolvedUpgradesLegacyDefaults() {
        let legacy = [
            DistractionRule(id: "messages", app: "Messages", title: ""),
            DistractionRule(id: "mail", app: "Mail", title: "")
        ]
        let resolved = DistractionRule.resolved(legacy)
        #expect(resolved == DistractionRule.presets)
        #expect(resolved.count > 2)
    }

    @Test func resolvedKeepsCustomLists() {
        let custom = [DistractionRule(id: "only", app: "Slack", title: "")]
        #expect(DistractionRule.resolved(custom) == custom)
    }
}

struct BoardOverviewTests {
    @Test func tallyPutsCustomWithTodo() {
        let result = BoardOverview.tally([
            (.todo, 2),
            (.inProgress, 1),
            (.done, 3),
            (.custom, 4)
        ])
        #expect(result.todo == 6)
        #expect(result.inProgress == 1)
        #expect(result.done == 3)
    }

    @Test func progressIsDoneOverTotal() {
        let board = BoardOverview(
            id: "1",
            name: "Work",
            summary: "",
            pinned: false,
            archived: false,
            spentHours: 1,
            todo: 1,
            inProgress: 1,
            done: 2,
            nextTitle: "Ship"
        )
        #expect(board.total == 4)
        #expect(abs(board.progress - 0.5) < 0.001)
        #expect(board.canArchive == false)
    }

    @Test func canArchiveWhenEveryCardIsDone() {
        let board = BoardOverview(
            id: "1",
            name: "Work",
            summary: "",
            pinned: false,
            archived: false,
            spentHours: 1,
            todo: 0,
            inProgress: 0,
            done: 3,
            nextTitle: nil
        )
        #expect(board.canArchive)
    }

    @Test func emptyBoardCannotArchive() {
        let board = BoardOverview(
            id: "1",
            name: "Work",
            summary: "",
            pinned: false,
            archived: false,
            spentHours: 0,
            todo: 0,
            inProgress: 0,
            done: 0,
            nextTitle: nil
        )
        #expect(board.canArchive == false)
    }
}

struct BoardArchiveTests {
    @MainActor
    @Test func cannotArchiveUntilEveryCardIsDone() throws {
        let model = AppModel(stack: try TempoStore.memory())
        model.createBoard(name: "Ship")
        let boardID = try #require(model.selectedBoardID)
        #expect(model.canArchive(boardID) == false)

        let lists = model.fetchLists(boardID: boardID)
        let todo = try #require(lists.first { $0.role == .todo })
        let done = try #require(lists.first { $0.role == .done })
        for card in model.fetchCards(listID: todo.id) {
            model.moveCard(card.id, to: done.id)
        }
        #expect(model.canArchive(boardID))

        model.archiveBoard(boardID)
        #expect(model.fetchBoard(boardID)?.archived == true)
        #expect(model.fetchBoards().isEmpty)
        #expect(model.selectedBoardID == nil)
        #expect(model.boardOverviews(includeArchived: true).contains { $0.id == boardID && $0.archived })
    }

    @MainActor
    @Test func archiveDoesNothingWhenCardsRemainOpen() throws {
        let model = AppModel(stack: try TempoStore.memory())
        model.createBoard(name: "Open")
        let boardID = try #require(model.selectedBoardID)
        model.archiveBoard(boardID)
        #expect(model.fetchBoard(boardID)?.archived == false)
        #expect(model.selectedBoardID == boardID)
    }
}

struct FocusSessionTests {
    @MainActor
    @Test func pauseKeepsSessionImmersed() throws {
        let model = AppModel(stack: try TempoStore.memory())
        #expect(model.isFocusSession == false)
        model.start()
        #expect(model.isFocusSession)
        model.pause()
        #expect(model.isFocusSession)
        #expect(model.clock.runState == .paused)
        model.cancel()
        #expect(model.isFocusSession == false)
    }

    @MainActor
    @Test func inProgressCardsUsesFocusedList() throws {
        let model = AppModel(stack: try TempoStore.memory())
        model.createBoard(name: "Board")
        let boardID = try #require(model.selectedBoardID)
        let lists = model.fetchLists(boardID: boardID)
        let todo = try #require(lists.first { $0.role == .todo })
        let progress = try #require(lists.first { $0.role == .inProgress })
        #expect(model.inProgressCards(boardID: boardID).isEmpty)
        let card = try #require(model.fetchCards(listID: todo.id).first)
        model.moveCard(card.id, to: progress.id)
        let inProgress = model.inProgressCards(boardID: boardID)
        #expect(inProgress.count == 1)
        #expect(inProgress.first?.id == card.id)
    }

    @MainActor
    @Test func selectFocusCardMovesIntoInProgress() throws {
        let model = AppModel(stack: try TempoStore.memory())
        model.createBoard(name: "Board")
        let boardID = try #require(model.selectedBoardID)
        let todo = try #require(model.fetchLists(boardID: boardID).first { $0.role == .todo })
        let card = try #require(model.fetchCards(listID: todo.id).first)
        model.setBoard(boardID)
        model.selectFocusCard(card.id)
        #expect(model.clock.cardID == card.id)
        #expect(model.inProgressCards(boardID: boardID).contains { $0.id == card.id })
    }

    @Test func sidebarToggleHidesAndShowsDuringBoardSession() {
        let shown = FocusSplitVisibility.resolved(
            isFocusSession: true,
            hasBoard: true,
            sessionHidesSidebar: false,
            idle: .automatic
        )
        #expect(shown == .all)
        let hidden = FocusSplitVisibility.sessionHidesSidebar(
            current: false,
            isFocusSession: true,
            hasBoard: true,
            newValue: .detailOnly
        )
        #expect(hidden)
        #expect(
            FocusSplitVisibility.resolved(
                isFocusSession: true,
                hasBoard: true,
                sessionHidesSidebar: true,
                idle: .automatic
            ) == .detailOnly
        )
        let revealed = FocusSplitVisibility.sessionHidesSidebar(
            current: true,
            isFocusSession: true,
            hasBoard: true,
            newValue: .all
        )
        #expect(revealed == false)
    }

    @Test func idleSidebarToggleDoesNotUseSessionHide() {
        let idle = FocusSplitVisibility.resolved(
            isFocusSession: false,
            hasBoard: true,
            sessionHidesSidebar: true,
            idle: .automatic
        )
        #expect(idle == .automatic)
        #expect(
            FocusSplitVisibility.sessionHidesSidebar(
                current: false,
                isFocusSession: false,
                hasBoard: true,
                newValue: .detailOnly
            ) == false
        )
    }
}

struct ImportTests {
    @Test func mergeKeepsExistingIDs() {
        let existing = ImportBundle(sessions: [sample("a")], cards: [], lists: [], boards: [], moves: [])
        let incoming = ImportBundle(
            sessions: [
                sample("a", hours: 9),
                sample("b")
            ],
            cards: [],
            lists: [],
            boards: [],
            moves: []
        )
        let merged = DataMerger.merge(existing: existing, incoming: incoming)
        #expect(merged.sessions.map(\.id).sorted() == ["a", "b"])
        #expect(merged.sessions.first { $0.id == "a" }?.hours == 1)
    }

    @Test func jsonRoundTrip() throws {
        let bundle = ImportBundle(sessions: [sample("s")], cards: [], lists: [], boards: [], moves: [])
        let object = LegacyDecoder.exportObject(from: bundle)
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try #require(LegacyDecoder.bundle(fromJSON: data))
        #expect(decoded.sessions.map(\.id) == ["s"])
    }

    @Test func tagsMatchHashQuery() {
        #expect(TagParser.matches(query: "#ship", title: "Release #ship", notes: ""))
        #expect(!TagParser.matches(query: "#ship", title: "Release", notes: "notes"))
    }

    private func sample(_ id: String, hours: Double = 1) -> ImportedSession {
        ImportedSession(
            id: id,
            start: Date(timeIntervalSince1970: 1_700_000_000),
            hours: hours,
            switchTimes: 0,
            boardID: nil,
            rotten: false,
            efficiency: nil,
            primaryApp: nil,
            apps: [],
            titles: []
        )
    }
}

struct MiniTimerLayoutTests {
    @Test func compactFrameKeepsTopLeftOfOriginalWindow() {
        let full = CGRect(x: 120, y: 80, width: 1080, height: 720)
        let mini = MiniTimerLayout.compactFrame(from: full)
        #expect(mini.origin.x == 120)
        #expect(mini.width == MiniTimerLayout.size.width)
        #expect(mini.height == MiniTimerLayout.size.height)
        #expect(mini.maxY == full.maxY)
    }
}

struct MarkdownPreviewTests {
    @Test func listItemsStaySeparate() {
        #expect(MarkdownPreview.blocks(from: "- one\n- two").map(\.testLabel) == ["ul:one|two"])
    }

    @Test func headingDoesNotMergeIntoBody() {
        #expect(MarkdownPreview.blocks(from: "# Title\nbody").map(\.testLabel) == ["h1:Title", "p:body"])
    }

    @Test func hashTagIsNotAHeading() {
        #expect(MarkdownPreview.blocks(from: "#world").map(\.testLabel) == ["p:#world"])
    }

    @Test func singleNewlinesBecomeLineBreaks() {
        #expect(MarkdownPreview.blocks(from: "a\nb").map(\.testLabel) == ["p:a\nb"])
    }

    @Test func taskListKeepsCheckboxes() {
        #expect(
            MarkdownPreview.blocks(from: "- [ ] todo\n- [x] done").map(\.testLabel) == ["ul:[ ]todo|[x]done"]
        )
    }

    @Test func boldAndCodeStayInline() {
        let blocks = MarkdownPreview.blocks(from: "use `code` and **bold**")
        #expect(blocks.map(\.testLabel) == ["p:use code and bold"])
        guard case let .paragraph(text) = blocks.first else {
            Issue.record("expected paragraph")
            return
        }
        let intents = text.runs.compactMap(\.inlinePresentationIntent)
        #expect(intents.contains { $0.contains(.code) })
        #expect(intents.contains { $0.contains(.stronglyEmphasized) })
    }
}

struct MenuBarIconTests {
    @Test func signatureBucketsProgressAndMinutes() {
        let running = MenuBarIcon.signature(
            remaining: 25 * 60 - 1,
            progress: 0.12,
            running: true,
            phase: .focus,
            dark: false
        )
        #expect(running.minutes == 25)
        #expect(running.eighths == 1)
        #expect(running.running)
        let idle = MenuBarIcon.signature(
            remaining: 5 * 60,
            progress: 0,
            running: false,
            phase: .shortBreak,
            dark: true
        )
        #expect(idle.minutes == 5)
        #expect(idle.eighths == 0)
        #expect(idle.phase == .shortBreak)
    }
}

struct WindowTitleTests {
    @Test func attributedStringAndWhitespaceBecomeText() {
        #expect(WindowTitle.string(from: "  Hello  ") == "Hello")
        #expect(WindowTitle.string(from: NSAttributedString(string: "Doc.swift")) == "Doc.swift")
        #expect(WindowTitle.string(from: NSNumber(value: 1)).isEmpty)
    }

    @Test func documentNameUsesLastPathComponent() {
        #expect(WindowTitle.documentName("file:///Users/me/App.swift") == "App.swift")
        #expect(WindowTitle.documentName("/tmp/Notes.txt") == "Notes.txt")
        #expect(WindowTitle.documentName("Inbox") == "Inbox")
    }

    @Test func windowListPicksLargestNamedWindowForPID() {
        let windows: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: 10,
                kCGWindowLayer as String: 0,
                kCGWindowName as String: "Tiny",
                kCGWindowBounds as String: ["Width": 10.0, "Height": 10.0]
            ],
            [
                kCGWindowOwnerPID as String: 10,
                kCGWindowLayer as String: 0,
                kCGWindowName as String: "Main",
                kCGWindowBounds as String: ["Width": 800.0, "Height": 600.0]
            ],
            [
                kCGWindowOwnerPID as String: 10,
                kCGWindowLayer as String: 0,
                kCGWindowName as String: "",
                kCGWindowBounds as String: ["Width": 2000.0, "Height": 2000.0]
            ],
            [
                kCGWindowOwnerPID as String: 11,
                kCGWindowLayer as String: 0,
                kCGWindowName as String: "Other",
                kCGWindowBounds as String: ["Width": 9000.0, "Height": 9000.0]
            ]
        ]
        #expect(WindowTitle.fromWindowList(windows, pid: 10) == "Main")
    }

    @Test func emptyTitleIsNotCached() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            WindowTitle.shouldReuseCache(
                pid: 1,
                cachedPID: 1,
                cachedTitle: "",
                cachedAt: now,
                now: now
            ) == false
        )
        #expect(
            WindowTitle.shouldReuseCache(
                pid: 1,
                cachedPID: 1,
                cachedTitle: "X",
                cachedAt: now.addingTimeInterval(-2),
                now: now
            ) == false
        )
        #expect(
            WindowTitle.shouldReuseCache(
                pid: 1,
                cachedPID: 1,
                cachedTitle: "X",
                cachedAt: now,
                now: now
            )
        )
        #expect(
            WindowTitle.shouldReuseCache(
                pid: 2,
                cachedPID: 1,
                cachedTitle: "X",
                cachedAt: now,
                now: now
            ) == false
        )
    }
}

struct SankeyFlowTests {
    @Test func splitsFocusedAndDistracted() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            ActivitySample(id: 1, sessionID: "s", capturedAt: start, appName: "Xcode", windowTitle: "App.swift", bundleID: "dev.apple.xcode"),
            ActivitySample(id: 2, sessionID: "s", capturedAt: start.addingTimeInterval(10), appName: "Mail", windowTitle: "Inbox", bundleID: "com.apple.mail"),
            ActivitySample(id: 3, sessionID: "s", capturedAt: start.addingTimeInterval(20), appName: "Mail", windowTitle: "Inbox", bundleID: "com.apple.mail")
        ]
        let rules = [DistractionRule(id: "mail", app: "Mail", title: "")]
        let diagram = SankeyFlow.make(samples: samples, rules: rules, fallbackInterval: 2)
        #expect(diagram.nodes.contains { $0.id == SankeyFlow.focusedID })
        #expect(diagram.nodes.contains { $0.id == SankeyFlow.distractedID })
        #expect(diagram.links.contains { $0.distracted })
        #expect(diagram.links.contains { !$0.distracted && $0.target == SankeyFlow.focusedID })
    }

    @Test func compactedKeepsTheLargestTitles() {
        let intervals = (0..<12).map { index in
            FocusInterval(
                id: "\(index)",
                start: Double(index),
                duration: Double(12 - index),
                app: "Xcode",
                title: "File\(index).swift",
                distracted: false
            )
        }
        let compacted = SankeyFlow.compacted(SankeyFlow.make(intervals: intervals), maxTitles: 4)
        let titles = compacted.nodes.filter { $0.column == 1 }
        #expect(titles.count == 4)
        #expect(titles.contains { $0.id == "title-other" })
    }
}

struct SankeyLayoutTests {
    @Test func placesThreeColumnsAndRibbons() {
        let intervals = [
            FocusInterval(id: "1", start: 0, duration: 20, app: "Xcode", title: "App.swift", distracted: false),
            FocusInterval(id: "2", start: 20, duration: 10, app: "Mail", title: "Inbox", distracted: true)
        ]
        let diagram = SankeyFlow.make(intervals: intervals)
        let placed = SankeyLayout.place(diagram, in: CGSize(width: 640, height: 280))
        #expect(placed.nodes.contains { $0.column == 0 })
        #expect(placed.nodes.contains { $0.column == 1 })
        #expect(placed.nodes.contains { $0.column == 2 })
        #expect(!placed.links.isEmpty)
        #expect(placed.nodes.allSatisfy { $0.frame.height >= 1 })
    }
}

struct FocusLaneTests {
    @Test func mergesAdjacentSamplesFromTheSameApp() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            ActivitySample(id: 1, sessionID: "s", capturedAt: start, appName: "Xcode", windowTitle: "App.swift", bundleID: "dev.apple.xcode"),
            ActivitySample(id: 2, sessionID: "s", capturedAt: start.addingTimeInterval(10), appName: "Xcode", windowTitle: "App.swift", bundleID: "dev.apple.xcode"),
            ActivitySample(id: 3, sessionID: "s", capturedAt: start.addingTimeInterval(20), appName: "Mail", windowTitle: "Inbox", bundleID: "com.apple.mail")
        ]
        let session = SessionFact(
            id: "s",
            start: start,
            seconds: 30,
            boardID: nil,
            rotten: false,
            counts: true,
            efficiency: nil,
            primaryApp: "Xcode",
            apps: [],
            titles: []
        )
        let intervals = FocusLane.make(
            samples: samples,
            session: session,
            rules: [DistractionRule(id: "mail", app: "Mail", title: "")],
            fallback: 2
        )
        #expect(intervals.count == 2)
        #expect(intervals[0].app == "Xcode")
        #expect(intervals[0].distracted == false)
        #expect(intervals[1].app == "Mail")
        #expect(intervals[1].distracted)
        #expect(abs(FocusLane.focusedSeconds(intervals) - 20) < 0.01)
    }

    @Test func fallsBackToAppSlicesWhenSamplesAreMissing() {
        let session = SessionFact(
            id: "s",
            start: .now,
            seconds: 1500,
            boardID: nil,
            rotten: false,
            counts: true,
            efficiency: nil,
            primaryApp: "Xcode",
            apps: [
                AppSlice(name: "Xcode", seconds: 1000),
                AppSlice(name: "Safari", seconds: 500)
            ],
            titles: []
        )
        let intervals = FocusLane.make(samples: [], session: session, rules: [], fallback: 2)
        #expect(intervals.map(\.app) == ["Xcode", "Safari"])
        #expect(abs(intervals.reduce(0) { $0 + $1.duration } - 1500) < 0.01)
    }
}

struct StatisticsRangeTests {
    @Test func dayRangeUsesTwentyFourHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_724_000_000)
        let snapshot = Analytics.make(sessions: [], cards: [], range: .day, now: now, calendar: calendar)
        #expect(snapshot.points.count == 24)
    }

    @Test func weekRangeOnlyCountsThisWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = Date(timeIntervalSince1970: 1_724_000_000)
        let inside = SessionFact(
            id: "in",
            start: now,
            seconds: 1500,
            boardID: nil,
            rotten: false,
            counts: true,
            efficiency: nil,
            primaryApp: nil,
            apps: [],
            titles: []
        )
        let outside = SessionFact(
            id: "out",
            start: now.addingTimeInterval(-40 * 24 * 3600),
            seconds: 1500,
            boardID: nil,
            rotten: false,
            counts: true,
            efficiency: nil,
            primaryApp: nil,
            apps: [],
            titles: []
        )
        let snapshot = Analytics.make(sessions: [inside, outside], cards: [], range: .week, now: now, calendar: calendar)
        #expect(snapshot.pomodoros == 1)
    }
}

struct PomodoroTallyTests {
    @Test func countsTodayWeekAndMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_724_000_000)
        let sessions = [
            SessionFact(id: "a", start: now, seconds: 1500, boardID: nil, rotten: false, counts: true, efficiency: nil, primaryApp: nil, apps: [], titles: []),
            SessionFact(id: "b", start: now.addingTimeInterval(-3 * 24 * 3600), seconds: 1500, boardID: nil, rotten: false, counts: true, efficiency: nil, primaryApp: nil, apps: [], titles: []),
            SessionFact(id: "c", start: now.addingTimeInterval(-40 * 24 * 3600), seconds: 1500, boardID: nil, rotten: false, counts: true, efficiency: nil, primaryApp: nil, apps: [], titles: []),
            SessionFact(id: "d", start: now, seconds: 120, boardID: nil, rotten: true, counts: false, efficiency: nil, primaryApp: nil, apps: [], titles: [])
        ]
        let tally = Analytics.pomodoroTally(sessions: sessions, now: now, calendar: calendar)
        #expect(tally.today == 1)
        #expect(tally.week >= 1)
        #expect(tally.month >= tally.week)
    }
}

struct PermissionAskTests {
    @Test func promptsOnlyOnceUntilGranted() {
        #expect(PermissionAsk.shouldShowSystemPrompt(didAsk: false, isGranted: false))
        #expect(!PermissionAsk.shouldShowSystemPrompt(didAsk: true, isGranted: false))
        #expect(!PermissionAsk.shouldShowSystemPrompt(didAsk: false, isGranted: true))
        #expect(!PermissionAsk.shouldShowSystemPrompt(didAsk: true, isGranted: true))
    }

    @Test func settingsOpensSystemSettingsAfterDenial() {
        #expect(PermissionAsk.settingsAction(didAsk: false, isGranted: false) == .askSystem)
        #expect(PermissionAsk.settingsAction(didAsk: true, isGranted: false) == .openSystemSettings)
        #expect(PermissionAsk.settingsAction(didAsk: true, isGranted: true) == .none)
        #expect(PermissionAsk.settingsAction(didAsk: false, isGranted: true) == .none)
    }

    @Test func loadsLegacySettingsWithoutPermissionFlags() throws {
        let json = """
        {"focusMinutes":30,"shortBreakMinutes":5,"longBreakMinutes":15,"longBreakInterval":4,"monitorInterval":2,"confirmDeleteCard":true,"notificationsEnabled":true,"soundEnabled":true,"suggestBoard":true,"appearance":"dark","language":"zh-Hans","distractionRules":[],"welcomed":true}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.focusMinutes == 30)
        #expect(settings.welcomed)
        #expect(settings.appearance == .dark)
        #expect(!settings.askedAccessibility)
        #expect(!settings.askedNotifications)
    }
}

