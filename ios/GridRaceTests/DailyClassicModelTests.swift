import Foundation
import XCTest
import SwiftUI
import UIKit
import Darwin
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
    func testDailyNativeScreenCapturesAndAccessibilityScrollContent() async throws {
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
                                      name: "\(device)-daily-\(state)-\(dark ? "dark" : "light")", dark: dark)
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

    func testDailyGameplayContainmentAndHardModeErrorRecovery() async throws {
        let fixture = try Fixture()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        for landscape in [false, true] {
            let model = try fixture.model(store: FailingStore(), now: { now })
            model.updateHardMode(true)
            fixture.type("civic", into: model)
            model.submitGuess()
            let hosted = try await GameplayContainmentHost(
                GameplayRouteView(.daily) { DailyGameView(model: model) }, landscape: landscape)
            defer { hosted.close() }
            try hosted.assertGameplay(in: self, name: "daily-hard-mode", notices: [GameplayContainmentHost.hardModeReminder])
            fixture.type("zzzzz", into: model)
            model.submitGuess()
            try await hosted.settle()
            try hosted.assertGameplay(in: self, name: "daily-hard-mode-error", notices: [try XCTUnwrap(model.errorMessage)])
            XCTAssertFalse(hosted.elements().contains { $0.label == GameplayContainmentHost.hardModeReminder })
            model.deleteLetter()
            try await hosted.settle()
            try hosted.assertGameplay(in: self, name: "daily-hard-mode-edited", notices: [GameplayContainmentHost.hardModeReminder])
            hosted.close()
            let clueModel = try fixture.model(store: FailingStore(), now: { now })
            clueModel.updateHardMode(true)
            fixture.type("crane", into: clueModel)
            clueModel.submitGuess()
            fixture.type("stone", into: clueModel)
            clueModel.submitGuess()
            let clueHost = try await GameplayContainmentHost(GameplayRouteView(.daily) { DailyGameView(model: clueModel) }, landscape: landscape)
            defer { clueHost.close() }
            try clueHost.assertGameplay(in: self, name: "daily-clue-error", notices: [try XCTUnwrap(clueModel.errorMessage)])
            clueHost.close()
            // Appearance retries pending completion, so keep storage unavailable
            // throughout the hosted fixture rather than failing only one write.
            let terminalStore = FailingStore()
            terminalStore.historySaveFailures = 100
            terminalStore.progressSaveFailures = 100
            let terminal = try fixture.model(store: terminalStore, now: { now })
            fixture.type("adore", into: terminal)
            terminal.submitGuess()
            let resultHost = try await GameplayContainmentHost(GameplayRouteView(.daily) { DailyGameView(model: terminal) }, landscape: landscape)
            defer { resultHost.close() }
            try resultHost.assertGameplay(in: self, name: "daily-terminal-storage-error", notices: [try XCTUnwrap(terminal.errorMessage)],
                                          expectsKeyboard: false, actions: ["Share result", "View statistics"])
        }
        let model = try fixture.model(store: FailingStore(), now: { now })
        model.updateHardMode(true)
        fixture.type("civic", into: model)
        model.submitGuess()
        fixture.type("zzzzz", into: model)
        model.submitGuess()
        let hosted = try await GameplayContainmentHost(GameplayRouteView(.daily) { DailyGameView(model: model) },
                                                       landscape: false, accessibility: true)
        defer { hosted.close() }
        try hosted.assertGameplay(in: self, name: "daily-AX-error", notices: [try XCTUnwrap(model.errorMessage)])
        model.deleteLetter()
        try await hosted.settle()
        try hosted.assertGameplay(in: self, name: "daily-AX-restored-reminder", notices: [GameplayContainmentHost.hardModeReminder])
    }

    func testContainmentGateRejectsActualClippedBoardAndPassesRestoredFixture() async throws {
        for clipped in [false, true, false] {
            let hosted = try await GameplayContainmentHost(NavigationStack {
                HStack(spacing: 8) {
                    BoardView(rows: [], draft: "", isPlaying: true, compactLayout: true)
                        .frame(width: 244, height: 293)
                        .offset(y: clipped ? 24 : 0)
                        .clipped()
                    LetterKeyboardView(keyboard: KeyboardState(), typeLetter: { _ in }, submit: {}, delete: {})
                }
                .navigationTitle("Containment fixture").navigationBarTitleDisplayMode(.inline)
            }, landscape: true)
            defer { hosted.close() }
            if clipped {
                let options = XCTExpectedFailure.Options()
                options.issueMatcher = { $0.compactDescription.contains("outside") }
                try XCTExpectFailure("An actual clipped last row must fail the same containment gate", options: options) {
                    try hosted.assertGameplay(in: self, name: "negative-clipped-board")
                }
            } else {
                try hosted.assertGameplay(in: self, name: "restored-board")
            }
        }
    }

    private func capture<V: View>(_ view: V, scene: UIWindowScene, name: String, dark: Bool = false,
                                  accessibility: Bool = false) async throws {
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

    func testSettingsStorageNoticeAndRetryAreRenderedUnderHardModeSaveFailure() async throws {
        let fixture = try Fixture()
        let store = FailingStore()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try fixture.model(store: store, now: { now })
        store.progressSaveFailures = 100
        model.updateHardMode(true)
        let hosted = try await GameplayContainmentHost(
            NavigationStack { DailySettingsView(model: model) }, landscape: false)
        defer { hosted.close() }
        let elements = hosted.elements()
        XCTAssertTrue(elements.contains { $0.label == model.storageMessage })
        let retry = try XCTUnwrap(elements.first { $0.label == "Retry saving" && $0.button })
        XCTAssertTrue(hosted.isVisible(retry))
        let image = UIGraphicsImageRenderer(bounds: hosted.window.bounds).image { _ in
            hosted.window.drawHierarchy(in: hosted.window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Settings-Hard-Mode-storage-retry"
        attachment.lifetime = .keepAlways
        add(attachment)
        store.progressSaveFailures = 0
        XCTAssertTrue(model.retryPersistence())
        try await hosted.settle()
        XCTAssertFalse(hosted.elements().contains { $0.label == "Retry saving" })
        XCTAssertTrue(try fixture.model(store: store, now: { now }).game.progress.hardModeEnabled)
    }

    func testPriorDayTerminalFallbackSurvivesRepeatedRelaunchAndRetry() throws {
        let fixture = try Fixture()
        let store = FailingStore()
        var now = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(store: store, now: { now })
        fixture.type("adore", into: model)
        store.historySaveFailures = 10
        model.submitGuess()
        let terminal = try XCTUnwrap(store.savedProgress)
        XCTAssertNotNil(terminal.completion)
        XCTAssertNotNil(model.storageMessage)
        now = fixture.date(day: fixture.epochDay + 1, seconds: 100)
        for _ in 0..<2 {
            model = try fixture.model(store: store, now: { now })
            XCTAssertEqual(model.puzzle.day, fixture.epochDay)
            XCTAssertTrue(model.game.isComplete)
            XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
            XCTAssertEqual(store.savedProgress, terminal)
            XCTAssertNil(store.savedHistory)
        }
        store.historySaveFailures = 0
        XCTAssertTrue(model.retryPersistence())
        model.refreshForCurrentDay()
        XCTAssertEqual(model.puzzle.day, fixture.epochDay + 1)
        XCTAssertEqual(store.savedHistory?.statistics.gamesPlayed, 1)
        model = try fixture.model(store: store, now: { now })
        XCTAssertEqual(model.history.statistics.gamesPlayed, 1)
        XCTAssertFalse(model.game.isComplete)
    }

    func testAccountTerminalFallbackRolloverPreservesOtherAccountAndGuestFiles() throws {
        let fixture = try Fixture()
        let store = AccountDailyClassicStore(rootDirectory: fixture.directory, userID: UUID())
        let other = AccountDailyClassicStore(rootDirectory: fixture.directory, userID: UUID())
        let guest = DailyClassicStore(directory: fixture.directory.appending(path: "Guest"))
        let yesterday = fixture.date(day: fixture.epochDay, seconds: 100)
        var model = try fixture.model(store: store, now: { yesterday })
        try other.save(model.game.progress)
        try guest.save(model.game.progress)
        let otherBefore = try other.loadProgress(), guestBefore = try guest.loadProgress()
        try store.save(DailyClassicHistory())
        let historyURL = store.directory.appending(path: "daily-history-v1.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: historyURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: historyURL.path) }
        fixture.type("adore", into: model)
        model.submitGuess()
        let terminal = model.game.progress
        let today = fixture.date(day: fixture.epochDay + 1, seconds: 100)
        model = try fixture.model(store: store, now: { today })
        XCTAssertTrue(model.game.isComplete)
        XCTAssertEqual(model.puzzle.day, fixture.epochDay)
        XCTAssertEqual(try store.loadProgress(), terminal)
        XCTAssertTrue(try store.loadHistory().completedResults.isEmpty)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: historyURL.path)
        XCTAssertTrue(model.retryPersistence())
        model.refreshForCurrentDay()
        XCTAssertEqual(model.puzzle.day, fixture.epochDay + 1)
        XCTAssertEqual(try store.loadHistory().statistics.gamesPlayed, 1)
        XCTAssertEqual(try other.loadProgress(), otherBefore)
        XCTAssertEqual(try guest.loadProgress(), guestBefore)
    }

    func testPriorDayInvalidFallbackIsNotImportedAndImmutableHistoryWins() throws {
        let fixture = try Fixture()
        let store = FailingStore()
        let yesterday = fixture.date(day: fixture.epochDay, seconds: 100)
        let finished = try fixture.model(store: store, now: { yesterday })
        fixture.type("adore", into: finished)
        finished.submitGuess()
        let terminal = finished.game.progress
        let today = fixture.date(day: fixture.epochDay + 1, seconds: 100)
        let restored = try fixture.model(store: store, now: { today })
        XCTAssertEqual(restored.history.completedResults, finished.history.completedResults)
        XCTAssertEqual(restored.puzzle.day, fixture.epochDay + 1)
        store.savedHistory = nil
        var bad = terminal
        bad.acceptedGuesses = []
        store.savedProgress = bad
        let invalid = try fixture.model(store: store, now: { today })
        XCTAssertTrue(invalid.history.completedResults.isEmpty)
        XCTAssertEqual(invalid.puzzle.day, fixture.epochDay + 1)
    }

    func testAcceptedProgressAndModeRetainSeparateStorageRetryAfterValidationError() throws {
        let fixture = try Fixture()
        let store = FailingStore()
        let now = fixture.date(day: fixture.epochDay, seconds: 100)
        let model = try fixture.model(store: store, now: { now })
        store.progressSaveFailures = 100
        model.updateHardMode(true)
        XCTAssertTrue(model.game.progress.hardModeEnabled)
        XCTAssertNotNil(model.storageMessage)
        fixture.type("zzzzz", into: model)
        model.submitGuess()
        XCTAssertNotNil(model.storageMessage)
        XCTAssertTrue(model.hasUnsavedProgress)
        store.progressSaveFailures = 0
        XCTAssertTrue(model.retryPersistence())
        XCTAssertNil(model.storageMessage)
        XCTAssertNotNil(model.errorMessage, "Saving must not clear a word-validation error")
        let relaunched = try fixture.model(store: store, now: { now })
        XCTAssertTrue(relaunched.game.progress.hardModeEnabled)
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

/// Shared by the three gameplay fixtures. Frames come from the hosted UIKit
/// accessibility hierarchy, never from the SwiftUI layout formula under test.
@MainActor
final class GameplayContainmentHost {
    static let hardModeReminder = "Hard Mode locked. Keep correct-position letters in place and reuse present letters in another position."
    struct Element {
        let label: String
        let frame: CGRect
        let context: String
        let button: Bool
        let clips: [CGRect]
    }
    let window: UIWindow
    let host: UIViewController
    let accessibility: Bool
    let requestedLandscape: Bool
    private let scene: UIWindowScene
    private let automation: GameplayAccessibilityAutomation

    init<V: View>(_ view: V, landscape: Bool, accessibility: Bool = false) async throws {
        scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        automation = try GameplayAccessibilityAutomation()
        self.accessibility = accessibility
        requestedLandscape = landscape
        host = UIHostingController(rootView: view.tint(Color.ink)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large))
        window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait))
        try await settle()
        window.frame = scene.coordinateSpace.bounds
        try await settle()
        XCTAssertEqual(scene.interfaceOrientation.isLandscape, landscape, "OS scene must honor the requested orientation")
    }

    func settle() async throws {
        try await Task.sleep(for: .milliseconds(2500))
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        automation.restore()
    }

    var viewport: CGRect {
        var rect = window.convert(window.bounds.inset(by: window.safeAreaInsets), to: nil)
        for bar in views(window).compactMap({ $0 as? UINavigationBar }) where !bar.isHidden {
            let frame = bar.convert(bar.bounds, to: nil)
            if frame.intersects(rect) {
                rect = CGRect(x: rect.minX, y: max(rect.minY, frame.maxY), width: rect.width,
                              height: max(0, rect.maxY - max(rect.minY, frame.maxY)))
            }
        }
        return rect
    }

    private func views(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views($0) }
    }

    func elements() -> [Element] {
        var seen: Set<ObjectIdentifier> = []
        var result: [Element] = []
        func visit(_ object: NSObject, context: String, clips: [CGRect]) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            var clipping = clips
            if let view = object as? UIView {
                guard !view.isHidden, view.alpha > 0 else { return }
                if view.clipsToBounds { clipping.append(view.convert(view.bounds, to: nil)) }
            }
            let label = object.accessibilityLabel ?? ""
            let nextContext = ["Your six-row game board", "Letter keyboard"].contains(label) ? label : context
            if !label.isEmpty {
                result.append(Element(label: label, frame: object.accessibilityFrame, context: context,
                                      button: object.accessibilityTraits.contains(.button),
                                      clips: clipping + physicalClips(of: object)))
            }
            if let children = object.accessibilityElements {
                for child in children {
                    if let child = child as? NSObject { visit(child, context: nextContext, clips: clipping) }
                }
            }
            let count = object.accessibilityElementCount()
            if count > 0, count < 1000 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject {
                        visit(child, context: nextContext, clips: clipping)
                    }
                }
            }
            if let view = object as? UIView {
                for child in view.subviews { visit(child, context: nextContext, clips: clipping) }
            }
        }
        visit(host.view, context: "", clips: [])
        return result
    }

    private func physicalClips(of object: NSObject) -> [CGRect] {
        var cursor: NSObject? = object
        var visited: Set<ObjectIdentifier> = []
        var clips: [CGRect] = []
        while let current = cursor, visited.insert(ObjectIdentifier(current)).inserted {
            if let view = current as? UIView {
                if view.clipsToBounds { clips.append(view.convert(view.bounds, to: nil)) }
                cursor = view.superview
            } else if let element = current as? UIAccessibilityElement {
                cursor = element.accessibilityContainer as? NSObject
            } else {
                cursor = nil
            }
        }
        return clips
    }

    // 0.0001pt accommodates normalized AX-frame roundoff, far below one pixel.
    func isVisible(_ element: Element) -> Bool {
        guard element.frame.width > 0, element.frame.height > 0 else { return false }
        return ([viewport] + element.clips).allSatisfy {
            $0.insetBy(dx: -0.0001, dy: -0.0001).contains(element.frame)
        }
    }

    private func tile(_ element: Element) -> Bool {
        element.context == "Your six-row game board" &&
            (element.label.hasPrefix("Empty tile,") || element.label.hasPrefix("Letter "))
    }

    private func key(_ element: Element) -> Bool {
        element.context == "Letter keyboard" && element.button
    }

    func assertGameplay(in test: XCTestCase, name: String, notices: [String] = [], expectsKeyboard: Bool = true,
                        actions: [String] = [], opponents: Int = 0, hasTimer: Bool = false,
                        file: StaticString = #filePath, line: UInt = #line) throws {
        let bars = views(window).compactMap { $0 as? UINavigationBar }.filter { !$0.isHidden }
        XCTAssertFalse(bars.isEmpty, "Navigation chrome must be hosted", file: file, line: line)
        for bar in bars {
            XCTAssertTrue(window.convert(window.bounds, to: nil).contains(bar.convert(bar.bounds, to: nil)),
                          "Navigation chrome outside scene", file: file, line: line)
        }
        let initial = elements()
        let tiles = initial.filter(tile)
        let keys = initial.filter(key)
        XCTAssertEqual(tiles.count, 30, "All six rows must be observed: \(name)", file: file, line: line)
        XCTAssertEqual(keys.count, expectsKeyboard ? 28 : 0, "26 letters plus Submit/Delete must be observed: \(name)", file: file, line: line)
        let opponentElements = initial.filter { $0.label.hasPrefix("Opponent ") }
        let timerElements = initial.filter { $0.label.contains("seconds remaining") }
        XCTAssertEqual(opponentElements.count, opponents, "Opponent chrome missing", file: file, line: line)
        if hasTimer { XCTAssertEqual(timerElements.count, 1, "Timer missing", file: file, line: line) }
        let wanted = tiles + keys + initial.filter {
            actions.contains($0.label) || notices.contains($0.label) || $0.label.hasPrefix("Opponent ") || $0.label.contains("seconds remaining")
        }
        for notice in notices + actions {
            XCTAssertTrue(initial.contains { $0.label == notice }, "Complete notice missing: \(notice)", file: file, line: line)
        }
        var reached: Set<Int> = []
        var reachEvidence: [Int: String] = [:]
        func observe() {
            let current = elements()
            // Semantic occurrence preserves duplicate letters/feedback tiles.
            for (index, expected) in wanted.enumerated() {
                let occurrence = wanted[..<index].filter { $0.label == expected.label && $0.context == expected.context }.count
                let matches = current.filter { $0.label == expected.label && $0.context == expected.context }
                if matches.indices.contains(occurrence), isVisible(matches[occurrence]) {
                    reached.insert(index)
                    if reachEvidence[index] == nil {
                        let offsets = views(host.view).compactMap { $0 as? UIScrollView }.map { "\($0.contentOffset)" }
                        reachEvidence[index] = "\(expected.label): visibleFrame=\(matches[occurrence].frame), scrollOffsets=\(offsets)"
                    }
                }
            }
        }
        observe()
        if accessibility {
            let scrolls = views(host.view).compactMap { $0 as? UIScrollView }
            let vertical = scrolls.filter { $0.contentSize.height > $0.bounds.height + 1 }
            let horizontal = scrolls.filter { $0.contentSize.width > $0.bounds.width + 1 }
            func offsets(_ maximum: CGFloat, viewport: CGFloat) -> [CGFloat] {
                let steps = max(1, Int(ceil(maximum / max(1, viewport / 4))))
                return (0...steps).map { maximum * CGFloat($0) / CGFloat(steps) }
            }
            // Sweep vertical content densely, then each board/keyboard horizontal
            // scroll at that position. Each required full frame must be visible
            // in at least one real scroll position, not just intersect the image.
            for scroll in vertical {
                let original = scroll.contentOffset
                let minimum = -scroll.adjustedContentInset.top
                let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                for distance in offsets(maximum - minimum, viewport: scroll.bounds.height) {
                    scroll.setContentOffset(CGPoint(x: original.x, y: minimum + distance), animated: false)
                    host.view.layoutIfNeeded()
                    observe()
                    for cross in horizontal {
                        let originalCross = cross.contentOffset
                        let minimumX = -cross.adjustedContentInset.left
                        let maximumX = max(minimumX, cross.contentSize.width - cross.bounds.width + cross.adjustedContentInset.right)
                        for distanceX in offsets(maximumX - minimumX, viewport: cross.bounds.width) {
                            cross.setContentOffset(CGPoint(x: minimumX + distanceX, y: originalCross.y), animated: false)
                            host.view.layoutIfNeeded()
                            observe()
                        }
                        cross.setContentOffset(originalCross, animated: false)
                    }
                }
                scroll.setContentOffset(original, animated: false)
            }
        }
        for (index, element) in wanted.enumerated() {
            XCTAssertTrue(reached.contains(index), "\(name): \(element.label) \(element.frame) outside \(viewport) or clipped by \(element.clips)", file: file, line: line)
        }
        if !accessibility {
            // D16's tile floor is landscape-only. Portrait empty dashed-shape
            // AX bounds are not an independently established layout-size oracle.
            for element in requestedLandscape ? tiles : [] {
                let floor: CGFloat = 48
                XCTAssertGreaterThanOrEqual(element.frame.width + 0.0001, floor, file: file, line: line)
                XCTAssertGreaterThanOrEqual(element.frame.height + 0.0001, floor, file: file, line: line)
            }
            for action in initial.filter({ actions.contains($0.label) }) {
                XCTAssertGreaterThanOrEqual(action.frame.width + 0.0001, 44, file: file, line: line)
                XCTAssertGreaterThanOrEqual(action.frame.height + 0.0001, 44, file: file, line: line)
            }
            for element in keys {
                let action = ["Submit guess", "Delete letter"].contains(element.label)
                XCTAssertGreaterThanOrEqual(element.frame.width + 0.0001, action ? 44 : 32, file: file, line: line)
                XCTAssertGreaterThanOrEqual(element.frame.height + 0.0001, 48, file: file, line: line)
            }
            for tile in tiles {
                XCTAssertFalse(keys.contains { tile.frame.intersection($0.frame).width > 0.0001 && tile.frame.intersection($0.frame).height > 0.0001 },
                               "Board overlaps keyboard", file: file, line: line)
            }
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let imageAttachment = XCTAttachment(image: image)
        imageAttachment.name = name
        imageAttachment.lifetime = .keepAlways
        test.add(imageAttachment)
        let report = "\(name): scene=\(scene.coordinateSpace.bounds), orientation=\(scene.interfaceOrientation.rawValue) (OS), safeArea=\(window.safeAreaInsets), viewport=\(viewport), DynamicType=\(accessibility ? "AX5" : "large") (injected)\n" + initial.map { "\($0.context) | \($0.label) | \($0.frame)" }.joined(separator: "\n") + "\nReachability observations:\n" + reachEvidence.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = name + "-hierarchy"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}

/// UIKit lazily synthesizes SwiftUI's AX tree only for an accessibility client.
/// Use the system's automation switch in the test process, then restore its prior
/// value. This private runtime bootstrap is test-only; observations below it use
/// public UIKit container/label/frame APIs. Unsupported runtimes fail explicitly.
private final class GameplayAccessibilityAutomation {
    private let handle: UnsafeMutableRawPointer
    private let setEnabled: @convention(c) (Int32) -> Void
    private let previous: Int32
    private var restored = false

    init() throws {
        let root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
        handle = try XCTUnwrap(dlopen(root + "/usr/lib/libAccessibility.dylib", RTLD_NOW),
                              "System accessibility automation runtime unavailable")
        let getter = try XCTUnwrap(dlsym(handle, "_AXSAutomationEnabled"))
        let setter = try XCTUnwrap(dlsym(handle, "_AXSSetAutomationEnabled"))
        let getEnabled = unsafeBitCast(getter, to: (@convention(c) () -> Int32).self)
        setEnabled = unsafeBitCast(setter, to: (@convention(c) (Int32) -> Void).self)
        previous = getEnabled()
        setEnabled(1)
    }

    deinit { restore() }

    func restore() {
        guard !restored else { return }
        setEnabled(previous)
        dlclose(handle)
        restored = true
    }
}

/// Push the same AppRoute as the product so UIKit supplies actual Back chrome;
/// no synthetic safe-area padding or navigation-height constants are injected.
struct GameplayRouteView<Content: View>: View {
    let route: AppRoute
    let content: Content
    init(_ route: AppRoute, @ViewBuilder content: () -> Content) {
        self.route = route
        self.content = content()
    }
    var body: some View {
        NavigationStack(path: .constant([route])) {
            Color.page.navigationDestination(for: AppRoute.self) { _ in content }
        }
    }
}
