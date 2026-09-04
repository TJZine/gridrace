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

    func testSubmitAcrossUTCMidnightCannotMutateYesterday() throws {
        let fixture = try Fixture()
        var now = fixture.date(day: fixture.epochDay, seconds: 86_399)
        let model = try fixture.model(now: { now })
        fixture.type("adore", into: model)

        now = fixture.date(day: fixture.epochDay + 1)
        model.submitGuess()
        XCTAssertEqual(model.puzzle.number, 2)
        XCTAssertTrue(model.game.rows.isEmpty)
        XCTAssertFalse(model.game.isComplete)
        XCTAssertEqual(model.errorMessage, "A new daily puzzle is ready.")
    }

    func testSubmitUsesOneClockSampleAcrossMidnight() throws {
        let fixture = try Fixture()
        let samples = [
            fixture.date(day: fixture.epochDay, seconds: 100),
            fixture.date(day: fixture.epochDay, seconds: 86_399),
            fixture.date(day: fixture.epochDay + 1)
        ]
        var calls = 0
        let model = try fixture.model(now: {
            defer { calls += 1 }
            return samples[min(calls, samples.count - 1)]
        })
        fixture.type("adore", into: model)

        model.submitGuess()

        XCTAssertEqual(calls, 2, "Submission must use the same timestamp for its guard and mutation")
        XCTAssertTrue(model.game.isComplete)
    }

    func testCompletedHistoryWinsOverStaleProgress() throws {
        let fixture = try Fixture()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(now: { now })
        let stale = model.game.progress
        fixture.type("adore", into: model)
        model.submitGuess()
        try DailyClassicStore(directory: fixture.directory).save(stale)

        model = try fixture.model(now: { now })
        XCTAssertTrue(model.game.isComplete)
        XCTAssertEqual(model.game.completion?.outcome, .solved)
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
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

    func testBackwardClockCompletionRestoresAndRecordsStatisticsOnce() throws {
        let fixture = try Fixture()
        var now = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(now: { now })
        fixture.type("civic", into: model)
        model.submitGuess()
        now = fixture.date(day: fixture.epochDay, seconds: 50)
        fixture.type("adore", into: model)
        model.submitGuess()

        model = try fixture.model(now: { now })
        XCTAssertTrue(model.game.isComplete)
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
        XCTAssertEqual(model.game.progress.acceptedGuesses.map(\.acceptedAt), [
            fixture.date(day: fixture.epochDay, seconds: 100),
            fixture.date(day: fixture.epochDay, seconds: 100)
        ])
    }

    func testCorruptProgressIsDiscardedWithoutErasingHistory() throws {
        let fixture = try Fixture()
        var model = try fixture.model(now: { fixture.date(day: fixture.epochDay) })
        fixture.type("adore", into: model)
        model.submitGuess()
        try Data("{".utf8).write(
            to: fixture.directory.appending(path: "daily-progress-v1.json"),
            options: .atomic
        )

        model = try fixture.model(now: { fixture.date(day: fixture.epochDay + 1) })
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
        XCTAssertEqual(model.homeStatus, .unplayed)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.directory.appending(path: "daily-progress-v1.json").path
        ), "A fresh valid progress file should replace the corrupt file")
    }

    func testGuestResetRemovesOnlyGuestDailyFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceGuestResetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let guestStore = DailyClassicStore(directory: root)

        // Seed realistic guest Daily files through the production store seam.
        let fixture = try Fixture()
        let guestModel = try DailyClassicModel(
            pack: fixture.pack,
            store: guestStore,
            defaults: fixture.defaults,
            now: { fixture.date(day: fixture.epochDay, seconds: 100) }
        )
        fixture.type("adore", into: guestModel)
        guestModel.submitGuess()
        let guestProgressURL = root.appending(path: "daily-progress-v1.json")
        let guestHistoryURL = root.appending(path: "daily-history-v1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestProgressURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestHistoryURL.path))

        // Seed two account caches with distinct sentinel content.
        let accountIDs = [UUID(), UUID()]
        var sentinelSnapshots: [URL: Data] = [:]
        for userID in accountIDs {
            let accountStore = AccountDailyClassicStore(rootDirectory: root, userID: userID)
            try accountStore.save(guestModel.game.progress)
            try accountStore.save(guestModel.history)
            try accountStore.save(DailySyncMetadata())
            let sentinel = accountStore.directory.appending(path: "sentinel.txt")
            let content = Data("account-\(userID.uuidString)".utf8)
            try content.write(to: sentinel, options: .atomic)
            for file in ["daily-progress-v1.json", "daily-history-v1.json", "daily-sync-metadata-v1.json", "sentinel.txt"] {
                let url = accountStore.directory.appending(path: file)
                sentinelSnapshots[url] = try Data(contentsOf: url)
            }
        }

        try guestStore.resetGuestDailyData()

        XCTAssertFalse(FileManager.default.fileExists(atPath: guestProgressURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: guestHistoryURL.path))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "Guest reset must never remove the shared GridRace root")
        for (url, expected) in sentinelSnapshots {
            XCTAssertEqual(try Data(contentsOf: url), expected, "Guest reset must preserve \(url.path)")
        }

        // Missing guest files are tolerated so recovery stays idempotent.
        XCTAssertNoThrow(try guestStore.resetGuestDailyData())
    }

    func testTerminalPersistenceRetriesAfterBothWritesFail() throws {
        let fixture = try Fixture()
        let store = FailingStore()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(store: store, now: { now })
        fixture.type("adore", into: model)
        store.historySaveFailures = 1
        store.progressSaveFailures = 1
        model.submitGuess()
        XCTAssertTrue(model.game.isComplete)
        XCTAssertNil(store.savedHistory)

        model.refreshForCurrentDay()
        XCTAssertEqual(store.savedHistory?.statistics.gamesPlayed, 1)

        model = try fixture.model(store: store, now: { now })
        XCTAssertTrue(model.game.isComplete)
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
    }
}

private enum TestStoreError: Error { case failed }

private final class FailingStore: DailyClassicStoring, @unchecked Sendable {
    var savedProgress: DailyClassicProgress?
    var savedHistory: DailyClassicHistory?
    var historySaveFailures = 0
    var progressSaveFailures = 0

    func loadProgress() throws -> DailyClassicProgress? { savedProgress }

    func save(_ progress: DailyClassicProgress) throws {
        if progressSaveFailures > 0 {
            progressSaveFailures -= 1
            throw TestStoreError.failed
        }
        savedProgress = progress
    }

    func discardProgress() throws { savedProgress = nil }

    func loadHistory() throws -> DailyClassicHistory { savedHistory ?? DailyClassicHistory() }

    func save(_ history: DailyClassicHistory) throws {
        if historySaveFailures > 0 {
            historySaveFailures -= 1
            throw TestStoreError.failed
        }
        savedHistory = history
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

    func model(
        store: any DailyClassicStoring,
        now: @escaping @MainActor () -> Date
    ) throws -> DailyClassicModel {
        try DailyClassicModel(pack: pack, store: store, defaults: defaults, now: now)
    }

    func type(_ text: String, into model: DailyClassicModel) {
        for letter in text { model.typeLetter(letter) }
    }

    func date(day: Int, seconds: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400 + seconds))
    }
}
