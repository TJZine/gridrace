import Foundation
import XCTest
@testable import GridRace

final class DailyClassicTests: XCTestCase {
    private let epochDay = 20_696
    private let accepted = Set(["stone", "civic", "crane", "bloom", "mouse", "sassy", "assay"])

    func testUTCIdentitySelectionAndResetAreStable() throws {
        let pack = try DailyWordPack.load(from: packData())
        let firstDate = date(day: epochDay, seconds: 123)
        let secondDate = date(day: epochDay + 1, seconds: 1)

        let first = try DailyPuzzleSchedule.puzzle(at: firstDate, in: pack)
        let second = try DailyPuzzleSchedule.puzzle(at: secondDate, in: pack)
        XCTAssertEqual(first.id, "daily-classic-2026-08-31")
        XCTAssertEqual(first.number, 1)
        XCTAssertEqual(first.answer, "stone")
        XCTAssertEqual(second.number, 2)
        XCTAssertEqual(second.answer, "civic")
        XCTAssertEqual(
            DailyPuzzleSchedule.nextReset(after: firstDate),
            date(day: epochDay + 1)
        )
        XCTAssertThrowsError(try DailyPuzzleSchedule.puzzle(at: date(day: epochDay - 1), in: pack))
        XCTAssertThrowsError(try DailyPuzzleSchedule.puzzle(at: date(day: epochDay + 3), in: pack))
    }

    func testWordPackRejectsScheduleAndDictionaryDrift() throws {
        XCTAssertNoThrow(try DailyWordPack.load(from: packData()))
        XCTAssertThrowsError(try DailyWordPack.load(from: packData(answers: ["stone", "stone"])))
        XCTAssertThrowsError(try DailyWordPack.load(from: packData(answers: ["other"])))
    }

    func testBundledWordPackIdentityIsPinned() throws {
        let published = try DailyWordPack.load(from: packData(
            id: "daily-classic-en-US-v1",
            epochDay: 20_696
        ))
        XCTAssertNoThrow(try DailyWordPack.validateBundledIdentity(published))

        let wrongID = try DailyWordPack.load(from: packData(id: "replacement", epochDay: 20_696))
        XCTAssertThrowsError(try DailyWordPack.validateBundledIdentity(wrongID))
        let wrongSchedule = try DailyWordPack.load(from: packData(
            id: "daily-classic-en-US-v1",
            scheduleVersion: 2,
            epochDay: 20_696
        ))
        XCTAssertThrowsError(try DailyWordPack.validateBundledIdentity(wrongSchedule))
        let wrongEpoch = try DailyWordPack.load(from: packData(
            id: "daily-classic-en-US-v1",
            epochDay: 20_697
        ))
        XCTAssertThrowsError(try DailyWordPack.validateBundledIdentity(wrongEpoch))
    }

    func testSixthGuessCanWinOrFailAndCompletionIsImmutable() throws {
        var solved = game(answer: "stone")
        for _ in 0..<5 { submit("civic", to: &solved) }
        let final = submit("stone", to: &solved)
        XCTAssertEqual(final.completion?.outcome, .solved)
        XCTAssertEqual(final.completion?.guessCount, 6)
        let completed = solved.progress
        solved.type("A")
        solved.deleteBackward()
        _ = solved.setHardMode(true)
        _ = solved.submit()
        XCTAssertEqual(solved.progress, completed)

        var failed = game(answer: "stone")
        for _ in 0..<6 { submit("civic", to: &failed) }
        XCTAssertEqual(failed.completion?.outcome, .failed)
        XCTAssertEqual(failed.progress.acceptedGuesses.count, 6)
    }

    func testProgressRoundTripsWithDraftAndRows() throws {
        let puzzle = puzzle(answer: "stone")
        var original = DailyClassicGame(puzzle: puzzle, acceptedWords: accepted)
        _ = submit("civic", to: &original)
        original.type("C")
        original.type("R")

        let data = try DailyClassicPersistence.encode(original.progress)
        let saved = try DailyClassicPersistence.decodeProgress(from: data)
        let restored = try DailyClassicGame(puzzle: puzzle, acceptedWords: accepted, restoring: saved)
        XCTAssertEqual(restored.progress, original.progress)
        XCTAssertEqual(restored.draft, "CR")
        XCTAssertEqual(restored.rows.count, 1)
        XCTAssertEqual(restored.keyboard.feedback(for: "C"), .absent)
    }

    func testAcceptedTimestampsClampWhenClockMovesBackward() throws {
        var game = game(answer: "stone")
        for letter in "civic" { game.type(letter) }
        _ = game.submit(at: date(day: epochDay, seconds: 100))
        for letter in "stone" { game.type(letter) }
        _ = game.submit(at: date(day: epochDay, seconds: 50))

        XCTAssertEqual(game.progress.acceptedGuesses.map(\.acceptedAt), [
            date(day: epochDay, seconds: 100),
            date(day: epochDay, seconds: 100)
        ])
        XCTAssertEqual(game.completion?.completedAt, date(day: epochDay, seconds: 100))
        XCTAssertNoThrow(try DailyClassicGame(
            puzzle: game.puzzle,
            acceptedWords: accepted,
            restoring: game.progress
        ))
    }

    func testRestoreRejectsWrongPuzzleOrTamperedFeedback() throws {
        let originalPuzzle = puzzle(answer: "stone")
        var original = DailyClassicGame(puzzle: originalPuzzle, acceptedWords: accepted)
        _ = submit("civic", to: &original)
        XCTAssertThrowsError(
            try DailyClassicGame(
                puzzle: puzzle(answer: "stone", day: epochDay + 1),
                acceptedWords: accepted,
                restoring: original.progress
            )
        )

        var tampered = original.progress
        tampered.acceptedGuesses[0] = DailyGuess(
            word: "civic",
            feedback: Array(repeating: .correct, count: 5),
            acceptedAt: Date()
        )
        XCTAssertThrowsError(
            try DailyClassicGame(puzzle: originalPuzzle, acceptedWords: accepted, restoring: tampered)
        )
    }

    func testHardModeRequiresGreensYellowsAndDuplicateMinimums() {
        let green = [
            DailyGuess(word: "stone", feedback: [.correct, .absent, .absent, .absent, .absent], acceptedAt: Date())
        ]
        XCTAssertEqual(
            DailyHardMode.violation(for: "crane", previous: green),
            .requiredPosition(letter: "s", position: 0)
        )

        let yellow = [
            DailyGuess(word: "crane", feedback: [.present, .absent, .absent, .absent, .absent], acceptedAt: Date())
        ]
        XCTAssertEqual(
            DailyHardMode.violation(for: "civic", previous: yellow),
            .misplacedPosition(letter: "c", position: 0)
        )

        let duplicate = [
            DailyGuess(word: "sassy", feedback: [.present, .correct, .correct, .absent, .absent], acceptedAt: Date())
        ]
        XCTAssertEqual(
            DailyHardMode.violation(for: "crane", previous: duplicate),
            .requiredPosition(letter: "a", position: 1)
        )
        XCTAssertEqual(
            DailyHardMode.violation(for: "basic", previous: duplicate),
            .missingLetter(letter: "s", minimumCount: 2)
        )
    }

    func testHardModeLocksAfterFirstAcceptedGuess() {
        var game = game(answer: "stone")
        XCTAssertTrue(game.setHardMode(true))
        _ = submit("civic", to: &game)
        XCTAssertFalse(game.setHardMode(false))
        XCTAssertTrue(game.progress.hardModeEnabled)
    }

    func testHardModeRejectionDoesNotConsumeGuess() {
        var game = DailyClassicGame(
            puzzle: puzzle(answer: "assay"),
            acceptedWords: accepted,
            hardModeEnabled: true
        )
        _ = submit("sassy", to: &game)
        let rejected = submit("sassy", to: &game)
        XCTAssertEqual(
            rejected.error,
            .hardMode(.misplacedPosition(letter: "s", position: 0))
        )
        XCTAssertEqual(game.rows.count, 1)
        XCTAssertEqual(game.draft, "SASSY")
    }

    func testStatisticsApplyOnceAndCalculateStreaks() {
        var history = DailyClassicHistory()
        let day1 = result(day: epochDay, outcome: .solved, guesses: 3)
        let day2 = result(day: epochDay + 1, outcome: .solved, guesses: 2)
        let day4 = result(day: epochDay + 3, outcome: .solved, guesses: 4)
        let day5 = result(day: epochDay + 4, outcome: .failed, guesses: 6)

        XCTAssertTrue(history.record(day1))
        XCTAssertFalse(history.record(day1))
        XCTAssertTrue(history.record(day2))
        XCTAssertEqual(history.statistics.currentStreak, 2)
        XCTAssertTrue(history.record(day4))
        XCTAssertEqual(history.statistics.currentStreak, 1, "A missed day breaks the streak")
        XCTAssertTrue(history.record(day5))
        XCTAssertEqual(history.statistics.currentStreak, 0, "A failed puzzle breaks the streak")
        XCTAssertEqual(history.statistics.longestStreak, 2)
        XCTAssertEqual(history.statistics.gamesPlayed, 4)
        XCTAssertEqual(history.statistics.gamesWon, 3)
        XCTAssertEqual(history.statistics.solvePercentage, 75)
        XCTAssertEqual(history.statistics.guessDistribution, [2: 1, 3: 1, 4: 1])
    }

    func testMissedDayHidesOtherwiseStoredCurrentStreak() {
        var history = DailyClassicHistory()
        _ = history.record(result(day: epochDay, outcome: .solved, guesses: 2))
        XCTAssertEqual(
            history.statistics.currentStreak(asOf: epochDay + 1, latestResultDay: history.latestResultDay),
            1
        )
        XCTAssertEqual(
            history.statistics.currentStreak(asOf: epochDay + 2, latestResultDay: history.latestResultDay),
            0
        )
    }

    func testHistoryAndSettingsRoundTrip() throws {
        var history = DailyClassicHistory()
        _ = history.record(result(day: epochDay, outcome: .solved, guesses: 2))
        let restored = try DailyClassicHistory.load(from: DailyClassicPersistence.encode(history))
        XCTAssertEqual(restored, history)

        let suite = "DailyClassicTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DailyClassicSettings(
            hapticsEnabled: false,
            highContrastEnabled: true,
            hardModeEnabled: true
        )
        try settings.save(to: defaults)
        XCTAssertEqual(DailyClassicSettings.load(from: defaults), settings)
    }

    func testHistoryMigratesLegacyFormatAndRejectsUnknownVersion() throws {
        var history = DailyClassicHistory()
        _ = history.record(result(day: epochDay, outcome: .solved, guesses: 2))
        let encoded = try DailyClassicPersistence.encode(history)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        object.removeValue(forKey: "formatVersion")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try DailyClassicHistory.load(from: legacy), history)

        object["formatVersion"] = 2
        let future = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try DailyClassicHistory.load(from: future))
    }

    func testCanonicalV1IdentityRejectsInconsistentTuplesAndOutOfRangeDays() {
        let firstID = "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: epochDay))"
        let lastDay = DailyPuzzleIdentity.lastDay
        let lastID = "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: lastDay))"
        func candidate(
            puzzleID: String,
            puzzleNumber: Int,
            puzzleDay: Int,
            wordPackID: String,
            scheduleVersion: Int,
            completedAt: Date
        ) -> DailyCompletedResult {
            DailyCompletedResult(
                puzzleID: puzzleID,
                puzzleNumber: puzzleNumber,
                puzzleDay: puzzleDay,
                wordPackID: wordPackID,
                scheduleVersion: scheduleVersion,
                guesses: [
                    DailyGuess(
                        word: "civic",
                        feedback: Array(repeating: .absent, count: 5),
                        acceptedAt: date(day: puzzleDay)
                    ),
                    DailyGuess(
                        word: "stone",
                        feedback: Array(repeating: .correct, count: 5),
                        acceptedAt: date(day: puzzleDay, seconds: 1)
                    )
                ],
                outcome: .solved,
                guessCount: 2,
                completedAt: completedAt
            )
        }

        var history = DailyClassicHistory()
        // Structurally valid shape with a number from another schedule day.
        XCTAssertFalse(history.record(candidate(
            puzzleID: firstID, puzzleNumber: 2, puzzleDay: epochDay,
            wordPackID: "daily-classic-en-US-v1", scheduleVersion: 1,
            completedAt: date(day: epochDay, seconds: 100)
        )))
        // Puzzle id names a different day than the puzzle day.
        XCTAssertFalse(history.record(candidate(
            puzzleID: "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: epochDay + 1))",
            puzzleNumber: 1, puzzleDay: epochDay,
            wordPackID: "daily-classic-en-US-v1", scheduleVersion: 1,
            completedAt: date(day: epochDay, seconds: 100)
        )))
        // Legacy word-pack id and non-v1 schedule version.
        XCTAssertFalse(history.record(candidate(
            puzzleID: firstID, puzzleNumber: 1, puzzleDay: epochDay,
            wordPackID: "daily-classic-v1", scheduleVersion: 1,
            completedAt: date(day: epochDay, seconds: 100)
        )))
        XCTAssertFalse(history.record(candidate(
            puzzleID: firstID, puzzleNumber: 1, puzzleDay: epochDay,
            wordPackID: "daily-classic-en-US-v1", scheduleVersion: 2,
            completedAt: date(day: epochDay, seconds: 100)
        )))
        // Days outside the published 725-answer schedule.
        XCTAssertFalse(history.record(candidate(
            puzzleID: "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: epochDay - 1))",
            puzzleNumber: 0, puzzleDay: epochDay - 1,
            wordPackID: "daily-classic-en-US-v1", scheduleVersion: 1,
            completedAt: date(day: epochDay - 1, seconds: 100)
        )))
        XCTAssertFalse(history.record(candidate(
            puzzleID: "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: lastDay + 1))",
            puzzleNumber: DailyPuzzleIdentity.lastNumber + 1, puzzleDay: lastDay + 1,
            wordPackID: "daily-classic-en-US-v1", scheduleVersion: 1,
            completedAt: date(day: lastDay + 1, seconds: 100)
        )))
        XCTAssertTrue(history.completedResults.isEmpty)

        // Schedule boundaries are accepted: #1 on the epoch day, #725 last.
        XCTAssertTrue(history.record(candidate(
            puzzleID: firstID, puzzleNumber: 1, puzzleDay: epochDay,
            wordPackID: "daily-classic-en-US-v1", scheduleVersion: 1,
            completedAt: date(day: epochDay, seconds: 100)
        )))
        XCTAssertTrue(history.record(candidate(
            puzzleID: lastID,
            puzzleNumber: DailyPuzzleIdentity.lastNumber,
            puzzleDay: lastDay,
            wordPackID: "daily-classic-en-US-v1", scheduleVersion: 1,
            completedAt: date(day: lastDay, seconds: 100)
        )))
        XCTAssertEqual(history.completedResults.map(\.puzzleNumber), [1, 725])
    }

    func testCompletedResultReconstructsImmutableProgress() throws {
        let completed = DailyCompletedResult(
            puzzleID: "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: epochDay))",
            puzzleNumber: 1,
            puzzleDay: epochDay,
            wordPackID: "test-v1",
            scheduleVersion: 1,
            hardModeEnabled: true,
            guesses: ["civic", "stone"].enumerated().map { index, word in
                DailyGuess(
                    word: word,
                    feedback: GameRules.evaluate(answer: "stone", guess: word),
                    acceptedAt: date(day: epochDay, seconds: index)
                )
            },
            outcome: .solved,
            guessCount: 2,
            completedAt: date(day: epochDay, seconds: 100)
        )
        let saved = DailyClassicProgress(result: completed)
        let restored = try DailyClassicGame(
            puzzle: puzzle(answer: "stone"),
            acceptedWords: accepted,
            restoring: saved
        )
        XCTAssertEqual(restored.completedResult, completed)
        XCTAssertTrue(restored.progress.hardModeEnabled)
    }

    func testShareIsCompactAndSpoilerSafe() {
        let result = DailyCompletedResult(
            puzzleID: "daily-classic-2024-10-04",
            puzzleNumber: 1,
            puzzleDay: epochDay,
            wordPackID: "test-v1",
            scheduleVersion: 1,
            guesses: [
                DailyGuess(word: "civic", feedback: [.absent, .present, .absent, .absent, .absent], acceptedAt: Date()),
                DailyGuess(word: "stone", feedback: Array(repeating: .correct, count: 5), acceptedAt: Date())
            ],
            outcome: .solved,
            guessCount: 2,
            completedAt: Date()
        )
        let text = DailyClassicShare.text(for: result)
        XCTAssertTrue(text.contains("GridRace Daily Classic #1 2/6"))
        XCTAssertFalse(text.lowercased().contains("stone"))
        XCTAssertFalse(text.lowercased().contains("civic"))
        XCTAssertEqual(text.components(separatedBy: "\n").suffix(2), ["−↻−−−", "✓✓✓✓✓"])
    }

    private func packData(
        answers: [String] = ["stone", "civic", "crane"],
        id: String = "test-v1",
        scheduleVersion: Int = 1,
        epochDay: Int? = nil
    ) -> Data {
        let object: [String: Any] = [
            "formatVersion": 1,
            "id": id,
            "scheduleVersion": scheduleVersion,
            "locale": "en-US",
            "wordLength": 5,
            "epochDay": epochDay ?? self.epochDay,
            "acceptedGuesses": Array(accepted).sorted(),
            "answers": answers
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func puzzle(answer: String, day: Int? = nil) -> DailyPuzzle {
        let puzzleDay = day ?? epochDay
        return DailyPuzzle(
            id: "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: puzzleDay))",
            number: puzzleDay - epochDay + 1,
            day: puzzleDay,
            answer: answer,
            wordPackID: "test-v1",
            scheduleVersion: 1
        )
    }

    private func game(answer: String) -> DailyClassicGame {
        DailyClassicGame(puzzle: puzzle(answer: answer), acceptedWords: accepted)
    }

    @discardableResult
    private func submit(_ word: String, to game: inout DailyClassicGame) -> DailySubmission {
        for letter in word { game.type(letter) }
        return game.submit(at: date(day: game.puzzle.day, seconds: 100))
    }

    private func result(day: Int, outcome: DailyOutcome, guesses: Int) -> DailyCompletedResult {
        let rows = (0..<guesses).map { index in
            DailyGuess(
                word: index == guesses - 1 && outcome == .solved ? "stone" : "civic",
                feedback: index == guesses - 1 && outcome == .solved
                    ? Array(repeating: .correct, count: 5)
                    : Array(repeating: .absent, count: 5),
                acceptedAt: date(day: day, seconds: index)
            )
        }
        return DailyCompletedResult(
            puzzleID: "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: day))",
            puzzleNumber: day - epochDay + 1,
            puzzleDay: day,
            wordPackID: "daily-classic-en-US-v1",
            scheduleVersion: 1,
            guesses: rows,
            outcome: outcome,
            guessCount: guesses,
            completedAt: date(day: day, seconds: 100)
        )
    }

    private func date(day: Int, seconds: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400 + seconds))
    }
}
