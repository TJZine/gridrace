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

    func testGeneratedProfileNeedsInitialSetup() {
        let generated = profile(name: "Player 12abef")
        XCTAssertTrue(generated.needsSetup)
        XCTAssertFalse(profile(name: "Player One").needsSetup)
    }

    private func profile(name: String) -> PlayerProfile {
        PlayerProfile(
            userID: UUID(),
            displayName: name,
            avatarSeed: "seed",
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
                                                     createdAt: .distantPast, updatedAt: .distantPast)
                let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
                    urlString: "http://127.0.0.1:54321", publishableKey: "local-test-key"))
                let coordinator = try DailyAccountCoordinator(
                    dailyPack: DailyWordPack.load(bundle: .main), tutorialPack: WordPack.load(bundle: .main),
                    guestStore: DailyClassicStore(directory: root.appending(path: "Guest")),
                    accountService: SupabaseAccountService(configuration: configuration), accountModelService: account,
                    accountStoreFactory: { AccountDailyClassicStore(rootDirectory: root, userID: $0) },
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
            return PlayerProfile(userID: b, displayName: "Blair", avatarSeed: "b", createdAt: .distantPast, updatedAt: .distantPast)
        }
        let remotes = [a: CoordinatorDailyRemote(userID: a), b: CoordinatorDailyRemote(userID: b)]
        let coordinator = try DailyAccountCoordinator(
            dailyPack: DailyWordPack.load(bundle: .main), tutorialPack: WordPack.load(bundle: .main),
            guestStore: fixture.guestStore, accountService: nil, accountModelService: service,
            dailyRemoteFactory: { remotes[$0]! },
            accountStoreFactory: { AccountDailyClassicStore(rootDirectory: fixture.root, userID: $0) },
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
        coordinator.resolveFirstConflict(useCloud: true)
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
            liveStoreFactory: { _ in AccountLifecycleLiveStore(LiveRecoveryState()) }
        )
    }

    private func importResult(priorWords: [String] = []) throws -> DailyCompletedResult {
        let pack = try DailyWordPack.load(bundle: .main)
        let date = Date(timeIntervalSince1970: TimeInterval(pack.epochDay * 86_400))
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
            accountStoreFactory: { AccountDailyClassicStore(rootDirectory: root, userID: $0) },
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
    func testSessionRestorationLoadsOnlyTheOwnersProfile() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.restoredSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex")
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
        service.loadedProfile = profile(userID: userID, name: "Taylor")
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
        service.loadedProfile = profile(userID: userID, name: "Alex")
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
        service.loadedProfile = profile(userID: userID, name: "Alex")
        let model = AccountModel(service: service)
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")
        await waitForAccountCondition { !model.isLoadingProfile }
        let oldSeed = model.avatarSeedDraft
        model.displayNameDraft = "Sam-2"
        model.randomizeAvatar()
        service.updatedProfile = profile(
            userID: userID,
            name: "Sam-2",
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
        service.loadedProfile = profile(userID: userID, name: "Alex")
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
        service.loadedProfile = profile(userID: userID, name: "Alex")
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
        service.loadedProfile = profile(userID: userID, name: "Alex")
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
            let bProfile = profile(userID: b, name: "Blair")
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
            else { suspended?.resume(returning: profile(userID: a, name: "Alex")) }
            await waitForAccountCondition { completedA }
            XCTAssertEqual(identities, [a, nil, b])
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
        suspended?.resume(returning: profile(userID: userID, name: "Alex"))
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
        let ready = profile(userID: userID, name: "Alex")
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
        let hosted = try await GameplayContainmentHost(NavigationStack { AccountView(model: model) }, landscape: false)
        defer { hosted.close() }
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

    private func session(_ userID: UUID) -> AccountSession {
        AccountSession(userID: userID, expiresAt: Date().addingTimeInterval(3_600))
    }

    private func profile(
        userID: UUID,
        name: String,
        avatarSeed: String = "avatar-seed"
    ) -> PlayerProfile {
        PlayerProfile(
            userID: userID,
            displayName: name,
            avatarSeed: avatarSeed,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}

@MainActor
private final class AccountServiceMock: AccountServicing {
    private let stream: AsyncStream<AccountSession?>
    private let continuation: AsyncStream<AccountSession?>.Continuation

    var restoredSession: AccountSession?
    var refreshedSession: AccountSession?
    var appleSession: AccountSession?
    var loadedProfile: PlayerProfile?
    var profileLoader: (@MainActor (UUID) async throws -> PlayerProfile)?
    var updatedProfile: PlayerProfile?
    var deleteError: Error?
    var signInDelay: Duration?
    var appleCredentials: (idToken: String, nonce: String)?
    var loadedUserIDs: [UUID] = []
    var profileUpdateCount = 0
    var signOutCount = 0
    var deleteCount = 0
    var lastProfileUpdate: (name: String, seed: String)?

    init() {
        let pair = AsyncStream<AccountSession?>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    var authStateChanges: AsyncStream<AccountSession?> { stream }

    func restoreSession() async throws -> AccountSession? { restoredSession }
    func refreshSession() async throws -> AccountSession? { refreshedSession }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AccountSession {
        appleCredentials = (idToken, rawNonce)
        if let signInDelay { try await Task.sleep(for: signInDelay) }
        guard let appleSession else { throw TestError.failed }
        return appleSession
    }

    func signInForLocalTesting(email: String, password: String) async throws -> AccountSession {
        guard let appleSession else { throw TestError.failed }
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

    func signOut() async throws { signOutCount += 1 }

    func deleteAccount() async throws {
        deleteCount += 1
        if let deleteError { throw deleteError }
    }

    func emit(_ session: AccountSession?) {
        continuation.yield(session)
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
            guard progress.guesses.starts(with: current.guesses), progress.hardModeEnabled == current.hardModeEnabled else {
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
