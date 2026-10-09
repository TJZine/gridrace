import Foundation
import XCTest
@testable import GridRace

/// Exercises the composition and recovery actions consumed directly by AppRootView.
/// Platform interaction/VoiceOver acceptance remains separate from this boundary.
@MainActor
final class AppStartupTests: XCTestCase {
    func testBundleFailureStopsBeforeStorageAndOffersOnlyRetry() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var bundleUnavailable = true
        var storeAttempts = 0
        let startup = AppStartupModel(
            loadPacks: {
                if bundleUnavailable { throw DailyClassicError.missingWordPack }
                return try self.packs()
            },
            makeStore: { storeAttempts += 1; return fixture.store },
            makeApp: makeApp
        )
        startup.loadApp()
        guard case .bundledData? = startup.loadFailure else { return XCTFail("Expected bundle recovery") }
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        XCTAssertEqual(storeAttempts, 0)
        startup.perform(.resetGuest)
        XCTAssertEqual(try fixture.snapshot(), fixture.original)
        bundleUnavailable = false
        startup.perform(.retry)
        XCTAssertNotNil(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(storeAttempts, 1)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" }, fixture.original)
        try assertFreshProgress(startup, fixture: fixture)
    }

    func testConstructionFailureRetainsStorageDiagnosisAndRetryRecoversWithoutReset() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var unavailable = true
        var storeAttempts = 0
        let startup = AppStartupModel(
            loadPacks: packs,
            makeStore: {
                storeAttempts += 1
                if unavailable { throw CocoaError(.fileReadNoPermission) }
                return fixture.store
            },
            makeApp: makeApp
        )
        startup.loadApp()
        guard case .storageUnavailable? = startup.loadFailure else { return XCTFail("Expected storage recovery") }
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        XCTAssertEqual(storeAttempts, 1, "Construction occurs once per attempt")
        startup.perform(.resetGuest)
        XCTAssertEqual(storeAttempts, 1)
        XCTAssertEqual(try fixture.snapshot(), fixture.original)
        unavailable = false
        startup.perform(.retry)
        XCTAssertNotNil(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(storeAttempts, 2)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" }, fixture.original)
        try assertFreshProgress(startup, fixture: fixture)
    }

    func testPuzzleUnavailableRetainsBundleClassificationAndCannotResetConstructedStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let startup = AppStartupModel(
            loadPacks: packs,
            makeStore: { fixture.store },
            makeApp: { _, _, _ in throw DailyClassicError.puzzleUnavailable }
        )
        startup.loadApp()
        guard case .bundledData? = startup.loadFailure else { return XCTFail("Expected bundle recovery") }
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        startup.perform(.resetGuest)
        XCTAssertEqual(try fixture.snapshot(), fixture.original)
    }

    func testCorruptHistoryOrUnreadableProgressRetryPreservesFilesAndScopedResetRecovers() throws {
        for filename in ["daily-progress-v1.json", "daily-history-v1.json"] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            if filename == "daily-progress-v1.json" {
                let progress = fixture.root.appending(path: filename, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: progress, withIntermediateDirectories: true)
                try Data("unreadable as a progress file".utf8).write(to: progress.appending(path: "fixture.txt"))
            } else {
                let puzzle = try DailyPuzzleSchedule.puzzle(at: Date(), in: packs().daily)
                try fixture.store.save(DailyClassicProgress(puzzle: puzzle, hardModeEnabled: false))
                try Data("invalid saved data".utf8).write(to: fixture.root.appending(path: filename))
            }
            let before = try fixture.snapshot()
            var storeAttempts = 0
            let startup = AppStartupModel(
                loadPacks: packs,
                makeStore: { storeAttempts += 1; return fixture.store },
                makeApp: makeApp
            )
            startup.loadApp()
            guard case .savedData(let retained)? = startup.loadFailure else { return XCTFail("Expected guest recovery for \(filename)") }
            XCTAssertEqual(retained.directory, fixture.root)
            XCTAssertEqual(startup.loadFailure?.actions, [.retry, .resetGuest])
            XCTAssertEqual(storeAttempts, 1)
            startup.perform(.retry)
            XCTAssertNil(startup.appModel)
            XCTAssertEqual(startup.loadFailure?.actions, [.retry, .resetGuest])
            XCTAssertEqual(try fixture.snapshot(), before, "Retry must preserve even unreadable guest files")
            startup.perform(.resetGuest)
            XCTAssertNotNil(startup.appModel)
            XCTAssertNil(startup.loadFailure)
            let after = try fixture.snapshot()
            XCTAssertEqual(after.filter { $0.key != "daily-progress-v1.json" },
                           before.filter { $0.key != "daily-history-v1.json" && !$0.key.hasPrefix("daily-progress-v1.json") })
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appending(path: "daily-history-v1.json").path))
            XCTAssertEqual(try fixture.store.loadHistory(), DailyClassicHistory())
            try assertFreshProgress(startup, fixture: fixture)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.path))
            // A stale reset intent after recovery cannot clear subsequently saved data.
            try fixture.store.save(DailyClassicHistory())
            let recovered = try fixture.snapshot()
            startup.perform(.resetGuest)
            XCTAssertEqual(try fixture.snapshot(), recovered)
        }
    }

    func testInvalidProgressUsesExistingRepairWithoutExposingRootReset() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("invalid saved progress".utf8).write(to: fixture.root.appending(path: "daily-progress-v1.json"))
        let startup = AppStartupModel(loadPacks: packs, makeStore: { fixture.store }, makeApp: makeApp)
        startup.loadApp()
        XCTAssertNotNil(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" }, fixture.original,
                       "Existing invalid-progress repair preserves history and accounts")
        try assertFreshProgress(startup, fixture: fixture)
    }

    func testConstructionRetryPreservesExistingNonemptyProgress() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try packs().daily
        let now = Date()
        let puzzle = try DailyPuzzleSchedule.puzzle(at: now, in: pack)
        var game = DailyClassicGame(puzzle: puzzle, acceptedWords: Set(pack.acceptedGuesses))
        let word = try XCTUnwrap(pack.acceptedGuesses.first { $0 != puzzle.answer })
        for letter in word { game.type(letter) }
        XCTAssertNotNil(game.submit(at: now).guess)
        try fixture.store.save(game.progress)
        let before = try fixture.snapshot()
        var unavailable = true
        let startup = AppStartupModel(
            loadPacks: packs,
            makeStore: {
                if unavailable { throw CocoaError(.fileReadNoPermission) }
                return fixture.store
            },
            makeApp: makeApp
        )
        startup.loadApp()
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        XCTAssertEqual(try fixture.snapshot(), before)
        unavailable = false
        startup.perform(.retry)
        let app = try XCTUnwrap(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(app.daily.game.progress, game.progress)
        XCTAssertEqual(try fixture.store.loadProgress(), game.progress)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" },
                       before.filter { $0.key != "daily-progress-v1.json" })
    }

    private func assertFreshProgress(_ startup: AppStartupModel, fixture: Fixture,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let app = try XCTUnwrap(startup.appModel, file: file, line: line)
        let saved = try XCTUnwrap(fixture.store.loadProgress(), file: file, line: line)
        let restored = try DailyClassicGame(puzzle: app.daily.puzzle,
                                           acceptedWords: Set(packs().daily.acceptedGuesses), restoring: saved)
        XCTAssertEqual(saved, app.daily.game.progress, file: file, line: line)
        XCTAssertEqual(saved.puzzleID, app.daily.puzzle.id, file: file, line: line)
        XCTAssertTrue(restored.rows.isEmpty, file: file, line: line)
        XCTAssertTrue(restored.draft.isEmpty, file: file, line: line)
        XCTAssertNil(restored.completion, file: file, line: line)
    }

    private func packs() throws -> (tutorial: WordPack, daily: DailyWordPack) {
        (try WordPack.load(bundle: .main), try DailyWordPack.load(bundle: .main))
    }

    private func makeApp(_ daily: DailyWordPack, _ tutorial: WordPack, _ store: DailyClassicStore) throws -> DailyAccountCoordinator {
        try DailyAccountCoordinator(dailyPack: daily, tutorialPack: tutorial, guestStore: store, accountService: nil)
    }

    private struct Fixture {
        let root: URL
        let original: [String: Data]
        var store: DailyClassicStore { DailyClassicStore(directory: root) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "GridRaceStartupTests-\(UUID())", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let guest = DailyClassicStore(directory: root)
            try guest.save(DailyClassicHistory())
            for userID in [UUID(), UUID()] {
                let account = AccountDailyClassicStore(rootDirectory: root, userID: userID)
                try account.save(DailyClassicHistory())
                try account.save(DailySyncMetadata())
            }
            try Data("unrelated root file".utf8).write(to: root.appending(path: "retained.txt"))
            original = try Self.snapshot(root)
        }

        func snapshot() throws -> [String: Data] { try Self.snapshot(root) }
        func remove() { try? FileManager.default.removeItem(at: root) }

        private static func snapshot(_ root: URL) throws -> [String: Data] {
            let urls = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
            var files: [String: Data] = [:]
            for case let url as URL in urls {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    files[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
                }
            }
            return files
        }
    }
}
