import Foundation
import XCTest
import SwiftUI
import UIKit
@testable import GridRace

final class AppleNonceTests: XCTestCase {
    func testNonceUsesSecureAllowedShapeAndRequestedLength() throws {
        let nonce = try AppleNonce.generate(length: 48)
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        XCTAssertEqual(nonce.count, 48)
        XCTAssertTrue(nonce.allSatisfy(allowed.contains))
    }

    func testSHA256MatchesKnownValue() {
        XCTAssertEqual(
            AppleNonce.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}

final class PlayerProfileTests: XCTestCase {
    func testDisplayNameNormalizationMatchesDatabaseBoundary() {
        XCTAssertEqual(PlayerProfile.normalizedDisplayName("  Alex-7  "), "Alex-7")
        XCTAssertEqual(PlayerProfile.normalizedDisplayName("O'Brien"), "O'Brien")
        XCTAssertEqual(PlayerProfile.normalizedDisplayName("Anne-Marie"), "Anne-Marie")
        XCTAssertNil(PlayerProfile.normalizedDisplayName("A"))
        XCTAssertNil(PlayerProfile.normalizedDisplayName("A  B"))
        XCTAssertNil(PlayerProfile.normalizedDisplayName("-Alex"))
        XCTAssertNil(PlayerProfile.normalizedDisplayName("Alex_7"))
        XCTAssertNil(PlayerProfile.normalizedDisplayName("abcdefghijklmnopq"))
    }

    func testDisplayNameNormalizationBoundaryLengthsAndBlankAndUnicode() {
        // Empty and blank-only inputs normalize to nothing.
        XCTAssertNil(PlayerProfile.normalizedDisplayName(""))
        XCTAssertNil(PlayerProfile.normalizedDisplayName("   "))
        XCTAssertNil(PlayerProfile.normalizedDisplayName(" \t\n "))
        // Length boundaries: 1 rejects, 2 accepts, 16 accepts, 17 rejects.
        XCTAssertNil(PlayerProfile.normalizedDisplayName("A"))
        XCTAssertEqual(PlayerProfile.normalizedDisplayName("Al"), "Al")
        XCTAssertEqual(
            PlayerProfile.normalizedDisplayName("abcdefghijklmnop"),
            "abcdefghijklmnop"
        )
        XCTAssertNil(PlayerProfile.normalizedDisplayName("abcdefghijklmnopq"))
        // Non-ASCII letters are rejected even at valid lengths.
        XCTAssertNil(PlayerProfile.normalizedDisplayName("Stöne"))
        XCTAssertNil(PlayerProfile.normalizedDisplayName("Renée"))
        XCTAssertNil(PlayerProfile.normalizedDisplayName("Alex😀"))
    }

    func testSetupCompletionIsIndependentOfPermittedName() {
        let generated = profile(name: "Player 12abef", setupCompleted: false)
        XCTAssertTrue(generated.needsSetup)
        XCTAssertFalse(profile(name: "Player 12abef", setupCompleted: true).needsSetup)
        XCTAssertFalse(profile(name: "Player One", setupCompleted: true).needsSetup)
        XCTAssertTrue(profile(name: "Custom Name", setupCompleted: false).needsSetup)
        XCTAssertEqual(PlayerProfile.normalizedDisplayName("Player abcdef"), "Player abcdef")
    }

    func testWireRequiresExplicitBooleanSetupCompletion() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original = profile(name: "Player abcdef", setupCompleted: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        for completed in [false, true] {
            wire["setup_completed"] = completed
            let decoded = try decoder.decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: wire))
            XCTAssertEqual(decoded.setupCompleted, completed)
            XCTAssertEqual(decoded.needsSetup, !completed)
            XCTAssertEqual(decoded.displayName, "Player abcdef")
        }
        wire.removeValue(forKey: "setup_completed")
        XCTAssertThrowsError(try decoder.decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: wire)))
        let invalidStates: [Any] = [NSNull(), "true", 1, [], [:]]
        for invalid in invalidStates {
            wire["setup_completed"] = invalid
            XCTAssertThrowsError(try decoder.decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: wire)))
        }
    }

    private func profile(name: String, setupCompleted: Bool) -> PlayerProfile {
        PlayerProfile(
            userID: UUID(),
            displayName: name,
            avatarSeed: "seed",
            setupCompleted: setupCompleted,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}

@MainActor
final class PlayerAvatarPaletteTests: XCTestCase {
    func testSeedToSymbolMappingIsStable() {
        // Snapshot of the frozen mapping: order and hash must not change,
        // or persisted seeds would resolve to different symbols.
        XCTAssertEqual(
            PlayerAvatarView.avatarSymbols,
            [
                "hare.fill", "tortoise.fill", "bird.fill", "fish.fill",
                "ladybug.fill", "pawprint.fill", "leaf.fill", "bolt.fill",
            ]
        )
        XCTAssertEqual(PlayerAvatarView.avatarSwatches.count, PlayerAvatarView.avatarSymbols.count)
        XCTAssertEqual(PlayerAvatarView.paletteIndex(for: "seed"), 1)
        XCTAssertEqual(PlayerAvatarView.paletteIndex(for: "avatar-seed"), 5)
        XCTAssertEqual(PlayerAvatarView.paletteIndex(for: ""), 0)
        XCTAssertEqual(PlayerAvatarView.paletteIndex(for: "Alex"), 6)
        XCTAssertEqual(PlayerAvatarView.paletteIndex(for: "a"), 1)
    }

    func testEveryBackgroundMeetsWhiteContrast() {
        for swatch in PlayerAvatarView.avatarSwatches {
            XCTAssertGreaterThanOrEqual(
                Self.contrastAgainstWhite(
                    red: swatch.red,
                    green: swatch.green,
                    blue: swatch.blue
                ),
                3.0,
                "swatch (\(swatch.red), \(swatch.green), \(swatch.blue))"
            )
        }
    }

    private static func contrastAgainstWhite(red: Double, green: Double, blue: Double) -> Double {
        let luminance =
            0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
        return 1.05 / (luminance + 0.05)
    }

    private static func linearize(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

final class SupabaseAccountConfigurationTests: XCTestCase {
    func testMissingOrMalformedConfigurationDisablesAccounts() {
        XCTAssertNil(SupabaseAccountService.Configuration(urlString: nil, publishableKey: "key"))
        XCTAssertNil(SupabaseAccountService.Configuration(urlString: "https://example.test", publishableKey: ""))
        XCTAssertNil(SupabaseAccountService.Configuration(urlString: "file:///tmp/backend", publishableKey: "key"))
    }

    func testHTTPConfigurationSupportsLocalSupabase() {
        XCTAssertEqual(
            SupabaseAccountService.Configuration(
                urlString: "http://127.0.0.1:54321",
                publishableKey: "publishable"
            )?.projectURL.absoluteString,
            "http://127.0.0.1:54321"
        )
    }
}

@MainActor
final class DailyAccountCoordinatorTests: XCTestCase {
    func testImmediateColdRestoreAndLaterAccountSwitchPreserveInactiveGuestFiles() async throws {
        let fixture = try GuestStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try fixture.guestBytes()
        let service = AccountServiceMock()
        let restored = AccountSession(userID: UUID(), expiresAt: .distantFuture)
        service.restoration = {
            // The real service publishes its commit before returning it. Its
            // subscription also buffers an initial nil before this command.
            service.emit(restored)
            return restored
        }
        let coordinator = try fixture.coordinator(service: service)
        XCTAssertEqual(try fixture.guestBytes(), before)
        await coordinator.start()
        XCTAssertEqual(coordinator.account.session, restored)
        let next = AccountSession(userID: UUID(), expiresAt: .distantFuture)
        service.emit(next)
        await waitForAccountCondition { coordinator.account.session == next }
        // Observing the later identity proves the preceding buffered values were
        // consumed; checking only start()'s return would miss the transient guest.
        XCTAssertEqual(coordinator.account.session, next)
        XCTAssertEqual(coordinator.daily.game.progress.puzzleDay, Int(fixture.current.timeIntervalSince1970 / 86_400))
        XCTAssertEqual(try fixture.guestBytes(), before)
    }

    func testSignedInColdStartupNeverWritesInactiveGuestBeforeOrAfterHeldRestoration() async throws {
        let fixture = try GuestStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try fixture.guestBytes()
        let service = AccountServiceMock()
        let userID = UUID()
        var held: CheckedContinuation<AccountSession?, Error>?
        service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
        let coordinator = try fixture.coordinator(service: service)
        XCTAssertEqual(try fixture.guestBytes(), before, "Capture before constructor catches eager writes")
        let initial = Task { await coordinator.start() }
        await waitForAccountCondition { held != nil }
        service.emitState(AccountAuthState(session: nil, recovery: .init(action: .restore, storageIssue: nil)))
        await waitForAccountCondition { coordinator.account.authRecovery?.action == .restore }
        coordinator.foregrounded()
        await coordinator.start()
        XCTAssertEqual(service.restoreCallCount, 1)
        XCTAssertEqual(try fixture.guestBytes(), before)
        held?.resume(returning: AccountSession(userID: userID, expiresAt: .distantFuture))
        await initial.value
        XCTAssertEqual(coordinator.account.session?.userID, userID)
        XCTAssertEqual(try fixture.guestBytes(), before)
        let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
        let accountProgress = try XCTUnwrap(store.loadProgress())
        let coldService = AccountServiceMock()
        coldService.restoredSession = AccountSession(userID: userID, expiresAt: .distantFuture)
        let cold = try fixture.coordinator(service: coldService)
        XCTAssertEqual(try fixture.guestBytes(), before)
        await cold.start()
        XCTAssertEqual(cold.daily.game.progress, accountProgress)
        XCTAssertEqual(try fixture.guestBytes(), before)
    }

    func testSingleLatestRestoreSettlesGuestAfterProvisionalNilAndCurrentNilOrError() async throws {
        for terminal in [false, true] {
            for failure in [false, true] {
                let fixture = try GuestStartupFixture()
                defer { try? FileManager.default.removeItem(at: fixture.root) }
                if terminal {
                    let old = Date(timeIntervalSince1970: 20_696 * 86_400 + 100)
                    let puzzle = try DailyPuzzleSchedule.puzzle(at: old, in: fixture.pack)
                    var game = DailyClassicGame(puzzle: puzzle, acceptedWords: Set(fixture.pack.acceptedGuesses))
                    for letter in puzzle.answer { game.type(letter) }
                    XCTAssertNil(game.submit(at: old).error)
                    try fixture.guestStore.save(game.progress)
                }
                let before = try fixture.guestBytes()
                let service = AccountServiceMock()
                var held: CheckedContinuation<AccountSession?, Error>?
                service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
                let coordinator = try fixture.coordinator(service: service)
                let guest = coordinator.daily
                let initial = Task { await coordinator.start() }
                await waitForAccountCondition { held != nil }
                service.emitState(AccountAuthState(session: nil, recovery: .init(action: .restore, storageIssue: nil)))
                await waitForAccountCondition { coordinator.account.authRecovery?.action == .restore }
                coordinator.foregrounded()
                XCTAssertEqual(try fixture.guestBytes(), before)
                XCTAssertFalse(guest.isPersistenceActive)
                if failure {
                    // Current storage-error restoration can publish cleanup recovery before throwing.
                    service.emitState(AccountAuthState(session: nil, recovery: .init(action: .cleanup, storageIssue: nil)))
                    await waitForAccountCondition { coordinator.account.authRecovery?.action == .cleanup }
                    XCTAssertEqual(try fixture.guestBytes(), before)
                    held?.resume(throwing: TestError.failed)
                } else { held?.resume(returning: nil) }
                await initial.value
                XCTAssertEqual(service.restoreCallCount, 1, "No second restore is needed to settle this attempt")
                XCTAssertTrue(coordinator.daily === guest)
                XCTAssertTrue(guest.isPersistenceActive)
                XCTAssertNil(coordinator.account.session)
                XCTAssertEqual(coordinator.account.errorMessage != nil, failure)
                XCTAssertEqual(guest.puzzle.day, 20_697)
                XCTAssertTrue(guest.game.rows.isEmpty)
                XCTAssertEqual(try fixture.guestStore.loadProgress(), guest.game.progress)
                XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults.count, terminal ? 1 : 0)
                XCTAssertEqual(try Data(contentsOf: fixture.guestStore.directory.appending(path: "sibling.dat")), Data("protected sibling".utf8))
            }
        }
    }

    func testExplicitCleanupWhileAlreadyNilInvalidatesLateRestorationFallback() async throws {
        for failure in [false, true] {
            let fixture = try GuestStartupFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let before = try fixture.guestBytes()
            let service = AccountServiceMock()
            var held: CheckedContinuation<AccountSession?, Error>?
            service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
            let coordinator = try fixture.coordinator(service: service)
            let initial = Task { await coordinator.start() }
            await waitForAccountCondition { held != nil }
            service.emitState(AccountAuthState(session: nil, recovery: .init(action: .cleanup, storageIssue: nil)))
            await waitForAccountCondition { coordinator.account.authRecovery?.action == .cleanup }
            XCTAssertFalse(coordinator.daily.isPersistenceActive)
            XCTAssertEqual(try fixture.guestBytes(), before)
            await coordinator.account.retryAuthRecovery()
            XCTAssertEqual(service.cleanupRetryCount, 1)
            XCTAssertNil(coordinator.account.session)
            XCTAssertTrue(coordinator.daily.isPersistenceActive, "Completed explicit cleanup owns signed-out fallback")
            let afterCleanup = try fixture.guestBytes()
            XCTAssertNotEqual(afterCleanup, before)
            if failure { held?.resume(throwing: TestError.failed) }
            else { held?.resume(returning: nil) }
            await initial.value
            coordinator.foregrounded()
            XCTAssertEqual(try fixture.guestBytes(), afterCleanup, "An obsolete restore cannot replace completed cleanup state")
            XCTAssertNil(coordinator.account.errorMessage, "Old restore error cannot replace current cleanup state")
            service.restoration = nil
            await coordinator.start()
            XCTAssertEqual(service.restoreCallCount, 1, "Late supersession cannot reopen a completed signed-out intent")
        }
    }

    func testCompletedSignOutWithoutRetiredUUIDActivatesPreparedTerminalGuest() async throws {
        let fixture = try GuestStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let old = Date(timeIntervalSince1970: 20_696 * 86_400 + 100)
        let puzzle = try DailyPuzzleSchedule.puzzle(at: old, in: fixture.pack)
        var game = DailyClassicGame(puzzle: puzzle, acceptedWords: Set(fixture.pack.acceptedGuesses))
        for letter in puzzle.answer { game.type(letter) }
        XCTAssertNil(game.submit(at: old).error)
        try fixture.guestStore.save(game.progress)
        let before = try fixture.guestBytes()
        let service = AccountServiceMock()
        var held: CheckedContinuation<AccountSession?, Error>?
        service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
        let coordinator = try fixture.coordinator(service: service)
        let initial = Task { await coordinator.start() }
        await waitForAccountCondition { held != nil }
        service.emitState(AccountAuthState(session: nil, recovery: .init(action: .restore, storageIssue: nil)))
        await waitForAccountCondition { coordinator.account.authRecovery?.action == .restore }
        XCTAssertEqual(try fixture.guestBytes(), before)
        await coordinator.account.signOut() // Mock returns no retired UUID, matching unbound restoration.
        XCTAssertEqual(service.signOutCount, 1)
        XCTAssertTrue(coordinator.daily.isPersistenceActive)
        XCTAssertEqual(coordinator.daily.puzzle.day, 20_697)
        XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults.count, 1)
        let afterSignOut = try fixture.guestBytes()
        held?.resume(returning: nil)
        await initial.value
        XCTAssertEqual(try fixture.guestBytes(), afterSignOut)
        XCTAssertNil(coordinator.account.errorMessage)
        service.restoration = nil
        await coordinator.start()
        XCTAssertEqual(service.restoreCallCount, 1)
    }

    func testCancelledStartupDoesNotAcquireGuestAndCanDeliberatelyRestart() async throws {
        for cancelTask in [false, true] {
            let fixture = try GuestStartupFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let before = try fixture.guestBytes()
            let service = AccountServiceMock()
            var held: CheckedContinuation<AccountSession?, Error>?
            service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
            let coordinator = try fixture.coordinator(service: service)
            let initial = Task { await coordinator.start() }
            await waitForAccountCondition { held != nil }
            service.emitState(AccountAuthState(session: nil, recovery: .init(action: .restore, storageIssue: nil)))
            await waitForAccountCondition { coordinator.account.authRecovery?.action == .restore }
            if cancelTask { initial.cancel() }
            held?.resume(throwing: CancellationError())
            await initial.value
            XCTAssertEqual(try fixture.guestBytes(), before)
            XCTAssertFalse(coordinator.daily.isPersistenceActive)
            XCTAssertNil(coordinator.account.errorMessage)
            service.restoration = nil
            await coordinator.start()
            XCTAssertEqual(service.restoreCallCount, 2)
            XCTAssertTrue(coordinator.daily.isPersistenceActive)
            XCTAssertEqual(try fixture.guestStore.loadProgress(), coordinator.daily.game.progress)
        }
    }

    func testGuestFallbackAndExplicitInputRemainAvailableDuringAccountRecovery() async throws {
        for outcome in ["nil", "failure", "input"] {
            let fixture = try GuestStartupFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let service = AccountServiceMock()
            var held: CheckedContinuation<AccountSession?, Error>?
            service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
            let coordinator = try fixture.coordinator(service: service)
            let guestOwner = coordinator.daily
            let initial = Task { await coordinator.start() }
            await waitForAccountCondition { held != nil }
            XCTAssertTrue(coordinator.isDailyPlayable)
            if outcome == "input" {
                coordinator.daily.typeLetter("C")
                XCTAssertTrue(guestOwner.isPersistenceActive)
                XCTAssertEqual(try fixture.guestStore.loadProgress()?.draft, "C")
                held?.resume(returning: AccountSession(userID: UUID(), expiresAt: .distantFuture))
            } else if outcome == "failure" {
                held?.resume(throwing: TestError.failed)
            } else { held?.resume(returning: nil) }
            await initial.value
            if outcome == "input" {
                XCTAssertFalse(coordinator.daily === guestOwner)
                coordinator.sessionChanged(to: nil)
                XCTAssertTrue(coordinator.daily === guestOwner)
                XCTAssertEqual(coordinator.daily.game.draft, "C")
            } else {
                XCTAssertTrue(coordinator.daily === guestOwner)
                XCTAssertTrue(guestOwner.isPersistenceActive)
                XCTAssertEqual(try fixture.guestStore.loadProgress(), guestOwner.game.progress)
                XCTAssertEqual(coordinator.account.errorMessage != nil, outcome == "failure")
            }
        }
    }

    func testStaleRestorationCannotActivateGuestAfterIntentionalAccountSignIn() async throws {
        let fixture = try GuestStartupFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try fixture.guestBytes()
        let service = AccountServiceMock()
        var held: CheckedContinuation<AccountSession?, Error>?
        service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
        let coordinator = try fixture.coordinator(service: service)
        let initial = Task { await coordinator.start() }
        await waitForAccountCondition { held != nil }
        service.emitState(AccountAuthState(session: nil, recovery: .init(action: .restore, storageIssue: nil)))
        await waitForAccountCondition { coordinator.account.authRecovery?.action == .restore }
        let userID = UUID()
        service.appleSession = AccountSession(userID: userID, expiresAt: .distantFuture)
        await coordinator.account.signInWithApple(idToken: "test", rawNonce: "test")
        held?.resume(returning: nil)
        await initial.value
        XCTAssertEqual(coordinator.account.session?.userID, userID)
        XCTAssertTrue(coordinator.daily.isPersistenceActive)
        XCTAssertEqual(try fixture.guestBytes(), before)
    }

    func testLogoutAndDeletionActivateRetainedGuestTerminalRecoveryBeforeRollover() async throws {
        for deletion in [false, true] {
            let fixture = try GuestStartupFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let old = Date(timeIntervalSince1970: 20_696 * 86_400 + 100)
            let puzzle = try DailyPuzzleSchedule.puzzle(at: old, in: fixture.pack)
            var terminal = DailyClassicGame(puzzle: puzzle, acceptedWords: Set(fixture.pack.acceptedGuesses))
            for letter in puzzle.answer { terminal.type(letter) }
            XCTAssertNil(terminal.submit(at: old).error)
            try fixture.guestStore.save(terminal.progress)
            let before = try fixture.guestBytes()
            let service = AccountServiceMock()
            let userID = UUID()
            service.restoredSession = AccountSession(userID: userID, expiresAt: .distantFuture)
            let coordinator = try fixture.coordinator(service: service)
            let guestOwner = coordinator.daily
            await coordinator.start()
            XCTAssertEqual(try fixture.guestBytes(), before, "Account restoration cannot archive guest fallback")
            let accountStore = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
            let accountBefore = try accountStore.loadProgress()
            if deletion { await coordinator.account.deleteAccount() }
            else { await coordinator.account.signOut() }
            XCTAssertTrue(coordinator.daily === guestOwner)
            XCTAssertTrue(guestOwner.isPersistenceActive)
            XCTAssertEqual(guestOwner.puzzle.day, 20_697)
            XCTAssertTrue(guestOwner.game.rows.isEmpty)
            XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults, [try XCTUnwrap(terminal.completedResult)])
            XCTAssertEqual(try fixture.guestStore.loadProgress(), guestOwner.game.progress)
            XCTAssertEqual(try Data(contentsOf: fixture.guestStore.directory.appending(path: "sibling.dat")), Data("protected sibling".utf8))
            if deletion { XCTAssertNil(try accountStore.loadProgress()) }
            else { XCTAssertEqual(try accountStore.loadProgress(), accountBefore) }
        }
    }

    func testReadableUnwritableProgressSurvivesFailedSyncAndRecoversAcceptedOwner() async throws {
        let previousSettings = DailyClassicSettings.load(from: .standard)
        defer { try? previousSettings.save(to: .standard) }
        for kind in ["rows", "terminal", "mode"] {
            let fixture = try makeImportFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let userID = UUID()
            let remote = CoordinatorDailyRemote(userID: userID)
            let coordinator = try importCoordinator(fixture, remotes: [userID: remote])
            coordinator.sessionChanged(to: userID)
            await assertInitialSync(coordinator, remote: remote)
            let owner = coordinator.daily
            owner.updateHardMode(false)
            await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
            let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
            let progressURL = store.directory.appending(path: "daily-progress-v1.json")
            let historyURL = store.directory.appending(path: "daily-history-v1.json")
            let stale = try store.loadProgress()
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: progressURL.path)
            defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: progressURL.path) }
            if kind == "terminal" {
                try store.save(DailyClassicHistory())
                try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: historyURL.path)
            }
            defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: historyURL.path) }
            await remote.failNextPull()
            if kind == "mode" { owner.updateHardMode(true) }
            else {
                let words = kind == "terminal" ? [owner.puzzle.answer] : Array(["civic", "crane", "stone"].filter { $0 != owner.puzzle.answer }.prefix(2))
                for word in words {
                    for letter in word { owner.typeLetter(letter) }
                    owner.submitGuess()
                }
            }
            if kind == "rows" { XCTAssertEqual(owner.game.rows.count, 2) }
            let accepted = owner.game.progress
            await waitForAccountCondition { coordinator.syncStatus == .failed(.unavailable) }
            XCTAssertTrue(coordinator.daily === owner)
            XCTAssertEqual(owner.game.progress, accepted)
            XCTAssertEqual(try store.loadProgress(), stale, "Disk stays readable but stale")
            XCTAssertNotNil(owner.storageMessage)
            XCTAssertNoThrow(try store.save(try store.loadSyncMetadata()), "Metadata remains writable")
            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: progressURL.path)
            if kind == "terminal" {
                try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: historyURL.path)
            }
            coordinator.retrySync()
            await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
            if case .synced = coordinator.syncStatus {} else {
                XCTFail("Recovery kind=\(kind) status=\(coordinator.syncStatus) storage=\(owner.storageMessage ?? "none")")
            }
            XCTAssertTrue(coordinator.daily === owner)
            XCTAssertEqual(owner.game.progress.acceptedGuesses, accepted.acceptedGuesses)
            XCTAssertEqual(owner.game.progress.hardModeEnabled, accepted.hardModeEnabled)
            XCTAssertNil(owner.storageMessage)
            if kind == "terminal" { XCTAssertEqual(try store.loadHistory().completedResults.count, 1) }
        }
    }

    func testConflictIdentityRejectsRetiredAccountCallbackAndRefreshesImportChoice() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let a = UUID(), b = UUID()
        let accountResult = try importResult(priorWords: ["civic"])
        let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: a)
        var history = DailyClassicHistory()
        XCTAssertTrue(history.record(accountResult))
        try store.save(history)
        let remotes = [a: CoordinatorDailyRemote(userID: a, result: accountResult), b: CoordinatorDailyRemote(userID: b)]
        let coordinator = try importCoordinator(fixture, remotes: remotes)
        coordinator.sessionChanged(to: a)
        await assertInitialSync(coordinator, remote: remotes[a]!)
        coordinator.importGuestHistory()
        await waitForAccountCondition { coordinator.firstConflictID != nil }
        let oldID = try XCTUnwrap(coordinator.firstConflictID)
        coordinator.sessionChanged(to: b)
        await assertInitialSync(coordinator, remote: remotes[b]!)
        coordinator.sessionChanged(to: a)
        await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
        coordinator.importGuestHistory()
        await waitForAccountCondition { coordinator.firstConflictID != nil }
        let newID = try XCTUnwrap(coordinator.firstConflictID)
        XCTAssertNotEqual(oldID, newID)
        coordinator.resolveConflict(id: oldID, useCloud: false)
        XCTAssertEqual(coordinator.firstConflictID, newID)
        XCTAssertEqual(try store.loadHistory().completedResults, [accountResult])
        XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
        coordinator.resolveConflict(id: newID, useCloud: true)
        await waitForAccountCondition { !coordinator.canImportGuestHistory }
        XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults, [fixture.guestResult])
    }

    func testGuestMultipleChoicesAndPartialMetadataFailureRemainRetryable() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let userID = UUID()
        let secondGuest = try importResult(dayOffset: 1)
        var guestHistory = try fixture.guestStore.loadHistory()
        XCTAssertTrue(guestHistory.record(secondGuest))
        try fixture.guestStore.save(guestHistory)
        let firstAccount = try importResult(priorWords: ["civic"])
        let secondAccount = try importResult(priorWords: ["civic"], dayOffset: 1)
        let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
        var accountHistory = DailyClassicHistory()
        XCTAssertTrue(accountHistory.record(firstAccount))
        XCTAssertTrue(accountHistory.record(secondAccount))
        try store.save(accountHistory)
        let remote = CoordinatorDailyRemote(userID: userID, result: firstAccount)
        await remote.addResult(secondAccount)
        let coordinator = try importCoordinator(fixture, remotes: [userID: remote])
        coordinator.sessionChanged(to: userID)
        await assertInitialSync(coordinator, remote: remote)
        coordinator.importGuestHistory()
        await waitForAccountCondition { coordinator.conflicts.count == 2 }
        let firstID = try XCTUnwrap(coordinator.firstConflictID)
        let metadataURL = store.directory.appending(path: "daily-sync-metadata-v1.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: metadataURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadataURL.path) }
        coordinator.resolveConflict(id: firstID, useCloud: false)
        await waitForAccountCondition { coordinator.syncStatus == .failed(.invalidData) }
        XCTAssertEqual(coordinator.firstConflictID, firstID)
        XCTAssertEqual(coordinator.conflicts.count, 2)
        XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
        XCTAssertEqual(try store.loadHistory().result(for: fixture.guestResult.puzzleID), fixture.guestResult)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadataURL.path)
        coordinator.resolveConflict(id: firstID, useCloud: false)
        await waitForAccountCondition { coordinator.conflicts.count == 1 }
        XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
        coordinator.resolveConflict(id: try XCTUnwrap(coordinator.firstConflictID), useCloud: false)
        await waitForAccountCondition { !coordinator.canImportGuestHistory }
        XCTAssertEqual(try store.loadSyncMetadata().guestImportDecision, .imported)
        XCTAssertEqual(try store.loadHistory().completedResults, guestHistory.completedResults)
        XCTAssertEqual(try fixture.guestStore.loadHistory(), guestHistory)
    }

    func testAuthoritativeCompletionSettlesDirtyActiveAttemptWithoutWaitingForProgressStorage() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let userID = UUID()
        let remote = CoordinatorDailyRemote(userID: userID)
        let coordinator = try importCoordinator(fixture, remotes: [userID: remote])
        coordinator.sessionChanged(to: userID)
        await assertInitialSync(coordinator, remote: remote)
        let owner = coordinator.daily
        var completed = DailyClassicGame(puzzle: owner.puzzle,
            acceptedWords: Set(try DailyWordPack.load(bundle: .main).acceptedGuesses))
        for letter in owner.puzzle.answer { completed.type(letter) }
        XCTAssertNil(completed.submit(at: Date().dailyWireDate).error)
        let result = try XCTUnwrap(completed.completedResult)
        await remote.addResult(result)
        let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
        let progressURL = store.directory.appending(path: "daily-progress-v1.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: progressURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: progressURL.path) }
        let word = ["civic", "crane"].first { $0 != owner.puzzle.answer }!
        for letter in word { owner.typeLetter(letter) }
        owner.submitGuess()
        await waitForAccountCondition { owner.game.isComplete }
        XCTAssertTrue(coordinator.daily === owner)
        XCTAssertEqual(owner.game.completedResult, result)
        XCTAssertEqual(try store.loadHistory().completedResults, [result])
        XCTAssertNil(owner.storageMessage, "The immutable history write settles terminal durability")
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: progressURL.path)
        coordinator.retrySync()
        await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
        XCTAssertEqual(owner.game.completedResult, result)
    }

    func testGuestPrefixIsAdoptedBeforeHistoricalChoicesAndAfterPartialStagingFailure() async throws {
        let previousSettings = DailyClassicSettings.load(from: .standard)
        defer { try? previousSettings.save(to: .standard) }
        for failsMetadata in [false, true] {
            let fixture = try makeImportFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let userID = UUID()
            let accountResult = try importResult(priorWords: ["civic"])
            let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
            var history = DailyClassicHistory()
            XCTAssertTrue(history.record(accountResult))
            try store.save(history)
            let remote = CoordinatorDailyRemote(userID: userID, result: accountResult)
            let coordinator = try importCoordinator(fixture, remotes: [userID: remote])
            coordinator.sessionChanged(to: userID)
            await assertInitialSync(coordinator, remote: remote)
            let owner = coordinator.daily
            owner.updateHardMode(false)
            await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
            let words = Array(["civic", "crane", "stone", "adore"].filter { $0 != owner.puzzle.answer }.prefix(3))
            for letter in words[0] { owner.typeLetter(letter) }
            owner.submitGuess()
            await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
            var guestGame = try DailyClassicGame(puzzle: owner.puzzle,
                acceptedWords: Set(try DailyWordPack.load(bundle: .main).acceptedGuesses), restoring: owner.game.progress)
            for letter in words[1] { guestGame.type(letter) }
            XCTAssertNil(guestGame.submit(at: Date().addingTimeInterval(1)).error)
            try fixture.guestStore.save(guestGame.progress)
            let guestProgress = try fixture.guestStore.loadProgress()
            let metadataURL = store.directory.appending(path: "daily-sync-metadata-v1.json")
            if failsMetadata { try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: metadataURL.path) }
            defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadataURL.path) }
            coordinator.importGuestHistory()
            if failsMetadata {
                await waitForAccountCondition { coordinator.syncStatus == .failed(.invalidData) }
            } else {
                await waitForAccountCondition { coordinator.conflicts.count == 1 }
            }
            XCTAssertTrue(coordinator.daily === owner)
            XCTAssertEqual(owner.game.rows.count, 2, "Durable imported prefix must reach retained owner before gameplay")
            owner.typeLetter("S")
            XCTAssertEqual(try store.loadProgress()?.acceptedGuesses.count, 2)
            owner.deleteLetter()
            if failsMetadata {
                try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadataURL.path)
                coordinator.importGuestHistory()
                await waitForAccountCondition { coordinator.conflicts.count == 1 }
            }
            for letter in words[2] { owner.typeLetter(letter) }
            owner.submitGuess()
            await waitForAccountCondition { if case .conflict = coordinator.syncStatus { true } else { false } }
            XCTAssertEqual(owner.game.rows.count, 3)
            XCTAssertEqual(try store.loadProgress()?.acceptedGuesses.count, 3)
            XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
            XCTAssertTrue(coordinator.canImportGuestHistory)
            XCTAssertEqual(try fixture.guestStore.loadProgress(), guestProgress)
            XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults, [fixture.guestResult])
            coordinator.resolveConflict(id: try XCTUnwrap(coordinator.firstConflictID), useCloud: true)
            await waitForAccountCondition { !coordinator.canImportGuestHistory }
            XCTAssertEqual(owner.game.rows.count, 3)
        }
    }

    func testAccountActivationFailureNeverDisplaysGuestDataAndRetryReopensCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceAccountActivationTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let guestStore = DailyClassicStore(directory: root.appending(path: "Guest"))
        let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
            urlString: "http://127.0.0.1:54321",
            publishableKey: "local-test-key"
        ))
        var attempts = 0
        let coordinator = try DailyAccountCoordinator(
            dailyPack: DailyWordPack.load(bundle: .main),
            tutorialPack: WordPack.load(bundle: .main),
            guestStore: guestStore,
            accountService: SupabaseAccountService(configuration: configuration),
            dailyRemoteFactory: { _ in UnavailableDailyRemote() },
            accountStoreFactory: { userID in
                attempts += 1
                if attempts == 1 { throw TestError.failed }
                return AccountDailyClassicStore(rootDirectory: root, userID: userID)
            }
        )
        coordinator.daily.typeLetter("A")
        XCTAssertEqual(coordinator.daily.homeStatus, .inProgress(0))

        coordinator.sessionChanged(to: UUID())

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(coordinator.daily.homeStatus, .unplayed)
        XCTAssertEqual(coordinator.syncStatus, .failed(.invalidData))
        XCTAssertFalse(coordinator.isDailyPlayable)
        coordinator.daily.typeLetter("A")
        XCTAssertEqual(coordinator.daily.errorMessage, "Your puzzle could not be saved. Try again.")

        coordinator.retrySync()

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(coordinator.daily.homeStatus, .unplayed)
        XCTAssertTrue(coordinator.isDailyPlayable)
    }

    func testCorruptAccountMetadataBlocksGameplayUntilSignOutRestoresGuest() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceCorruptAccountTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let guestStore = DailyClassicStore(directory: root.appending(path: "Guest"))
        let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
            urlString: "http://127.0.0.1:54321",
            publishableKey: "local-test-key"
        ))
        let coordinator = try DailyAccountCoordinator(
            dailyPack: DailyWordPack.load(bundle: .main),
            tutorialPack: WordPack.load(bundle: .main),
            guestStore: guestStore,
            accountService: SupabaseAccountService(configuration: configuration),
            accountStoreFactory: { userID in
                let store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
                try FileManager.default.createDirectory(
                    at: store.directory,
                    withIntermediateDirectories: true
                )
                try Data("{".utf8).write(
                    to: store.directory.appending(path: "daily-sync-metadata-v1.json")
                )
                return store
            }
        )
        coordinator.daily.typeLetter("G")

        coordinator.sessionChanged(to: UUID())

        XCTAssertFalse(coordinator.isDailyPlayable)
        XCTAssertEqual(coordinator.daily.homeStatus, .unplayed)

        coordinator.sessionChanged(to: nil)

        XCTAssertTrue(coordinator.isDailyPlayable)
        XCTAssertEqual(coordinator.daily.game.draft, "G")
    }

    func testNilSessionKeepsFirstCleanupFailureReachableAndRetriesOnLaterNotification() async throws {
        let fixture = try makeLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.coordinator.daily.typeLetter("G")
        await fixture.coordinator.account.signInWithApple(idToken: "token", rawNonce: "nonce")
        fixture.coordinator.daily.typeLetter("A")
        fixture.liveStore.clearFailuresRemaining = 1

        fixture.coordinator.sessionChanged(to: nil)

        XCTAssertEqual(fixture.coordinator.daily.game.draft, "G")
        XCTAssertEqual(fixture.coordinator.live.phase, .storageUnavailable)
        XCTAssertTrue(fixture.coordinator.live.canDiscardRecovery)
        XCTAssertNotEqual(fixture.liveStore.storedState, LiveRecoveryState())

        fixture.coordinator.sessionChanged(to: nil)

        XCTAssertEqual(fixture.coordinator.live.phase, .inactive)
        XCTAssertFalse(fixture.coordinator.live.canDiscardRecovery)
        XCTAssertEqual(fixture.liveStore.storedState, LiveRecoveryState())
        XCTAssertEqual(fixture.coordinator.daily.game.draft, "G")
    }

    func testSignOutHidesAccountDataAndKeepsFailedLiveCleanupReachable() async throws {
        let fixture = try makeLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.liveStore.rejectsLoads = true
        fixture.liveStore.rejectsClears = true
        fixture.coordinator.daily.typeLetter("G")

        await fixture.coordinator.account.signInWithApple(idToken: "token", rawNonce: "nonce")
        fixture.coordinator.daily.typeLetter("A")
        XCTAssertEqual(fixture.coordinator.daily.game.draft, "A")

        await fixture.coordinator.account.signOut()

        XCTAssertEqual(fixture.accountService.signOutCount, 1)
        XCTAssertFalse(fixture.coordinator.account.isSignedIn)
        XCTAssertEqual(fixture.coordinator.daily.game.draft, "G")
        XCTAssertEqual(fixture.coordinator.live.phase, .storageUnavailable)
        XCTAssertTrue(fixture.coordinator.live.canDiscardRecovery)
        XCTAssertEqual(
            fixture.coordinator.account.errorMessage,
            "You’re signed out, but saved live recovery data could not be removed. Open Live Race to retry or discard it."
        )

        fixture.liveStore.rejectsLoads = false
        fixture.liveStore.rejectsClears = false
        fixture.coordinator.live.discardRecovery()
        XCTAssertEqual(fixture.liveStore.storedState, LiveRecoveryState())

        let relaunchedService = AccountServiceMock()
        relaunchedService.appleSession = AccountSession(
            userID: fixture.userID,
            expiresAt: Date().addingTimeInterval(3_600)
        )
        relaunchedService.loadedProfile = fixture.profile
        let relaunched = try makeCoordinator(
            root: fixture.root,
            guestStore: DailyClassicStore(directory: fixture.root.appending(path: "Guest")),
            accountModelService: relaunchedService,
            liveStore: fixture.liveStore
        )
        await relaunched.account.signInWithApple(idToken: "token", rawNonce: "nonce")

        XCTAssertEqual(relaunched.live.phase, .inactive)
        XCTAssertNil(relaunched.live.pendingIntent)
        XCTAssertEqual(fixture.liveStore.storedState, LiveRecoveryState())
    }

    func testDeletionClearsDailyCacheOnceAndKeepsFailedLiveCleanupReachable() async throws {
        let fixture = try makeLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.liveStore.rejectsLoads = true
        fixture.liveStore.rejectsClears = true
        fixture.coordinator.daily.typeLetter("G")
        await fixture.coordinator.account.signInWithApple(idToken: "token", rawNonce: "nonce")
        fixture.coordinator.daily.typeLetter("A")
        let accountDirectory = AccountDailyClassicStore(
            rootDirectory: fixture.root,
            userID: fixture.userID
        ).directory
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountDirectory.path))

        await fixture.coordinator.account.deleteAccount()

        XCTAssertEqual(fixture.accountService.deleteCount, 1)
        XCTAssertFalse(fixture.coordinator.account.isSignedIn)
        XCTAssertEqual(fixture.coordinator.daily.game.draft, "G")
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountDirectory.path))
        XCTAssertEqual(fixture.coordinator.live.phase, .storageUnavailable)
        XCTAssertTrue(fixture.coordinator.live.canDiscardRecovery)
        XCTAssertTrue(fixture.coordinator.account.errorMessage?.contains("account was deleted") == true)

        fixture.liveStore.rejectsLoads = false
        fixture.liveStore.rejectsClears = false
        fixture.coordinator.live.discardRecovery()

        XCTAssertEqual(fixture.accountService.deleteCount, 1)
        XCTAssertEqual(fixture.liveStore.storedState, LiveRecoveryState())
        XCTAssertEqual(fixture.coordinator.live.phase, .inactive)
    }

    func testSuccessfulAccountLifecycleCleanupRemainsSilent() async throws {
        let fixture = try makeLifecycleFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        await fixture.coordinator.account.signInWithApple(idToken: "token", rawNonce: "nonce")
        await fixture.coordinator.account.signOut()

        XCTAssertNil(fixture.coordinator.account.errorMessage)
        XCTAssertEqual(fixture.coordinator.live.phase, .inactive)
        XCTAssertEqual(fixture.liveStore.storedState, LiveRecoveryState())

        await fixture.coordinator.account.signInWithApple(idToken: "token", rawNonce: "nonce")
        await fixture.coordinator.account.deleteAccount()

        XCTAssertNil(fixture.coordinator.account.errorMessage)
        XCTAssertEqual(fixture.accountService.deleteCount, 1)
        XCTAssertFalse(fixture.coordinator.account.isSignedIn)
        XCTAssertEqual(fixture.coordinator.live.phase, .inactive)
    }

    func testBothRecoveryFormatsUseSameFileAndCleanupOnlyTheSignedOutOrDeletedAccount() async throws {
        for format in [1, 2] {
            for deletesAccount in [false, true] {
                let root = FileManager.default.temporaryDirectory
                    .appending(path: "GridRaceLiveCleanup-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: root) }
                let userID = UUID(), otherID = UUID(), matchID = UUID(), requestID = UUID()
                let owner = LiveMatchRecoveryStore(rootDirectory: root, userID: userID)
                let other = LiveMatchRecoveryStore(rootDirectory: root, userID: otherID)
                let otherState = LiveRecoveryState(matchID: UUID())
                try other.save(otherState)
                let otherFile = other.directory.appending(path: "live-recovery-v1.json")
                let otherBytes = try Data(contentsOf: otherFile)
                let ownerFile = owner.directory.appending(path: "live-recovery-v1.json")
                try FileManager.default.createDirectory(at: owner.directory, withIntermediateDirectories: true)
                if format == 1 {
                    try Data(#"{"formatVersion":1,"matchID":"\#(matchID)","pendingIntent":{"kind":"guess","matchID":"\#(matchID)","requestID":"\#(requestID)","word":"STONE"}}"#.utf8)
                        .write(to: ownerFile)
                } else {
                    try owner.save(LiveRecoveryState(matchID: matchID, pendingIntent:
                        .guess(matchID: matchID, requestID: requestID, word: "STONE", roundNumber: 3, clientBuild: 2)))
                }
                let account = AccountServiceMock()
                account.appleSession = AccountSession(userID: userID, expiresAt: Date().addingTimeInterval(3_600))
                account.loadedProfile = PlayerProfile(userID: userID, displayName: "Alex", avatarSeed: "seed",
                                                     setupCompleted: true,
                                                     createdAt: .distantPast, updatedAt: .distantPast)
                let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
                    urlString: "http://127.0.0.1:54321", publishableKey: "local-test-key"))
                let coordinator = try DailyAccountCoordinator(
                    dailyPack: DailyWordPack.load(bundle: .main), tutorialPack: WordPack.load(bundle: .main),
                    guestStore: DailyClassicStore(directory: root.appending(path: "Guest")),
                    accountService: SupabaseAccountService(configuration: configuration), accountModelService: account,
                    accountStoreFactory: { AccountDailyClassicStore(rootDirectory: root, userID: $0) },
                    liveTransportFactory: accountLifecycleTransport,
            liveStoreFactory: { LiveMatchRecoveryStore(rootDirectory: root, userID: $0) })
                coordinator.live.backgrounded()
                await coordinator.account.signInWithApple(idToken: "token", rawNonce: "nonce")
                XCTAssertEqual(coordinator.live.savedMatchID, matchID)
                XCTAssertEqual(try owner.load().formatVersion, 2, "legacy migration saves in the original path")
                XCTAssertEqual(coordinator.live.pendingIntent,
                    .guess(matchID: matchID, requestID: requestID, word: "STONE",
                           roundNumber: format == 1 ? 1 : 3, clientBuild: format == 1 ? 1 : 2))
                if deletesAccount { await coordinator.account.deleteAccount() }
                else { await coordinator.account.signOut() }
                XCTAssertFalse(FileManager.default.fileExists(atPath: ownerFile.path))
                XCTAssertEqual(try Data(contentsOf: otherFile), otherBytes)
                XCTAssertEqual(try other.load(), otherState)
                XCTAssertNil(coordinator.live.pendingIntent)
                XCTAssertNil(coordinator.live.savedMatchID)
                XCTAssertEqual(coordinator.live.phase, .inactive)
                XCTAssertNil(coordinator.account.errorMessage)
                XCTAssertEqual(account.deleteCount, deletesAccount ? 1 : 0)
                XCTAssertEqual(account.signOutCount, deletesAccount ? 0 : 1)
            }
        }
    }

    func testAuthStreamSwitchesDailyCacheBeforeSuspendedProfileReturns() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let a = UUID(), b = UUID()
        let service = AccountServiceMock()
        service.restoredSession = AccountSession(userID: a, expiresAt: .distantFuture)
        var suspended: CheckedContinuation<PlayerProfile, Error>?
        var returned = false
        service.profileLoader = { userID in
            if userID == a {
                defer { returned = true }
                return try await withCheckedThrowingContinuation { suspended = $0 }
            }
            return PlayerProfile(userID: b, displayName: "Blair", avatarSeed: "b", setupCompleted: true, createdAt: .distantPast, updatedAt: .distantPast)
        }
        let remotes = [a: CoordinatorDailyRemote(userID: a), b: CoordinatorDailyRemote(userID: b)]
        let coordinator = try DailyAccountCoordinator(
            dailyPack: DailyWordPack.load(bundle: .main), tutorialPack: WordPack.load(bundle: .main),
            guestStore: fixture.guestStore, accountService: nil, accountModelService: service,
            dailyRemoteFactory: { remotes[$0]! },
            accountStoreFactory: { AccountDailyClassicStore(rootDirectory: fixture.root, userID: $0) },
            liveTransportFactory: accountLifecycleTransport,
            liveStoreFactory: { _ in AccountLifecycleLiveStore(LiveRecoveryState()) }
        )
        coordinator.daily.typeLetter("G")
        await coordinator.start()
        await waitForAccountCondition { suspended != nil }
        coordinator.daily.typeLetter("A")
        service.emit(nil)
        await waitForAccountCondition { coordinator.account.session == nil }
        XCTAssertEqual(coordinator.daily.game.draft, "G")
        service.emit(AccountSession(userID: b, expiresAt: .distantFuture))
        await waitForAccountCondition { coordinator.account.profile?.userID == b }
        XCTAssertEqual(coordinator.daily.game.draft, "")
        XCTAssertTrue(coordinator.isDailyPlayable)
        suspended?.resume(throwing: TestError.failed)
        await waitForAccountCondition { returned }
        XCTAssertEqual(coordinator.account.session?.userID, b)
        XCTAssertEqual(coordinator.account.profile?.displayName, "Blair")
        XCTAssertNil(coordinator.account.errorMessage)
        XCTAssertEqual(coordinator.daily.game.draft, "")
        XCTAssertEqual(try fixture.guestStore.loadProgress()?.draft, "G")
    }

    func testSuspendedAImportCannotMarkBImportedOrHideBOffer() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let a = UUID(), b = UUID()
        let remoteA = CoordinatorDailyRemote(userID: a)
        let remoteB = CoordinatorDailyRemote(userID: b)
        let coordinator = try importCoordinator(fixture, remotes: [a: remoteA, b: remoteB])
        coordinator.sessionChanged(to: a)
        await assertInitialSync(coordinator, remote: remoteA)
        XCTAssertTrue(coordinator.canImportGuestHistory)
        await remoteA.suspendNextPull()
        coordinator.importGuestHistory()
        await waitForAccountCondition { await remoteA.isSuspended }
        let storeA = AccountDailyClassicStore(rootDirectory: fixture.root, userID: a)
        XCTAssertNil(try storeA.loadSyncMetadata().guestImportDecision)
        XCTAssertEqual(try storeA.loadHistory().completedResults, [fixture.guestResult])

        coordinator.sessionChanged(to: b)
        await assertInitialSync(coordinator, remote: remoteB)
        let storeB = AccountDailyClassicStore(rootDirectory: fixture.root, userID: b)
        XCTAssertNil(try storeB.loadSyncMetadata().guestImportDecision)
        XCTAssertTrue(coordinator.canImportGuestHistory)
        XCTAssertTrue(try storeB.loadHistory().completedResults.isEmpty)
        await remoteA.releasePull()
        await waitForAccountCondition { await remoteA.releasedPullReturned }
        XCTAssertNil(try storeB.loadSyncMetadata().guestImportDecision)
        XCTAssertTrue(coordinator.canImportGuestHistory)
        XCTAssertNil(try storeA.loadSyncMetadata().guestImportDecision)
        XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults, [fixture.guestResult])
    }

    func testCanceledImportStagingDoesNotCreatePendingDecisionForReplacement() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let a = UUID(), b = UUID()
        let remotes = [a: CoordinatorDailyRemote(userID: a), b: CoordinatorDailyRemote(userID: b)]
        let coordinator = try importCoordinator(fixture, remotes: remotes)
        coordinator.sessionChanged(to: a)
        await assertInitialSync(coordinator, remote: remotes[a]!)
        coordinator.importGuestHistory()
        // Replace the account before the scheduled staging task can run.
        coordinator.sessionChanged(to: b)
        await assertInitialSync(coordinator, remote: remotes[b]!)
        let storeA = AccountDailyClassicStore(rootDirectory: fixture.root, userID: a)
        let storeB = AccountDailyClassicStore(rootDirectory: fixture.root, userID: b)
        XCTAssertTrue(try storeA.loadHistory().completedResults.isEmpty)
        XCTAssertNil(try storeA.loadSyncMetadata().guestImportDecision)
        XCTAssertNil(try storeB.loadSyncMetadata().guestImportDecision)
        XCTAssertTrue(coordinator.canImportGuestHistory)
    }

    func testImportRetryForSameAccountFinishesDecisionAfterNetworkFailure() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let userID = UUID()
        let remote = CoordinatorDailyRemote(userID: userID)
        let coordinator = try importCoordinator(fixture, remotes: [userID: remote])
        coordinator.sessionChanged(to: userID)
        await assertInitialSync(coordinator, remote: remote)
        await remote.failNextPull()
        coordinator.importGuestHistory()
        await waitForAccountCondition { if case .failed = coordinator.syncStatus { true } else { false } }
        let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
        XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
        XCTAssertTrue(coordinator.canImportGuestHistory)
        coordinator.retrySync()
        await waitForAccountCondition { !coordinator.canImportGuestHistory }
        XCTAssertEqual(try store.loadSyncMetadata().guestImportDecision, .imported)
        XCTAssertEqual(try store.loadHistory().completedResults, [fixture.guestResult])
        XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults, [fixture.guestResult])
    }

    func testGuestImportConflictKeepsDecisionPendingUntilExplicitResolution() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let userID = UUID()
        let accountResult = try importResult(priorWords: ["civic"])
        let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
        var history = DailyClassicHistory()
        XCTAssertTrue(history.record(accountResult))
        try store.save(history)
        let remote = CoordinatorDailyRemote(userID: userID, result: accountResult)
        let coordinator = try importCoordinator(fixture, remotes: [userID: remote])
        coordinator.sessionChanged(to: userID)
        await assertInitialSync(coordinator, remote: remote)
        coordinator.importGuestHistory()
        await waitForAccountCondition { !coordinator.conflicts.isEmpty }
        XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
        XCTAssertTrue(coordinator.canImportGuestHistory)
        coordinator.retrySync()
        // This retry must not bypass the still-unresolved import choice.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(coordinator.conflicts.isEmpty)
        XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
        coordinator.resolveConflict(id: try XCTUnwrap(coordinator.firstConflictID), useCloud: true)
        await waitForAccountCondition { !coordinator.canImportGuestHistory }
        XCTAssertEqual(try store.loadSyncMetadata().guestImportDecision, .imported)
        XCTAssertTrue(coordinator.conflicts.isEmpty)
        XCTAssertEqual(try store.loadHistory().completedResults, [accountResult])
        XCTAssertEqual(try fixture.guestStore.loadHistory().completedResults, [fixture.guestResult])
    }

    func testFailedGuestStagingCannotBeMarkedImportedByLaterSync() async throws {
        let fixture = try makeImportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let userID = UUID()
        let remote = CoordinatorDailyRemote(userID: userID)
        let coordinator = try importCoordinator(fixture, remotes: [userID: remote])
        coordinator.sessionChanged(to: userID)
        await assertInitialSync(coordinator, remote: remote)
        try Data("{".utf8).write(to: fixture.guestStore.directory.appending(path: "daily-history-v1.json"))
        coordinator.importGuestHistory()
        await waitForAccountCondition { coordinator.syncStatus == .failed(.invalidData) }
        coordinator.retrySync()
        await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
        let store = AccountDailyClassicStore(rootDirectory: fixture.root, userID: userID)
        XCTAssertNil(try store.loadSyncMetadata().guestImportDecision)
        XCTAssertTrue(coordinator.canImportGuestHistory)
    }

    private func makeImportFixture() throws -> (root: URL, guestStore: DailyClassicStore, guestResult: DailyCompletedResult) {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceCoordinatorImport-\(UUID().uuidString)")
        let guestStore = DailyClassicStore(directory: root.appending(path: "Guest"))
        let result = try importResult()
        var history = DailyClassicHistory()
        XCTAssertTrue(history.record(result))
        try guestStore.save(history)
        return (root, guestStore, result)
    }

    private func importCoordinator(
        _ fixture: (root: URL, guestStore: DailyClassicStore, guestResult: DailyCompletedResult),
        remotes: [UUID: CoordinatorDailyRemote]
    ) throws -> DailyAccountCoordinator {
        try DailyAccountCoordinator(
            dailyPack: DailyWordPack.load(bundle: .main), tutorialPack: WordPack.load(bundle: .main),
            guestStore: fixture.guestStore, accountService: nil,
            dailyRemoteFactory: { remotes[$0]! },
            accountStoreFactory: { AccountDailyClassicStore(rootDirectory: fixture.root, userID: $0) },
            liveTransportFactory: accountLifecycleTransport,
            liveStoreFactory: { _ in AccountLifecycleLiveStore(LiveRecoveryState()) }
        )
    }

    private func importResult(priorWords: [String] = [], dayOffset: Int = 0) throws -> DailyCompletedResult {
        let pack = try DailyWordPack.load(bundle: .main)
        let date = Date(timeIntervalSince1970: TimeInterval((pack.epochDay + dayOffset) * 86_400))
        let puzzle = try DailyPuzzleSchedule.puzzle(at: date, in: pack)
        var game = DailyClassicGame(puzzle: puzzle, acceptedWords: Set(pack.acceptedGuesses))
        for (index, word) in (priorWords + [puzzle.answer]).enumerated() {
            for letter in word { game.type(letter) }
            let submitted = game.submit(at: date.addingTimeInterval(TimeInterval(index + 1)))
            XCTAssertNil(submitted.error)
        }
        return try XCTUnwrap(game.completedResult)
    }

    private func assertInitialSync(_ coordinator: DailyAccountCoordinator, remote: CoordinatorDailyRemote) async {
        await waitForAccountCondition { if case .synced = coordinator.syncStatus { true } else { false } }
        let uploads = await remote.progressUploads
        let canonical = await remote.canonicalProgress
        XCTAssertEqual(uploads.count, 1, "Activation must synchronize its real blank active progress")
        XCTAssertNil(uploads.first?.expectedRevision)
        XCTAssertEqual(canonical?.userID, remote.userID)
        XCTAssertEqual(canonical?.puzzleID, coordinator.daily.puzzle.id)
        XCTAssertEqual(canonical?.guesses, [])
        XCTAssertEqual(canonical?.revision, 1)
    }

    private func makeLifecycleFixture() throws -> LifecycleFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceAccountLifecycleTests-\(UUID().uuidString)")
        let userID = UUID()
        let accountService = AccountServiceMock()
        accountService.appleSession = AccountSession(
            userID: userID,
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let profile = PlayerProfile(
            userID: userID,
            displayName: "Alex",
            avatarSeed: "seed",
            setupCompleted: true,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        accountService.loadedProfile = profile
        let liveStore = AccountLifecycleLiveStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        let guestStore = DailyClassicStore(directory: root.appending(path: "Guest"))
        let coordinator = try makeCoordinator(
            root: root,
            guestStore: guestStore,
            accountModelService: accountService,
            liveStore: liveStore
        )
        return LifecycleFixture(
            root: root,
            userID: userID,
            profile: profile,
            accountService: accountService,
            liveStore: liveStore,
            coordinator: coordinator
        )
    }

    private func makeCoordinator(
        root: URL,
        guestStore: DailyClassicStore,
        accountModelService: any AccountServicing,
        liveStore: AccountLifecycleLiveStore
    ) throws -> DailyAccountCoordinator {
        let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
            urlString: "http://127.0.0.1:54321",
            publishableKey: "local-test-key"
        ))
        return try DailyAccountCoordinator(
            dailyPack: DailyWordPack.load(bundle: .main),
            tutorialPack: WordPack.load(bundle: .main),
            guestStore: guestStore,
            accountService: SupabaseAccountService(configuration: configuration),
            accountModelService: accountModelService,
            dailyRemoteFactory: { _ in UnavailableDailyRemote() },
            accountStoreFactory: { AccountDailyClassicStore(rootDirectory: root, userID: $0) },
            liveTransportFactory: accountLifecycleTransport,
            liveStoreFactory: { _ in liveStore }
        )
    }
}

@MainActor
private struct LifecycleFixture {
    let root: URL
    let userID: UUID
    let profile: PlayerProfile
    let accountService: AccountServiceMock
    let liveStore: AccountLifecycleLiveStore
    let coordinator: DailyAccountCoordinator
}

@MainActor
final class AccountModelTests: XCTestCase {
    func testSameValueSetupSaveAppliesReturnedCompletionAndRestores() async {
        for name in ["Player abcdef", "Custom Name"] {
            let userID = UUID()
            let service = AccountServiceMock()
            service.appleSession = session(userID)
            service.loadedProfile = profile(userID: userID, name: name, setupCompleted: false)
            let model = AccountModel(service: service)
            var signInSheet = AccountSheetState(isSignedIn: false)
            var editingSheet = AccountSheetState(isSignedIn: true)

            await model.signInWithApple(idToken: "token", rawNonce: "nonce")
            await waitForAccountCondition { !model.isLoadingProfile }
            XCTAssertTrue(model.needsProfileSetup)
            XCTAssertEqual(model.displayNameDraft, name)
            XCTAssertFalse(signInSheet.observe(isSignedIn: model.isSignedIn, profileReady: profileReady(model)))
            model.randomizeAvatar()
            XCTAssertTrue(model.needsProfileSetup, "Changing the draft avatar cannot complete setup")
            let saved = profile(userID: userID, name: name, setupCompleted: true, avatarSeed: model.avatarSeedDraft)
            service.updatedProfile = saved

            await model.saveProfile()

            XCTAssertEqual(service.lastProfileUpdate?.name, name, "Same-value Save must reach the service")
            XCTAssertEqual(model.profile, saved)
            XCTAssertFalse(model.needsProfileSetup)
            XCTAssertTrue(signInSheet.observe(isSignedIn: model.isSignedIn, profileReady: profileReady(model)))
            XCTAssertFalse(editingSheet.observe(isSignedIn: model.isSignedIn, profileReady: profileReady(model)))

            let restoredService = AccountServiceMock()
            restoredService.restoredSession = session(userID)
            restoredService.loadedProfile = saved
            let restored = AccountModel(service: restoredService)
            await restored.start()
            await waitForAccountCondition { !restored.isLoadingProfile }
            XCTAssertEqual(restored.profile, saved)
            XCTAssertFalse(restored.needsProfileSetup)
        }
    }

    func testUnavailableProfileAndFailedSaveKeepSetupSheetOpenUntilRetry() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        let model = AccountModel(service: service)
        var sheet = AccountSheetState(isSignedIn: false)
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }
        XCTAssertNil(model.profile)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(sheet.observe(isSignedIn: model.isSignedIn, profileReady: profileReady(model)))

        let incomplete = profile(userID: userID, name: "Player abcdef", setupCompleted: false)
        service.loadedProfile = incomplete
        await model.retryProfile()
        XCTAssertEqual(model.profile, incomplete)
        XCTAssertFalse(sheet.observe(isSignedIn: model.isSignedIn, profileReady: profileReady(model)))
        await model.saveProfile() // No successful response is configured.
        XCTAssertEqual(model.profile, incomplete)
        XCTAssertTrue(model.needsProfileSetup)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(sheet.observe(isSignedIn: model.isSignedIn, profileReady: profileReady(model)))

        service.updatedProfile = profile(userID: userID, name: "Player abcdef", setupCompleted: true)
        await model.saveProfile()
        XCTAssertEqual(service.profileUpdateCount, 2)
        XCTAssertFalse(model.needsProfileSetup)
        XCTAssertTrue(sheet.observe(isSignedIn: model.isSignedIn, profileReady: profileReady(model)))
    }

    func testInitialSnapshotPrecedesImmediateRestoreAndLaterNilRemainsAuthoritative() async {
        let service = AccountServiceMock()
        let restored = session(UUID())
        service.restoration = {
            service.emit(restored)
            return restored
        }
        var identities: [UUID?] = []
        let model = AccountModel(service: service, didChangeSession: { identities.append($0) })
        let outcome = await model.start()
        await waitForAccountCondition { identities.filter { $0 != nil }.count == 2 }
        XCTAssertEqual(outcome, .settled(restored.userID))
        XCTAssertEqual(identities, [nil, restored.userID, restored.userID])
        XCTAssertEqual(model.session, restored)

        service.emit(nil)
        await waitForAccountCondition { identities.count == 4 }
        XCTAssertEqual(identities, [nil, restored.userID, restored.userID, nil])
        XCTAssertNil(model.session, "Only the initial snapshot is ordered before restore; future nil still signs out")
    }

    func testRestorationOutcomesDistinguishProvisionalNilAndSupersededRetry() async throws {
        let service = AccountServiceMock()
        var holds: [CheckedContinuation<AccountSession?, Error>] = []
        service.restoration = { try await withCheckedThrowingContinuation { holds.append($0) } }
        var nilNotifications = 0
        var completions: [AccountModel.RestorationOutcome] = []
        let model = AccountModel(service: service,
            didChangeSession: { if $0 == nil { nilNotifications += 1 } },
            didFinishRestoration: { completions.append($0) })
        let initial = Task { await model.start() }
        await waitForAccountCondition { holds.count == 1 }
        let duplicate = await model.start()
        XCTAssertEqual(duplicate, .alreadyStarted)
        service.emit(nil)
        await waitForAccountCondition { nilNotifications == 2 }
        XCTAssertTrue(completions.isEmpty, "A provisional stream nil is not restoration settlement")
        let retry = Task { await model.restoreSession() }
        await waitForAccountCondition { holds.count == 2 }
        holds[0].resume(returning: nil)
        let obsolete = await initial.value
        XCTAssertEqual(obsolete, .superseded)
        XCTAssertTrue(completions.isEmpty, "Older attempt cannot settle the latest restore")
        XCTAssertTrue(model.isRestoring)
        holds[1].resume(returning: nil)
        let latest = await retry.value
        XCTAssertEqual(latest, .settled(nil))
        XCTAssertEqual(completions, [.settled(nil)])
        XCTAssertFalse(model.isRestoring)
    }

    func testCompletedCleanupDoesNotReauthorizeOlderRestoreReceipt() async throws {
        for failure in [false, true] {
            let service = AccountServiceMock()
            var held: CheckedContinuation<AccountSession?, Error>?
            service.restoration = { try await withCheckedThrowingContinuation { held = $0 } }
            var outcomes: [AccountModel.RestorationOutcome] = []
            var cleanupCompletions = 0
            let model = AccountModel(service: service,
                didFinishRestoration: { outcomes.append($0) },
                didCompleteSignedOutIntent: { cleanupCompletions += 1 })
            let initial = Task { await model.start() }
            await waitForAccountCondition { held != nil }
            service.emitState(AccountAuthState(session: nil, recovery: .init(action: .cleanup, storageIssue: nil)))
            await waitForAccountCondition { model.authRecovery?.action == .cleanup }
            await model.retryAuthRecovery()
            XCTAssertEqual(cleanupCompletions, 1)
            XCTAssertTrue(outcomes.isEmpty, "Completed cleanup is not a restoration outcome")
            if failure { held?.resume(throwing: TestError.failed) }
            else { held?.resume(returning: nil) }
            let outcome = await initial.value
            XCTAssertEqual(outcome, .superseded)
            XCTAssertEqual(outcomes, [.superseded])
            XCTAssertNil(model.errorMessage)
        }
    }

    func testSessionRestorationLoadsOnlyTheOwnersProfile() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.restoredSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex", setupCompleted: true)
        let model = AccountModel(service: service)

        await model.start()
        await waitForAccountCondition { !model.isLoadingProfile }

        XCTAssertEqual(model.session?.userID, userID)
        XCTAssertEqual(model.profile?.displayName, "Alex")
        XCTAssertEqual(service.loadedUserIDs, [userID])
    }

    func testAppleSignInPassesRawNonceAndLoadsProfile() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Taylor", setupCompleted: true)
        let model = AccountModel(service: service)

        await model.signInWithApple(idToken: "identity-token", rawNonce: "raw-nonce")
        await waitForAccountCondition { !model.isLoadingProfile }

        XCTAssertEqual(service.appleCredentials?.idToken, "identity-token")
        XCTAssertEqual(service.appleCredentials?.nonce, "raw-nonce")
        XCTAssertEqual(model.profile?.displayName, "Taylor")
        XCTAssertFalse(model.isWorking)
    }

    func testInvalidProfileIsRejectedBeforeNetwork() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex", setupCompleted: true)
        let model = AccountModel(service: service)
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }
        model.displayNameDraft = "A"

        await model.saveProfile()

        XCTAssertEqual(service.profileUpdateCount, 0)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
    }

    func testProfileEditingAndAvatarRandomizationPersistTogether() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex", setupCompleted: true)
        let model = AccountModel(service: service)
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }
        let oldSeed = model.avatarSeedDraft
        model.displayNameDraft = "Sam-2"
        model.randomizeAvatar()
        service.updatedProfile = profile(
            userID: userID,
            name: "Sam-2",
            setupCompleted: true,
            avatarSeed: model.avatarSeedDraft
        )

        await model.saveProfile()

        XCTAssertNotEqual(model.avatarSeedDraft, oldSeed)
        XCTAssertEqual(service.lastProfileUpdate?.name, "Sam-2")
        XCTAssertEqual(service.lastProfileUpdate?.seed, model.avatarSeedDraft)
        XCTAssertEqual(model.profile?.displayName, "Sam-2")
    }

    func testDeletionCallbackRunsOnlyAfterServerSuccess() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex", setupCompleted: true)
        var deletedUserID: UUID?
        let model = AccountModel(
            service: service,
            didDeleteAccount: { deletedUserID = $0 }
        )
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }

        service.deleteError = TestError.failed
        await model.deleteAccount()
        XCTAssertNil(deletedUserID)
        XCTAssertEqual(model.session?.userID, userID)

        service.deleteError = nil
        await model.deleteAccount()
        XCTAssertEqual(deletedUserID, userID)
        XCTAssertNil(model.session)
    }

    func testDeletionReportsLocalCleanupFailureAfterServerSuccess() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex", setupCompleted: true)
        let model = AccountModel(
            service: service,
            didDeleteAccount: { _ in throw TestError.failed }
        )
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }

        await model.deleteAccount()

        XCTAssertNil(model.session)
        XCTAssertTrue(model.errorMessage?.contains("local data") == true)
    }

    func testSignOutCallbackReceivesAccountBeforeStateIsCleared() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex", setupCompleted: true)
        var signedOutUserID: UUID?
        let model = AccountModel(service: service, didSignOut: {
            signedOutUserID = $0
            return true
        })
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }

        await model.signOut()

        XCTAssertEqual(signedOutUserID, userID)
        XCTAssertNil(model.session)
        XCTAssertNil(model.profile)
    }

    func testCancellationAlwaysEndsLoadingWithoutPresentingAnError() async {
        let service = AccountServiceMock()
        service.signInDelay = .seconds(60)
        let model = AccountModel(service: service)

        let task = Task { await model.signInWithApple(idToken: "token", rawNonce: "nonce") }
        await Task.yield()
        task.cancel()
        await task.value

        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.session)
    }

    func testRepeatedProfileLoadFailureEmitsErrorEventAgain() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        let model = AccountModel(service: service)

        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }
        XCTAssertEqual(model.errorMessage, "Your profile couldn't be loaded. Try again.")
        let firstEvent = model.errorEvent

        await model.retryProfile()

        XCTAssertEqual(model.errorMessage, "Your profile couldn't be loaded. Try again.")
        XCTAssertEqual(model.errorEvent, firstEvent + 1)
    }

    func testSuspendedProfileDoesNotBlockNilAndReplacementIdentityOrApplyLateResults() async {
        for lateFailure in [false, true] {
            let a = UUID(), b = UUID()
            let service = AccountServiceMock()
            service.restoredSession = session(a)
            var suspended: CheckedContinuation<PlayerProfile, Error>?
            var completedA = false
            let bProfile = profile(userID: b, name: "Blair", setupCompleted: true)
            service.profileLoader = { userID in
                if userID == b { return bProfile }
                defer { completedA = true }
                return try await withCheckedThrowingContinuation { suspended = $0 }
            }
            var identities: [UUID?] = []
            let model = AccountModel(service: service, didChangeSession: { identities.append($0) })
            await model.start()
            await waitForAccountCondition { suspended != nil }
            XCTAssertEqual(model.session?.userID, a)
            XCTAssertTrue(model.isLoadingProfile)
            XCTAssertFalse(model.isWorking)

            service.emit(nil)
            await waitForAccountCondition { model.session == nil }
            XCTAssertNil(model.profile)
            XCTAssertEqual(model.displayNameDraft, "")
            service.emit(session(b))
            await waitForAccountCondition { model.profile == bProfile }
            let errorEvent = model.errorEvent
            if lateFailure { suspended?.resume(throwing: TestError.failed) }
            else { suspended?.resume(returning: profile(userID: a, name: "Alex", setupCompleted: true)) }
            await waitForAccountCondition { completedA }
            XCTAssertEqual(identities, [nil, a, nil, b])
            XCTAssertEqual(model.session?.userID, b)
            XCTAssertEqual(model.profile, bProfile)
            XCTAssertEqual(model.displayNameDraft, "Blair")
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.errorEvent, errorEvent)
            XCTAssertFalse(model.isLoadingProfile)
        }
    }

    func testSameUserRefreshKeepsPendingProfileAndReadyProfile() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.restoredSession = session(userID)
        service.refreshedSession = session(userID)
        var suspended: CheckedContinuation<PlayerProfile, Error>?
        service.profileLoader = { _ in
            try await withCheckedThrowingContinuation { suspended = $0 }
        }
        let model = AccountModel(service: service)
        await model.start()
        await waitForAccountCondition { suspended != nil }
        await model.refreshSession()
        XCTAssertEqual(service.loadedUserIDs, [userID])
        XCTAssertTrue(model.isLoadingProfile)
        suspended?.resume(returning: profile(userID: userID, name: "Alex", setupCompleted: true))
        await waitForAccountCondition { !model.isLoadingProfile }
        await model.refreshSession()
        XCTAssertEqual(service.loadedUserIDs, [userID])
        XCTAssertEqual(model.profile?.displayName, "Alex")
    }

    func testRetrySupersedesLateFailureWithinSameAccount() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.restoredSession = session(userID)
        var suspended: CheckedContinuation<PlayerProfile, Error>?
        var returned = false
        let ready = profile(userID: userID, name: "Alex", setupCompleted: true)
        service.profileLoader = { _ in
            if suspended != nil { return ready }
            defer { returned = true }
            return try await withCheckedThrowingContinuation { suspended = $0 }
        }
        let model = AccountModel(service: service)
        await model.start()
        await waitForAccountCondition { suspended != nil }
        await model.retryProfile()
        XCTAssertEqual(model.profile, ready)
        suspended?.resume(throwing: TestError.failed)
        await waitForAccountCondition { returned }
        XCTAssertEqual(model.profile, ready)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoadingProfile)
    }

    func testProfileFailureDoesNotPreventSignOutOrDeletion() async {
        for deleting in [false, true] {
            let service = AccountServiceMock()
            let userID = UUID()
            service.appleSession = session(userID)
            let model = AccountModel(service: service)
            await model.signInWithApple(idToken: "token", rawNonce: "nonce")
            await waitForAccountCondition { !model.isLoadingProfile }
            XCTAssertNotNil(model.errorMessage)
            XCTAssertFalse(model.isWorking)
            if deleting { await model.deleteAccount() } else { await model.signOut() }
            XCTAssertNil(model.session)
            XCTAssertNil(model.profile)
            XCTAssertEqual(deleting ? service.deleteCount : service.signOutCount, 1)
        }
    }

    /// Hosted accessibility hierarchy and screenshot evidence; OS VoiceOver is a separate gate.
    func testProfileFailedAccountRendersReachableLifecycleControls() async throws {
        let service = AccountServiceMock()
        service.restoredSession = session(UUID())
        let model = AccountModel(service: service)
        await model.start()
        await waitForAccountCondition { !model.isLoadingProfile }
        XCTAssertNotNil(model.errorMessage)
        try await GameplayContainmentHost.withHost(NavigationStack { AccountView(model: model) }, landscape: false) { hosted in
            let controls = accountAccessibilityElements(hosted.host.view)
            let elements = hosted.elements()
            let hierarchy = controls.map {
                "label=\($0.accessibilityLabel ?? "") id=\(accountAccessibilityIdentifier($0) ?? "") traits=\($0.accessibilityTraits.rawValue) frame=\($0.accessibilityFrame)"
            }.joined(separator: "\n")
            let hierarchyAttachment = XCTAttachment(string: hierarchy)
            hierarchyAttachment.name = "Account-profile-failed-public-accessibility-tree"
            hierarchyAttachment.lifetime = .keepAlways
            add(hierarchyAttachment)
            for (identifier, label) in [("account-sign-out", "Sign out"), ("account-delete", "Delete account")] {
                let control = try XCTUnwrap(controls.first { accountAccessibilityIdentifier($0) == identifier })
                XCTAssertTrue(control.accessibilityTraits.contains(.button))
                XCTAssertFalse(control.accessibilityTraits.contains(.notEnabled))
                let matches = elements.filter { $0.label == label && $0.button }
                XCTAssertEqual(matches.count, 1)
                let element = try XCTUnwrap(matches.first)
                XCTAssertTrue(hosted.isVisible(element), "\(label) must have its full frame inside the usable viewport and clipping ancestors")
            }
            let image = UIGraphicsImageRenderer(bounds: hosted.window.bounds).image { _ in
                hosted.window.drawHierarchy(in: hosted.window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Account-profile-failed-lifecycle-controls"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func profileReady(_ model: AccountModel) -> Bool {
        model.profile != nil && !model.isWorking && !model.needsProfileSetup
    }

    private func session(_ userID: UUID) -> AccountSession {
        AccountSession(userID: userID, expiresAt: Date().addingTimeInterval(3_600))
    }

    private func profile(
        userID: UUID,
        name: String,
        setupCompleted: Bool,
        avatarSeed: String = "avatar-seed"
    ) -> PlayerProfile {
        PlayerProfile(
            userID: userID,
            displayName: name,
            avatarSeed: avatarSeed,
            setupCompleted: setupCompleted,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}

@MainActor
private final class GuestStartupFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceGuestStartup-\(UUID().uuidString)")
    let pack: DailyWordPack
    let current = Date(timeIntervalSince1970: 20_697 * 86_400 + 100)
    var guestStore: DailyClassicStore { DailyClassicStore(directory: root.appending(path: "Guest")) }

    init() throws {
        pack = try DailyWordPack.load(from: JSONSerialization.data(withJSONObject: [
            "formatVersion": 1, "id": "daily-classic-en-US-v1", "scheduleVersion": 1,
            "locale": "en-US", "wordLength": 5, "epochDay": 20_696,
            "acceptedGuesses": ["adore", "civic", "stone"], "answers": ["stone", "adore"]
        ]))
        let old = Date(timeIntervalSince1970: 20_696 * 86_400 + 100)
        let puzzle = try DailyPuzzleSchedule.puzzle(at: old, in: pack)
        var game = DailyClassicGame(puzzle: puzzle, acceptedWords: Set(pack.acceptedGuesses))
        for letter in "civic" { game.type(letter) }
        XCTAssertNil(game.submit(at: old).error)
        try guestStore.save(game.progress)
        try guestStore.save(DailyClassicHistory())
        try Data("protected sibling".utf8).write(to: guestStore.directory.appending(path: "sibling.dat"))
    }

    func guestBytes() throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: guestStore.directory.path)
        return try Dictionary(uniqueKeysWithValues: names.map {
            ($0, try Data(contentsOf: guestStore.directory.appending(path: $0)))
        })
    }

    func coordinator(service: AccountServiceMock) throws -> DailyAccountCoordinator {
        try DailyAccountCoordinator(dailyPack: pack, tutorialPack: WordPack.load(bundle: .main),
            guestStore: guestStore, accountService: nil, accountModelService: service,
            dailyRemoteFactory: { _ in UnavailableDailyRemote() },
            accountStoreFactory: { AccountDailyClassicStore(rootDirectory: self.root, userID: $0) },
            liveStoreFactory: { LiveMatchRecoveryStore(rootDirectory: self.root, userID: $0) },
            now: { self.current })
    }
}

@MainActor
// Shared with DailySyncTests for faithful coordinator cold-restoration coverage.
final class AccountServiceMock: AccountServicing {
    private var currentState = AccountAuthState(session: nil)
    private var continuation: AsyncStream<AccountAuthState>.Continuation?

    var restoration: (@MainActor () async throws -> AccountSession?)?
    private(set) var restoreCallCount = 0
    var restoredSession: AccountSession?
    var refreshedSession: AccountSession?
    var appleSession: AccountSession?
    var loadedProfile: PlayerProfile?
    var profileLoader: (@MainActor (UUID) async throws -> PlayerProfile)?
    var updatedProfile: PlayerProfile?
    var deleteError: Error?
    var deletionRecovery: AccountAuthRecovery?
    var cleanupRetryCount = 0
    var signInDelay: Duration?
    var appleCredentials: (idToken: String, nonce: String)?
    var loadedUserIDs: [UUID] = []
    var profileUpdateCount = 0
    var signOutCount = 0
    var deleteCount = 0
    var lastProfileUpdate: (name: String, seed: String)?

    var authStateChanges: AsyncStream<AccountAuthState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(currentState)
        }
    }

    func restoreSession() async throws -> AccountSession? {
        restoreCallCount += 1
        let restored = if let restoration { try await restoration() } else { restoredSession }
        currentState = AccountAuthState(session: restored)
        return restored
    }
    func refreshSession() async throws -> AccountSession? {
        currentState = AccountAuthState(session: refreshedSession)
        return refreshedSession
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AccountSession {
        appleCredentials = (idToken, rawNonce)
        if let signInDelay { try await Task.sleep(for: signInDelay) }
        guard let appleSession else { throw TestError.failed }
        currentState = AccountAuthState(session: appleSession)
        return appleSession
    }

    func signInForLocalTesting(email: String, password: String) async throws -> AccountSession {
        guard let appleSession else { throw TestError.failed }
        currentState = AccountAuthState(session: appleSession)
        return appleSession
    }

    func loadProfile(userID: UUID) async throws -> PlayerProfile {
        loadedUserIDs.append(userID)
        if let profileLoader { return try await profileLoader(userID) }
        guard let loadedProfile else { throw TestError.failed }
        return loadedProfile
    }

    func updateProfile(
        userID: UUID,
        displayName: String,
        avatarSeed: String
    ) async throws -> PlayerProfile {
        profileUpdateCount += 1
        lastProfileUpdate = (displayName, avatarSeed)
        guard let updatedProfile else { throw TestError.failed }
        return updatedProfile
    }

    func signOut() async -> AccountSignOutOutcome {
        signOutCount += 1
        currentState = AccountAuthState(session: nil)
        return AccountSignOutOutcome(localRecovery: nil, remoteLogoutFailed: false)
    }

    func deleteAccount() async throws -> ConfirmedAccountDeletion {
        deleteCount += 1
        if let deleteError { throw deleteError }
        currentState = AccountAuthState(session: nil, recovery: deletionRecovery)
        return ConfirmedAccountDeletion(localRecovery: deletionRecovery)
    }
    func retrySignedOutCleanup() async -> AccountAuthState {
        cleanupRetryCount += 1
        currentState = AccountAuthState(session: nil)
        return currentState
    }

    func emitState(_ state: AccountAuthState) {
        currentState = state
        continuation?.yield(state)
    }

    func emit(_ session: AccountSession?) {
        emitState(AccountAuthState(session: session))
    }
}

private final class AccountLifecycleLiveStore: LiveMatchRecoveryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: LiveRecoveryState
    var rejectsLoads = false
    var rejectsClears = false
    var clearFailuresRemaining = 0

    var storedState: LiveRecoveryState {
        lock.withLock { state }
    }

    init(_ state: LiveRecoveryState) {
        self.state = state
    }

    func load() throws -> LiveRecoveryState {
        try lock.withLock {
            if rejectsLoads { throw TestError.failed }
            return state
        }
    }

    func save(_ state: LiveRecoveryState) throws {
        lock.withLock { self.state = state }
    }

    func clear() throws {
        try lock.withLock {
            if clearFailuresRemaining > 0 {
                clearFailuresRemaining -= 1
                throw TestError.failed
            }
            if rejectsClears { throw TestError.failed }
            state = LiveRecoveryState()
            rejectsLoads = false
        }
    }
}

private enum TestError: Error {
    case failed
}

final class DailySyncLifecycleTests: XCTestCase {
    func testFreshLifecyclePermitsPendingMarks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceLifecycleTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let userID = UUID()
        let store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
        let engine = DailySyncEngine(
            userID: userID,
            store: store,
            remote: UnavailableDailyRemote(),
            lifecycle: DailySyncLifecycle()
        )
        try store.save(DailyClassicProgress(
            puzzleID: "daily-classic-2026-08-31",
            puzzleNumber: 1,
            puzzleDay: 20_696,
            wordPackID: "daily-classic-en-US-v1",
            scheduleVersion: 1,
            hardModeEnabled: false,
            acceptedGuesses: [],
            draft: "",
            completion: nil
        ))

        try await engine.markProgressPending()
        try await engine.markResultPending("daily-classic-2026-08-31")

        let metadata = try store.loadSyncMetadata()
        XCTAssertTrue(metadata.pendingProgress)
        XCTAssertEqual(metadata.pendingResultPuzzleIDs, ["daily-classic-2026-08-31"])
    }

    func testInvalidatedLifecycleBlocksMarksWithoutRecreatingCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceLifecycleTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let userID = UUID()
        let store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
        let lifecycle = DailySyncLifecycle()
        let engine = DailySyncEngine(
            userID: userID,
            store: store,
            remote: UnavailableDailyRemote(),
            lifecycle: lifecycle
        )
        lifecycle.invalidate()
        XCTAssertTrue(lifecycle.isInvalidated)
        lifecycle.invalidate()

        await XCTAssertThrowsCancellation(try await engine.markProgressPending())
        await XCTAssertThrowsCancellation(try await engine.markResultPending("puzzle"))
        await XCTAssertThrowsCancellation(try await engine.markAllLocalDataPending())

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testPerformRunsWorkExactlyOnceWhileValid() throws {
        let lifecycle = DailySyncLifecycle()
        var runs = 0
        try lifecycle.performThrowingIfValid { runs += 1 }
        XCTAssertEqual(runs, 1)
        XCTAssertFalse(lifecycle.isInvalidated)
    }

    func testPerformNeverRunsWorkAfterInvalidation() throws {
        let lifecycle = DailySyncLifecycle()
        lifecycle.invalidate()
        var runs = 0
        XCTAssertThrowsError(try lifecycle.performThrowingIfValid { runs += 1 }) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(runs, 0)
    }

    func testPerformPropagatesWorkErrorsAndReleasesTheLock() throws {
        struct Boom: Error {}
        let lifecycle = DailySyncLifecycle()
        XCTAssertThrowsError(try lifecycle.performThrowingIfValid { throw Boom() }) { error in
            XCTAssertTrue(error is Boom)
        }
        var runs = 0
        try lifecycle.performThrowingIfValid { runs += 1 }
        XCTAssertEqual(runs, 1)
        XCTAssertFalse(lifecycle.isInvalidated)
    }

    func testConcurrentMutationsAndInvalidationLoseNothing() async {
        let lifecycle = DailySyncLifecycle()
        let completed = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    do {
                        try lifecycle.performThrowingIfValid {}
                        return true
                    } catch is CancellationError {
                        return false
                    } catch {
                        XCTFail("Unexpected error \(error)")
                        return false
                    }
                }
            }
            lifecycle.invalidate()
            var count = 0
            for await ran in group {
                if ran { count += 1 }
            }
            return count
        }
        XCTAssertGreaterThanOrEqual(completed, 0)
        XCTAssertLessThanOrEqual(completed, 64)
        var lateRuns = 0
        do {
            try lifecycle.performThrowingIfValid { lateRuns += 1 }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertEqual(lateRuns, 0)
    }

    func testDeletedCacheReadsAsEmptyWithoutRecreation() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceLifecycleTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let userID = UUID()
        let store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
        var history = DailyClassicHistory()
        XCTAssertTrue(history.record(DailyCompletedResult(
            puzzleID: "daily-classic-2026-08-31",
            puzzleNumber: 1,
            puzzleDay: 20_696,
            wordPackID: "daily-classic-en-US-v1",
            scheduleVersion: 1,
            guesses: [DailyGuess(
                word: "stone",
                feedback: Array(repeating: .correct, count: 5),
                acceptedAt: Date(timeIntervalSince1970: 1_788_134_401)
            )],
            outcome: .solved,
            guessCount: 1,
            completedAt: Date(timeIntervalSince1970: 1_788_134_500)
        )))
        try store.save(history)

        try store.deleteAccountCache()

        XCTAssertTrue(try store.loadHistory().completedResults.isEmpty)
        XCTAssertNil(try store.loadProgress())
        XCTAssertEqual(try store.loadSyncMetadata(), DailySyncMetadata())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    private func XCTAssertThrowsCancellation(
        _ expression: @autoclosure () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected CancellationError", file: file, line: line)
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }
}

private actor UnavailableDailyRemote: DailySyncRemote {
    func pull() async throws -> DailyCloudSnapshot {
        throw DailySyncRemoteError.unavailable
    }

    func pushProgress(_ progress: DailyProgressUploadDTO) async throws -> DailyProgressPushOutcome {
        throw DailySyncRemoteError.unavailable
    }

    func importResult(_ result: DailyImportedResultUploadDTO) async throws -> DailyResultImportOutcome {
        throw DailySyncRemoteError.unavailable
    }
}

@MainActor
private func waitForAccountCondition(
    file: StaticString = #filePath, line: UInt = #line,
    _ condition: @MainActor () async -> Bool
) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("Timed out waiting for account state", file: file, line: line)
}

@MainActor
private func accountAccessibilityIdentifier(_ object: NSObject) -> String? {
    // SwiftUI's synthesized AX nodes can expose the public getter without
    // declaring Objective-C protocol conformance on the proxy class.
    guard object.responds(to: #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)) else { return nil }
    return object.value(forKey: "accessibilityIdentifier") as? String
}

@MainActor
private func accountAccessibilityElements(_ root: NSObject) -> [NSObject] {
    var visited = Set<ObjectIdentifier>()
    func collect(_ object: NSObject) -> [NSObject] {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
        var elements = [object]
        if let children = object.accessibilityElements {
            for child in children {
                if let child = child as? NSObject { elements += collect(child) }
            }
        }
        let count = object.accessibilityElementCount()
        if count > 0, count != NSNotFound {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject {
                    elements += collect(child)
                }
            }
        }
        if let view = object as? UIView { elements += view.subviews.flatMap(collect) }
        return elements
    }
    return collect(root)
}

private actor CoordinatorDailyRemote: DailySyncRemote {
    let userID: UUID
    private var results: [String: DailyImportedResultDTO] = [:]
    private(set) var canonicalProgress: DailyProgressDTO?
    private(set) var progressUploads: [DailyProgressUploadDTO] = []
    private var shouldSuspend = false
    private var shouldFail = false
    private var suspendedPull: CheckedContinuation<Void, Never>?
    private(set) var releasedPullReturned = false
    var isSuspended: Bool { suspendedPull != nil }

    init(userID: UUID, result: DailyCompletedResult? = nil) {
        self.userID = userID
        if let result { results[result.puzzleID] = Self.dto(DailyImportedResultUploadDTO(result), userID: userID) }
    }

    func suspendNextPull() { shouldSuspend = true }
    func failNextPull() { shouldFail = true }
    func addResult(_ result: DailyCompletedResult) {
        results[result.puzzleID] = Self.dto(DailyImportedResultUploadDTO(result), userID: userID)
    }
    func releasePull() {
        suspendedPull?.resume()
        suspendedPull = nil
    }
    func pull() async throws -> DailyCloudSnapshot {
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { suspendedPull = $0 }
            releasedPullReturned = true
        }
        if shouldFail {
            shouldFail = false
            throw DailySyncRemoteError.unavailable
        }
        return DailyCloudSnapshot(progress: canonicalProgress, importedResults: results.values.sorted { $0.puzzleID < $1.puzzleID })
    }
    func pushProgress(_ progress: DailyProgressUploadDTO) async throws -> DailyProgressPushOutcome {
        progressUploads.append(progress)
        let current = canonicalProgress.flatMap { $0.puzzleID == progress.puzzleID ? $0 : nil }
        if let current {
            guard progress.expectedRevision == current.revision else { return .serverAhead(current) }
            guard progress.guesses.starts(with: current.guesses),
                  current.guesses.isEmpty || progress.hardModeEnabled == current.hardModeEnabled else {
                return .conflict(.progress(current))
            }
        }
        let stored = DailyProgressDTO(
            userID: userID, puzzleID: progress.puzzleID, puzzleNumber: progress.puzzleNumber,
            puzzleDay: progress.puzzleDay, wordPackID: progress.wordPackID, scheduleVersion: progress.scheduleVersion,
            hardModeEnabled: progress.hardModeEnabled, guesses: progress.guesses,
            revision: (current?.revision ?? 0) + 1, serverUpdatedAt: .now
        )
        canonicalProgress = stored
        return .stored(stored)
    }
    func importResult(_ result: DailyImportedResultUploadDTO) async throws -> DailyResultImportOutcome {
        let stored = Self.dto(result, userID: userID)
        results[stored.puzzleID] = stored
        return .stored(stored)
    }
    private static func dto(_ result: DailyImportedResultUploadDTO, userID: UUID) -> DailyImportedResultDTO {
        DailyImportedResultDTO(
            userID: userID, puzzleID: result.puzzleID, puzzleNumber: result.puzzleNumber,
            puzzleDay: result.puzzleDay, wordPackID: result.wordPackID, scheduleVersion: result.scheduleVersion,
            hardModeEnabled: result.hardModeEnabled, guesses: result.guesses, outcome: result.outcome,
            guessCount: result.guessCount, clientCompletedAt: result.clientCompletedAt, serverImportedAt: .now
        )
    }
}

@MainActor
private func accountLifecycleTransport(_ userID: UUID) -> LiveAccountTransport {
    LiveAccountTransport(userID: userID,
        service: SupabaseLiveMatchService(invoke: { _, _ in throw LiveMatchServiceError.unavailable }),
        realtime: nil, refresh: { _ in false }, isValid: { true })
}

@MainActor
extension DailyAccountCoordinatorTests {
    func testDeletedDailyRetryOnlyRemovesCapturedAccountWhileNewAccountStaysActive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DeletedDailyRetry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let deleted = UUID(), other = UUID(), service = AccountServiceMock()
        var failDeletedFactory = false
        service.appleSession = AccountSession(userID: deleted, expiresAt: Date().addingTimeInterval(3600))
        service.loadedProfile = PlayerProfile(userID: deleted, displayName: "Fixture", avatarSeed: "fixture", setupCompleted: true, createdAt: Date(), updatedAt: Date())
        let guest = DailyClassicStore(directory: root.appending(path: "Guest"))
        let coordinator = try DailyAccountCoordinator(dailyPack: DailyWordPack.load(bundle: .main),
            tutorialPack: WordPack.load(bundle: .main), guestStore: guest, accountService: nil,
            accountModelService: service, dailyRemoteFactory: { _ in UnavailableDailyRemote() },
            accountStoreFactory: { userID in
                if userID == deleted && failDeletedFactory { throw TestError.failed }
                return AccountDailyClassicStore(rootDirectory: root, userID: userID)
            }, liveTransportFactory: accountLifecycleTransport,
            liveStoreFactory: { _ in AccountLifecycleLiveStore(LiveRecoveryState()) })
        coordinator.daily.typeLetter("G")
        let guestProgress = try guest.loadProgress()
        await coordinator.account.signInWithApple(idToken: "synthetic", rawNonce: "synthetic")
        let deletedDirectory = AccountDailyClassicStore(rootDirectory: root, userID: deleted).directory
        XCTAssertTrue(FileManager.default.fileExists(atPath: deletedDirectory.path))
        failDeletedFactory = true
        await coordinator.account.deleteAccount()
        XCTAssertTrue(coordinator.account.canRetryDeletedDailyData)
        XCTAssertEqual(coordinator.account.pendingDeletedDailyUserIDs, [deleted])
        XCTAssertTrue(FileManager.default.fileExists(atPath: deletedDirectory.path))
        service.appleSession = AccountSession(userID: other, expiresAt: Date().addingTimeInterval(3600))
        service.loadedProfile = PlayerProfile(userID: other, displayName: "Other", avatarSeed: "other", setupCompleted: true, createdAt: Date(), updatedAt: Date())
        await coordinator.account.signInWithApple(idToken: "synthetic", rawNonce: "synthetic")
        let retained = coordinator.daily
        retained.typeLetter("B")
        let otherStore = AccountDailyClassicStore(rootDirectory: root, userID: other)
        let otherProgress = try otherStore.loadProgress()
        await coordinator.account.retryDeletedDailyData()
        XCTAssertTrue(coordinator.account.canRetryDeletedDailyData)
        failDeletedFactory = false
        await coordinator.account.retryDeletedDailyData()
        XCTAssertFalse(coordinator.account.canRetryDeletedDailyData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedDirectory.path))
        XCTAssertEqual(coordinator.account.session?.userID, other)
        XCTAssertTrue(coordinator.daily === retained)
        XCTAssertEqual(try otherStore.loadProgress(), otherProgress)
        XCTAssertEqual(try guest.loadProgress(), guestProgress)
        XCTAssertEqual(service.deleteCount, 1)
    }
}

@MainActor
extension AccountModelTests {
    func testSignedOutRecoveryRendersEnabledVisibleControls() async throws {
        for action in [AccountAuthRecovery.Action.restore, .cleanup] {
            let service = AccountServiceMock(), model = AccountModel(service: service)
            await model.start()
            service.emitState(AccountAuthState(session: nil, recovery: .init(action: action, storageIssue: nil)))
            await waitForAccountCondition { model.authRecovery?.action == action }
            try await GameplayContainmentHost.withHost(NavigationStack { AccountView(model: model) }, landscape: false) { hosted in
                let labels = action == .restore ? ["Retry account restore", "Sign out on this device"] : ["Retry account cleanup"]
                let controls = accountAccessibilityElements(hosted.host.view)
                let elements = hosted.elements()
                for label in labels {
                    let control = try XCTUnwrap(controls.first { $0.accessibilityLabel == label })
                    XCTAssertTrue(control.accessibilityTraits.contains(.button))
                    XCTAssertFalse(control.accessibilityTraits.contains(.notEnabled))
                    let element = try XCTUnwrap(elements.first { $0.label == label && $0.button })
                    XCTAssertTrue(hosted.isVisible(element))
                }
            }
        }
    }
}

@MainActor
extension DailyAccountCoordinatorTests {
    func testIndependentDeletionCleanupFailuresAndResolvedLiveNoticeUseCurrentOwner() async throws {
        for failures in 1...7 {
            let authFailed = failures & 1 != 0, dailyFailed = failures & 2 != 0, liveFailed = failures & 4 != 0
            let root = FileManager.default.temporaryDirectory.appending(path: "DeletionFailures-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let user = UUID(), other = UUID(), service = AccountServiceMock()
            service.appleSession = AccountSession(userID: user, expiresAt: Date().addingTimeInterval(3600))
            service.loadedProfile = PlayerProfile(userID: user, displayName: "Fixture", avatarSeed: "fixture", setupCompleted: true, createdAt: Date(), updatedAt: Date())
            if authFailed { service.deletionRecovery = .init(action: .cleanup, storageIssue: nil) }
            var rejectsDeletedDaily = false
            let guest = DailyClassicStore(directory: root.appending(path: "Guest"))
            let live = AccountLifecycleLiveStore(LiveRecoveryState(pendingIntent: .create(requestID: UUID())))
            live.rejectsLoads = true
            let otherStore = AccountDailyClassicStore(rootDirectory: root, userID: other)
            let otherModel = try DailyClassicModel(pack: DailyWordPack.load(bundle: .main), store: otherStore)
            otherModel.typeLetter("B")
            let otherProgress = try otherStore.loadProgress()
            let coordinator = try DailyAccountCoordinator(dailyPack: DailyWordPack.load(bundle: .main),
                tutorialPack: WordPack.load(bundle: .main), guestStore: guest, accountService: nil,
                accountModelService: service, dailyRemoteFactory: { _ in UnavailableDailyRemote() },
                accountStoreFactory: { id in
                    if id == user && rejectsDeletedDaily { throw TestError.failed }
                    return AccountDailyClassicStore(rootDirectory: root, userID: id)
                }, liveTransportFactory: accountLifecycleTransport, liveStoreFactory: { _ in live })
            coordinator.daily.typeLetter("G")
            let guestProgress = try guest.loadProgress()
            await coordinator.account.signInWithApple(idToken: "synthetic", rawNonce: "synthetic")
            let deletedDirectory = AccountDailyClassicStore(rootDirectory: root, userID: user).directory
            rejectsDeletedDaily = dailyFailed
            live.rejectsClears = liveFailed
            await coordinator.account.deleteAccount()
            XCTAssertEqual(service.deleteCount, 1)
            XCTAssertNil(coordinator.account.session)
            XCTAssertEqual(coordinator.account.authRecovery != nil, authFailed)
            XCTAssertEqual(coordinator.account.canRetryDeletedDailyData, dailyFailed)
            XCTAssertEqual(FileManager.default.fileExists(atPath: deletedDirectory.path), dailyFailed)
            XCTAssertEqual(coordinator.live.hasPendingAccountCleanup(for: user), liveFailed)
            XCTAssertEqual(coordinator.account.errorMessage?.contains("Retry Daily cleanup") == true, dailyFailed)
            XCTAssertEqual(coordinator.account.errorMessage?.contains("Open Live Race") == true, liveFailed)
            if liveFailed {
                live.rejectsClears = false
                coordinator.live.discardRecovery()
                XCTAssertFalse(coordinator.live.hasPendingAccountCleanup(for: user))
            }
            if dailyFailed {
                await coordinator.account.retryDeletedDailyData() // Still fails; resolved Live must not be advertised.
                XCTAssertTrue(coordinator.account.errorMessage?.contains("Retry Daily cleanup") == true)
                XCTAssertFalse(coordinator.account.errorMessage?.contains("Open Live Race") == true)
            }
            if authFailed { await coordinator.account.retryAuthRecovery() }
            rejectsDeletedDaily = false
            if dailyFailed { await coordinator.account.retryDeletedDailyData() }
            XCTAssertNil(coordinator.account.authRecovery)
            XCTAssertFalse(coordinator.account.canRetryDeletedDailyData)
            XCTAssertNil(coordinator.account.errorMessage)
            XCTAssertEqual(try guest.loadProgress(), guestProgress)
            XCTAssertEqual(try otherStore.loadProgress(), otherProgress)
            XCTAssertEqual(service.deleteCount, 1)
        }
    }
}

@MainActor
extension AccountModelTests {
    func testDeletedDailyRetryRendersEnabledVisibleActionAndUsesCapturedUser() async throws {
        let user = UUID(), service = AccountServiceMock()
        service.appleSession = session(user)
        service.loadedProfile = profile(userID: user, name: "Fixture", setupCompleted: true)
        var retried: [UUID] = []
        let model = AccountModel(service: service, didDeleteAccount: { id in
            throw AccountLocalDeletionFailure(dailyCacheUserID: id, liveRecoveryPending: false)
        }, retryDeletedDailyCleanup: { retried.append($0) })
        await model.signInWithApple(idToken: "synthetic", rawNonce: "synthetic")
        await model.deleteAccount()
        try await GameplayContainmentHost.withHost(NavigationStack { AccountView(model: model) }, landscape: false) { hosted in
            let controls = accountAccessibilityElements(hosted.host.view)
            let action = try XCTUnwrap(controls.first { $0.accessibilityLabel == "Retry Daily cleanup" })
            XCTAssertTrue(action.accessibilityTraits.contains(.button))
            XCTAssertFalse(action.accessibilityTraits.contains(.notEnabled))
            let element = try XCTUnwrap(hosted.elements().first { $0.label == "Retry Daily cleanup" && $0.button })
            XCTAssertTrue(hosted.isVisible(element))
            await model.retryDeletedDailyData()
            XCTAssertEqual(retried, [user])
            XCTAssertFalse(model.canRetryDeletedDailyData)
        }
    }
}
