import XCTest
import SwiftUI
@testable import GridRace

@MainActor
final class TutorialModelTests: XCTestCase {
    private let words: Set<String> = [
        "stone", "crane", "grape", "civic", "bloom", "mouse", "faith", "earth", "grace"
    ]

    func testCountdownUsesAbsoluteTimestampsAcrossJumps() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let window = CountdownWindow(
            startsAt: start.addingTimeInterval(3),
            endsAt: start.addingTimeInterval(183)
        )

        XCTAssertEqual(window.state(at: start), .countdown(3))
        XCTAssertEqual(window.state(at: start.addingTimeInterval(2.2)), .countdown(1))
        XCTAssertEqual(window.state(at: start.addingTimeInterval(3)), .playing(180))
        XCTAssertEqual(window.state(at: start.addingTimeInterval(183)), .expired)
        XCTAssertEqual(window.state(at: start.addingTimeInterval(1_000)), .expired)
    }

    func testCountdownTaskCanBeCancelled() {
        let model = makeModel()
        model.startTutorial()
        XCTAssertTrue(model.countdownTaskIsActive)
        model.cancelSessionTasks()
        XCTAssertFalse(model.countdownTaskIsActive)
    }

    func testCountdownCompletionAndGhostProgressExposeOnlyCoarseState() {
        let base = Date(timeIntervalSinceReferenceDate: 2_000)
        var clock = base
        let model = makeModel(now: { clock })
        defer { model.cancelSessionTasks() }

        model.startTutorial()
        clock = base.addingTimeInterval(3)
        model.refreshFromClock()
        XCTAssertEqual(model.phase, .playing)
        XCTAssertEqual(model.roundSecondsRemaining, 180)

        clock = base.addingTimeInterval(35)
        model.refreshFromClock()
        XCTAssertEqual(model.opponents[0].acceptedGuessCount, 3)
        XCTAssertEqual(model.opponents[0].state, .solved)
        XCTAssertEqual(model.opponents[1].acceptedGuessCount, 3)
        XCTAssertEqual(model.opponents[1].state, .playing)
        XCTAssertEqual(
            model.opponents[1].accessibilityLabel,
            "Opponent Sam, 3 guesses submitted, still playing, connected."
        )
    }

    func testInvalidTutorialGuessKeepsDraftAndRow() {
        let base = Date(timeIntervalSinceReferenceDate: 3_000)
        var clock = base
        let model = makeModel(now: { clock })
        defer { model.cancelSessionTasks() }
        model.startTutorial()
        clock = base.addingTimeInterval(3)
        model.refreshFromClock()
        for letter in "zzzzz" { model.typeLetter(letter) }
        model.submitGuess()

        XCTAssertEqual(model.phase, .playing)
        XCTAssertEqual(model.board.rows.count, 0)
        XCTAssertEqual(model.board.draft, "ZZZZZ")
        XCTAssertNotNil(model.errorMessage)
    }

    func testTutorialEditingUsesLetterAndDeleteIntentsDuringPlay() {
        let base = Date(timeIntervalSinceReferenceDate: 3_500)
        var clock = base
        let model = makeModel(now: { clock })
        defer { model.cancelSessionTasks() }
        model.startTutorial()
        clock = base.addingTimeInterval(3)
        model.refreshFromClock()

        for letter in "ston" { model.typeLetter(letter) }
        XCTAssertEqual(model.board.draft, "STON")

        model.deleteLetter()
        XCTAssertEqual(model.board.draft, "STO")
    }

    func testTutorialInputIntentsAreIgnoredOutsidePlayingRoute() {
        let base = Date(timeIntervalSinceReferenceDate: 3_600)
        var clock = base
        let model = makeModel(now: { clock })
        defer { model.cancelSessionTasks() }

        model.typeLetter("s")
        model.deleteLetter()
        model.submitGuess()
        XCTAssertEqual(model.phase, .introduction)
        XCTAssertEqual(model.board.draft, "")

        model.startTutorial()
        clock = base.addingTimeInterval(3)
        model.refreshFromClock()
        for letter in "stone" { model.typeLetter(letter) }
        model.submitGuess()
        XCTAssertEqual(model.phase, .reveal)

        model.typeLetter("a")
        model.deleteLetter()
        model.submitGuess()
        XCTAssertEqual(model.phase, .reveal)
        XCTAssertEqual(model.board.draft, "")
    }

    func testReducedMotionRevealIsCompleteImmediatelyAndLocalFirst() {
        let base = Date(timeIntervalSinceReferenceDate: 4_000)
        var clock = base
        let model = makeModel(now: { clock })
        model.setReduceMotion(true)
        model.startTutorial()
        clock = base.addingTimeInterval(3)
        model.refreshFromClock()
        for letter in "stone" { model.typeLetter(letter) }
        model.submitGuess()

        XCTAssertEqual(model.phase, .reveal)
        XCTAssertEqual(model.revealBoards.map(\.name), ["You", "Alex", "Sam"])
        XCTAssertEqual(model.revealBoards.map(\.rows.count), [1, 3, 6])
        XCTAssertEqual(model.visibleRows(in: 0), 1)
        XCTAssertEqual(model.visibleRows(in: 1), 3)
        XCTAssertEqual(model.visibleRows(in: 2), 6)
        XCTAssertTrue(model.revealSummaryVisible)
        XCTAssertFalse(model.revealTaskIsActive)
    }

    func testAnimatedRevealAdvancesOneOriginalRowAtATime() {
        let base = Date(timeIntervalSinceReferenceDate: 5_000)
        var clock = base
        let model = makeModel(now: { clock })
        defer { model.cancelSessionTasks() }
        model.startTutorial()
        clock = base.addingTimeInterval(3)
        model.refreshFromClock()
        for letter in "stone" { model.typeLetter(letter) }
        model.submitGuess()

        XCTAssertEqual(model.phase, .reveal)
        XCTAssertEqual(model.visibleRevealRowCount, 0)
        XCTAssertFalse(model.revealSummaryVisible)

        model.advanceReveal()
        XCTAssertEqual(model.visibleRows(in: 0), 1)
        XCTAssertEqual(model.visibleRows(in: 1), 0)
        for _ in 1..<10 { model.advanceReveal() }
        XCTAssertEqual(model.visibleRows(in: 2), 6)
        XCTAssertTrue(model.revealSummaryVisible)
    }

    func testDeadlineTimesOutAndStartsReveal() {
        let base = Date(timeIntervalSinceReferenceDate: 6_000)
        var clock = base
        let model = makeModel(now: { clock })
        defer { model.cancelSessionTasks() }
        model.setReduceMotion(true)
        model.startTutorial()
        clock = base.addingTimeInterval(183)
        model.refreshFromClock()

        XCTAssertEqual(model.phase, .reveal)
        XCTAssertEqual(model.board.status, .timedOut)
        XCTAssertEqual(model.revealBoards.first?.result, "Timed out")
    }

    func testReplayCancelsWorkAndReturnsToIntroduction() {
        let model = makeModel()
        model.startTutorial()
        model.replay()
        XCTAssertEqual(model.phase, .introduction)
        XCTAssertFalse(model.countdownTaskIsActive)
        XCTAssertFalse(model.revealTaskIsActive)
        XCTAssertEqual(model.board.rows.count, 0)
    }

    func testSubmitReconcilesCachedPlayingAtAbsoluteDeadline() {
        let base = Date(timeIntervalSinceReferenceDate: 7_000)
        for elapsed in [182.999, 183, 183.001, 1_000] {
            var clock = base
            var clockReads = 0
            let model = makeModel(now: {
                clockReads += 1
                return clock
            })
            defer { model.cancelSessionTasks() }
            model.startTutorial()
            clock = base.addingTimeInterval(3)
            model.refreshFromClock()
            for letter in "stone" { model.typeLetter(letter) }

            // No timer tick occurs between the clock jump and Submit.
            clock = base.addingTimeInterval(elapsed)
            clockReads = 0
            XCTAssertEqual(model.phase, .playing)
            model.submitGuess()

            XCTAssertEqual(clockReads, 1)
            XCTAssertEqual(model.phase, .reveal)
            XCTAssertFalse(model.countdownTaskIsActive)
            if elapsed < 183 {
                XCTAssertEqual(model.board.status, .solved)
                XCTAssertEqual(model.board.rows.map(\.word), ["stone"])
                XCTAssertEqual(model.hapticEvent, 1)
                XCTAssertEqual(model.revealBoards.first?.result, "Solved")
            } else {
                XCTAssertEqual(model.board.status, .timedOut)
                XCTAssertTrue(model.board.rows.isEmpty)
                XCTAssertEqual(model.hapticEvent, 0)
                XCTAssertEqual(model.revealBoards.first?.result, "Timed out")
            }

            model.advanceReveal()
            let revealedBoards = model.revealBoards
            let visibleRows = model.visibleRevealRowCount
            let opponents = model.opponents
            let terminalBoard = model.board
            clock = base.addingTimeInterval(2_000)
            model.refreshFromClock()
            model.typeLetter("a")
            model.deleteLetter()
            model.submitGuess()

            XCTAssertEqual(model.board, terminalBoard)
            XCTAssertEqual(model.revealBoards, revealedBoards)
            XCTAssertEqual(model.visibleRevealRowCount, visibleRows)
            XCTAssertEqual(model.opponents, opponents)
        }
    }

    func testSubmitReconcilesCountdownBoundaryBeforeAcceptingInput() {
        let base = Date(timeIntervalSinceReferenceDate: 8_000)
        var clock = base
        let model = makeModel(now: { clock })
        defer { model.cancelSessionTasks() }
        model.startTutorial()

        clock = base.addingTimeInterval(2.999)
        model.submitGuess()
        model.typeLetter("c")
        XCTAssertEqual(model.phase, .countdown)
        XCTAssertEqual(model.countdownSeconds, 1)
        XCTAssertTrue(model.board.rows.isEmpty)
        XCTAssertEqual(model.board.draft, "")

        clock = base.addingTimeInterval(3)
        model.submitGuess()
        XCTAssertEqual(model.phase, .playing)
        XCTAssertEqual(model.roundSecondsRemaining, 180)
        for letter in "crane" { model.typeLetter(letter) }
        model.submitGuess()
        XCTAssertEqual(model.board.rows.map(\.word), ["crane"])
        XCTAssertEqual(model.board.status, .playing)

        model.replay()
        XCTAssertEqual(model.phase, .introduction)
        model.startTutorial()
        // A background jump can skip the entire countdown and round.
        clock = clock.addingTimeInterval(1_000)
        model.submitGuess()
        XCTAssertEqual(model.phase, .reveal)
        XCTAssertEqual(model.board.status, .timedOut)
        XCTAssertTrue(model.board.rows.isEmpty)
    }

    func testPracticeGameplayContainmentAndAccessibilityReachability() async throws {
        for accessibility in [false, true] {
            for landscape in accessibility ? [false] : [false, true] {
                let base = Date(timeIntervalSinceReferenceDate: 3_000)
                var clock = base.addingTimeInterval(3)
                let model = makeModel(now: { clock })
                model.startTutorial()
                clock = base.addingTimeInterval(6)
                model.refreshFromClock()
                defer { model.cancelSessionTasks() }
                let hosted = try await GameplayContainmentHost(
                    GameplayRouteView(.tutorial) {
                        TutorialView(model: model, hapticsEnabled: .constant(false))
                    }, landscape: landscape, accessibility: accessibility)
                defer { hosted.close() }
                try hosted.assertGameplay(in: self, name: "practice-playing", opponents: 2, hasTimer: true)
                for letter in "zzzzz" { model.typeLetter(letter) }
                model.submitGuess()
                try await hosted.settle()
                try hosted.assertGameplay(in: self, name: "practice-error", notices: [try XCTUnwrap(model.errorMessage)], opponents: 2, hasTimer: true)
            }
        }
    }

    private func makeModel(
        now: @escaping @MainActor () -> Date = { Date(timeIntervalSinceReferenceDate: 10_000) }
    ) -> TutorialModel {
        TutorialModel(
            acceptedWords: words,
            now: now,
            sleep: { _ in try await Task<Never, Never>.sleep(for: .seconds(60)) }
        )
    }
}
