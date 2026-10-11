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
            wordPackID: "daily-classic-en-US-v1",
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

    func testRemoteRetainsPerPuzzleProgressAndImportsOnlyTheRequestedDay() async throws {
        let remote = TestDailyRemote(userID: userID)
        let oldUpload = DailyProgressUploadDTO(progress: progress(words: ["civic"]), expectedRevision: nil)
        let newUpload = DailyProgressUploadDTO(
            progress: progress(day: day + 1, words: ["crane"]), expectedRevision: nil
        )
        guard case let .stored(oldRow) = try await remote.pushProgress(oldUpload) else {
            return XCTFail("The old puzzle must insert its own progress row")
        }
        guard case let .stored(newRow) = try await remote.pushProgress(newUpload) else {
            return XCTFail("A different puzzle must insert without conflicting with the old row")
        }
        XCTAssertEqual(oldRow.revision, 1)
        XCTAssertEqual(newRow.revision, 1)
        let latest = try await remote.pull()
        let current = await remote.currentProgress()
        XCTAssertEqual(latest.progress, newRow)
        XCTAssertEqual(current, newRow)

        let oldRetry = try await remote.pushProgress(oldUpload)
        XCTAssertEqual(oldRetry, .stored(oldRow), "Inserting a new day must retain the old row and revision")
        let oldAdvance = DailyProgressUploadDTO(
            progress: progress(words: ["civic", "crane"]), expectedRevision: oldRow.revision
        )
        guard case let .stored(advancedOldRow) = try await remote.pushProgress(oldAdvance) else {
            return XCTFail("The retained old row must still accept its next revision")
        }
        XCTAssertEqual(advancedOldRow.revision, 2)
        XCTAssertEqual(advancedOldRow.guesses.map(\.domain), oldAdvance.guesses.map(\.domain))
        let afterOldAdvance = try await remote.pull()
        XCTAssertEqual(afterOldAdvance.progress, newRow, "Updating an older puzzle must not change the latest day")

        let oldResult = result(words: ["civic", "crane", "stone"])
        guard case let .stored(importedOldRow) = try await remote.importResult(DailyImportedResultUploadDTO(oldResult)) else {
            return XCTFail("The old puzzle result must import")
        }
        let afterOldImport = try await remote.pull()
        let currentAfterImport = await remote.currentProgress()
        XCTAssertEqual(afterOldImport.importedResults.map(\.domain), [oldResult])
        XCTAssertEqual(afterOldImport.progress, newRow, "Importing the old result must preserve the newer progress row")
        XCTAssertEqual(currentAfterImport, newRow)
        let completedOldRetry = try await remote.pushProgress(oldAdvance)
        XCTAssertEqual(completedOldRetry, .completed(importedOldRow))

        let newResult = result(day: day + 1, words: ["crane", "stone"])
        _ = try await remote.importResult(DailyImportedResultUploadDTO(newResult))
        let afterBothImports = try await remote.pull()
        XCTAssertNil(afterBothImports.progress, "Importing both results must remove both puzzles' progress rows")
        XCTAssertEqual(afterBothImports.importedResults.map(\.domain), [oldResult, newResult])
    }

    @MainActor
    func testSelectedAcceptedPuzzleSurvivesOtherDeviceDayAndColdRestart() async throws {
        for selectedOffset in [0, 1] {
            let fixture = SyncFixture(userID: userID)
            defer { fixture.remove() }
            let selectedDay = day + selectedOffset
            let otherDay = day + 1 - selectedOffset
            let selected = progress(day: selectedDay, words: ["civic"], draft: "ST")
            let other = progress(day: otherDay, words: ["adore"])
            let remote = TestDailyRemote(userID: userID, progress: progressDTO(other, userID: userID))
            try fixture.store.save(selected)
            let engine = fixture.engine(remote: remote)
            // Pending metadata may be absent: durable accepted rows still derive upload work.
            let status = try await engine.synchronize()
            XCTAssertEqual(status, .synced(fixture.syncDate))
            XCTAssertEqual(try fixture.store.loadProgress(), selected)
            let uploaded = try await remote.pull(puzzleID: selected.puzzleID)
            XCTAssertEqual(uploaded.progress?.guesses.map(\.domain), selected.acceptedGuesses)
            let untouched = try await remote.pull(puzzleID: other.puzzleID)
            XCTAssertEqual(untouched.progress?.domain, other)
            let defaults = try XCTUnwrap(UserDefaults(suiteName: "GridRaceSelectedRestart.\(UUID())"))
            let model = try DailyClassicModel(pack: dailyPack(answerCount: 2), store: fixture.store,
                defaults: defaults, now: { self.date(day: selectedDay, seconds: 100) })
            XCTAssertEqual(model.game.progress.acceptedGuesses, selected.acceptedGuesses)
            XCTAssertEqual(model.game.draft, "ST")
            XCTAssertFalse(model.hasUnsavedProgress)
        }
    }

    @MainActor
    func testLatestDiscoveryAndNormalForwardUnfinishedRollover() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let earlier = progress(words: ["civic"])
        let remote = TestDailyRemote(userID: userID, progress: progressDTO(earlier, userID: userID))
        let discovered = try await fixture.engine(remote: remote).synchronize()
        XCTAssertEqual(discovered, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), earlier)
        var now = date(day: day, seconds: 100)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GridRaceForwardRollover.\(UUID())"))
        let model = try DailyClassicModel(pack: dailyPack(answerCount: 2), store: fixture.store,
            defaults: defaults, now: { now })
        now = date(day: day + 1, seconds: 100)
        model.refreshForCurrentDay()
        XCTAssertTrue(model.game.rows.isEmpty, "Normal forward rollover still disposes unfinished prior-day state")
        let next = model.game.progress
        let rolled = try await fixture.engine(remote: remote).synchronize()
        XCTAssertEqual(rolled, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), next)
        let oldCloud = try await remote.pull(puzzleID: earlier.puzzleID)
        XCTAssertEqual(oldCloud.progress?.domain, earlier)
        let newCloud = try await remote.pull(puzzleID: next.puzzleID)
        XCTAssertEqual(newCloud.progress?.guesses, [])
    }

    func testSelectedPuzzleMetadataFailureRetainsRowsAndRetryUploadsOwnIdentity() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let selected = progress(words: ["civic"])
        let future = progress(day: day + 1, words: ["adore"])
        let remote = TestDailyRemote(userID: userID, progress: progressDTO(future, userID: userID))
        try fixture.store.save(selected)
        try fixture.store.save(DailySyncMetadata(pendingProgress: true))
        let metadata = fixture.store.directory.appending(path: "daily-sync-metadata-v1.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: metadata.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadata.path) }
        let failed = try await fixture.engine(remote: remote).synchronize()
        XCTAssertEqual(failed, .failed(.unavailable))
        XCTAssertEqual(try fixture.store.loadProgress(), selected)
        XCTAssertTrue(try fixture.store.loadSyncMetadata().pendingProgress)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadata.path)
        let synced = try await fixture.engine(remote: remote).synchronize()
        XCTAssertEqual(synced, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), selected)
        let restored = try await remote.pull(puzzleID: selected.puzzleID)
        XCTAssertEqual(restored.progress?.guesses.map(\.domain), selected.acceptedGuesses)
        XCTAssertFalse(try fixture.store.loadSyncMetadata().pendingProgress)
    }

    func testSelectionChangeDuringTargetedPullCannotReplaceNewSlot() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let old = progress(words: ["civic"])
        let selected = progress(day: day + 1, words: ["civic"], draft: "ST")
        let remote = GateRemote(userID: userID)
        await remote.suspendNextPull()
        try fixture.store.save(old)
        let task = Task { try await fixture.engine(remote: remote).synchronize() }
        guard await Self.waitForPullSuspension(remote) else { return }
        try fixture.store.save(selected)
        await remote.completePull(with: DailyCloudSnapshot(
            progress: progressDTO(old, userID: userID), importedResults: []))
        guard await Self.waitForPushSuspension(remote) else { return }
        let upload = await remote.pushedProgress()
        XCTAssertEqual(upload?.puzzleID, selected.puzzleID)
        XCTAssertEqual(try fixture.store.loadProgress(), selected)
        await remote.completePush(with: .stored(progressDTO(selected, userID: userID)))
        let status = try await task.value
        XCTAssertEqual(status, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), selected)
    }

    func testCancellationDuringTargetedPullRetainsSelectedBytes() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let selected = progress(words: ["civic"])
        let remote = GateRemote(userID: userID)
        await remote.suspendNextPull()
        try fixture.store.save(selected)
        let path = fixture.store.directory.appending(path: "daily-progress-v1.json")
        let before = try Data(contentsOf: path)
        let task = Task { try await fixture.engine(remote: remote).synchronize() }
        guard await Self.waitForPullSuspension(remote) else { return }
        task.cancel()
        await remote.completePull(with: DailyCloudSnapshot(progress: nil, importedResults: []))
        do { _ = try await task.value; XCTFail("Cancelled pull must not reconcile") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation error") }
        XCTAssertEqual(try Data(contentsOf: path), before)
    }

    func testSelectedCloudCompletionWinsWhileOtherDayProgressIsRetained() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let selected = progress(words: ["civic"])
        let future = progress(day: day + 1, words: ["adore"])
        let completed = result(words: ["civic", "stone"])
        let remote = TestDailyRemote(userID: userID, progress: progressDTO(future, userID: userID),
            results: [completed.puzzleID: resultDTO(completed, userID: userID)])
        try fixture.store.save(selected)
        let synced = try await fixture.engine(remote: remote).synchronize()
        XCTAssertEqual(synced, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), DailyClassicProgress(result: completed))
        XCTAssertEqual(try fixture.store.loadHistory().statistics.gamesPlayed, 1)
        let futureCloud = try await remote.pull(puzzleID: future.puzzleID)
        XCTAssertEqual(futureCloud.progress?.domain, future)
        let resynced = try await fixture.engine(remote: remote).synchronize()
        XCTAssertEqual(resynced, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadHistory().statistics.gamesPlayed, 1)
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

        try await engine.resolve(try engine.choice(for: conflict), with: .useCloud)
        XCTAssertEqual(try fixture.store.loadProgress(), cloud)
        let resolvedStatus = try await engine.status()
        XCTAssertEqual(resolvedStatus, .idle)
    }

    func testLocalCompletionReplacesCloudProgressAndDoesNotReconflict() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = result(words: ["stone"])
        let cloud = progress(words: ["civic"])
        try fixture.store.save(history(local))
        try fixture.store.save(DailyClassicProgress(result: local))
        let remote = TestDailyRemote(
            userID: userID,
            progress: progressDTO(cloud, userID: userID)
        )
        let engine = fixture.engine(remote: remote)
        try await engine.markResultPending(local.puzzleID)

        let status = try await engine.synchronize()
        XCTAssertEqual(status, .synced(fixture.syncDate))

        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [local])
        XCTAssertEqual(
            try fixture.store.loadHistory().statistics,
            DailyStatistics.calculate(from: [local])
        )
        XCTAssertEqual(try fixture.store.loadProgress(), DailyClassicProgress(result: local))
        XCTAssertFalse(try fixture.store.loadSyncMetadata().hasPendingChanges)
        let retry = try await engine.synchronize()
        let importCalls = await remote.importCallCount()
        XCTAssertEqual(retry, .synced(fixture.syncDate))
        XCTAssertEqual(importCalls, 1)
        let remoteProgress = await remote.currentProgress()
        let storedResultCount = await remote.storedResultCount()
        XCTAssertNil(remoteProgress)
        XCTAssertEqual(storedResultCount, 1)
    }

    func testLocalCompletionDominatesCloudProgressAcrossHardModeMismatch() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = result(words: ["stone"])
        let localProgress = DailyClassicProgress(result: local)
        let cloud = progress(words: ["civic"], hardMode: true)
        try fixture.store.save(history(local))
        try fixture.store.save(localProgress)
        let remote = TestDailyRemote(
            userID: userID,
            progress: progressDTO(cloud, userID: userID)
        )
        let engine = fixture.engine(remote: remote)
        try await engine.markResultPending(local.puzzleID)

        let status = try await engine.synchronize()
        XCTAssertEqual(status, .synced(fixture.syncDate))

        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [local])
        XCTAssertEqual(try fixture.store.loadProgress(), localProgress)
        XCTAssertFalse(try fixture.store.loadSyncMetadata().hasPendingChanges)
        let retry = try await engine.synchronize()
        let importCalls = await remote.importCallCount()
        XCTAssertEqual(retry, .synced(fixture.syncDate))
        XCTAssertEqual(importCalls, 1)
    }

    @MainActor
    func testFreshLocalReconciliationRunsOnGameplayActor() throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let engine = fixture.engine(remote: TestDailyRemote(userID: userID))

        // This synchronous call compiles only while engine reconciliation and
        // DailyClassicModel writes share MainActor ownership.
        XCTAssertEqual(try engine.status(), .idle)
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

        try await fixture.engine(remote: remote).resolve(try fixture.engine(remote: remote).choice(for: conflicts[0]), with: .useCloud)
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
        try await engine.resolve(try engine.choice(for: XCTUnwrap(conflicts.first)), with: .keepDevice)

        XCTAssertEqual(try fixture.store.loadProgress(), local)
        let retryStatus = try await engine.synchronize()
        XCTAssertEqual(retryStatus, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), local)
    }

    @MainActor
    func testDivergentCloudCompletionRemainsTerminalAndRebuildsStatistics() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = progress(words: ["crane"], draft: "A")
        let cloud = result(words: ["adore"])
        try fixture.store.save(local)
        let remote = TestDailyRemote(
            userID: userID,
            results: [cloud.puzzleID: resultDTO(cloud, userID: userID)]
        )
        let engine = fixture.engine(remote: remote)
        try await engine.markProgressPending()

        let status = try await engine.synchronize()
        XCTAssertEqual(status, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), DailyClassicProgress(result: cloud))
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [cloud])
        XCTAssertEqual(
            try fixture.store.loadHistory().statistics,
            DailyStatistics.calculate(from: [cloud])
        )

        let reloaded = try DailyClassicModel(
            pack: dailyPack(),
            store: fixture.store,
            now: { self.date(day: self.day, seconds: 0) }
        )
        XCTAssertTrue(reloaded.game.isComplete)
        XCTAssertEqual(reloaded.history.completedResults, [cloud])
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

        try await engine.resolve(try engine.choice(for: conflicts[0]), with: .useCloud)
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
        let guestResult = result(day: day + 1, words: ["stone"])
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

    @MainActor
    func testGuestSolvedRelaunchImportsTerminalProgressWithoutMutatingGuest() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root.appending(path: "Guest"))
        let suite = "GridRaceSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = date(day: day, seconds: 100)
        var model = try DailyClassicModel(
            pack: dailyPack(), store: guest, defaults: defaults, now: { now }
        )
        for letter in "adore" { model.typeLetter(letter) }
        model.submitGuess()
        let terminal = try XCTUnwrap(model.game.completedResult)
        model = try DailyClassicModel(
            pack: dailyPack(), store: guest, defaults: defaults, now: { now }
        )
        XCTAssertTrue(model.game.isComplete)
        let terminalProgress = model.game.progress
        let store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
        let remote = TestDailyRemote(userID: userID)
        let engine = DailySyncEngine(userID: userID, store: store, remote: remote)

        let staged = try await engine.stageGuestImport(from: guest)
        XCTAssertEqual(staged, .pending)
        XCTAssertNil(try store.loadProgress())
        XCTAssertEqual(try store.loadHistory().completedResults, [terminal])
        XCTAssertEqual(try guest.loadProgress(), terminalProgress)
        XCTAssertEqual(try guest.loadHistory().completedResults, [terminal])

        _ = try await engine.synchronize()
        let storedResultCount = await remote.storedResultCount()
        XCTAssertEqual(storedResultCount, 1)
    }

    @MainActor
    func testGuestFailedRelaunchRecoversMissingHistoryIdempotently() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root.appending(path: "Guest"))
        let suite = "GridRaceSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = date(day: day, seconds: 100)
        var model = try DailyClassicModel(
            pack: dailyPack(), store: guest, defaults: defaults, now: { now }
        )
        for word in ["civic", "stone", "civic", "stone", "civic", "stone"] {
            for letter in word { model.typeLetter(letter) }
            model.submitGuess()
        }
        let terminal = try XCTUnwrap(model.game.completedResult)
        XCTAssertEqual(terminal.outcome, .failed)
        model = try DailyClassicModel(
            pack: dailyPack(), store: guest, defaults: defaults, now: { now }
        )
        XCTAssertTrue(model.game.isComplete)
        let terminalProgress = model.game.progress
        try FileManager.default.removeItem(
            at: guest.directory.appending(path: "daily-history-v1.json")
        )
        let store = AccountDailyClassicStore(rootDirectory: root, userID: userID)
        let remote = TestDailyRemote(userID: userID)
        let engine = DailySyncEngine(userID: userID, store: store, remote: remote)

        let staged = try await engine.stageGuestImport(from: guest)
        XCTAssertEqual(staged, .pending)
        XCTAssertEqual(try store.loadHistory().completedResults, [terminal])
        XCTAssertEqual(
            try store.loadHistory().statistics,
            DailyStatistics.calculate(from: [terminal])
        )
        XCTAssertEqual(try guest.loadProgress(), terminalProgress)
        XCTAssertTrue(try guest.loadHistory().completedResults.isEmpty)

        _ = try await engine.synchronize()
        let repeatedStage = try await engine.stageGuestImport(from: guest)
        XCTAssertEqual(repeatedStage, .pending)
        XCTAssertEqual(try store.loadHistory().completedResults, [terminal])
        let storedResultCount = await remote.storedResultCount()
        XCTAssertEqual(storedResultCount, 1)
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

        try await engine.resolve(try engine.choice(for: conflicts[0], isGuestImport: true), with: .keepDevice)
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

    func testReconcilerRejectsCloudProgressWithInconsistentIdentity() {
        let inconsistent = DailyClassicProgress(
            puzzleID: puzzleID(day: day),
            puzzleNumber: 2,
            puzzleDay: day,
            wordPackID: "daily-classic-en-US-v1",
            scheduleVersion: 1,
            hardModeEnabled: false,
            acceptedGuesses: [],
            draft: "",
            completion: nil
        )
        XCTAssertThrowsError(try DailySyncReconciler.reconcile(
            localProgress: nil,
            localHistory: DailyClassicHistory(),
            incomingProgress: inconsistent,
            incomingResults: []
        )) { error in
            XCTAssertEqual(error as? DailySyncError, .invalidCloudData)
        }
    }

    func testReconcilerRejectsCloudResultOutsidePublishedSchedule() {
        let outOfRange = result(day: DailyPuzzleIdentity.lastDay + 1, words: ["stone"])
        XCTAssertThrowsError(try DailySyncReconciler.reconcile(
            localProgress: nil,
            localHistory: DailyClassicHistory(),
            incomingProgress: nil,
            incomingResults: [outOfRange]
        )) { error in
            XCTAssertEqual(error as? DailySyncError, .invalidCloudData)
        }
    }

    @MainActor
    func testLocalSupabaseTwoClientSyncAndDeletionWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        let admission = try LocalIntegrationAdmission.admit(environment: environment, purpose: .daily)
        var stage = "construct-services"
        print("DAILY stage=\(stage)")
        do {
            let configuration = admission.configuration
            let email = admission.email
            let password = admission.password
            // Independent devices do not share credential storage. Using the default
            // Keychain service here lets the second sign-in retire the first client's keys.
            let credentialNamespace = "GridRaceDailyIntegration.\(UUID().uuidString)"
            let firstService = SupabaseAccountService(configuration: configuration,
                storage: SecureAuthStorage(service: credentialNamespace + ".first"))
            let secondService = SupabaseAccountService(configuration: configuration,
                storage: SecureAuthStorage(service: credentialNamespace + ".second"))
            stage = "sign-in-first"
            print("DAILY stage=\(stage)")
            let firstSession = try await firstService.signInForLocalTesting(
                email: email,
                password: password
            )
            stage = "sign-in-second"
            print("DAILY stage=\(stage)")
            let secondSession = try await secondService.signInForLocalTesting(
                email: email,
                password: password
            )
            stage = "validate-fixture-identities"
            print("DAILY stage=\(stage)")
            try admission.validateIdentity(firstSession.userID)
            try admission.validateIdentity(secondSession.userID)

            let first = SyncFixture(userID: firstSession.userID)
            let second = SyncFixture(userID: secondSession.userID)
            defer {
                print("DAILY stage=remove-owned-first-fixture")
                first.remove()
                print("DAILY stage=remove-owned-second-fixture")
                second.remove()
                print("DAILY stage=fixture-teardown-complete")
            }
            stage = "construct-first-engine"
            print("DAILY stage=\(stage)")
            let firstEngine = first.engine(remote: try firstService.makeDailySyncRemote(userID: firstSession.userID))
            stage = "construct-second-engine"
            print("DAILY stage=\(stage)")
            let secondEngine = second.engine(remote: try secondService.makeDailySyncRemote(userID: secondSession.userID))
            let empty = progress(words: [])
            stage = "save-first-empty"
            print("DAILY stage=\(stage)")
            try first.store.save(empty)
            stage = "mark-first-empty-pending"
            print("DAILY stage=\(stage)")
            try firstEngine.markProgressPending()
            stage = "sync-first-empty"
            print("DAILY stage=\(stage)")
            let emptyStatus = try await firstEngine.synchronize()
            guard case .synced = emptyStatus else {
                return XCTFail("The empty progress status was \(safeName(emptyStatus))")
            }
            let accepted = progress(words: ["civic"])
            stage = "save-first-accepted"
            print("DAILY stage=\(stage)")
            try first.store.save(accepted)
            try firstEngine.markProgressPending()
            stage = "sync-first-accepted"
            print("DAILY stage=\(stage)")
            let firstProgressStatus = try await firstEngine.synchronize()
            guard case .synced = firstProgressStatus else {
                return XCTFail("The first client progress status was \(safeName(firstProgressStatus))")
            }

            stage = "restore-second-selected"
            print("DAILY stage=\(stage)")
            guard case .synced = try await secondEngine.synchronize() else {
                return XCTFail("The second client did not restore progress")
            }
            XCTAssertEqual(
                try second.store.loadProgress()?.acceptedGuesses,
                accepted.acceptedGuesses
            )

            // Date disagreement: the first device still owns D while the second owns D+1.
            // Targeted reads must upload/resume D and leave the later row intact.
            let future = progress(day: day + 1, words: ["civic"])
            stage = "save-second-future"
            print("DAILY stage=\(stage)")
            try second.store.save(future)
            try secondEngine.markProgressPending()
            guard case .synced = try await secondEngine.synchronize() else {
                return XCTFail("The second client's future-day row was not stored")
            }
            stage = "advance-first-selected"
            print("DAILY stage=\(stage)")
            let advanced = progress(words: ["civic", "crane"])
            try first.store.save(advanced)
            try firstEngine.markProgressPending()
            guard case .synced = try await firstEngine.synchronize() else {
                return XCTFail("Selected older-day accepted rows were not uploaded")
            }
            XCTAssertEqual(try first.store.loadProgress(), advanced)
            stage = "cold-store-selected-read"
            print("DAILY stage=\(stage)")
            let coldStore = AccountDailyClassicStore(rootDirectory: first.store.directory
                .deletingLastPathComponent().deletingLastPathComponent(), userID: firstSession.userID)
            XCTAssertEqual(try coldStore.loadProgress(), advanced)
            let firstRemote = try firstService.makeDailySyncRemote()
            stage = "pull-selected-identity"
            print("DAILY stage=\(stage)")
            let selectedCloud = try await firstRemote.pull(puzzleID: advanced.puzzleID)
            XCTAssertEqual(selectedCloud.progress?.guesses.map(\.domain), advanced.acceptedGuesses)
            stage = "pull-future-identity"
            print("DAILY stage=\(stage)")
            let laterCloud = try await firstRemote.pull(puzzleID: future.puzzleID)
            XCTAssertEqual(laterCloud.progress?.guesses.map(\.domain), future.acceptedGuesses)
            // Completion restoration below continues to observe D on the second device.
            stage = "restore-second-selected-before-completion"
            print("DAILY stage=\(stage)")
            try second.store.save(accepted)

            stage = "save-selected-completion"
            print("DAILY stage=\(stage)")
            let completed = result(words: ["civic", "crane", "stone"])
            try first.store.save(history(completed))
            stage = "mark-completion-pending"
            print("DAILY stage=\(stage)")
            try firstEngine.markResultPending(completed.puzzleID)
            stage = "sync-selected-completion"
            print("DAILY stage=\(stage)")
            guard case .synced = try await firstEngine.synchronize() else {
                return XCTFail("The first client did not synchronize completion")
            }
            stage = "restore-selected-completion"
            print("DAILY stage=\(stage)")
            guard case .synced = try await secondEngine.synchronize() else {
                return XCTFail("The second client did not restore completion")
            }
            XCTAssertEqual(try second.store.loadHistory().completedResults, [completed])
            XCTAssertEqual(try second.store.loadHistory().statistics.gamesPlayed, 1)

            stage = "divergent-future-attempts"
            print("DAILY stage=\(stage)")
            let nextDay = day + 1
            let firstAttempt = progress(day: nextDay, words: ["civic"])
            let secondAttempt = progress(day: nextDay, words: ["crane"])
            try first.store.save(firstAttempt)
            try firstEngine.markProgressPending()
            guard case .synced = try await firstEngine.synchronize() else {
                return XCTFail("The first divergent attempt was not stored")
            }
            try second.store.save(secondAttempt)
            try secondEngine.markProgressPending()
            stage = "sync-divergent-future"
            print("DAILY stage=\(stage)")
            guard case .conflict = try await secondEngine.synchronize() else {
                return XCTFail("Divergent real-client progress did not produce a conflict")
            }

            stage = "remote-delete"
            print("DAILY stage=\(stage)")
            _ = try await firstService.deleteAccount()
            stage = "clear-first-cache"
            print("DAILY stage=\(stage)")
            try first.store.deleteAccountCache()
            stage = "clear-second-cache"
            print("DAILY stage=\(stage)")
            try second.store.deleteAccountCache()
            stage = "acknowledge-deletion"
            print("DAILY stage=\(stage)")
            try firstService.acknowledgeAccountDeletion(userID: firstSession.userID)
            stage = "retire-second-client"
            print("DAILY stage=\(stage)")
            let secondRetirement = await secondService.signOut()
            XCTAssertNil(secondRetirement.localRecovery, "The second client's owned credentials must retire locally")
            stage = "complete"
            print("DAILY stage=\(stage)")
            print("PASS disposable Daily two-client sync and deletion")
        } catch {
            XCTFail("Daily integration failed at stage \(stage): \(Self.safeFilesystemDiagnostic(error))")
        }
    }

    /// Never includes localized text, userInfo payloads, file paths or account identifiers.
    private static func safeFilesystemDiagnostic(_ error: any Error) -> String {
        func domainName(_ domain: String) -> String {
            switch domain {
            case NSCocoaErrorDomain: "cocoa"
            case NSPOSIXErrorDomain: "posix"
            case NSURLErrorDomain: "url"
            default: "other"
            }
        }
        if error is CancellationError { return "kind=cancellation" }
        let error = error as NSError
        var diagnostic = "domain=\(domainName(error.domain)) code=\(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            diagnostic += " underlying-domain=\(domainName(underlying.domain)) underlying-code=\(underlying.code)"
        }
        return diagnostic
    }

    // MARK: - U-01 remediation regressions (GR-01, GR-02, GR-04)

    func testMismatchedModeEmptyLocalYieldsToNonEmptyCloud() throws {
        let local = progress(words: [], draft: "AB", hardMode: false)
        let cloud = progress(words: ["civic"], hardMode: true)
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: local,
            localHistory: DailyClassicHistory(),
            incomingProgress: cloud,
            incomingResults: []
        )
        XCTAssertTrue(reconciliation.conflicts.isEmpty)
        let merged = try XCTUnwrap(reconciliation.progress)
        XCTAssertEqual(merged.acceptedGuesses, cloud.acceptedGuesses)
        XCTAssertTrue(merged.hardModeEnabled)
        XCTAssertEqual(merged.draft, "AB")
    }

    func testMismatchedModeNonEmptyLocalDominatesEmptyCloud() throws {
        let local = progress(words: ["crane"], hardMode: false)
        let cloud = progress(words: [], hardMode: true)
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: local,
            localHistory: DailyClassicHistory(),
            incomingProgress: cloud,
            incomingResults: []
        )
        XCTAssertTrue(reconciliation.conflicts.isEmpty)
        XCTAssertEqual(reconciliation.progress, local)
    }

    func testMismatchedModeDivergentNonEmptyAttemptsConflict() throws {
        let local = progress(words: ["crane"], hardMode: false)
        let cloud = progress(words: ["civic"], hardMode: true)
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: local,
            localHistory: DailyClassicHistory(),
            incomingProgress: cloud,
            incomingResults: []
        )
        XCTAssertEqual(reconciliation.conflicts.count, 1)
        guard case .progress(let puzzleID, _, let cloudAttempt) = reconciliation.conflicts[0] else {
            return XCTFail("Expected a progress conflict")
        }
        XCTAssertEqual(puzzleID, local.puzzleID)
        XCTAssertEqual(reconciliation.progress, local)
        XCTAssertEqual(cloudAttempt.acceptedGuesses, cloud.acceptedGuesses)
    }

    func testMismatchedModeEmptyEmptyKeepsLocalWithoutConflict() throws {
        let local = progress(words: [], draft: "AB", hardMode: false)
        let cloud = progress(words: [], hardMode: true)
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: local,
            localHistory: DailyClassicHistory(),
            incomingProgress: cloud,
            incomingResults: []
        )
        XCTAssertTrue(reconciliation.conflicts.isEmpty)
        XCTAssertEqual(reconciliation.progress, local)
        XCTAssertEqual(reconciliation.progress?.draft, "AB")
        XCTAssertEqual(reconciliation.progress?.hardModeEnabled, false)
    }

    func testMismatchedModeShorterLocalNeverHidesLongerCloud() throws {
        let local = progress(words: ["civic"], hardMode: false)
        let cloud = progress(words: ["civic", "stone"], hardMode: true)
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: local,
            localHistory: DailyClassicHistory(),
            incomingProgress: cloud,
            incomingResults: []
        )
        XCTAssertEqual(reconciliation.conflicts.count, 1)
        XCTAssertEqual(reconciliation.progress?.acceptedGuesses, local.acceptedGuesses)
        guard case .progress(_, _, let cloudAttempt) = reconciliation.conflicts[0] else {
            return XCTFail("Expected a progress conflict")
        }
        XCTAssertEqual(cloudAttempt.acceptedGuesses.count, 2)
    }

    func testMismatchedModeEmptyProgressYieldsToIncomingResult() throws {
        let local = progress(words: [], hardMode: false)
        let cloudResult = result(words: ["civic", "stone"], hardMode: true)
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: local,
            localHistory: DailyClassicHistory(),
            incomingProgress: nil,
            incomingResults: [cloudResult]
        )
        XCTAssertTrue(reconciliation.conflicts.isEmpty)
        XCTAssertEqual(reconciliation.history.completedResults, [cloudResult])
    }

    func testMismatchedModeIncomingResultDominatesNonEmptyProgress() throws {
        let local = progress(words: ["crane"], hardMode: false)
        let cloudResult = result(words: ["civic", "stone"], hardMode: true)
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: local,
            localHistory: DailyClassicHistory(),
            incomingProgress: nil,
            incomingResults: [cloudResult]
        )
        XCTAssertTrue(reconciliation.conflicts.isEmpty)
        XCTAssertEqual(reconciliation.history.completedResults, [cloudResult])
        XCTAssertEqual(reconciliation.progress, DailyClassicProgress(result: cloudResult))
    }

    func testLocalProgressConvergesWithoutPendingMetadata() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = progress(words: ["civic"])
        try fixture.store.save(local)
        let remote = TestDailyRemote(
            userID: userID,
            progress: progressDTO(progress(words: [], hardMode: true), userID: userID, revision: 4)
        )

        let status = try await fixture.engine(remote: remote).synchronize()

        XCTAssertEqual(status, .synced(fixture.syncDate))
        let stored = await remote.currentProgress()
        let uploaded = try XCTUnwrap(stored)
        XCTAssertEqual(uploaded.guesses.map(\.domain), local.acceptedGuesses)
        XCTAssertEqual(uploaded.hardModeEnabled, local.hardModeEnabled)
        XCTAssertEqual(uploaded.revision, 5)
        XCTAssertEqual(try fixture.store.loadProgress(), local)
        XCTAssertFalse(try fixture.store.loadSyncMetadata().hasPendingChanges)
    }

    func testLocalResultConvergesWithoutPendingMetadata() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let completed = result(words: ["stone"])
        try fixture.store.save(history(completed))
        let remote = TestDailyRemote(userID: userID)

        let status = try await fixture.engine(remote: remote).synchronize()

        XCTAssertEqual(status, .synced(fixture.syncDate))
        let storedCount = await remote.storedResultCount()
        XCTAssertEqual(storedCount, 1)
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [completed])
        XCTAssertFalse(try fixture.store.loadSyncMetadata().hasPendingChanges)
    }

    func testCrashBetweenHistoryAndProgressWritesStillConverges() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let completed = result(words: ["civic", "stone"])
        try fixture.store.save(history(completed))
        try fixture.store.save(progress(words: ["civic"]))
        let remote = TestDailyRemote(userID: userID)

        let status = try await fixture.engine(remote: remote).synchronize()

        XCTAssertEqual(status, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), DailyClassicProgress(result: completed))
        let crashStoredCount = await remote.storedResultCount()
        XCTAssertEqual(crashStoredCount, 1)
        XCTAssertFalse(try fixture.store.loadSyncMetadata().hasPendingChanges)
    }

    func testExplicitlyIgnoredResultIsNotReuploaded() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = result(words: ["stone"])
        let cloud = result(words: ["civic", "stone"])
        try fixture.store.save(history(local))
        let firstRemote = TestDailyRemote(
            userID: userID,
            results: [cloud.puzzleID: resultDTO(cloud, userID: userID)]
        )
        let engine = fixture.engine(remote: firstRemote)
        guard case .conflict(let conflicts) = try await engine.synchronize() else {
            return XCTFail("Expected an immutable-result conflict")
        }
        try await engine.resolve(try engine.choice(for: conflicts[0]), with: .keepDevice)

        let secondRemote = TestDailyRemote(userID: userID)
        let retry = try await fixture.engine(remote: secondRemote).synchronize()

        XCTAssertEqual(retry, .synced(fixture.syncDate))
        let retryImportCalls = await secondRemote.importCallCount()
        let retryStoredCount = await secondRemote.storedResultCount()
        XCTAssertEqual(retryImportCalls, 0)
        XCTAssertEqual(retryStoredCount, 0)
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [local])
    }

    func testNewResultArrivingDuringSuspendedUploadIsNotDropped() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let first = result(words: ["stone"])
        let second = result(day: day + 1, words: ["civic"])
        try fixture.store.save(history(first))
        let remote = GateRemote(userID: userID)
        let engine = fixture.engine(remote: remote)
        try await engine.markResultPending(first.puzzleID)

        let syncTask = Task { try await engine.synchronize() }
        guard await Self.waitForImportSuspension(remote) else { return }
        var combined = try fixture.store.loadHistory()
        XCTAssertTrue(combined.record(second))
        try fixture.store.save(combined)
        let importUpload = await remote.lastImportUpload()
        let upload = try XCTUnwrap(importUpload)
        await remote.completeImport(with: .stored(remote.storedResult(for: upload)))

        let importStatus = try await syncTask.value
        XCTAssertEqual(importStatus, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [first, second])
        let uploadedIDs = await remote.importedPuzzleIDs
        XCTAssertEqual(uploadedIDs, [first.puzzleID])
        XCTAssertFalse(try fixture.store.loadSyncMetadata().hasPendingChanges)
    }

    @MainActor
    func testGameplayWriteDuringSuspendedPushIsNeitherOverwrittenNorCleared() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        try fixture.store.save(progress(words: ["civic"]))
        let suite = "GridRaceSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try DailyClassicModel(
            pack: dailyPack(),
            store: fixture.store,
            defaults: defaults,
            now: { self.fixedDate(100) }
        )
        let remote = GateRemote(userID: userID)
        let engine = fixture.engine(remote: remote)
        try engine.markProgressPending()

        let syncTask = Task { try await engine.synchronize() }
        guard await Self.waitForPushSuspension(remote) else { return }
        for letter in "stone" { model.typeLetter(letter) }
        model.submitGuess()
        let advanced = model.game.progress
        let pushUpload = await remote.lastPushUpload()
        let upload = try XCTUnwrap(pushUpload)
        await remote.completePush(with: .stored(remote.storedProgress(for: upload, revision: 1)))

        let pushStatus = try await syncTask.value
        XCTAssertEqual(pushStatus, .synced(fixture.syncDate))
        XCTAssertEqual(try fixture.store.loadProgress(), advanced)
        XCTAssertTrue(try fixture.store.loadSyncMetadata().pendingProgress)
    }

    func testCancellationAfterRemoteCompletionPerformsNoLocalWrites() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let initial = progress(words: ["civic"], draft: "AB")
        try fixture.store.save(initial)
        let remote = GateRemote(userID: userID)
        let engine = fixture.engine(remote: remote)
        try await engine.markProgressPending()

        let syncTask = Task { try await engine.synchronize() }
        guard await Self.waitForPushSuspension(remote) else { return }
        syncTask.cancel()
        let cancelledUpload = await remote.lastPushUpload()
        let upload = try XCTUnwrap(cancelledUpload)
        let longer = remote.advancedProgress(for: upload, appending: ["stone", "crane"], revision: 2)
        await remote.completePush(with: .serverAhead(longer))

        do {
            _ = try await syncTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertEqual(try fixture.store.loadProgress(), initial)
        XCTAssertTrue(try fixture.store.loadSyncMetadata().pendingProgress)
    }

    func testInvalidatedSyncCannotRecreateDeletedCache() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        try fixture.store.save(progress(words: ["civic"]))
        let remote = GateRemote(userID: userID)
        let engine = fixture.engine(remote: remote)
        try await engine.markProgressPending()

        let syncTask = Task { try await engine.synchronize() }
        guard await Self.waitForPushSuspension(remote) else { return }
        // Force deletion at the exact point where the old check-then-write code
        // would have performed three writes (history, progress snapshot,
        // metadata) for this response. Every one of them now runs inside the
        // lifecycle lock, so each must throw instead of recreating state.
        fixture.lifecycle.invalidate()
        try fixture.store.deleteAccountCache()
        let completedUpload = DailyImportedResultUploadDTO(result(words: ["civic", "stone"]))
        await remote.completePush(with: .completed(remote.storedResult(for: completedUpload)))

        do {
            _ = try await syncTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.directory.path))
        XCTAssertTrue(try fixture.store.loadHistory().completedResults.isEmpty)
        XCTAssertEqual(try fixture.store.loadSyncMetadata(), DailySyncMetadata())
    }

    func testMarksAfterInvalidationThrowInsteadOfRecreatingCache() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        fixture.lifecycle.invalidate()
        try fixture.store.deleteAccountCache()
        let engine = fixture.engine(remote: GateRemote(userID: userID))

        await XCTAssertThrowsCancellation(try await engine.markProgressPending())
        await XCTAssertThrowsCancellation(try await engine.markResultPending("puzzle"))
        await XCTAssertThrowsCancellation(try await engine.markAllLocalDataPending())

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.directory.path))
    }

    func testAccountSwitchInvalidatesStaleSyncWhileNewSyncProceeds() async throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let completed = result(words: ["stone"])
        try fixture.store.save(history(completed))
        let gated = GateRemote(userID: userID)
        let staleEngine = fixture.engine(remote: gated)
        try await staleEngine.markResultPending(completed.puzzleID)

        let staleTask = Task { try await staleEngine.synchronize() }
        guard await Self.waitForImportSuspension(gated) else { return }
        fixture.lifecycle.invalidate()

        let liveRemote = TestDailyRemote(userID: userID)
        let liveEngine = DailySyncEngine(
            userID: userID,
            store: fixture.store,
            remote: liveRemote,
            now: { fixture.syncDate }
        )
        let liveStatus = try await liveEngine.synchronize()
        XCTAssertEqual(liveStatus, .synced(fixture.syncDate))
        let gatedUpload = await gated.lastImportUpload()
        let upload = try XCTUnwrap(gatedUpload)
        await gated.completeImport(with: .stored(gated.storedResult(for: upload)))

        do {
            _ = try await staleTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertEqual(try fixture.store.loadHistory().completedResults, [completed])
        let liveStoredCount = await liveRemote.storedResultCount()
        XCTAssertEqual(liveStoredCount, 1)
    }

    // MARK: - U-07 remediation regression (GR-09)

    func testImportedResultsPaginationReturns1001ResultsExactlyOnceInStableOrder() async throws {
        let total = 1_001
        let pageSize = 1_000
        var rows: [DailyImportedResultDTO] = []
        rows.reserveCapacity(total)
        for index in 0..<total {
            let puzzleDay = day + index / 2
            rows.append(DailyImportedResultDTO(
                userID: userID,
                puzzleID: "\(puzzleID(day: puzzleDay))-\(String(format: "%04d", index))",
                puzzleNumber: index + 1,
                puzzleDay: puzzleDay,
                wordPackID: "daily-classic-en-US-v1",
                scheduleVersion: 1,
                hardModeEnabled: false,
                guesses: [],
                outcome: .solved,
                guessCount: 0,
                clientCompletedAt: fixedDate(100),
                serverImportedAt: fixedDate(600)
            ))
        }
        let expected = rows.sorted {
            if $0.puzzleDay != $1.puzzleDay { return $0.puzzleDay < $1.puzzleDay }
            return $0.puzzleID < $1.puzzleID
        }
        let store = PaginatedResultsStore(rows: expected)
        let client = SupabaseClient(
            supabaseURL: URL(string: "http://127.0.0.1:54321")!,
            supabaseKey: "test-key"
        )
        let remote = SupabaseDailySyncRemote(
            client: client,
            pageSize: pageSize,
            fetchProgress: { _ in [] },
            fetchResultsPage: { cursor, limit in
                try await store.page(after: cursor, limit: limit)
            }
        )

        let snapshot = try await remote.pull()

        XCTAssertNil(snapshot.progress)
        XCTAssertEqual(snapshot.importedResults.count, total)
        XCTAssertEqual(snapshot.importedResults.map(\.puzzleID), expected.map(\.puzzleID))
        XCTAssertEqual(Set(snapshot.importedResults.map(\.puzzleID)).count, total)
        let calls = await store.calls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertNil(calls[0].cursor)
        XCTAssertEqual(calls[0].limit, pageSize)
        XCTAssertEqual(calls[1].cursor, DailyImportedResultsCursor(expected[pageSize - 1]))
        XCTAssertEqual(calls[1].limit, pageSize)
    }

    func testTargetedRemotePullPassesIdentityAndRejectsMismatchedResponses() async throws {
        let selected = progressDTO(progress(words: ["civic"]), userID: userID)
        let future = progressDTO(progress(day: day + 1, words: ["adore"]), userID: userID)
        let client = SupabaseClient(supabaseURL: URL(string: "http://127.0.0.1:54321")!, supabaseKey: "test-key")
        let matching = SupabaseDailySyncRemote(client: client,
            fetchProgress: { requested in
                XCTAssertEqual(requested, selected.puzzleID)
                return [selected]
            }, fetchResultsPage: { _, _ in [] })
        let snapshot = try await matching.pull(puzzleID: selected.puzzleID)
        XCTAssertEqual(snapshot.progress, selected)
        let mismatched = SupabaseDailySyncRemote(client: client,
            fetchProgress: { _ in [future] }, fetchResultsPage: { _, _ in [] })
        do {
            _ = try await mismatched.pull(puzzleID: selected.puzzleID)
            XCTFail("A targeted query cannot silently return another puzzle")
        } catch let error as DailySyncRemoteError { XCTAssertEqual(error, .invalidData) }
    }

    @MainActor
    func testDeferredProgressChoiceProtectsNextDayAndRefreshesAdvancedSameDay() throws {
        for resolution in [DailyProgressConflictResolution.keepDevice, .useCloud] {
            let fixture = SyncFixture(userID: userID)
            defer { fixture.remove() }
            let local = progress(words: ["crane"])
            let cloud = progress(words: ["civic"])
            try fixture.store.save(local)
            let engine = fixture.engine(remote: TestDailyRemote(userID: userID))
            let conflict = DailySyncConflict.progress(puzzleID: local.puzzleID, local: local, cloud: cloud)
            let preview = try engine.choice(for: conflict)
            let newer = progress(day: day + 1, words: ["civic"])
            try fixture.store.save(newer)
            XCTAssertEqual(try engine.resolve(preview, with: resolution), .noLongerApplicable)
            XCTAssertEqual(try fixture.store.loadProgress(), newer)
            try fixture.store.save(local)
            let advanced = progress(words: ["crane", "civic"])
            try fixture.store.save(advanced)
            guard case .refreshed(let fresh) = try engine.resolve(preview, with: resolution) else {
                return XCTFail("Advancement requires fresh consent")
            }
            XCTAssertNotEqual(fresh.id, preview.id)
            XCTAssertEqual(try fixture.store.loadProgress(), advanced)
            XCTAssertEqual(try engine.resolve(fresh, with: resolution), .applied)
            XCTAssertEqual(try fixture.store.loadProgress(), resolution == .useCloud ? cloud : advanced)
        }
    }

    @MainActor
    func testGuestChoiceUsesAccountBasisAndPreservesGuestOnRefresh() throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let guest = progress(words: ["crane"])
        let account = progress(words: ["civic"])
        try fixture.store.save(account)
        let engine = fixture.engine(remote: TestDailyRemote(userID: userID))
        let conflict = DailySyncConflict.progress(puzzleID: guest.puzzleID, local: guest, cloud: account)
        let preview = try engine.choice(for: conflict, isGuestImport: true)
        let advanced = progress(words: ["civic", "crane"])
        try fixture.store.save(advanced)
        guard case .refreshed(let fresh) = try engine.resolve(preview, with: .keepDevice),
              case .progress(_, let shownGuest, let shownAccount) = fresh.conflict else {
            return XCTFail("Expected refreshed import")
        }
        XCTAssertEqual(shownGuest, guest)
        XCTAssertEqual(shownAccount, advanced)
        XCTAssertEqual(try engine.resolve(fresh, with: .keepDevice), .applied)
        XCTAssertEqual(try fixture.store.loadProgress(), guest, "Unchanged preview permits deliberate replacement")
    }

    @MainActor
    func testTerminalDeferredProgressBranchesCannotOverwriteNextDaySlot() throws {
        for terminalOnLocal in [false, true] {
            for resolution in [DailyProgressConflictResolution.keepDevice, .useCloud] {
                let fixture = SyncFixture(userID: userID)
                defer { fixture.remove() }
                let completed = result(words: ["stone"])
                let terminal = DailyClassicProgress(result: completed)
                let active = progress(words: ["civic"])
                let local = terminalOnLocal ? terminal : active
                let cloud = terminalOnLocal ? active : terminal
                try fixture.store.save(local)
                if terminalOnLocal { try fixture.store.save(history(completed)) }
                let engine = fixture.engine(remote: TestDailyRemote(userID: userID))
                let preview = try engine.choice(for: .progress(puzzleID: active.puzzleID, local: local, cloud: cloud))
                let newer = progress(day: day + 1, words: ["crane"])
                try fixture.store.save(newer)
                XCTAssertEqual(try engine.resolve(preview, with: resolution), .noLongerApplicable)
                XCTAssertEqual(try fixture.store.loadProgress(), newer)
            }
        }
    }

    @MainActor
    func testResolveMetadataFailureRetriesWithoutLosingSelectedBoard() throws {
        let fixture = SyncFixture(userID: userID)
        defer { fixture.remove() }
        let local = progress(words: ["crane"]), cloud = progress(words: ["civic"])
        try fixture.store.save(local)
        let engine = fixture.engine(remote: TestDailyRemote(userID: userID))
        let preview = try engine.choice(for: .progress(puzzleID: local.puzzleID, local: local, cloud: cloud))
        let metadataURL = fixture.store.directory.appending(path: "daily-sync-metadata-v1.json")
        try fixture.store.save(DailySyncMetadata())
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: metadataURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadataURL.path) }
        XCTAssertThrowsError(try engine.resolve(preview, with: .useCloud))
        XCTAssertEqual(try fixture.store.loadProgress(), cloud, "Progress succeeds before metadata fails")
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: metadataURL.path)
        XCTAssertEqual(try engine.resolve(preview, with: .useCloud), .applied)
        XCTAssertEqual(try fixture.store.loadProgress(), cloud)
    }

    @MainActor
    func testCoordinatorClockSelectsGuestAndAccountDayAndProtectsDelayedImportAfterRollover() async throws {
        let pack = try DailyWordPack.load(from: JSONSerialization.data(withJSONObject: [
            "formatVersion": 1, "id": "daily-classic-en-US-v1", "scheduleVersion": 1,
            "locale": "en-US", "wordLength": 5, "epochDay": day,
            "acceptedGuesses": ["adore", "civic", "stone"],
            "answers": ["civic", "stone", "adore"]
        ]))
        for useCloud in [false, true] {
            let root = temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let guest = DailyClassicStore(directory: root.appending(path: "Guest"))
            let accountStore = AccountDailyClassicStore(rootDirectory: root, userID: userID)
            var clock = date(day: day + 1, seconds: 100)
            let initialPuzzle = try DailyPuzzleSchedule.puzzle(at: clock, in: pack)
            var guestGame = DailyClassicGame(puzzle: initialPuzzle, acceptedWords: Set(pack.acceptedGuesses))
            var accountGame = guestGame
            for letter in "adore" { guestGame.type(letter) }
            for letter in "civic" { accountGame.type(letter) }
            XCTAssertNil(guestGame.submit(at: clock).error)
            XCTAssertNil(accountGame.submit(at: clock).error)
            try guest.save(guestGame.progress)
            let historicalDate = date(day: day, seconds: 100)
            let historicalPuzzle = try DailyPuzzleSchedule.puzzle(at: historicalDate, in: pack)
            var historicalGame = DailyClassicGame(puzzle: historicalPuzzle, acceptedWords: Set(pack.acceptedGuesses))
            for letter in historicalPuzzle.answer { historicalGame.type(letter) }
            XCTAssertNil(historicalGame.submit(at: historicalDate).error)
            try guest.save(history(try XCTUnwrap(historicalGame.completedResult)))
            try accountStore.save(accountGame.progress)
            let remote = TestDailyRemote(userID: userID,
                progress: progressDTO(accountGame.progress, userID: userID, revision: 1))
            let coordinator = try DailyAccountCoordinator(
                dailyPack: pack, tutorialPack: WordPack.load(bundle: .main), guestStore: guest,
                accountService: nil, dailyRemoteFactory: { _ in remote },
                accountStoreFactory: { AccountDailyClassicStore(rootDirectory: root, userID: $0) },
                liveStoreFactory: { LiveMatchRecoveryStore(rootDirectory: root, userID: $0) },
                now: { clock })
            XCTAssertEqual(coordinator.daily.puzzle, initialPuzzle)
            XCTAssertEqual(coordinator.daily.game.progress, guestGame.progress)
            coordinator.sessionChanged(to: userID)
            XCTAssertEqual(coordinator.daily.puzzle, initialPuzzle)
            XCTAssertEqual(coordinator.daily.game.progress, accountGame.progress)
            await waitForClockCondition { if case .synced = coordinator.syncStatus { true } else { false } }
            coordinator.importGuestHistory()
            await waitForClockCondition { coordinator.firstConflictID != nil }
            let oldChoice = try XCTUnwrap(coordinator.firstConflictID)
            let guestBefore = try guest.loadProgress()
            clock = date(day: day + 2, seconds: 100)
            // Exercise the same owner method called by the actual scenePhase path.
            coordinator.foregrounded()
            let nextPuzzle = try DailyPuzzleSchedule.puzzle(at: clock, in: pack)
            XCTAssertEqual(coordinator.daily.puzzle, nextPuzzle)
            XCTAssertTrue(coordinator.daily.game.rows.isEmpty)
            for letter in "civic" { coordinator.daily.typeLetter(letter) }
            coordinator.daily.submitGuess()
            await waitForClockCondition { if case .conflict = coordinator.syncStatus { true } else { false } }
            XCTAssertEqual(coordinator.daily.game.rows.count, 1)
            XCTAssertEqual(coordinator.daily.game.progress.acceptedGuesses.first?.acceptedAt, clock)
            XCTAssertEqual(coordinator.firstConflictID, oldChoice, "Pending import consent survives ordinary next-day play")
            let nextProgress = try XCTUnwrap(accountStore.loadProgress())
            coordinator.resolveConflict(id: oldChoice, useCloud: useCloud)
            await waitForClockCondition { coordinator.firstConflictID != oldChoice }
            XCTAssertEqual(try accountStore.loadProgress(), nextProgress)
            XCTAssertEqual(coordinator.daily.game.progress, nextProgress)
            XCTAssertEqual(try guest.loadProgress(), guestBefore)
            await waitForClockCondition { if case .synced = coordinator.syncStatus { true } else { false } }
            func guestFiles() throws -> [String: Data] {
                let names = try FileManager.default.contentsOfDirectory(atPath: guest.directory.path)
                return try Dictionary(uniqueKeysWithValues: names.map {
                    ($0, try Data(contentsOf: guest.directory.appending(path: $0)))
                })
            }
            let guestBytes = try guestFiles()
            let restoreService = AccountServiceMock()
            restoreService.restoredSession = AccountSession(userID: userID, expiresAt: .distantFuture)
            let cold = try DailyAccountCoordinator(
                dailyPack: pack, tutorialPack: WordPack.load(bundle: .main), guestStore: guest,
                accountService: nil, accountModelService: restoreService,
                dailyRemoteFactory: { _ in remote },
                accountStoreFactory: { AccountDailyClassicStore(rootDirectory: root, userID: $0) },
                liveStoreFactory: { LiveMatchRecoveryStore(rootDirectory: root, userID: $0) },
                now: { clock })
            XCTAssertEqual(try guestFiles(), guestBytes,
                "A signed-in cold constructor must not roll over the inactive guest slot")
            await cold.start()
            await waitForClockCondition { if case .synced = cold.syncStatus { true } else { false } }
            XCTAssertEqual(cold.daily.game.progress, nextProgress)
            XCTAssertEqual(try accountStore.loadProgress(), nextProgress)
            XCTAssertEqual(try accountStore.loadSyncMetadata().guestImportDecision, .imported)
            XCTAssertEqual(try guestFiles(), guestBytes)
            coordinator.sessionChanged(to: nil)
            coordinator.foregrounded()
            XCTAssertEqual(coordinator.daily.puzzle, nextPuzzle, "Guest owner shares the injected clock after return")
        }
    }

    @MainActor
    private func waitForClockCondition(_ condition: @MainActor () -> Bool,
                                       file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for coordinator clock state", file: file, line: line)
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

    @discardableResult
    private static func waitForImportSuspension(_ remote: GateRemote) async -> Bool {
        for _ in 0..<1_000 {
            if await remote.isImportSuspended { return true }
            await Task.yield()
        }
        await remote.failImport()
        XCTFail("Timed out waiting for suspended result import")
        return false
    }

    @discardableResult
    private static func waitForPullSuspension(_ remote: GateRemote) async -> Bool {
        for _ in 0..<1_000 {
            if await remote.isPullSuspended { return true }
            await Task.yield()
        }
        await remote.completePull(with: DailyCloudSnapshot(progress: nil, importedResults: []))
        XCTFail("Timed out waiting for suspended targeted pull")
        return false
    }

    @discardableResult
    private static func waitForPushSuspension(_ remote: GateRemote) async -> Bool {
        for _ in 0..<1_000 {
            if await remote.isPushSuspended { return true }
            await Task.yield()
        }
        await remote.failPush()
        XCTFail("Timed out waiting for suspended progress push")
        return false
    }

    private func progress(day: Int? = nil, words: [String], draft: String = "", hardMode: Bool = false) -> DailyClassicProgress {
        let puzzleDay = day ?? self.day
        return DailyClassicProgress(
            puzzleID: puzzleID(day: puzzleDay),
            puzzleNumber: puzzleDay - self.day + 1,
            puzzleDay: puzzleDay,
            wordPackID: "daily-classic-en-US-v1",
            scheduleVersion: 1,
            hardModeEnabled: hardMode,
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

    private func result(day: Int? = nil, words: [String], hardMode: Bool = false) -> DailyCompletedResult {
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
            puzzleNumber: puzzleDay - self.day + 1,
            puzzleDay: puzzleDay,
            wordPackID: "daily-classic-en-US-v1",
            scheduleVersion: 1,
            hardModeEnabled: hardMode,
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

    private func dailyPack(answerCount: Int = 1) throws -> DailyWordPack {
        try DailyWordPack.load(from: JSONSerialization.data(withJSONObject: [
            "formatVersion": 1,
            "id": "daily-classic-en-US-v1",
            "scheduleVersion": 1,
            "locale": "en-US",
            "wordLength": 5,
            "epochDay": day,
            "acceptedGuesses": ["adore", "civic", "stone"],
            "answers": Array(["adore", "stone"].prefix(answerCount))
        ]))
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
    let lifecycle = DailySyncLifecycle()
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
        DailySyncEngine(
            userID: userID,
            store: store,
            remote: remote,
            now: { self.syncDate },
            lifecycle: lifecycle
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor TestDailyRemote: DailySyncRemote {
    private let userID: UUID
    private var progressByPuzzleID: [String: DailyProgressDTO]
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
        if let progress {
            progressByPuzzleID = [progress.puzzleID: progress]
        } else {
            progressByPuzzleID = [:]
        }
        self.results = results
    }

    func pull(puzzleID: String?) throws -> DailyCloudSnapshot {
        if pullFailures > 0 {
            pullFailures -= 1
            throw DailySyncRemoteError.unavailable
        }
        let selectedProgress: DailyProgressDTO?
        if let puzzleID { selectedProgress = progressByPuzzleID[puzzleID] }
        else { selectedProgress = currentProgress() }
        return DailyCloudSnapshot(
            progress: selectedProgress,
            importedResults: results.values.sorted { $0.puzzleDay < $1.puzzleDay }
        )
    }

    func pushProgress(_ upload: DailyProgressUploadDTO) throws -> DailyProgressPushOutcome {
        if let completed = results[upload.puzzleID] {
            return .completed(completed)
        }
        guard let existing = progressByPuzzleID[upload.puzzleID] else {
            let inserted = dto(upload, revision: 1)
            progressByPuzzleID[upload.puzzleID] = inserted
            return .stored(inserted)
        }
        guard sameIdentity(upload, existing) else { return .conflict(.progress(existing)) }
        let local = upload.guesses.map(\.domain)
        let cloud = existing.guesses.map(\.domain)
        let changesMode = upload.hardModeEnabled != existing.hardModeEnabled
        if changesMode && !cloud.isEmpty { return .conflict(.progress(existing)) }
        if !changesMode {
            if local == cloud { return .stored(existing) }
            if DailySyncReconciler.isPrefix(local, of: cloud) { return .serverAhead(existing) }
            guard DailySyncReconciler.isPrefix(cloud, of: local) else {
                return .conflict(.progress(existing))
            }
        }
        if let expected = upload.expectedRevision, expected != existing.revision {
            return .conflict(.progress(existing))
        }
        let advanced = dto(upload, revision: existing.revision + 1)
        progressByPuzzleID[upload.puzzleID] = advanced
        return .stored(advanced)
    }

    func importResult(_ upload: DailyImportedResultUploadDTO) throws -> DailyResultImportOutcome {
        imports += 1
        let incoming = dto(upload)
        if let existing = results[upload.puzzleID] {
            return existing.domain == incoming.domain
                ? .stored(existing)
                : .conflict(.result(existing))
        }
        progressByPuzzleID.removeValue(forKey: upload.puzzleID)
        results[upload.puzzleID] = incoming
        return .stored(incoming)
    }

    func failNextPull() { pullFailures += 1 }
    func currentProgress() -> DailyProgressDTO? {
        progressByPuzzleID.values.max { $0.puzzleDay < $1.puzzleDay }
    }
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

    private func sameIdentity(_ upload: DailyProgressUploadDTO, _ existing: DailyProgressDTO) -> Bool {
        upload.puzzleID == existing.puzzleID
            && upload.puzzleNumber == existing.puzzleNumber
            && upload.puzzleDay == existing.puzzleDay
            && upload.wordPackID == existing.wordPackID
            && upload.scheduleVersion == existing.scheduleVersion
    }
}

/// Controllable transport double for U-01 suspension races. Each mutating call
/// parks on a checked continuation until the test resumes it, so concurrent
/// writes, cancellation, or lifecycle invalidation land deterministically
/// while the request is in flight.
private actor GateRemote: DailySyncRemote {
    private let userID: UUID
    private let serverDate = Date(timeIntervalSince1970: 1_788_220_700)
    private var shouldSuspendPull = false
    private var pullContinuation: CheckedContinuation<DailyCloudSnapshot, Error>?
    private var importContinuation: CheckedContinuation<DailyResultImportOutcome, Error>?
    private var pushContinuation: CheckedContinuation<DailyProgressPushOutcome, Error>?
    private var lastImport: DailyImportedResultUploadDTO?
    private var lastPush: DailyProgressUploadDTO?
    private(set) var importCalls = 0
    private(set) var importedPuzzleIDs: [String] = []
    private(set) var pushCalls = 0

    var isPullSuspended: Bool { pullContinuation != nil }
    func suspendNextPull() { shouldSuspendPull = true }
    func completePull(with snapshot: DailyCloudSnapshot) {
        pullContinuation?.resume(returning: snapshot)
        pullContinuation = nil
    }
    func pushedProgress() -> DailyProgressUploadDTO? { lastPush }

    var isImportSuspended: Bool { importContinuation != nil }
    var isPushSuspended: Bool { pushContinuation != nil }

    init(userID: UUID) {
        self.userID = userID
    }

    func pull(puzzleID: String?) async throws -> DailyCloudSnapshot {
        if shouldSuspendPull {
            shouldSuspendPull = false
            return try await withCheckedThrowingContinuation { pullContinuation = $0 }
        }
        return DailyCloudSnapshot(progress: nil, importedResults: [])
    }

    func importResult(_ upload: DailyImportedResultUploadDTO) async throws -> DailyResultImportOutcome {
        importCalls += 1
        importedPuzzleIDs.append(upload.puzzleID)
        lastImport = upload
        return try await withCheckedThrowingContinuation { importContinuation = $0 }
    }

    func pushProgress(_ upload: DailyProgressUploadDTO) async throws -> DailyProgressPushOutcome {
        pushCalls += 1
        lastPush = upload
        return try await withCheckedThrowingContinuation { pushContinuation = $0 }
    }

    func completeImport(with outcome: DailyResultImportOutcome) {
        importContinuation?.resume(returning: outcome)
        importContinuation = nil
    }

    func completePush(with outcome: DailyProgressPushOutcome) {
        pushContinuation?.resume(returning: outcome)
        pushContinuation = nil
    }

    func failImport() {
        importContinuation?.resume(throwing: CancellationError())
        importContinuation = nil
    }

    func failPush() {
        pushContinuation?.resume(throwing: CancellationError())
        pushContinuation = nil
    }

    func lastImportUpload() -> DailyImportedResultUploadDTO? { lastImport }
    func lastPushUpload() -> DailyProgressUploadDTO? { lastPush }

    nonisolated func storedResult(for upload: DailyImportedResultUploadDTO) -> DailyImportedResultDTO {
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

    nonisolated func storedProgress(for upload: DailyProgressUploadDTO, revision: Int) -> DailyProgressDTO {
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

    nonisolated func advancedProgress(
        for upload: DailyProgressUploadDTO,
        appending words: [String],
        revision: Int
    ) -> DailyProgressDTO {
        var guesses = upload.guesses
        for (index, word) in words.enumerated() {
            guesses.append(DailyGuessDTO(DailyGuess(
                word: word,
                feedback: Array(repeating: .absent, count: 5),
                acceptedAt: Date(timeIntervalSince1970: TimeInterval(1_788_220_000 + index))
            )))
        }
        return DailyProgressDTO(
            userID: userID,
            puzzleID: upload.puzzleID,
            puzzleNumber: upload.puzzleNumber,
            puzzleDay: upload.puzzleDay,
            wordPackID: upload.wordPackID,
            scheduleVersion: upload.scheduleVersion,
            hardModeEnabled: upload.hardModeEnabled,
            guesses: guesses,
            revision: revision,
            serverUpdatedAt: serverDate
        )
    }
}

/// In-memory page server for the GR-09 pagination proof. After the first page it
/// inserts an older row, reproducing the drift that offset pagination permits.
private actor PaginatedResultsStore {
    private var rows: [DailyImportedResultDTO]
    private var recorded: [(cursor: DailyImportedResultsCursor?, limit: Int)] = []

    init(rows: [DailyImportedResultDTO]) {
        self.rows = rows
    }

    func page(after cursor: DailyImportedResultsCursor?, limit: Int) throws -> [DailyImportedResultDTO] {
        recorded.append((cursor: cursor, limit: limit))
        guard limit > 0 else {
            throw DailySyncRemoteError.unavailable
        }
        let page = rows.filter {
            guard let cursor else { return true }
            return cursor.precedes(DailyImportedResultsCursor($0))
        }.prefix(limit)
        if cursor == nil, let first = rows.first {
            rows.insert(DailyImportedResultDTO(
                userID: first.userID,
                puzzleID: "daily-classic-0000-00-00",
                puzzleNumber: 0,
                puzzleDay: first.puzzleDay - 1,
                wordPackID: first.wordPackID,
                scheduleVersion: first.scheduleVersion,
                hardModeEnabled: false,
                guesses: [],
                outcome: .solved,
                guessCount: 0,
                clientCompletedAt: first.clientCompletedAt,
                serverImportedAt: first.serverImportedAt
            ), at: 0)
        }
        return Array(page)
    }

    func calls() -> [(cursor: DailyImportedResultsCursor?, limit: Int)] { recorded }
}
