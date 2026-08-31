import Foundation
import XCTest
@testable import GridRace

@MainActor
final class DailyClassicModelTests: XCTestCase {
    func testDraftAndAcceptedRowsRestoreAfterRecreation() throws {
        let fixture = try Fixture()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(now: { now })
        fixture.type("civic", into: model)
        model.submitGuess()
        fixture.type("CR", into: model)

        model = try fixture.model(now: { now })
        XCTAssertEqual(model.game.rows.map(\.word), ["civic"])
        XCTAssertEqual(model.game.draft, "CR")
        XCTAssertEqual(model.homeStatus, .inProgress(1))
    }

    func testCompletedResultRestoresWithoutDuplicatingStatistics() throws {
        let fixture = try Fixture()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(now: { now })
        fixture.type("adore", into: model)
        model.submitGuess()
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
        XCTAssertEqual(model.history.statistics.gamesWon, 1)

        model = try fixture.model(now: { now })
        XCTAssertTrue(model.game.isComplete)
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
        model.submitGuess()
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
    }

    func testForegroundRefreshMovesToNextUTCPuzzleAndDropsOldDraft() throws {
        let fixture = try Fixture()
        var now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try fixture.model(now: { now })
        fixture.type("CR", into: model)

        now = fixture.date(day: fixture.epochDay + 1, seconds: 1)
        model.refreshForCurrentDay()
        XCTAssertEqual(model.puzzle.number, 2)
        XCTAssertEqual(model.puzzle.answer, "stone")
        XCTAssertEqual(model.game.draft, "")
        XCTAssertEqual(model.homeStatus, .unplayed)
    }

    func testSettingsPersistAndHardModeLocksAfterAcceptedGuess() throws {
        let fixture = try Fixture()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(now: { now })
        model.updateHaptics(false)
        model.updateHighContrast(true)
        model.updateHardMode(true)
        fixture.type("civic", into: model)
        model.submitGuess()
        model.updateHardMode(false)
        XCTAssertTrue(model.game.progress.hardModeEnabled)

        model = try fixture.model(now: { now })
        XCTAssertFalse(model.settings.hapticsEnabled)
        XCTAssertTrue(model.settings.highContrastEnabled)
        XCTAssertTrue(model.settings.hardModeEnabled)
        XCTAssertFalse(model.game.canChangeHardMode)
    }
}

@MainActor
private final class Fixture {
    let epochDay = 20_696
    let directory: URL
    let defaults: UserDefaults
    let pack: DailyWordPack

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = "GridRaceModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        pack = try DailyWordPack.load(from: JSONSerialization.data(withJSONObject: [
            "formatVersion": 1,
            "id": "daily-classic-en-US-v1",
            "scheduleVersion": 1,
            "locale": "en-US",
            "wordLength": 5,
            "epochDay": epochDay,
            "acceptedGuesses": ["adore", "civic", "crane", "stone"],
            "answers": ["adore", "stone"]
        ]))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func model(now: @escaping @MainActor () -> Date) throws -> DailyClassicModel {
        try DailyClassicModel(
            pack: pack,
            store: DailyClassicStore(directory: directory),
            defaults: defaults,
            now: now
        )
    }

    func type(_ text: String, into model: DailyClassicModel) {
        for letter in text { model.typeLetter(letter) }
    }

    func date(day: Int, seconds: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400 + seconds))
    }
}
