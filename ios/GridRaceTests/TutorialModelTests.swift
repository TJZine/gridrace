import XCTest
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
        let model = makeModel(now: { base })
        defer { model.cancelSessionTasks() }

        model.startTutorial()
        model.update(at: base.addingTimeInterval(3))
        XCTAssertEqual(model.phase, .playing)
        XCTAssertEqual(model.roundSecondsRemaining, 180)

        model.update(at: base.addingTimeInterval(35))
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
        let model = makeModel(now: { base })
        defer { model.cancelSessionTasks() }
        model.startTutorial()
        model.update(at: base.addingTimeInterval(3))
        for letter in "zzzzz" { model.typeLetter(letter) }
        model.submitGuess()

        XCTAssertEqual(model.phase, .playing)
        XCTAssertEqual(model.board.rows.count, 0)
        XCTAssertEqual(model.board.draft, "ZZZZZ")
        XCTAssertNotNil(model.errorMessage)
    }

    func testReducedMotionRevealIsCompleteImmediatelyAndLocalFirst() {
        let base = Date(timeIntervalSinceReferenceDate: 4_000)
        let model = makeModel(now: { base })
        model.setReduceMotion(true)
        model.startTutorial()
        model.update(at: base.addingTimeInterval(3))
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
        let model = makeModel(now: { base })
        defer { model.cancelSessionTasks() }
        model.startTutorial()
        model.update(at: base.addingTimeInterval(3))
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
        let model = makeModel(now: { base })
        defer { model.cancelSessionTasks() }
        model.setReduceMotion(true)
        model.startTutorial()
        model.update(at: base.addingTimeInterval(183))

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
