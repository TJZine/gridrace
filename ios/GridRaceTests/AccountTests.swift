import Foundation
import XCTest
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
        var isolatedSession = false
        let model = AccountModel(
            service: service,
            didChangeSession: { if $0 == nil { isolatedSession = true } },
            didDeleteAccount: { _ in throw TestError.failed }
        )
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")

        await model.deleteAccount()

        XCTAssertNil(model.session)
        XCTAssertTrue(isolatedSession)
        XCTAssertTrue(model.errorMessage?.contains("local data") == true)
    }

    func testSignOutCallbackReceivesAccountBeforeStateIsCleared() async {
        let userID = UUID()
        let service = AccountServiceMock()
        service.appleSession = session(userID)
        service.loadedProfile = profile(userID: userID, name: "Alex")
        var signedOutUserID: UUID?
        let model = AccountModel(service: service, didSignOut: { signedOutUserID = $0 })
        await model.signInWithApple(idToken: "token", rawNonce: "nonce")

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
        XCTAssertEqual(model.errorMessage, "Your profile couldn't be loaded. Try again.")
        let firstEvent = model.errorEvent

        await model.retryProfile()

        XCTAssertEqual(model.errorMessage, "Your profile couldn't be loaded. Try again.")
        XCTAssertEqual(model.errorEvent, firstEvent + 1)
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
    var updatedProfile: PlayerProfile?
    var deleteError: Error?
    var signInDelay: Duration?
    var appleCredentials: (idToken: String, nonce: String)?
    var loadedUserIDs: [UUID] = []
    var profileUpdateCount = 0
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

    func signOut() async throws {}

    func deleteAccount() async throws {
        if let deleteError { throw deleteError }
    }

    func emit(_ session: AccountSession?) {
        continuation.yield(session)
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
