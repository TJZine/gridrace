import Foundation
import XCTest
import SwiftUI
import UIKit
@testable import GridRace

@MainActor
final class DailyClassicModelTests: XCTestCase {
    func testProgramStampsAndResultStatus() {
        XCTAssertEqual(DailyHomeStatus.unplayed.action, "Play")
        XCTAssertEqual(DailyHomeStatus.inProgress(2).action, "Continue")
        XCTAssertEqual(DailyHomeStatus.inProgress(2).title, "2 of 6 rows used")
        XCTAssertEqual(DailyHomeStatus.solved(3).action, "Result")
        XCTAssertEqual(DailyHomeStatus.solved(3).title, "Solved in 3")
        XCTAssertEqual(DailyHomeStatus.failed.action, "Result")
        XCTAssertEqual(DailyHomeStatus.failed.title, "Not solved")
    }

    func testAccountSheetWaitsForSignInAndProfileAndStaysOpenForExpiredAuth() {
        var signedOut = AccountSheetState(isSignedIn: false)
        XCTAssertFalse(signedOut.observe(isSignedIn: false, profileReady: false))
        XCTAssertFalse(signedOut.observe(isSignedIn: true, profileReady: false), "Authentication alone cannot hide profile setup or a profile-load error")
        XCTAssertTrue(signedOut.observe(isSignedIn: true, profileReady: true))
        var expired = AccountSheetState(isSignedIn: true)
        XCTAssertFalse(expired.observe(isSignedIn: true, profileReady: true))
        XCTAssertFalse(expired.observe(isSignedIn: true, profileReady: false))
        XCTAssertFalse(expired.observe(isSignedIn: false, profileReady: false), "Sign-out and deletion keep the sheet open")
        XCTAssertTrue(expired.observe(isSignedIn: true, profileReady: true), "A new sign-in after sign-out can dismiss")
        var cancelled = AccountSheetState(isSignedIn: false)
        XCTAssertFalse(cancelled.observe(isSignedIn: true, profileReady: false))
        XCTAssertFalse(cancelled.observe(isSignedIn: false, profileReady: false))
        XCTAssertFalse(cancelled.observe(isSignedIn: false, profileReady: true))
    }

    /// Native target-runtime evidence with the real screen bounds and safe areas.
    /// AX captures include lower scroll content; OS VoiceOver remains an S4 gate.
    func testDailyNativeScreensFitAndAccessibilityContentScrolls() async throws {
        let fixture = try Fixture()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try fixture.model(now: { now })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let size = scene.screen.bounds.size
        let device = size.width < 390 ? "SE" : "Pro"
        let account = AccountModel(service: nil)
        for state in ["unplayed", "progress", "solved", "failed", "hard-mode", "storage", "resume", "resolve"] {
            if state == "progress" { fixture.type("civic", into: model); model.submitGuess() }
            if state == "solved" { fixture.type("adore", into: model); model.submitGuess() }
            let shown: DailyClassicModel
            if state == "failed" || state == "hard-mode" {
                shown = try fixture.model(store: FailingStore(), now: { now })
                if state == "hard-mode" { shown.updateHardMode(true) }
                for _ in 0..<(state == "failed" ? 6 : 1) { fixture.type("civic", into: shown); shown.submitGuess() }
            } else { shown = model }
            let store = DailyScreenLiveStore(fails: state == "resolve")
            let live = LiveMatchSession(service: DailyScreenLiveService(), realtime: nil, storeFactory: { _ in store })
            if state == "resume" || state == "resolve" {
                live.changeAccount(to: UUID())
                if state == "resume" {
                    live.leaveToHome()
                    XCTAssertTrue(live.hasSavedMatch)
                } else { XCTAssertEqual(live.phase, .storageUnavailable) }
            }
            for dark in [false, true] {
                let home = NavigationStack {
                    DailyHomeView(model: shown, account: account, live: live, syncMessage: nil,
                                  isDailyPlayable: state != "storage", retryDailyStorage: {}, openRoute: { _ in })
                }
                try await capture(home, scene: scene, name: "\(device)-home-\(state)-\(dark ? "dark" : "light")", dark: dark)
                if ["unplayed", "progress", "solved", "failed", "hard-mode"].contains(state) {
                    try await capture(NavigationStack { DailyGameView(model: shown) }, scene: scene,
                                      name: "\(device)-daily-\(state)-\(dark ? "dark" : "light")", dark: dark, mustFit: true)
                }
                if state == "solved" || state == "failed" {
                    try await capture(NavigationStack { DailyStatisticsView(model: shown) }, scene: scene,
                                      name: "\(device)-stats-\(state)-\(dark ? "dark" : "light")", dark: dark)
                }
            }
        }
        try await capture(NavigationStack { DailyGameView(model: model) }, scene: scene, name: "\(device)-daily-AX5", accessibility: true)
        let playing = try fixture.model(store: FailingStore(), now: { now })
        try await capture(NavigationStack { DailyGameView(model: playing) }, scene: scene, name: "\(device)-daily-play-AX5", accessibility: true)
        try await capture(NavigationStack { DailyStatisticsView(model: model) }, scene: scene, name: "\(device)-stats-AX5", accessibility: true)
    }

    private func capture<V: View>(_ view: V, scene: UIWindowScene, name: String, dark: Bool = false,
                                  accessibility: Bool = false, mustFit: Bool = false) async throws {
        let host = UIHostingController(rootView: view.tint(Color.ink).foregroundStyle(Color.ink)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large))
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutIfNeeded()
        let scrolls = descendants(host.view).compactMap { $0 as? UIScrollView }
        if mustFit {
            for scroll in scrolls where scroll.bounds.height > 100 {
                XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 1, "Default screen must fit: \(name)")
            }
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        func attach(_ suffix: String) {
            let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = name + suffix
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        attach("")
        if accessibility {
            for (index, scroll) in scrolls.enumerated() where scroll.contentSize.height > scroll.bounds.height {
                scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                host.view.layoutIfNeeded()
                attach("-bottom-\(index)")
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

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

    func testPreviousStreakFirstEverSolve() throws {
        let fixture = try Fixture()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try fixture.model(now: { now })
        fixture.type("adore", into: model)
        model.submitGuess()
        XCTAssertTrue(model.game.isComplete)
        XCTAssertEqual(model.previousDisplayedStreak, 0)
        XCTAssertEqual(model.displayedCurrentStreak, 1)
    }

    func testPreviousStreakConsecutiveSolve() throws {
        let fixture = try Fixture()
        var now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try fixture.model(now: { now })
        fixture.type("adore", into: model)
        model.submitGuess()

        now = fixture.date(day: fixture.epochDay + 1, seconds: 1)
        model.refreshForCurrentDay()
        XCTAssertEqual(model.previousDisplayedStreak, 1)
        fixture.type("stone", into: model)
        model.submitGuess()
        XCTAssertEqual(model.previousDisplayedStreak, 1)
        XCTAssertEqual(model.displayedCurrentStreak, 2)
    }

    func testPreviousStreakMissedDayResetsToZero() throws {
        let fixture = try Fixture()
        let pack = try DailyWordPack.load(from: JSONSerialization.data(withJSONObject: [
            "formatVersion": 1,
            "id": "daily-classic-en-US-v1",
            "scheduleVersion": 1,
            "locale": "en-US",
            "wordLength": 5,
            "epochDay": fixture.epochDay,
            "acceptedGuesses": ["adore", "civic", "crane", "stone"],
            "answers": ["adore", "civic", "crane", "stone"]
        ]))
        var now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try DailyClassicModel(
            pack: pack,
            store: DailyClassicStore(directory: fixture.directory),
            defaults: fixture.defaults,
            now: { now }
        )
        fixture.type("adore", into: model)
        model.submitGuess()

        now = fixture.date(day: fixture.epochDay + 2, seconds: 1)
        model.refreshForCurrentDay()
        XCTAssertEqual(model.puzzle.answer, "crane")
        XCTAssertEqual(model.previousDisplayedStreak, 0)
        XCTAssertEqual(model.displayedCurrentStreak, 0)
        fixture.type("crane", into: model)
        model.submitGuess()
        XCTAssertEqual(model.previousDisplayedStreak, 0)
        XCTAssertEqual(model.displayedCurrentStreak, 1)
    }

    func testPreviousStreakSurvivesFailedCurrentPuzzle() throws {
        let fixture = try Fixture()
        let pack = try DailyWordPack.load(from: JSONSerialization.data(withJSONObject: [
            "formatVersion": 1,
            "id": "daily-classic-en-US-v1",
            "scheduleVersion": 1,
            "locale": "en-US",
            "wordLength": 5,
            "epochDay": fixture.epochDay,
            "acceptedGuesses": ["adore", "civic", "crane", "stone"],
            "answers": ["adore", "civic", "crane", "stone"]
        ]))
        var now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try DailyClassicModel(
            pack: pack,
            store: DailyClassicStore(directory: fixture.directory),
            defaults: fixture.defaults,
            now: { now }
        )
        fixture.type("adore", into: model)
        model.submitGuess()

        now = fixture.date(day: fixture.epochDay + 1, seconds: 1)
        model.refreshForCurrentDay()
        XCTAssertEqual(model.puzzle.answer, "civic")
        for _ in 0..<6 {
            fixture.type("stone", into: model)
            model.submitGuess()
        }
        XCTAssertEqual(model.game.completion?.outcome, .failed)
        XCTAssertEqual(model.displayedCurrentStreak, 0)
        XCTAssertEqual(model.previousDisplayedStreak, 1)
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

private struct DailyScreenLiveStore: LiveMatchRecoveryStoring {
    let fails: Bool
    func load() throws -> LiveRecoveryState {
        if fails { throw LiveMatchRecoveryError.invalidData }
        return LiveRecoveryState(matchID: UUID())
    }
    func save(_ state: LiveRecoveryState) throws {}
    func clear() throws {}
}

private struct DailyScreenLiveService: LiveMatchServicing {
    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID {
        throw LiveMatchServiceError.unavailable
    }
    func joinMatch(code: String) async throws -> UUID { throw LiveMatchServiceError.unavailable }
    func startMatch(id: UUID, roundNumber: Int) async throws -> UUID { throw LiveMatchServiceError.unavailable }
    func submitGuess(matchID: UUID, roundNumber: Int, requestID: UUID, guess: String, clientBuild: Int) async throws -> LiveGuessReceipt {
        throw LiveMatchServiceError.unavailable
    }
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot { throw LiveMatchServiceError.unavailable }
}
