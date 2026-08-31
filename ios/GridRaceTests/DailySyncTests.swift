import Foundation
import Supabase
import XCTest
@testable import GridRace

final class DailySyncTests: XCTestCase {
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherUserID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let day = 20_696

    func testWireDTOsUseGuessesAndKeepOwnerAndServerTimestampsResponseOnly() throws {
        let progress = progress(words: ["civic"], draft: "ST")
        let uploadObject = try object(DailyProgressUploadDTO(progress: progress, expectedRevision: 4))
        XCTAssertNotNil(uploadObject["guesses"])
        XCTAssertNil(uploadObject["accepted_guesses"])
        XCTAssertNil(uploadObject["draft"])
        XCTAssertNil(uploadObject["completion"])
        XCTAssertNil(uploadObject["user_id"])
        XCTAssertNil(uploadObject["server_updated_at"])
        XCTAssertEqual(uploadObject["expected_revision"] as? Int, 4)

        let selectedProgress = progressDTO(progress, userID: userID, revision: 5)
        let selectedProgressObject = try object(selectedProgress)
        XCTAssertEqual(selectedProgressObject["user_id"] as? String, userID.uuidString)
        XCTAssertNotNil(selectedProgressObject["server_updated_at"])
        XCTAssertNotNil(selectedProgressObject["guesses"])

        let completed = result(words: ["civic", "stone"])
        let resultUploadObject = try object(DailyImportedResultUploadDTO(completed))
        XCTAssertNotNil(resultUploadObject["client_completed_at"])
        XCTAssertNil(resultUploadObject["server_imported_at"])
        XCTAssertNil(resultUploadObject["user_id"])

        let selectedResultObject = try object(resultDTO(completed, userID: userID))
        XCTAssertEqual(selectedResultObject["user_id"] as? String, userID.uuidString)
        XCTAssertNotNil(selectedResultObject["client_completed_at"])
        XCTAssertNotNil(selectedResultObject["server_imported_at"])
    }

    func testSupabaseProgressParametersMatchDatabaseJSONContract() throws {
        let upload = DailyProgressUploadDTO(
            progress: progress(words: ["civic"]),
            expectedRevision: nil
        )
        let data = try PostgrestClient.Configuration.jsonEncoder.encode(
            ProgressParameters(upload)
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(Set(payload.keys), [
            "p_puzzle_id", "p_puzzle_number", "p_puzzle_day", "p_word_pack_id",
            "p_schedule_version", "p_hard_mode_enabled", "p_guesses"
        ])
        let guesses = try XCTUnwrap(payload["p_guesses"] as? [[String: Any]])
        let guess = try XCTUnwrap(guesses.first)
        XCTAssertEqual(Set(guess.keys), ["word", "feedback", "accepted_at"])
        XCTAssertEqual(guess["accepted_at"] as? String, "2026-08-31T00:00:01.000Z")
        XCTAssertEqual(guess["feedback"] as? [Int], [0, 0, 0, 0, 0])
    }

    func testDatabaseMillisecondTimestampsDoNotCreateFalseConflicts() throws {
        let precise = Date(timeIntervalSince1970: 1_788_000_000.987_654)
        let localGuess = DailyGuess(
            word: "stone",
            feedback: Array(repeating: .correct, count: 5),
            acceptedAt: precise
        )
        let local = DailyCompletedResult(
            puzzleID: puzzleID(day: day),
            puzzleNumber: 1,
            puzzleDay: day,
            wordPackID: "test-v1",
            scheduleVersion: 1,
            guesses: [localGuess],
            outcome: .solved,
            guessCount: 1,
            completedAt: precise.addingTimeInterval(0.000_9)
        )
        var history = DailyClassicHistory()
        XCTAssertTrue(history.record(local))
        let cloud = DailyImportedResultDTO(
            userID: userID,
            puzzleID: local.puzzleID,
            puzzleNumber: local.puzzleNumber,
            puzzleDay: local.puzzleDay,
            wordPackID: local.wordPackID,
            scheduleVersion: local.scheduleVersion,
            hardModeEnabled: local.hardModeEnabled,
            guesses: local.guesses.map(DailyGuessDTO.init),
            outcome: local.outcome,
            guessCount: local.guessCount,
            clientCompletedAt: DailyImportedResultUploadDTO(local).clientCompletedAt,
            serverImportedAt: fixedDate(600)
        )

        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: nil,
            localHistory: history,
            cloud: DailyCloudSnapshot(progress: nil, importedResults: [cloud])
        )

        XCTAssertTrue(reconciliation.conflicts.isEmpty)
        XCTAssertEqual(reconciliation.history.completedResults, [local])
    }

    func testAccountStoresAreUUIDScopedAndDeletionLeavesGuestAndOtherAccountUntouched() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root)
        let first = AccountDailyClassicStore(rootDirectory: root, userID: userID)
        let second = AccountDailyClassicStore(rootDirectory: root, userID: otherUserID)
        let guestResult = result(words: ["stone"])
        let firstResult = result(day: day + 1, words: ["stone"])
        let secondResult = result(day: day + 2, words: ["stone"])
        try guest.save(history(guestResult))
        try first.save(history(firstResult))
        try second.save(history(secondResult))

        XCTAssertEqual(first.directory.lastPathComponent, userID.uuidString.lowercased())
        XCTAssertEqual(second.directory.lastPathComponent, otherUserID.uuidString.lowercased())
        XCTAssertNotEqual(first.directory, second.directory)

        try first.deleteAccountCache()

        XCTAssertTrue(try first.loadHistory().completedResults.isEmpty)
        XCTAssertEqual(try second.loadHistory().completedResults, [secondResult])
        XCTAssertEqual(try guest.loadHistory().completedResults, [guestResult])
    }

    func testCloudOnlyHistoryRestoresAndDerivesStatisticsWithoutReupload() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let completed = result(words: ["civic", "stone"])
        let remote = TestDailyRemote(userID: userID, results: [completed.puzzleID: resultDTO(completed, userID: userID)])
        let engine = fixture.engine(remote: remote)

        let status = try await engine.synchronize()

        XCTAssertEqual(status, .synced(fixture.syncDate))
        let restored = try fixture.store.loadHistory()
        XCTAssertEqual(restored.completedResults, [completed])
        XCTAssertEqual(restored.statistics.gamesPlayed, 1)
        XCTAssertEqual(restored.statistics.gamesWon, 1)
        let importCalls = await remote.importCallCount()
        XCTAssertEqual(importCalls, 0, "Pull-only records must not become pending uploads")
    }

    func testAcceptedRowsRestoreAcrossDevicesWhileDraftStaysDeviceLocal() async throws {
        let first = SyncFixture(userID: userID)
        let second = SyncFixture(userID: userID)
        defer { first.remove(); second.remove() }
        let remote = TestDailyRemote(userID: userID)
        let firstProgress = progress(words: ["civic"], draft: "ST")
        try first.store.save(firstProgress)
        try await first.engine(remote: remote).markProgressPending()

        let firstStatus = try await first.engine(remote: remote).synchronize()
        XCTAssertEqual(firstStatus, .synced(first.syncDate))

        let secondDraft = progress(words: [], draft: "CR")
        try second.store.save(secondDraft)
        let secondStatus = try await second.engine(remote: remote).synchronize()

        XCTAssertEqual(secondStatus, .synced(second.syncDate))
        let restored = try XCTUnwrap(second.store.loadProgress())
        XCTAssertEqual(restored.acceptedGuesses, firstProgress.acceptedGuesses)
        XCTAssertEqual(restored.draft, "CR")
        let remoteProgress = await remote.currentProgress()
        let uploaded = try XCTUnwrap(remoteProgress)
        XCTAssertEqual(uploaded.guesses.map(\.domain), firstProgress.acceptedGuesses)
    }

    func testExactDuplicateResultImportSucceedsWithoutDuplicateStatistics() async throws {
        let first = SyncFixture(userID: userID)
        let second = SyncFixture(userID: userID)
        defer { first.remove(); second.remove() }
        let completed = result(words: ["stone"])
        let remote = TestDailyRemote(userID: userID)

        try first.store.save(history(completed))
        let firstEngine = first.engine(remote: remote)
        try await firstEngine.markResultPending(completed.puzzleID)
        let firstStatus = try await firstEngine.synchronize()
        XCTAssertEqual(firstStatus, .synced(first.syncDate))

        try second.store.save(history(completed))
        let secondEngine = second.engine(remote: remote)
        try await secondEngine.markResultPending(completed.puzzleID)
        let secondStatus = try await secondEngine.synchronize()
        XCTAssertEqual(secondStatus, .synced(second.syncDate))

        XCTAssertEqual(try second.store.loadHistory().statistics.gamesPlayed, 1)
        let storedResults = await remote.storedResultCount()
        let importCalls = await remote.importCallCount()
        XCTAssertEqual(storedResults, 1)
        XCTAssertEqual(importCalls, 2)
    }

    func testOfflineFailureKeepsPendingSnapshotAndRetryClearsIt() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let completed = result(words: ["stone"])
        try fixture.store.save(history(completed))
        let remote = TestDailyRemote(userID: userID)
        await remote.failNextPull()
        let engine = fixture.engine(remote: remote)
        try await engine.markResultPending(completed.puzzleID)

        let failedStatus = try await engine.synchronize()
        let pendingStatus = try await engine.status()
        XCTAssertEqual(failedStatus, .failed(.unavailable))
        XCTAssertEqual(pendingStatus, .pending)

        let retryStatus = try await engine.synchronize()
        XCTAssertEqual(retryStatus, .synced(fixture.syncDate))
        XCTAssertFalse(try fixture.store.loadSyncMetadata().hasPendingChanges)
        let storedResults = await remote.storedResultCount()
        XCTAssertEqual(storedResults, 1)
    }

    func testDivergentProgressProducesConflictAndExplicitCloudChoice() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = progress(words: ["crane"], draft: "A")
        let cloud = progress(words: ["civic"])
        try fixture.store.save(local)
        let remote = TestDailyRemote(userID: userID, progress: progressDTO(cloud, userID: userID))
        let engine = fixture.engine(remote: remote)
        try await engine.markProgressPending()

        let status = try await engine.synchronize()
        guard case .conflict(let conflicts) = status,
              let conflict = conflicts.first else {
            return XCTFail("Expected a typed progress conflict")
        }
        XCTAssertEqual(try fixture.store.loadProgress(), local)
        let pendingStatus = try await engine.status()
        XCTAssertEqual(pendingStatus, .pending)

        try await engine.resolve(conflict, with: .useCloud)
        XCTAssertEqual(try fixture.store.loadProgress(), cloud)
        let resolvedStatus = try await engine.status()
        XCTAssertEqual(resolvedStatus, .idle)
    }

    func testCompatibleCompletionDominatesProgressAndStatisticsStayDerived() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let active = progress(words: ["civic"], draft: "ST")
        let completed = result(words: ["civic", "stone"])
        try fixture.store.save(active)
        let remote = TestDailyRemote(userID: userID, results: [completed.puzzleID: resultDTO(completed, userID: userID)])

        let status = try await fixture.engine(remote: remote).synchronize()

        XCTAssertEqual(status, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), DailyClassicProgress(result: completed))
        let restoredHistory = try fixture.store.loadHistory()
        XCTAssertEqual(restoredHistory.completedResults, [completed])
        XCTAssertEqual(restoredHistory.statistics, DailyStatistics.calculate(from: [completed]))
    }

    func testImmutableResultConflictPreservesLocalResult() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = result(words: ["stone"])
        let cloud = result(words: ["civic", "stone"])
        try fixture.store.save(history(local))
        let remote = TestDailyRemote(userID: userID, results: [cloud.puzzleID: resultDTO(cloud, userID: userID)])

        let status = try await fixture.engine(remote: remote).synchronize()

        guard case .conflict(let conflicts) = status,
              conflicts.count == 1,
              case .completedResult(
                puzzleID: let puzzleID,
                local: let retained,
                cloud: let existing
              ) = conflicts[0] else {
            return XCTFail("Expected an immutable-result conflict")
        }
        XCTAssertEqual(puzzleID, local.puzzleID)
        XCTAssertEqual(retained, local)
        XCTAssertEqual(existing, cloud)
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [local])

        try await fixture.engine(remote: remote).resolve(conflicts[0], with: .useCloud)
        let resolved = try fixture.store.loadHistory()
        XCTAssertEqual(resolved.completedResults, [cloud])
        XCTAssertEqual(resolved.statistics, DailyStatistics.calculate(from: [cloud]))
    }

    func testKeepingDeviceConflictStopsSilentRetriesAndRetainsLocalAttempt() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = progress(words: ["crane"], draft: "A")
        let cloud = progress(words: ["civic"])
        try fixture.store.save(local)
        let remote = TestDailyRemote(userID: userID, progress: progressDTO(cloud, userID: userID))
        let engine = fixture.engine(remote: remote)
        try await engine.markProgressPending()

        guard case .conflict(let conflicts) = try await engine.synchronize() else {
            return XCTFail("Expected a conflict")
        }
        try await engine.resolve(try XCTUnwrap(conflicts.first), with: .keepDevice)

        XCTAssertEqual(try fixture.store.loadProgress(), local)
        let retryStatus = try await engine.synchronize()
        XCTAssertEqual(retryStatus, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), local)
    }

    func testDivergentCloudCompletionWaitsForChoiceBeforeAffectingHistory() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = progress(words: ["crane"], draft: "A")
        let cloud = result(words: ["civic", "stone"])
        try fixture.store.save(local)
        let remote = TestDailyRemote(
            userID: userID,
            results: [cloud.puzzleID: resultDTO(cloud, userID: userID)]
        )
        let engine = fixture.engine(remote: remote)
        try await engine.markProgressPending()

        guard case .conflict(let conflicts) = try await engine.synchronize(),
              let conflict = conflicts.first else {
            return XCTFail("Expected a conflict with the cloud completion")
        }
        XCTAssertEqual(try fixture.store.loadProgress(), local)
        XCTAssertTrue(try fixture.store.loadHistory().completedResults.isEmpty)
        XCTAssertEqual(try fixture.store.loadHistory().statistics.gamesPlayed, 0)

        try await engine.resolve(conflict, with: .keepDevice)
        let retryStatus = try await engine.synchronize()
        XCTAssertEqual(retryStatus, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), local)
        XCTAssertTrue(try fixture.store.loadHistory().completedResults.isEmpty)
        XCTAssertEqual(try fixture.store.loadHistory().statistics.gamesPlayed, 0)
    }

    func testCompletedResultChoiceAlsoReplacesItsStaleBoardSnapshot() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = result(words: ["civic", "stone"])
        let cloud = result(words: ["crane", "stone"])
        let staleLocalProgress = progress(words: ["civic"])
        try fixture.store.save(history(local))
        try fixture.store.save(staleLocalProgress)
        let remote = TestDailyRemote(
            userID: userID,
            results: [cloud.puzzleID: resultDTO(cloud, userID: userID)]
        )
        let engine = fixture.engine(remote: remote)

        guard case .conflict(let conflicts) = try await engine.synchronize(),
              conflicts.count == 1,
              case .completedResult = conflicts[0] else {
            return XCTFail("Expected the completed-result conflict to take precedence")
        }
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [local])

        try await engine.resolve(conflicts[0], with: .useCloud)
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [cloud])
        XCTAssertEqual(try fixture.store.loadProgress(), DailyClassicProgress(result: cloud))
        let retryStatus = try await engine.synchronize()
        XCTAssertEqual(retryStatus, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [cloud])
    }

    func testGuestImportPreservesDraftAndNeverMutatesGuestFiles() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guestDirectory = root.appending(path: "Guest", directoryHint: .isDirectory)
        let accountRoot = root.appending(path: "AccountRoot", directoryHint: .isDirectory)
        let guest = DailyClassicStore(directory: guestDirectory)
        let guestProgress = progress(words: ["civic"], draft: "ST")
        let guestResult = result(day: day - 1, words: ["stone"])
        try guest.save(guestProgress)
        try guest.save(history(guestResult))
        let store = AccountDailyClassicStore(rootDirectory: accountRoot, userID: userID)
        let remote = TestDailyRemote(userID: userID)
        let syncDate = fixedDate(900)
        let engine = DailySyncEngine(userID: userID, store: store, remote: remote, now: { syncDate })

        let stagedStatus = try await engine.stageGuestImport(from: guest)
        XCTAssertEqual(stagedStatus, .pending)
        XCTAssertEqual(try store.loadProgress(), guestProgress)
        XCTAssertEqual(try guest.loadProgress(), guestProgress)
        XCTAssertEqual(try guest.loadHistory().completedResults, [guestResult])

        let syncedStatus = try await engine.synchronize()
        XCTAssertEqual(syncedStatus, .synced(syncDate))
        XCTAssertEqual(try guest.loadProgress(), guestProgress)
        XCTAssertEqual(try guest.loadHistory().completedResults, [guestResult])
        let remoteProgress = await remote.currentProgress()
        XCTAssertEqual((try XCTUnwrap(remoteProgress)).guesses.map(\.domain), guestProgress.acceptedGuesses)
    }

    func testGuestImportConflictLabelsDeviceAndSyncedAttemptsForExplicitChoice() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root.appending(path: "Guest"))
        let account = result(words: ["civic", "stone"])
        let device = result(words: ["stone"])
        try guest.save(history(device))
        let store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
        try store.save(history(account))
        let remote = TestDailyRemote(
            userID: userID,
            results: [account.puzzleID: resultDTO(account, userID: userID)]
        )
        let engine = DailySyncEngine(userID: userID, store: store, remote: remote)

        guard case .conflict(let conflicts) = try await engine.stageGuestImport(from: guest),
              case .completedResult(_, let shownDevice, let shownSynced) = try XCTUnwrap(conflicts.first)
        else { return XCTFail("Expected an imported-result conflict") }
        XCTAssertEqual(shownDevice, device)
        XCTAssertEqual(shownSynced, account)

        try await engine.resolve(conflicts[0], with: .keepDevice)
        XCTAssertEqual(try store.loadHistory().completedResults, [device])
        _ = try await engine.synchronize()
        XCTAssertEqual(try store.loadHistory().completedResults, [device])
    }

    func testSnapshotOwnedByAnotherUserIsRejectedWithoutLocalLeak() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let foreign = resultDTO(result(words: ["stone"]), userID: otherUserID)
        let remote = TestDailyRemote(userID: otherUserID, results: [foreign.puzzleID: foreign])

        let status = try await fixture.engine(remote: remote).synchronize()
        XCTAssertEqual(status, .failed(.invalidData))
        XCTAssertTrue(try fixture.store.loadHistory().completedResults.isEmpty)
    }

    @MainActor
    func testLocalSupabaseTwoClientSyncAndDeletionWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["GRIDRACE_LOCAL_SYNC_EMAIL"],
              let password = environment["GRIDRACE_LOCAL_SYNC_PASSWORD"],
              let url = environment["GRIDRACE_LOCAL_SUPABASE_URL"],
              let key = environment["GRIDRACE_LOCAL_SUPABASE_KEY"]
        else {
            throw XCTSkip("Local Supabase integration credentials are not configured")
        }
        let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
            urlString: url,
            publishableKey: key
        ))
        let firstService = SupabaseAccountService(configuration: configuration)
        let secondService = SupabaseAccountService(configuration: configuration)
        let firstSession = try await firstService.signInForLocalTesting(
            email: email,
            password: password
        )
        let secondSession = try await secondService.signInForLocalTesting(
            email: email,
            password: password
        )
        XCTAssertEqual(firstSession.userID, secondSession.userID)

        let first = SyncFixture(userID: firstSession.userID)
        let second = SyncFixture(userID: secondSession.userID)
        defer { first.remove(); second.remove() }
        let firstEngine = first.engine(remote: firstService.makeDailySyncRemote())
        let secondEngine = second.engine(remote: secondService.makeDailySyncRemote())
        let empty = progress(words: [])
        try first.store.save(empty)
        try await firstEngine.markProgressPending()
        let emptyStatus = try await firstEngine.synchronize()
        guard case .synced = emptyStatus else {
            return XCTFail("The empty progress status was \(safeName(emptyStatus))")
        }
        let accepted = progress(words: ["civic"])
        try first.store.save(accepted)
        try await firstEngine.markProgressPending()
        let firstProgressStatus = try await firstEngine.synchronize()
        guard case .synced = firstProgressStatus else {
            return XCTFail("The first client progress status was \(safeName(firstProgressStatus))")
        }

        guard case .synced = try await secondEngine.synchronize() else {
            return XCTFail("The second client did not restore progress")
        }
        XCTAssertEqual(
            try second.store.loadProgress()?.acceptedGuesses,
            accepted.acceptedGuesses
        )

        let completed = result(words: ["civic", "stone"])
        try first.store.save(history(completed))
        try await firstEngine.markResultPending(completed.puzzleID)
        guard case .synced = try await firstEngine.synchronize() else {
            return XCTFail("The first client did not synchronize completion")
        }
        guard case .synced = try await secondEngine.synchronize() else {
            return XCTFail("The second client did not restore completion")
        }
        XCTAssertEqual(try second.store.loadHistory().completedResults, [completed])
        XCTAssertEqual(try second.store.loadHistory().statistics.gamesPlayed, 1)

        let nextDay = day + 1
        let firstAttempt = progress(day: nextDay, words: ["civic"])
        let secondAttempt = progress(day: nextDay, words: ["crane"])
        try first.store.save(firstAttempt)
        try await firstEngine.markProgressPending()
        guard case .synced = try await firstEngine.synchronize() else {
            return XCTFail("The first divergent attempt was not stored")
        }
        try second.store.save(secondAttempt)
        try await secondEngine.markProgressPending()
        guard case .conflict = try await secondEngine.synchronize() else {
            return XCTFail("Divergent real-client progress did not produce a conflict")
        }

        try await firstService.deleteAccount()
        try first.store.deleteAccountCache()
        try second.store.deleteAccountCache()
    }

    private func progress(day: Int? = nil, words: [String], draft: String = "") -> DailyClassicProgress {
        let puzzleDay = day ?? self.day
        return DailyClassicProgress(
            puzzleID: puzzleID(day: puzzleDay),
            puzzleNumber: puzzleDay - self.day + 2,
            puzzleDay: puzzleDay,
            wordPackID: "test-v1",
            scheduleVersion: 1,
            hardModeEnabled: false,
            acceptedGuesses: words.enumerated().map { index, word in
                DailyGuess(
                    word: word,
                    feedback: Array(repeating: .absent, count: 5),
                    acceptedAt: date(day: puzzleDay, seconds: index + 1)
                )
            },
            draft: draft,
            completion: nil
        )
    }

    private func safeName(_ status: DailySyncStatus) -> String {
        switch status {
        case .idle: "idle"
        case .pending: "pending"
        case .synced: "synced"
        case .conflict: "conflict"
        case .failed(.unavailable): "failed-unavailable"
        case .failed(.rejected): "failed-rejected"
        case .failed(.invalidData): "failed-invalid-data"
        }
    }

    private func result(day: Int? = nil, words: [String]) -> DailyCompletedResult {
        let puzzleDay = day ?? self.day
        let guesses = words.enumerated().map { index, word in
            DailyGuess(
                word: word,
                feedback: index == words.count - 1
                    ? Array(repeating: .correct, count: 5)
                    : Array(repeating: .absent, count: 5),
                acceptedAt: date(day: puzzleDay, seconds: index + 1)
            )
        }
        return DailyCompletedResult(
            puzzleID: puzzleID(day: puzzleDay),
            puzzleNumber: puzzleDay - self.day + 2,
            puzzleDay: puzzleDay,
            wordPackID: "test-v1",
            scheduleVersion: 1,
            guesses: guesses,
            outcome: .solved,
            guessCount: guesses.count,
            completedAt: date(day: puzzleDay, seconds: 100)
        )
    }

    private func progressDTO(
        _ progress: DailyClassicProgress,
        userID: UUID,
        revision: Int = 1
    ) -> DailyProgressDTO {
        DailyProgressDTO(
            userID: userID,
            puzzleID: progress.puzzleID,
            puzzleNumber: progress.puzzleNumber,
            puzzleDay: progress.puzzleDay,
            wordPackID: progress.wordPackID,
            scheduleVersion: progress.scheduleVersion,
            hardModeEnabled: progress.hardModeEnabled,
            guesses: progress.acceptedGuesses.map(DailyGuessDTO.init),
            revision: revision,
            serverUpdatedAt: fixedDate(500)
        )
    }

    private func resultDTO(_ result: DailyCompletedResult, userID: UUID) -> DailyImportedResultDTO {
        DailyImportedResultDTO(
            userID: userID,
            puzzleID: result.puzzleID,
            puzzleNumber: result.puzzleNumber,
            puzzleDay: result.puzzleDay,
            wordPackID: result.wordPackID,
            scheduleVersion: result.scheduleVersion,
            hardModeEnabled: result.hardModeEnabled,
            guesses: result.guesses.map(DailyGuessDTO.init),
            outcome: result.outcome,
            guessCount: result.guessCount,
            clientCompletedAt: result.completedAt,
            serverImportedAt: fixedDate(600)
        )
    }

    private func history(_ results: DailyCompletedResult...) -> DailyClassicHistory {
        var history = DailyClassicHistory()
        for result in results { XCTAssertTrue(history.record(result)) }
        return history
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: DailyClassicPersistence.encode(value)) as? [String: Any])
    }

    private func puzzleID(day: Int) -> String {
        "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: day))"
    }

    private func date(day: Int, seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400 + seconds))
    }

    private func fixedDate(_ seconds: Int) -> Date {
        date(day: day, seconds: seconds)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "GridRaceSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private final class SyncFixture: @unchecked Sendable {
    let store: AccountDailyClassicStore
    let syncDate = Date(timeIntervalSince1970: 1_788_220_800)
    private let root: URL
    private let userID: UUID

    init(userID: UUID) {
        self.userID = userID
        root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceSyncFixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
    }

    func engine(remote: any DailySyncRemote) -> DailySyncEngine {
        DailySyncEngine(userID: userID, store: store, remote: remote, now: { self.syncDate })
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor TestDailyRemote: DailySyncRemote {
    private let userID: UUID
    private var progress: DailyProgressDTO?
    private var results: [String: DailyImportedResultDTO]
    private var pullFailures = 0
    private var imports = 0
    private let serverDate = Date(timeIntervalSince1970: 1_788_220_700)

    init(
        userID: UUID,
        progress: DailyProgressDTO? = nil,
        results: [String: DailyImportedResultDTO] = [:]
    ) {
        self.userID = userID
        self.progress = progress
        self.results = results
    }

    func pull() throws -> DailyCloudSnapshot {
        if pullFailures > 0 {
            pullFailures -= 1
            throw DailySyncRemoteError.unavailable
        }
        return DailyCloudSnapshot(
            progress: progress,
            importedResults: results.values.sorted { $0.puzzleDay < $1.puzzleDay }
        )
    }

    func pushProgress(_ upload: DailyProgressUploadDTO) throws -> DailyProgressPushOutcome {
        if let completed = results[upload.puzzleID] {
            let local = upload.guesses.map(\.domain)
            return DailySyncReconciler.isPrefix(local, of: completed.domain.guesses)
                ? .completed(completed)
                : .conflict(.completed(completed))
        }
        guard let existing = progress else {
            let inserted = dto(upload, revision: 1)
            progress = inserted
            return .stored(inserted)
        }
        guard samePuzzle(upload, existing) else { return .conflict(.progress(existing)) }
        let local = upload.guesses.map(\.domain)
        let cloud = existing.guesses.map(\.domain)
        if local == cloud { return .stored(existing) }
        if DailySyncReconciler.isPrefix(cloud, of: local) {
            let advanced = dto(upload, revision: existing.revision + 1)
            progress = advanced
            return .stored(advanced)
        }
        if DailySyncReconciler.isPrefix(local, of: cloud) { return .serverAhead(existing) }
        return .conflict(.progress(existing))
    }

    func importResult(_ upload: DailyImportedResultUploadDTO) throws -> DailyResultImportOutcome {
        imports += 1
        let incoming = dto(upload)
        if let existing = results[upload.puzzleID] {
            return existing.domain == incoming.domain
                ? .stored(existing)
                : .conflict(.result(existing))
        }
        if let existingProgress = progress, existingProgress.puzzleID == upload.puzzleID {
            let prefix = existingProgress.guesses.map(\.domain)
            if !DailySyncReconciler.isPrefix(prefix, of: incoming.domain.guesses) {
                return .conflict(.progress(existingProgress))
            }
            progress = nil
        }
        results[upload.puzzleID] = incoming
        return .stored(incoming)
    }

    func failNextPull() { pullFailures += 1 }
    func currentProgress() -> DailyProgressDTO? { progress }
    func storedResultCount() -> Int { results.count }
    func importCallCount() -> Int { imports }

    private func dto(_ upload: DailyProgressUploadDTO, revision: Int) -> DailyProgressDTO {
        DailyProgressDTO(
            userID: userID,
            puzzleID: upload.puzzleID,
            puzzleNumber: upload.puzzleNumber,
            puzzleDay: upload.puzzleDay,
            wordPackID: upload.wordPackID,
            scheduleVersion: upload.scheduleVersion,
            hardModeEnabled: upload.hardModeEnabled,
            guesses: upload.guesses,
            revision: revision,
            serverUpdatedAt: serverDate
        )
    }

    private func dto(_ upload: DailyImportedResultUploadDTO) -> DailyImportedResultDTO {
        DailyImportedResultDTO(
            userID: userID,
            puzzleID: upload.puzzleID,
            puzzleNumber: upload.puzzleNumber,
            puzzleDay: upload.puzzleDay,
            wordPackID: upload.wordPackID,
            scheduleVersion: upload.scheduleVersion,
            hardModeEnabled: upload.hardModeEnabled,
            guesses: upload.guesses,
            outcome: upload.outcome,
            guessCount: upload.guessCount,
            clientCompletedAt: upload.clientCompletedAt,
            serverImportedAt: serverDate
        )
    }

    private func samePuzzle(_ upload: DailyProgressUploadDTO, _ existing: DailyProgressDTO) -> Bool {
        upload.puzzleID == existing.puzzleID
            && upload.puzzleNumber == existing.puzzleNumber
            && upload.puzzleDay == existing.puzzleDay
            && upload.wordPackID == existing.wordPackID
            && upload.scheduleVersion == existing.scheduleVersion
            && upload.hardModeEnabled == existing.hardModeEnabled
    }
}
