import Foundation
import Observation
import XCTest
@testable import GridRace

@MainActor
final class LiveMatchRecoveryStoreTests: XCTestCase {
    func testRecoveryIsAccountScopedAndStoresOnlyPointerAndPendingIntent() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceLiveRecoveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstUser = UUID()
        let secondUser = UUID()
        let matchID = UUID()
        let requestID = UUID()
        let first = LiveMatchRecoveryStore(rootDirectory: root, userID: firstUser)
        let second = LiveMatchRecoveryStore(rootDirectory: root, userID: secondUser)
        let state = LiveRecoveryState(
            matchID: matchID,
            pendingIntent: .guess(matchID: matchID, requestID: requestID, word: "STONE")
        )

        try first.save(state)

        XCTAssertEqual(try first.load(), state)
        XCTAssertEqual(try second.load(), LiveRecoveryState())
        let data = try Data(contentsOf: first.directory.appending(path: "live-recovery-v1.json"))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("STONE"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("bearer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("answer"))
        try first.clear()
        XCTAssertEqual(try first.load(), LiveRecoveryState())
    }

    func testLegacyFilesDecodeExactPayloadAndMigrateInTheSameProtectedPath() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceV1Migration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        let other = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        let match = UUID(), request = UUID()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appending(path: "live-recovery-v1.json")
        for kind in ["pointer", "create", "guess"] {
            var json: [String: Any] = ["formatVersion": 1]
            if kind != "create" { json["matchID"] = match.uuidString }
            if kind == "create" { json["pendingIntent"] = ["kind": "create", "requestID": request.uuidString] }
            if kind == "guess" {
                json["pendingIntent"] = ["kind": "guess", "matchID": match.uuidString,
                                         "requestID": request.uuidString, "word": "STONE"]
            }
            let original = try JSONSerialization.data(withJSONObject: json)
            try original.write(to: file)
            var state = try store.load()
            XCTAssertEqual(state.formatVersion, 1)
            XCTAssertEqual(try Data(contentsOf: file), original, "load itself must not destroy legacy evidence")
            if kind == "create" {
                XCTAssertEqual(state.pendingIntent, .create(requestID: request, roundCount: 1, clientBuild: 1))
            } else if kind == "guess" {
                XCTAssertEqual(state.pendingIntent, .guess(matchID: match, requestID: request, word: "STONE",
                                                           roundNumber: 1, clientBuild: 1))
            }
            state.formatVersion = 2
            try store.save(state)
            XCTAssertEqual(try store.load(), state)
            XCTAssertEqual(try other.load(), LiveRecoveryState())
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(saved["formatVersion"] as? Int, 2)
            try store.clear()
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testUnknownMissingAndInconsistentV2RecoveryPreservesOriginalBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceV2Invalid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appending(path: "live-recovery-v1.json")
        let match = UUID(), request = UUID()
        let cases: [[String: Any]] = [
            ["formatVersion": 99],
            ["formatVersion": 1, "pendingIntent": ["kind": "create", "requestID": request.uuidString,
                                                  "roundCount": 3, "clientBuild": 2]],
            ["formatVersion": 1, "matchID": match.uuidString,
             "pendingIntent": ["kind": "guess", "matchID": match.uuidString, "requestID": request.uuidString,
                               "word": "STONE", "roundNumber": 2]],
            ["formatVersion": 2, "pendingIntent": ["kind": "create", "requestID": request.uuidString]],
            ["formatVersion": 2, "matchID": match.uuidString,
             "pendingIntent": ["kind": "create", "requestID": request.uuidString, "roundCount": 3, "clientBuild": 2]],
            ["formatVersion": 2, "pendingIntent": ["kind": "create", "requestID": request.uuidString,
                                                  "roundCount": 3, "clientBuild": 1]],
            ["formatVersion": 2, "matchID": match.uuidString,
             "pendingIntent": ["kind": "guess", "matchID": match.uuidString, "requestID": request.uuidString,
                               "word": "STONE", "roundNumber": 2, "clientBuild": 1]],
            ["formatVersion": 2, "matchID": match.uuidString,
             "pendingIntent": ["kind": "guess", "matchID": UUID().uuidString, "requestID": request.uuidString,
                               "word": "STONE", "roundNumber": 2, "clientBuild": 2]],
        ]
        for object in cases {
            let original = try JSONSerialization.data(withJSONObject: object)
            try original.write(to: file)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testCorruptOrInconsistentRecoveryFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceLiveRecoveryCorrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":3}"#.utf8).write(
            to: store.directory.appending(path: "live-recovery-v1.json")
        )
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? LiveMatchRecoveryError, .invalidData)
        }
    }
}

@MainActor
final class LiveMatchSessionTests: XCTestCase {
    func testFailedJoinPreservesSavedPointerAndErrorUntilExplicitResume() async throws {
        for error in [LiveMatchServiceError.server(.matchNotJoinable), .unavailable,
                      .server(.internalError), .invalidResponse] {
            let oldMatchID = UUID()
            let oldState = LiveRecoveryState(matchID: oldMatchID)
            let store = MemoryLiveRecoveryStore(oldState)
            let realtime = RealtimeHub()
            let snapshots = LockedValues<UUID>()
            let joins = LockedValues<String>()
            let timers = LockedValues<Duration>()
            let timer = AsyncGate()
            let session = makeSession(
                service: LiveServiceMock(
                    join: { code in
                        joins.append(code)
                        XCTAssertEqual(try store.load(), oldState)
                        throw error
                    },
                    snapshot: { matchID in
                        snapshots.append(matchID)
                        return Self.snapshot(matchID: matchID, status: .lobby, round: .pending)
                    }
                ),
                realtime: realtime,
                store: store,
                timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77),
                              retryBackoff: [.seconds(5)]),
                sleep: { duration in
                    if duration == .seconds(99) {
                        try await Task.sleep(for: duration)
                    } else {
                        timers.append(duration)
                        await timer.wait()
                    }
                }
            )
            session.backgrounded()
            session.changeAccount(to: UUID())
            session.leaveToHome()
            session.foregrounded()

            session.joinMatch(code: "ABC234")
            await eventually { !session.isCommandInFlight }
            session.backgrounded()
            session.foregrounded()
            await Task.yield()
            XCTAssertFalse(session.canRetry)
            session.retry()
            await Task.yield()

            XCTAssertFalse(session.canRetry)
            XCTAssertEqual(session.lastError, error)
            XCTAssertEqual(session.phase, .unavailable)
            XCTAssertEqual(session.savedMatchID, oldMatchID)
            XCTAssertEqual(store.storedState, oldState)
            XCTAssertNil(session.snapshot)
            XCTAssertEqual(realtime.subscriptionCount, 0)
            XCTAssertEqual(joins.values, ["ABC234"])
            XCTAssertTrue(snapshots.values.isEmpty)
            XCTAssertTrue(timers.values.isEmpty)

            session.leaveToHome()
            XCTAssertFalse(session.canRetry)
            session.resumeSavedMatch()
            XCTAssertTrue(session.canRetry)
            XCTAssertEqual(realtime.subscriptionCount, 1)
            XCTAssertTrue(snapshots.values.isEmpty)
            realtime.send(.ready)
            await eventually { session.phase == .ready }
            XCTAssertEqual(snapshots.values, [oldMatchID])
            XCTAssertEqual(session.snapshot?.match.id, oldMatchID)
            session.leaveToHome()
            await timer.open()
        }
    }

    func testDelayedCreateSuccessPreservesHomeUntilExplicitResume() async throws {
        try await assertDelayedSuccessRespectsHome(isCreate: true)
    }

    func testDelayedJoinSuccessPreservesHomeUntilExplicitResume() async throws {
        try await assertDelayedSuccessRespectsHome(isCreate: false)
    }

    func testDelayedSavedPointerJoinSuccessRespectsHomeAndResumeDuringCommand() async throws {
        try await assertDelayedSuccessRespectsHome(isCreate: false, hasSavedPointer: true)
    }

    func testFailedJoinAfterResumeDuringCommandDoesNotRecoverOldPointer() async throws {
        for returnsHomeAgain in [false, true] {
            let oldState = LiveRecoveryState(matchID: UUID())
            let store = MemoryLiveRecoveryStore(oldState)
            let realtime = RealtimeHub()
            let completion = AsyncGate()
            let joins = LockedCounter()
            let snapshots = LockedCounter()
            let session = makeSession(
                service: LiveServiceMock(
                    join: { _ in
                        joins.increment()
                        await completion.wait()
                        throw LiveMatchServiceError.server(.matchNotJoinable)
                    },
                    snapshot: { id in
                        snapshots.increment()
                        return Self.snapshot(matchID: id, status: .lobby, round: .pending)
                    }
                ),
                realtime: realtime,
                store: store
            )
            session.backgrounded()
            session.changeAccount(to: UUID())
            session.leaveToHome()
            session.foregrounded()
            session.joinMatch(code: "ABC234")
            await eventually { joins.value == 1 }
            XCTAssertFalse(session.canRetry)
            session.retry()
            XCTAssertTrue(session.isCommandInFlight)
            XCTAssertEqual(session.phase, .recovering)
            XCTAssertEqual(realtime.subscriptionCount, 0)
            session.leaveToHome()
            session.resumeSavedMatch()
            if returnsHomeAgain { session.leaveToHome() }
            await completion.open()
            await eventually { !session.isCommandInFlight }

            XCTAssertEqual(session.lastError, .server(.matchNotJoinable))
            XCTAssertEqual(store.storedState, oldState)
            XCTAssertEqual(session.savedMatchID, oldState.matchID)
            XCTAssertEqual(realtime.subscriptionCount, 0)
            XCTAssertEqual(snapshots.value, 0)
            session.leaveToHome()
        }
    }

    func testJoinResolutionPersistenceFailureRetainsOldPointerAndBlocksRecovery() async throws {
        let oldState = LiveRecoveryState(matchID: UUID())
        let store = MemoryLiveRecoveryStore(oldState)
        let realtime = RealtimeHub()
        let snapshots = LockedCounter()
        let session = makeSession(
            service: LiveServiceMock(
                join: { _ in return UUID() },
                snapshot: { id in
                    snapshots.increment()
                    return Self.snapshot(matchID: id, status: .lobby, round: .pending)
                }
            ),
            realtime: realtime,
            store: store
        )
        session.backgrounded()
        session.changeAccount(to: UUID())
        session.leaveToHome()
        session.foregrounded()
        store.rejectsWrites = true

        session.joinMatch(code: "ABC234")
        await eventually { !session.isCommandInFlight }
        session.resumeSavedMatch()
        session.backgrounded()
        session.foregrounded()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canRetryRecoveryStorage)
        XCTAssertFalse(session.canRetry)
        XCTAssertEqual(session.savedMatchID, oldState.matchID)
        XCTAssertEqual(store.storedState, oldState)
        XCTAssertNil(session.snapshot)
        XCTAssertEqual(realtime.subscriptionCount, 0)
        XCTAssertEqual(snapshots.value, 0)
        store.rejectsWrites = false
        session.retry()
        XCTAssertEqual(realtime.subscribedMatchIDs, [oldState.matchID!])
        XCTAssertEqual(snapshots.value, 0)
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        session.leaveToHome()
    }

    func testDelayedSavedPointerJoinCannotSelectRoomAfterAccountSwitch() async throws {
        let oldAccount = UUID()
        let newAccount = UUID()
        let oldStore = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: UUID()))
        let newStore = MemoryLiveRecoveryStore()
        let factory = MemoryLiveRecoveryStoreFactory([oldAccount: oldStore, newAccount: newStore])
        let realtime = RealtimeHub()
        let completion = AsyncGate()
        let joins = LockedCounter()
        let returns = LockedCounter()
        let session = LiveMatchSession(
            service: LiveServiceMock(join: { _ in
                joins.increment()
                await completion.wait()
                returns.increment()
                return UUID()
            }),
            realtime: realtime,
            storeFactory: factory.make
        )
        session.backgrounded()
        session.changeAccount(to: oldAccount)
        session.leaveToHome()
        session.foregrounded()
        session.joinMatch(code: "ABC234")
        await eventually { joins.value == 1 }

        XCTAssertEqual(session.changeAccount(to: newAccount), .completed)
        await completion.open()
        await eventually { returns.value == 1 }
        await Task.yield()
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertFalse(session.hasSavedMatch)
        XCTAssertEqual(oldStore.storedState, LiveRecoveryState())
        XCTAssertEqual(newStore.storedState, LiveRecoveryState())
        XCTAssertEqual(realtime.subscriptionCount, 0)
    }

    func testSavedPointerJoinSuccessInBackgroundWaitsForForegroundSubscription() async throws {
        let newMatchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: UUID()))
        let realtime = RealtimeHub()
        let completion = AsyncGate()
        let joins = LockedCounter()
        let snapshots = LockedValues<UUID>()
        let session = makeSession(
            service: LiveServiceMock(
                join: { _ in
                    joins.increment()
                    await completion.wait()
                    return newMatchID
                },
                snapshot: { id in
                    snapshots.append(id)
                    return Self.snapshot(matchID: id, status: .lobby, round: .pending)
                }
            ),
            realtime: realtime,
            store: store
        )
        session.backgrounded()
        session.changeAccount(to: UUID())
        session.leaveToHome()
        session.foregrounded()
        session.joinMatch(code: "ABC234")
        await eventually { joins.value == 1 }
        session.backgrounded()
        await completion.open()
        await eventually { !session.isCommandInFlight }

        XCTAssertEqual(store.storedState, LiveRecoveryState(matchID: newMatchID))
        XCTAssertEqual(realtime.subscriptionCount, 0)
        XCTAssertTrue(snapshots.values.isEmpty)
        session.foregrounded()
        XCTAssertEqual(realtime.subscribedMatchIDs, [newMatchID])
        XCTAssertTrue(snapshots.values.isEmpty)
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        XCTAssertEqual(snapshots.values, [newMatchID])
        session.leaveToHome()
    }

    func testVisibleJoinSubscribesBeforeCanonicalRecovery() async throws {
        let matchID = UUID()
        let oldMatchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: oldMatchID))
        let realtime = RealtimeHub()
        let snapshots = LockedCounter()
        let session = makeSession(
            service: LiveServiceMock(
                join: { code in
                    XCTAssertEqual(code, "ABC234")
                    return matchID
                },
                snapshot: { requestedID in
                    XCTAssertEqual(try store.load(), LiveRecoveryState(matchID: requestedID))
                    snapshots.increment()
                    return Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
                }
            ),
            realtime: realtime,
            store: store
        )
        session.backgrounded()
        session.changeAccount(to: UUID())
        session.leaveToHome()
        session.foregrounded()

        session.joinMatch(code: "ABC234")

        await eventually { !session.isCommandInFlight && realtime.subscriptionCount == 1 }
        XCTAssertEqual(session.savedMatchID, matchID)
        XCTAssertEqual(try store.load(), LiveRecoveryState(matchID: matchID))
        XCTAssertEqual(realtime.subscribedMatchIDs, [matchID])
        XCTAssertEqual(snapshots.value, 0)
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        XCTAssertEqual(session.snapshot?.match.id, matchID)
        XCTAssertEqual(snapshots.value, 1)
        session.leaveToHome()
    }

    private func assertDelayedSuccessRespectsHome(
        isCreate: Bool, hasSavedPointer: Bool = false
    ) async throws {
        // Cover Home, Resume during the command, and Home again after that Resume.
        for navigation in 0...2 {
            let matchID = UUID()
            let requestID = UUID()
            let oldState = hasSavedPointer ? LiveRecoveryState(matchID: UUID()) : LiveRecoveryState()
            let store = MemoryLiveRecoveryStore(oldState)
            let realtime = RealtimeHub()
            let completion = AsyncGate()
            let watchdog = AsyncGate()
            let creates = LockedValues<UUID>()
            let joins = LockedValues<String>()
            let snapshots = LockedCounter()
            let watchdogStarts = LockedCounter()
            let session = LiveMatchSession(
                service: LiveServiceMock(
                    create: { receivedID in
                        XCTAssertEqual(
                            try store.load(),
                            LiveRecoveryState(pendingIntent: .create(requestID: receivedID))
                        )
                        creates.append(receivedID)
                        await completion.wait()
                        return matchID
                    },
                    join: { code in
                        XCTAssertEqual(try store.load(), oldState)
                        joins.append(code)
                        await completion.wait()
                        return matchID
                    },
                    snapshot: { requestedID in
                        XCTAssertEqual(try store.load(), LiveRecoveryState(matchID: requestedID))
                        snapshots.increment()
                        return Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
                    }
                ),
                realtime: realtime,
                storeFactory: { _ in store },
                timing: .init(
                    requestTimeout: .seconds(99),
                    staleAfter: .seconds(77),
                    retryBackoff: [.seconds(5)]
                ),
                sleep: { duration in
                    if duration == .seconds(99) {
                        try await Task.sleep(for: duration)
                    } else {
                        watchdogStarts.increment()
                        await watchdog.wait()
                    }
                },
                makeUUID: { requestID }
            )
            session.backgrounded()
            session.changeAccount(to: UUID())
            session.leaveToHome()
            session.foregrounded()
            if isCreate {
                session.createMatch()
            } else {
                session.joinMatch(code: "ABC234")
            }
            await eventually { creates.values.count + joins.values.count == 1 }
            session.leaveToHome()
            if navigation > 0 {
                session.resumeSavedMatch()
                XCTAssertEqual(realtime.subscriptionCount, 0)
                if navigation == 2 { session.leaveToHome() }
            }
            await completion.open()
            await eventually { !session.isCommandInFlight }

            XCTAssertEqual(session.savedMatchID, matchID)
            XCTAssertEqual(try store.load(), LiveRecoveryState(matchID: matchID))
            XCTAssertNil(session.pendingIntent)
            XCTAssertNil(session.snapshot)
            XCTAssertEqual(snapshots.value, 0)
            XCTAssertEqual(watchdogStarts.value, 0)
            let resumedInFlight = (isCreate || hasSavedPointer) && navigation == 1
            XCTAssertEqual(session.phase, resumedInFlight ? .recovering : .inactive)
            XCTAssertEqual(realtime.subscriptionCount, resumedInFlight ? 1 : 0)

            if !resumedInFlight { session.resumeSavedMatch() }
            await eventually { realtime.subscriptionCount == 1 }
            XCTAssertEqual(realtime.subscribedMatchIDs, [matchID])
            realtime.send(.ready)
            await eventually { session.phase == .ready && watchdogStarts.value == 1 }
            XCTAssertEqual(session.snapshot?.match.id, matchID)
            XCTAssertEqual(snapshots.value, 1)
            XCTAssertEqual(creates.values, isCreate ? [requestID] : [])
            XCTAssertEqual(joins.values, isCreate ? [] : ["ABC234"])
            session.leaveToHome()
            await watchdog.open()
        }
    }

    func testCreateReplacesSavedMatchWithCreateIntentBeforeDispatch() async throws {
        let oldMatchID = UUID()
        let newMatchID = UUID()
        let requestID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: oldMatchID))
        let persistedAtDispatch = LockedValues<LiveRecoveryState>()
        let service = LiveServiceMock(create: { _ in
            persistedAtDispatch.append(try store.load())
            return newMatchID
        })
        let session = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { _ in store },
            makeUUID: { requestID }
        )
        session.changeAccount(to: UUID())
        session.leaveToHome()

        session.createMatch()

        await eventually { session.savedMatchID == newMatchID }
        XCTAssertEqual(
            persistedAtDispatch.values,
            [LiveRecoveryState(pendingIntent: .create(requestID: requestID))]
        )
    }

    func testCreateRestoresSavedMatchWhenReplacementPersistenceFails() async throws {
        let oldState = LiveRecoveryState(matchID: UUID())
        let store = MemoryLiveRecoveryStore(oldState)
        let creates = LockedCounter()
        let session = makeSession(
            service: LiveServiceMock(create: { _ in
                creates.increment()
                return UUID()
            }),
            realtime: nil,
            store: store
        )
        session.changeAccount(to: UUID())
        session.leaveToHome()
        store.rejectsWrites = true

        session.createMatch()
        await Task.yield()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(session.savedMatchID, oldState.matchID)
        XCTAssertNil(session.pendingIntent)
        XCTAssertEqual(store.storedState, oldState)
        XCTAssertEqual(creates.value, 0)
    }

    func testCreateResolutionStorageFailureRequiresExplicitRetryWithOriginalID() async throws {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore()
        let realtime = RealtimeHub()
        let attempts = LockedValues<UUID>()
        let snapshots = LockedCounter()
        let retrySleeps = LockedCounter()
        let retryGate = AsyncGate()
        let session = makeSession(
            service: LiveServiceMock(
                create: { requestID in
                    XCTAssertEqual(
                        store.storedState,
                        LiveRecoveryState(pendingIntent: .create(requestID: requestID))
                    )
                    attempts.append(requestID)
                    store.rejectsWrites = attempts.values.count <= 2
                    return matchID
                },
                snapshot: { id in
                    snapshots.increment()
                    return Self.snapshot(matchID: id, status: .lobby, round: .pending)
                }
            ),
            realtime: realtime,
            store: store,
            timing: .init(
                requestTimeout: .seconds(99),
                staleAfter: .seconds(77),
                retryBackoff: [.seconds(5)]
            ),
            sleep: { duration in
                if duration == .seconds(5) {
                    retrySleeps.increment()
                    await retryGate.wait()
                } else {
                    try await Task.sleep(for: duration)
                }
            }
        )
        session.changeAccount(to: UUID())
        session.createMatch()
        await eventually { !session.isCommandInFlight }
        let requestID = try XCTUnwrap(attempts.values.first)
        let original = LiveRecoveryState(pendingIntent: .create(requestID: requestID))
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertNil(session.lastError)
        XCTAssertTrue(session.canRetryRecoveryStorage)
        XCTAssertFalse(session.canRetry)
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertEqual(store.storedState, original)
        XCTAssertEqual(session.pendingIntent, original.pendingIntent)
        XCTAssertNil(session.savedMatchID)
        XCTAssertEqual(retrySleeps.value, 0)
        await retryGate.open()

        session.createMatch()
        session.joinMatch(code: "ABC234")
        session.startMatch()
        session.submitGuess("STONE")
        session.resumeSavedMatch()
        session.backgrounded()
        session.foregrounded()
        await Task.yield()
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(attempts.values, [requestID])
        XCTAssertEqual(realtime.subscriptionCount, 0)
        XCTAssertEqual(snapshots.value, 0)

        // A retry whose acknowledgement still cannot be saved must latch again.
        session.retry()
        await eventually { !session.isCommandInFlight }
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(attempts.values, [requestID, requestID])
        XCTAssertEqual(store.storedState, original)
        XCTAssertEqual(retrySleeps.value, 0)

        session.retry()
        await eventually { !session.isCommandInFlight && realtime.subscriptionCount == 1 }
        XCTAssertEqual(attempts.values, [requestID, requestID, requestID])
        XCTAssertEqual(store.storedState, LiveRecoveryState(matchID: matchID))
        XCTAssertNil(session.pendingIntent)
        XCTAssertNil(session.snapshot)
        XCTAssertEqual(snapshots.value, 0)
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        XCTAssertEqual(session.snapshot?.match.id, matchID)
        XCTAssertEqual(snapshots.value, 1)
        session.leaveToHome()
    }

    func testCreateResolutionStorageFailureCanBeDiscardedWithoutStaleReplay() async throws {
        let accountID = UUID()
        let store = MemoryLiveRecoveryStore()
        let attempts = LockedValues<UUID>()
        let service = LiveServiceMock(create: { requestID in
            attempts.append(requestID)
            store.rejectsWrites = true
            return UUID()
        })
        let session = makeSession(service: service, realtime: nil, store: store)
        session.changeAccount(to: accountID)
        session.createMatch()
        await eventually { !session.isCommandInFlight }
        let requestID = try XCTUnwrap(attempts.values.first)
        let original = LiveRecoveryState(pendingIntent: .create(requestID: requestID))
        store.rejectsClears = true
        session.discardRecovery()
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertEqual(store.storedState, original)

        store.rejectsClears = false
        session.discardRecovery()
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertFalse(session.hasSavedMatch)
        XCTAssertEqual(store.storedState, LiveRecoveryState())
        session.changeAccount(to: nil)
        session.changeAccount(to: accountID)
        session.resumeSavedMatch()
        session.backgrounded()
        session.foregrounded()
        let relaunched = makeSession(service: service, realtime: nil, store: store)
        relaunched.changeAccount(to: accountID)
        await Task.yield()
        XCTAssertEqual(relaunched.phase, .inactive)
        XCTAssertFalse(relaunched.hasSavedMatch)
        XCTAssertEqual(attempts.values, [requestID])
    }

    func testGuessResponseStorageFailureBlocksRealtimeAndForegroundReplayUntilRetry() async throws {
        for rejectsGuess in [false, true] {
            let matchID = UUID()
            let requestID = UUID()
            let intent = LivePendingIntent.guess(matchID: matchID, requestID: requestID, word: "STONE")
            let original = LiveRecoveryState(matchID: matchID, pendingIntent: intent)
            let store = MemoryLiveRecoveryStore(original)
            let realtime = RealtimeHub()
            let attempts = LockedValues<UUID>()
            let snapshots = LockedCounter()
            let session = makeSession(
                service: LiveServiceMock(
                    submit: { _, receivedID, _ in
                        attempts.append(receivedID)
                        store.rejectsWrites = attempts.values.count == 1
                        if rejectsGuess { throw LiveMatchServiceError.server(.wordNotAccepted) }
                        return Self.receipt()
                    },
                    snapshot: { id in
                        snapshots.increment()
                        return Self.snapshot(matchID: id, status: .inProgress, round: .playing)
                    }
                ),
                realtime: realtime,
                store: store
            )
            session.changeAccount(to: UUID())
            await eventually { realtime.subscriptionCount == 1 }
            realtime.send(.ready)
            await eventually { !session.isCommandInFlight && attempts.values.count == 1 }
            XCTAssertEqual(session.phase, .storageUnavailable)
            XCTAssertEqual(store.storedState, original)
            XCTAssertEqual(session.pendingIntent, intent)
            XCTAssertTrue(session.isInputLocked)
            realtime.send(.ready)
            realtime.send(.signal)
            await Task.yield()
            XCTAssertEqual(session.phase, .storageUnavailable)
            XCTAssertEqual(attempts.values, [requestID])
            session.resumeSavedMatch()
            session.backgrounded()
            session.foregrounded()
            await Task.yield()
            XCTAssertEqual(session.phase, .storageUnavailable)
            XCTAssertEqual(attempts.values, [requestID])
            XCTAssertEqual(realtime.subscriptionCount, 1)
            XCTAssertEqual(snapshots.value, 0)

            session.retry()
            await eventually { realtime.subscriptionCount == 2 }
            XCTAssertEqual(attempts.values, [requestID])
            realtime.send(.ready)
            await eventually { session.phase == .ready }
            XCTAssertEqual(attempts.values, [requestID, requestID])
            XCTAssertNil(store.storedState.pendingIntent)
            XCTAssertEqual(store.storedState.matchID, matchID)
            XCTAssertEqual(snapshots.value, 1)
            session.leaveToHome()
        }
    }

    func testInFlightSnapshotCannotErasePendingGuessStorageFailure() async throws {
        for snapshotFails in [false, true] {
            let matchID = UUID()
            let intent = LivePendingIntent.guess(matchID: matchID, requestID: UUID(), word: "STONE")
            let original = LiveRecoveryState(matchID: matchID, pendingIntent: intent)
            let store = MemoryLiveRecoveryStore(original)
            let realtime = RealtimeHub()
            let snapshots = LockedCounter()
            let responseGate = AsyncGate()
            let responseReturned = LockedCounter()
            let session = makeSession(
                service: LiveServiceMock(
                    submit: { _, _, _ in throw LiveMatchServiceError.server(.requestConflict) },
                    snapshot: { id in
                        let call = snapshots.increment()
                        if call == 2 {
                            await responseGate.wait()
                            responseReturned.increment()
                            if snapshotFails { throw LiveMatchServiceError.unavailable }
                        }
                        return Self.snapshot(matchID: id, status: .inProgress, round: .playing)
                    }
                ),
                realtime: realtime,
                store: store,
                timing: .init(
                    requestTimeout: .seconds(99),
                    staleAfter: .seconds(77),
                    retryBackoff: [.seconds(50)]
                )
            )
            session.changeAccount(to: UUID())
            await eventually { realtime.subscriptionCount == 1 }
            realtime.send(.ready)
            await eventually { session.snapshot != nil && !session.isCommandInFlight }
            realtime.send(.signal)
            await eventually { snapshots.value == 2 }
            // Coalesce another signal before storage fails; it must not fetch afterward.
            realtime.send(.signal)
            await Task.yield()
            store.rejectsWrites = true
            session.discardPendingGuess()
            XCTAssertEqual(session.phase, .storageUnavailable)
            await responseGate.open()
            await eventually { responseReturned.value == 1 }
            await Task.yield()
            XCTAssertEqual(session.phase, .storageUnavailable)
            XCTAssertNil(session.lastError)
            XCTAssertEqual(store.storedState, original)
            XCTAssertEqual(session.pendingIntent, intent)
            XCTAssertTrue(session.canRetryRecoveryStorage)
            XCTAssertFalse(session.canRetry)
            XCTAssertEqual(snapshots.value, 2)
            session.leaveToHome()
        }
    }

    func testHomeResumeRetriesPendingCreateWithOriginalRequestID() async throws {
        let requestID = UUID()
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore()
        let creates = LockedValues<UUID>()
        let service = LiveServiceMock(
            create: { receivedRequestID in
                creates.append(receivedRequestID)
                if creates.values.count <= 2 { throw LiveMatchServiceError.unavailable }
                return matchID
            },
            snapshot: { requestedID in
                Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
            }
        )
        let session = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { _ in store },
            timing: .init(
                requestTimeout: .seconds(10),
                staleAfter: .seconds(5),
                retryBackoff: [.seconds(100)]
            ),
            makeUUID: { requestID }
        )
        session.changeAccount(to: UUID())

        session.createMatch()
        await eventually { session.phase == .unavailable && !session.isCommandInFlight }
        XCTAssertTrue(session.canRetry)
        session.retry()
        XCTAssertFalse(session.canRetry)
        await eventually { session.phase == .unavailable && !session.isCommandInFlight }
        XCTAssertEqual(creates.values, [requestID, requestID])
        session.leaveToHome()
        XCTAssertFalse(session.canRetry)

        XCTAssertTrue(session.hasSavedMatch)
        XCTAssertEqual(session.pendingIntent, .create(requestID: requestID))
        session.resumeSavedMatch()

        await eventually { session.phase == .ready }
        XCTAssertEqual(creates.values, [requestID, requestID, requestID])
        XCTAssertEqual(session.savedMatchID, matchID)
        XCTAssertNil(session.pendingIntent)
    }

    func testHomeResumeRecoversSavedMatchAndPendingGuess() async throws {
        for hasPendingGuess in [false, true] {
            let matchID = UUID()
            let requestID = UUID()
            let intent: LivePendingIntent? = hasPendingGuess
                ? .guess(matchID: matchID, requestID: requestID, word: "STONE") : nil
            let store = MemoryLiveRecoveryStore(
                LiveRecoveryState(matchID: matchID, pendingIntent: intent)
            )
            let realtime = RealtimeHub()
            let submittedIDs = LockedValues<UUID>()
            let service = LiveServiceMock(
                submit: { receivedMatchID, receivedRequestID, word in
                    XCTAssertEqual(receivedMatchID, matchID)
                    XCTAssertEqual(word, "STONE")
                    submittedIDs.append(receivedRequestID)
                    return Self.receipt()
                },
                snapshot: { requestedID in
                    Self.snapshot(matchID: requestedID, status: .inProgress, round: .playing)
                }
            )
            let resumed = makeSession(service: service, realtime: realtime, store: store)
            resumed.backgrounded()
            resumed.changeAccount(to: UUID())
            resumed.leaveToHome()
            resumed.foregrounded()

            XCTAssertTrue(resumed.hasSavedMatch)
            resumed.resumeSavedMatch()
            await eventually { realtime.subscriptionCount == 1 }
            XCTAssertTrue(submittedIDs.values.isEmpty)
            realtime.send(.ready)

            await eventually { resumed.phase == .ready }
            XCTAssertEqual(resumed.snapshot?.match.id, matchID)
            XCTAssertEqual(submittedIDs.values, hasPendingGuess ? [requestID] : [])
            XCTAssertNil(resumed.pendingIntent)
            resumed.leaveToHome()
        }
    }

    func testCreatePersistsIntentBeforeDispatchAndMatchBeforeSnapshotExposure() async throws {
        let userID = UUID()
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore()
        let realtime = RealtimeHub()
        let order = LockedValues<String>()
        let service = LiveServiceMock(
            create: { requestID in
                let saved = try store.load()
                guard saved.pendingIntent == .create(requestID: requestID) else {
                    throw TestFailure.failed
                }
                order.append("create")
                return matchID
            },
            snapshot: { requestedID in
                order.append("snapshot")
                return Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
            }
        )
        let session = makeSession(service: service, realtime: realtime, store: store)
        session.changeAccount(to: userID)

        session.createMatch()

        await eventually { session.savedMatchID == matchID }
        XCTAssertNil(session.snapshot)
        XCTAssertEqual(try store.load().matchID, matchID)
        XCTAssertNil(try store.load().pendingIntent)
        await eventually { realtime.subscriptionCount == 1 }
        order.append("subscribe")
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        XCTAssertEqual(session.snapshot?.match.id, matchID)
        XCTAssertEqual(order.values, ["create", "subscribe", "snapshot"])
    }

    func testRelaunchRetriesSavedGuessOnlyAfterSubscriptionThenFetchesSnapshot() async throws {
        let matchID = UUID()
        let requestID = UUID()
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(
                matchID: matchID,
                pendingIntent: .guess(matchID: matchID, requestID: requestID, word: "STONE")
            )
        )
        let realtime = RealtimeHub()
        let order = LockedValues<String>()
        let service = LiveServiceMock(
            submit: { receivedMatchID, receivedRequestID, word in
                order.append("submit")
                guard receivedMatchID == matchID,
                      receivedRequestID == requestID,
                      word == "STONE"
                else { throw TestFailure.failed }
                return Self.receipt()
            },
            snapshot: { requestedID in
                order.append("snapshot")
                return Self.snapshot(matchID: requestedID, status: .inProgress, round: .playing)
            }
        )
        let session = makeSession(service: service, realtime: realtime, store: store)

        session.changeAccount(to: UUID())
        await eventually { realtime.subscriptionCount == 1 }
        XCTAssertTrue(order.values.isEmpty)
        order.append("subscribe")
        realtime.send(.ready)

        await eventually { session.phase == .ready }
        XCTAssertEqual(order.values, ["subscribe", "submit", "snapshot"])
        XCTAssertNil(session.pendingIntent)
        XCTAssertFalse(session.isInputLocked)
    }

    func testAcceptedFailedReceiptClearsPendingGuessAndRefreshesCanonicalState() async throws {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let realtime = RealtimeHub()
        let snapshots = LockedCounter()
        let service = LiveServiceMock(
            submit: { _, _, _ in Self.failedReceipt() },
            snapshot: { requestedID in
                if snapshots.increment() == 1 {
                    return Self.snapshot(matchID: requestedID, status: .inProgress, round: .playing)
                }
                return Self.snapshot(
                    matchID: requestedID,
                    status: .inProgress,
                    round: .playing,
                    selfPlayerState: .failed
                )
            }
        )
        let session = makeSession(service: service, realtime: realtime, store: store)
        session.changeAccount(to: UUID())
        await eventually { realtime.subscriptionCount == 1 }
        realtime.send(.ready)
        await eventually { session.phase == .ready }

        session.submitGuess("CRANE")

        await eventually {
            !session.isCommandInFlight
                && session.phase == .ready
                && session.snapshot?.round.players.first?.state == .failed
        }
        XCTAssertNil(session.pendingIntent)
        XCTAssertNil(try store.load().pendingIntent)
        XCTAssertEqual(session.guessDraft, "")
        XCTAssertGreaterThanOrEqual(snapshots.value, 2)
    }

    func testSignalsCoalesceAndPreCommandSnapshotCannotOverwriteCommandRecovery() async throws {
        let lobby = try Phase4LiveFixtures.snapshot("3-lobby")
        let playing = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: lobby.match.id))
        let realtime = RealtimeHub()
        let script = SnapshotScript(first: lobby, later: playing)
        let calls = LockedCounter()
        let starts = LockedValues<Int>()
        let service = LiveServiceMock(snapshot: { _ in
            if calls.increment() == 1 { return lobby }
            return try await script.next()
        }, startTargeted: { id, target in
            XCTAssertEqual(id, lobby.match.id)
            starts.append(target)
            return id
        })
        let session = makeSession(service: service, realtime: realtime, store: store)
        session.changeAccount(to: UUID())
        realtime.send(.ready)
        await eventually { session.snapshot == lobby }
        realtime.send(.signal)
        await eventually { await script.callCount == 1 }

        session.startMatch()
        realtime.send(.signal)
        realtime.send(.signal)
        await eventually { !session.isCommandInFlight && starts.values == [1] }
        await script.releaseFirst()

        await eventually { await script.callCount == 2 }
        await eventually { session.snapshot == playing && session.phase == .ready }
        let finalCallCount = await script.callCount
        XCTAssertEqual(finalCallCount, 2)
        session.leaveToHome()
    }

    func testAccountChangeClearsOldRecoveryAndDiscardsLateSnapshot() async throws {
        let firstUser = UUID()
        let secondUser = UUID()
        let matchID = UUID()
        let firstStore = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let secondStore = MemoryLiveRecoveryStore()
        let realtime = RealtimeHub()
        let script = SnapshotScript(
            first: Self.snapshot(matchID: matchID, status: .lobby, round: .pending),
            later: Self.snapshot(matchID: matchID, status: .lobby, round: .pending)
        )
        let service = LiveServiceMock(snapshot: { _ in try await script.next() })
        let session = LiveMatchSession(
            service: service,
            realtime: realtime,
            storeFactory: { $0 == firstUser ? firstStore : secondStore }
        )
        XCTAssertEqual(session.changeAccount(to: firstUser), .completed)
        await eventually { realtime.subscriptionCount == 1 }
        realtime.send(.ready)
        await eventually { await script.callCount == 1 }

        XCTAssertEqual(session.changeAccount(to: secondUser), .completed)
        await script.releaseFirst()
        await Task.yield()

        XCTAssertNil(session.snapshot)
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertEqual(try firstStore.load(), LiveRecoveryState())
    }

    func testAccountChangeReportsPendingCleanupUntilDurableClearSucceeds() throws {
        let firstUser = UUID()
        let secondUser = UUID()
        let firstStore = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        let secondStore = MemoryLiveRecoveryStore()
        let session = LiveMatchSession(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { $0 == firstUser ? firstStore : secondStore }
        )
        XCTAssertEqual(session.changeAccount(to: firstUser), .completed)
        firstStore.rejectsClears = true

        XCTAssertEqual(session.changeAccount(to: secondUser), .recoveryCleanupPending)
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertNotNil(firstStore.storedState.pendingIntent)

        firstStore.rejectsClears = false
        XCTAssertEqual(session.changeAccount(to: secondUser), .completed)
        XCTAssertEqual(try firstStore.load(), LiveRecoveryState())
        XCTAssertEqual(session.phase, .inactive)
    }

    func testSelectedRecoveryRetryRequiresAvailableAuthenticationAndForeground() async throws {
        for error in [LiveMatchServiceError.unavailable, .server(.notAuthenticated)] {
            let matchID = UUID()
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
            let realtime = RealtimeHub()
            let calls = LockedCounter()
            let session = makeSession(
                service: LiveServiceMock(snapshot: { id in
                    if calls.increment() == 1 { throw error }
                    return Self.snapshot(matchID: id, status: .lobby, round: .pending)
                }),
                realtime: realtime,
                store: store,
                timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77),
                              retryBackoff: [.seconds(100)])
            )
            XCTAssertFalse(session.canRetry)
            session.changeAccount(to: UUID())
            realtime.send(.ready)
            await eventually { session.lastError == error }

            if error == .server(.notAuthenticated) {
                XCTAssertEqual(session.phase, .needsSignIn)
                XCTAssertFalse(session.canRetry)
                session.retry()
                await Task.yield()
                XCTAssertEqual(session.phase, .needsSignIn)
                XCTAssertEqual(session.lastError, error)
                XCTAssertEqual(realtime.subscriptionCount, 1)
                XCTAssertEqual(calls.value, 1)
            } else {
                XCTAssertTrue(session.canRetry)
                session.backgrounded()
                XCTAssertFalse(session.canRetry)
                session.retry()
                XCTAssertEqual(session.lastError, error)
                XCTAssertEqual(realtime.subscriptionCount, 1)
                session.foregrounded()
                XCTAssertTrue(session.canRetry)
                session.retry()
                XCTAssertNil(session.lastError)
                XCTAssertEqual(session.phase, .recovering)
                XCTAssertEqual(realtime.subscriptionCount, 3)
                XCTAssertEqual(calls.value, 1)
                realtime.send(.ready)
                await eventually { session.phase == .ready }
                XCTAssertEqual(session.snapshot?.match.id, matchID)
                XCTAssertEqual(calls.value, 2)
            }
            XCTAssertEqual(store.storedState, LiveRecoveryState(matchID: matchID))
            session.leaveToHome()
            XCTAssertFalse(session.canRetry)
        }
    }

    func testAuthenticationRefreshesOnceThenRetriesTheSameSnapshot() async throws {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let realtime = RealtimeHub()
        let calls = LockedCounter()
        let refreshes = LockedCounter()
        let service = LiveServiceMock(snapshot: { requestedID in
            if calls.increment() == 1 {
                throw LiveMatchServiceError.server(.notAuthenticated)
            }
            return Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
        })
        let session = makeSession(
            service: service,
            realtime: realtime,
            store: store,
            refreshAuth: { _ in refreshes.increment(); return true }
        )
        session.changeAccount(to: UUID())
        await eventually { realtime.subscriptionCount == 1 }
        realtime.send(.ready)

        await eventually { session.phase == .ready }
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(refreshes.value, 1)
    }

    func testTimeoutRetainsCreateIdentityAndDoesNotClaimRollback() async throws {
        let store = MemoryLiveRecoveryStore()
        let service = LiveServiceMock(create: { _ in
            try await Task.sleep(for: .seconds(10))
            throw TestFailure.failed
        })
        let session = makeSession(
            service: service,
            realtime: nil,
            store: store,
            timing: .init(
                requestTimeout: .milliseconds(10),
                staleAfter: .seconds(5),
                retryBackoff: [.seconds(100)]
            )
        )
        session.changeAccount(to: UUID())

        session.createMatch()

        await eventually { session.phase == .unavailable && !session.isCommandInFlight }
        guard case .create = session.pendingIntent else {
            return XCTFail("Timed-out create must retain its request ID")
        }
        XCTAssertEqual(session.lastError, .unavailable)
    }

    func testStorageFailureBlocksDispatchAndKeepsSessionUnavailable() async {
        let store = MemoryLiveRecoveryStore()
        store.rejectsWrites = true
        let calls = LockedCounter()
        let service = LiveServiceMock(create: { _ in
            calls.increment()
            return UUID()
        })
        let session = makeSession(service: service, realtime: nil, store: store)
        session.changeAccount(to: UUID())

        session.createMatch()
        await Task.yield()

        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertNil(session.pendingIntent)
        XCTAssertNil(session.savedMatchID)
    }

    func testFactoryFailureBlocksCommandsUntilExplicitStorageRetry() async {
        let userID = UUID()
        let requestID = UUID()
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: requestID))
        )
        let factory = MemoryLiveRecoveryStoreFactory([userID: store])
        factory.rejectsConstruction = true
        let creates = LockedValues<UUID>()
        let session = LiveMatchSession(
            service: LiveServiceMock(create: { receivedRequestID in
                creates.append(receivedRequestID)
                return matchID
            }),
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )

        session.changeAccount(to: userID)
        session.createMatch()
        await Task.yield()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canRetryRecoveryStorage)
        XCTAssertFalse(session.canRetry)
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertNil(session.pendingIntent)
        XCTAssertTrue(creates.values.isEmpty)

        session.retry()
        await Task.yield()
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(creates.values.isEmpty)

        factory.rejectsConstruction = false
        session.retry()

        await eventually { session.savedMatchID == matchID }
        XCTAssertEqual(creates.values, [requestID])
    }

    func testFactoryRecoveryCanDiscardCreateWithoutLoadingOrReplayingIt() async throws {
        let userID = UUID()
        let requestID = UUID()
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: requestID))
        )
        let factory = MemoryLiveRecoveryStoreFactory([userID: store])
        factory.rejectsConstruction = true
        let creates = LockedCounter()
        let service = LiveServiceMock(create: { _ in
            creates.increment()
            return UUID()
        })
        let session = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        session.changeAccount(to: userID)

        factory.rejectsConstruction = false
        session.discardRecovery()
        session.changeAccount(to: nil)
        session.changeAccount(to: userID)
        await Task.yield()
        let relaunched = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: userID)
        await Task.yield()

        XCTAssertEqual(try store.load(), LiveRecoveryState())
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertEqual(relaunched.phase, .inactive)
        XCTAssertEqual(creates.value, 0)
    }

    func testFactoryRecoveryCanDiscardGuessWithoutLoadingOrReplayingIt() async throws {
        let userID = UUID()
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(
                matchID: matchID,
                pendingIntent: .guess(matchID: matchID, requestID: UUID(), word: "STONE")
            )
        )
        let factory = MemoryLiveRecoveryStoreFactory([userID: store])
        factory.rejectsConstruction = true
        let submits = LockedCounter()
        let service = LiveServiceMock(submit: { _, _, _ in
            submits.increment()
            return Self.receipt()
        })
        let session = LiveMatchSession(
            service: service,
            realtime: RealtimeHub(),
            storeFactory: { try factory.make($0) }
        )
        session.changeAccount(to: userID)

        factory.rejectsConstruction = false
        session.discardRecovery()
        session.changeAccount(to: nil)
        session.changeAccount(to: userID)
        let relaunched = LiveMatchSession(
            service: service,
            realtime: RealtimeHub(),
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: userID)
        await Task.yield()

        XCTAssertEqual(try store.load(), LiveRecoveryState())
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertEqual(relaunched.phase, .inactive)
        XCTAssertEqual(submits.value, 0)
    }

    func testFactoryFailureKeepsAccountSwitchAndSignOutOnOldAccountUntilClearSucceeds() throws {
        let firstUser = UUID()
        let secondUser = UUID()
        let switchStore = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        let secondStore = MemoryLiveRecoveryStore()
        let switchFactory = MemoryLiveRecoveryStoreFactory([
            firstUser: switchStore,
            secondUser: secondStore,
        ])
        switchFactory.rejectsConstruction = true
        let switching = LiveMatchSession(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { try switchFactory.make($0) }
        )
        switching.changeAccount(to: firstUser)

        switching.changeAccount(to: secondUser)

        XCTAssertEqual(switching.phase, .storageUnavailable)
        XCTAssertEqual(switchFactory.requestedAccountIDs, [firstUser, firstUser])
        XCTAssertNotNil(switchStore.storedState.pendingIntent)

        XCTAssertTrue(switching.canRetryRecoveryStorage)
        XCTAssertFalse(switching.canRetry)
        switchFactory.rejectsConstruction = false
        switching.retry()

        XCTAssertEqual(switching.phase, .inactive)
        XCTAssertEqual(switchFactory.requestedAccountIDs.suffix(2), [firstUser, secondUser])
        XCTAssertEqual(try switchStore.load(), LiveRecoveryState())

        let signOutStore = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        let signOutFactory = MemoryLiveRecoveryStoreFactory([firstUser: signOutStore])
        signOutFactory.rejectsConstruction = true
        let signingOut = LiveMatchSession(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { try signOutFactory.make($0) }
        )
        signingOut.changeAccount(to: firstUser)

        signingOut.changeAccount(to: nil)

        XCTAssertEqual(signingOut.phase, .storageUnavailable)
        XCTAssertEqual(signOutFactory.requestedAccountIDs, [firstUser, firstUser])
        XCTAssertNotNil(signOutStore.storedState.pendingIntent)

        signOutFactory.rejectsConstruction = false
        signingOut.discardRecovery()

        XCTAssertEqual(signingOut.phase, .inactive)
        XCTAssertEqual(try signOutStore.load(), LiveRecoveryState())
    }

    func testAuthReversionCancelsFailedAccountSwitchBeforeRetryingCurrentAccount() async throws {
        let firstUser = UUID()
        let secondUser = UUID()
        let firstRequestID = UUID()
        let secondRequestID = UUID()
        let firstMatchID = UUID()
        let firstStore = MemoryLiveRecoveryStore()
        let secondStore = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: secondRequestID))
        )
        let factory = MemoryLiveRecoveryStoreFactory([
            firstUser: firstStore,
            secondUser: secondStore,
        ])
        let creates = LockedValues<UUID>()
        let service = LiveServiceMock(create: { requestID in
            creates.append(requestID)
            return firstMatchID
        })
        let session = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) },
            makeUUID: { firstRequestID }
        )
        session.changeAccount(to: firstUser)
        firstStore.rejectsClears = true

        session.changeAccount(to: secondUser)
        session.changeAccount(to: firstUser)

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canRetryRecoveryStorage)
        XCTAssertFalse(session.canRetry)
        XCTAssertEqual(factory.requestedAccountIDs, [firstUser])

        factory.rejectsConstruction = true
        session.retry()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canRetryRecoveryStorage)
        XCTAssertFalse(session.canRetry)
        XCTAssertEqual(factory.requestedAccountIDs, [firstUser, firstUser])

        factory.rejectsConstruction = false
        session.retry()
        XCTAssertEqual(session.phase, .inactive)
        session.createMatch()

        await eventually { session.savedMatchID == firstMatchID }
        XCTAssertEqual(creates.values, [firstRequestID])
        XCTAssertFalse(factory.requestedAccountIDs.contains(secondUser))
        XCTAssertEqual(
            secondStore.storedState,
            LiveRecoveryState(pendingIntent: .create(requestID: secondRequestID))
        )

        let relaunched = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: firstUser)
        await Task.yield()

        XCTAssertEqual(relaunched.savedMatchID, firstMatchID)
        XCTAssertNil(relaunched.pendingIntent)
        XCTAssertEqual(creates.values, [firstRequestID])
        XCTAssertTrue(factory.requestedAccountIDs.allSatisfy { $0 == firstUser })
        XCTAssertEqual(try firstStore.load().matchID, firstMatchID)
    }

    func testAuthReversionCancelsFailedSignOutBeforeDiscardingCurrentAccount() async throws {
        let userID = UUID()
        let requestID = UUID()
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        store.rejectsLoads = true
        let factory = MemoryLiveRecoveryStoreFactory([userID: store])
        let creates = LockedValues<UUID>()
        let service = LiveServiceMock(create: { receivedRequestID in
            creates.append(receivedRequestID)
            return matchID
        })
        let session = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) },
            makeUUID: { requestID }
        )
        session.changeAccount(to: userID)
        store.rejectsClears = true

        session.changeAccount(to: nil)
        session.changeAccount(to: userID)

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canDiscardRecovery)

        session.discardRecovery()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canDiscardRecovery)

        store.rejectsClears = false
        session.discardRecovery()
        XCTAssertEqual(session.phase, .inactive)
        session.createMatch()

        await eventually { session.savedMatchID == matchID }
        XCTAssertEqual(creates.values, [requestID])
        XCTAssertEqual(try store.load().matchID, matchID)

        let relaunched = LiveMatchSession(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: userID)
        await Task.yield()

        XCTAssertEqual(relaunched.savedMatchID, matchID)
        XCTAssertNil(relaunched.pendingIntent)
        XCTAssertEqual(creates.values, [requestID])
    }

    func testFactoryRecoveryDiscardClearFailureRemainsControllable() {
        let userID = UUID()
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        store.rejectsClears = true
        let factory = MemoryLiveRecoveryStoreFactory([userID: store])
        factory.rejectsConstruction = true
        let session = LiveMatchSession(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        session.changeAccount(to: userID)

        factory.rejectsConstruction = false
        session.discardRecovery()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canRetryRecoveryStorage)
        XCTAssertFalse(session.canRetry)
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertNotNil(store.storedState.pendingIntent)
    }

    func testFailedLoadCanBeExplicitlyDiscarded() throws {
        let requestID = UUID()
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: requestID))
        )
        store.rejectsLoads = true
        let session = makeSession(service: LiveServiceMock(), realtime: nil, store: store)

        session.changeAccount(to: UUID())

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canDiscardRecovery)

        session.leaveToHome()

        XCTAssertEqual(session.phase, .storageUnavailable)
        session.discardRecovery()

        XCTAssertEqual(session.phase, .inactive)
        XCTAssertFalse(session.canDiscardRecovery)
        XCTAssertEqual(try store.load(), LiveRecoveryState())
    }

    func testFailedRecoveryDiscardRemainsStorageUnavailable() {
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        store.rejectsLoads = true
        store.rejectsClears = true
        let session = makeSession(service: LiveServiceMock(), realtime: nil, store: store)
        session.changeAccount(to: UUID())

        session.discardRecovery()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertNotNil(store.storedState.pendingIntent)
    }

    func testSuccessfulDiscardDoesNotReplayAfterSignOutAndReauthentication() async {
        let store = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        store.rejectsLoads = true
        let creates = LockedCounter()
        let service = LiveServiceMock(create: { _ in
            creates.increment()
            return UUID()
        })
        let session = makeSession(service: service, realtime: nil, store: store)
        let userID = UUID()
        session.changeAccount(to: userID)

        session.discardRecovery()
        session.changeAccount(to: nil)
        session.changeAccount(to: userID)
        await Task.yield()
        let relaunched = makeSession(service: service, realtime: nil, store: store)
        relaunched.changeAccount(to: userID)
        await Task.yield()

        XCTAssertEqual(session.phase, .inactive)
        XCTAssertNil(session.pendingIntent)
        XCTAssertEqual(relaunched.phase, .inactive)
        XCTAssertNil(relaunched.pendingIntent)
        XCTAssertEqual(creates.value, 0)
    }

    func testAccountSwitchAndSignOutClearFailuresAreSurfaced() {
        let firstUser = UUID()
        let secondUser = UUID()
        let firstStore = MemoryLiveRecoveryStore(
            LiveRecoveryState(pendingIntent: .create(requestID: UUID()))
        )
        let secondStore = MemoryLiveRecoveryStore()
        let session = LiveMatchSession(
            service: LiveServiceMock(),
            realtime: RealtimeHub(),
            storeFactory: { $0 == firstUser ? firstStore : secondStore }
        )
        session.changeAccount(to: firstUser)
        firstStore.rejectsClears = true

        session.changeAccount(to: secondUser)

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertNotNil(firstStore.storedState.pendingIntent)

        session.changeAccount(to: nil)

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertNotNil(firstStore.storedState.pendingIntent)
    }

    func testInvalidSavedMatchClearFailureIsSurfaced() async {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        store.rejectsClears = true
        let service = LiveServiceMock(snapshot: { _ in
            throw LiveMatchServiceError.server(.notAMatchMember)
        })
        let session = makeSession(service: service, realtime: nil, store: store)

        session.changeAccount(to: UUID())

        await eventually { session.phase == .storageUnavailable }
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertEqual(session.savedMatchID, matchID)
        XCTAssertEqual(store.storedState.matchID, matchID)
    }

    func testBackgroundStopsRecoveryAndForegroundResubscribesBeforeCatchup() async throws {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let realtime = RealtimeHub()
        let snapshots = LockedCounter()
        let service = LiveServiceMock(snapshot: { requestedID in
            snapshots.increment()
            return Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
        })
        let session = makeSession(service: service, realtime: realtime, store: store)
        session.changeAccount(to: UUID())
        await eventually { realtime.subscriptionCount == 1 }

        session.backgrounded()
        realtime.send(.ready)
        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(snapshots.value, 0)

        session.foregrounded()
        await eventually { realtime.subscriptionCount == 2 }
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        XCTAssertEqual(snapshots.value, 1)
    }

    func testRealtimeFailureKeepsSnapshotRecoveryAndResubscribesWithBackoff() async throws {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let realtime = RealtimeHub()
        let snapshots = LockedCounter()
        let service = LiveServiceMock(snapshot: { requestedID in
            snapshots.increment()
            return Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
        })
        let session = makeSession(
            service: service,
            realtime: realtime,
            store: store,
            timing: .init(
                requestTimeout: .seconds(99),
                staleAfter: .seconds(77),
                retryBackoff: [.seconds(5)]
            ),
            sleep: { duration in
                if duration == .seconds(5) {
                    try await Task.sleep(for: .milliseconds(1))
                } else {
                    try await Task.sleep(for: .seconds(100))
                }
            }
        )
        session.changeAccount(to: UUID())
        await eventually { realtime.subscriptionCount == 1 }

        realtime.finish(throwing: TestFailure.failed)

        await eventually { snapshots.value == 1 }
        await eventually { realtime.subscriptionCount == 2 }
    }

    func testDefinitiveGuessRejectionClearsIntentButConflictRetainsIt() async throws {
        let matchID = UUID()
        let rejectedStore = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let rejectedRealtime = RealtimeHub()
        let rejectedService = LiveServiceMock(
            submit: { _, _, _ in throw LiveMatchServiceError.server(.wordNotAccepted) },
            snapshot: { requestedID in
                Self.snapshot(matchID: requestedID, status: .inProgress, round: .playing)
            }
        )
        let rejected = makeSession(
            service: rejectedService,
            realtime: rejectedRealtime,
            store: rejectedStore
        )
        rejected.changeAccount(to: UUID())
        await eventually { rejectedRealtime.subscriptionCount == 1 }
        rejectedRealtime.send(.ready)
        await eventually { rejected.phase == .ready }

        rejected.submitGuess("XXXXX")
        await eventually { !rejected.isCommandInFlight }
        XCTAssertNil(rejected.pendingIntent)
        XCTAssertEqual(rejected.guessDraft, "XXXXX")

        let conflictRequest = UUID()
        let conflictStore = MemoryLiveRecoveryStore(
            LiveRecoveryState(
                matchID: matchID,
                pendingIntent: .guess(
                    matchID: matchID,
                    requestID: conflictRequest,
                    word: "STONE"
                )
            )
        )
        let conflictRealtime = RealtimeHub()
        let conflictAttempts = LockedValues<UUID>()
        let conflictService = LiveServiceMock(
            submit: { _, requestID, _ in
                conflictAttempts.append(requestID)
                throw LiveMatchServiceError.server(.requestConflict)
            },
            snapshot: { id in
                Self.snapshot(matchID: id, status: .completed, round: .revealed)
            }
        )
        let conflict = makeSession(
            service: conflictService,
            realtime: conflictRealtime,
            store: conflictStore
        )
        conflict.changeAccount(to: UUID())
        await eventually { conflictRealtime.subscriptionCount == 1 }
        conflictRealtime.send(.ready)
        await eventually {
            !conflict.isCommandInFlight && conflict.snapshot?.round.state == .revealed
        }
        XCTAssertEqual(
            conflict.pendingIntent,
            .guess(matchID: matchID, requestID: conflictRequest, word: "STONE")
        )
        XCTAssertEqual(conflict.lastError, .server(.requestConflict))
        XCTAssertTrue(conflict.canRetry)
        conflict.retry()
        XCTAssertFalse(conflict.canRetry)
        await eventually { !conflict.isCommandInFlight && conflict.lastError != nil }
        XCTAssertEqual(conflictAttempts.values, [conflictRequest, conflictRequest])
        XCTAssertTrue(conflict.canRetry)
        conflict.leaveToHome()
    }

    func testRecoveryUsesCappedBackoffSequenceAndOriginalCreateID() async throws {
        XCTAssertEqual(LiveMatchSessionTiming.production.requestTimeout, .seconds(10))
        XCTAssertEqual(LiveMatchSessionTiming.production.staleAfter, .seconds(5))
        XCTAssertEqual(
            LiveMatchSessionTiming.production.retryBackoff,
            [.seconds(5), .seconds(10), .seconds(20), .seconds(30)]
        )
        let store = MemoryLiveRecoveryStore()
        let matchID = UUID()
        let attempts = LockedValues<UUID>()
        let sleeps = LockedValues<Duration>()
        let service = LiveServiceMock(create: { requestID in
            attempts.append(requestID)
            if attempts.values.count < 5 { throw LiveMatchServiceError.unavailable }
            return matchID
        })
        let timing = LiveMatchSessionTiming(
            requestTimeout: .seconds(99),
            staleAfter: .seconds(77),
            retryBackoff: [.seconds(5), .seconds(10), .seconds(20), .seconds(30)]
        )
        let session = makeSession(
            service: service,
            realtime: RealtimeHub(),
            store: store,
            timing: timing,
            sleep: { duration in
                if duration == .seconds(99) {
                    try await Task.sleep(for: .seconds(100))
                } else {
                    sleeps.append(duration)
                    try await Task.sleep(for: .milliseconds(1))
                }
            }
        )
        session.changeAccount(to: UUID())

        session.createMatch()

        await eventually(timeout: 2) { attempts.values.count == 5 }
        await eventually { session.savedMatchID == matchID }
        XCTAssertEqual(Set(attempts.values).count, 1)
        XCTAssertEqual(sleeps.values, timing.retryBackoff)
        XCTAssertEqual(session.savedMatchID, matchID)
    }

    func testDisplayTimeUsesMonotonicElapsedAndDeadlineWaitsForCanonicalReveal() async throws {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let realtime = RealtimeHub()
        let clock = UptimeBox(100)
        let script = SnapshotScript(
            first: Self.snapshot(
                matchID: matchID,
                status: .inProgress,
                round: .playing,
                serverTime: Date(timeIntervalSince1970: 1_000),
                endsAt: Date(timeIntervalSince1970: 1_003)
            ),
            later: Self.snapshot(
                matchID: matchID,
                status: .completed,
                round: .revealed,
                serverTime: Date(timeIntervalSince1970: 1_004),
                endsAt: Date(timeIntervalSince1970: 1_003)
            ),
            suspendFirst: false
        )
        let timerStarted = LockedCounter()
        let releaseTimer = AsyncGate()
        let service = LiveServiceMock(snapshot: { _ in try await script.next() })
        let session = makeSession(
            service: service,
            realtime: realtime,
            store: store,
            timing: .init(
                requestTimeout: .seconds(99),
                staleAfter: .seconds(50),
                retryBackoff: [.seconds(5)]
            ),
            sleep: { duration in
                if duration == .seconds(99) {
                    try await Task.sleep(for: .seconds(100))
                } else {
                    _ = timerStarted.increment()
                    await releaseTimer.wait()
                }
            },
            uptime: { clock.value }
        )
        session.changeAccount(to: UUID())
        await eventually { realtime.subscriptionCount == 1 }
        realtime.send(.ready)
        await eventually { session.phase == .ready && timerStarted.value == 1 }

        clock.value = 104
        XCTAssertEqual(session.displayedServerTime, Date(timeIntervalSince1970: 1_004))
        XCTAssertTrue(session.isInputLocked)
        XCTAssertEqual(session.snapshot?.round.state, .playing)
        await releaseTimer.open()

        await eventually { session.snapshot?.round.state == .revealed }
        let finalCallCount = await script.callCount
        XCTAssertEqual(finalCallCount, 2)
    }

    func testLegacyMigrationSaveMustSucceedBeforeAnyCommandOrSnapshot() async throws {
        for isGuess in [false, true] {
            let match = UUID(), request = UUID()
            let intent: LivePendingIntent = isGuess
                ? .guess(matchID: match, requestID: request, word: "STONE", roundNumber: 1, clientBuild: 1)
                : .create(requestID: request, roundCount: 1, clientBuild: 1)
            let original = LiveRecoveryState(formatVersion: 1, matchID: isGuess ? match : nil, pendingIntent: intent)
            let store = MemoryLiveRecoveryStore(original)
            store.rejectsWrites = true
            let dispatches = LockedCounter()
            let session = makeSession(service: LiveServiceMock(
                snapshot: { id in
                    XCTAssertEqual(store.storedState.formatVersion, 2)
                    dispatches.increment()
                    return Self.snapshot(matchID: id, status: .completed, round: .revealed)
                },
                createConfigured: { id, count, build in
                    XCTAssertEqual(store.storedState.formatVersion, 2)
                    XCTAssertEqual(id, request); XCTAssertEqual(count, 1); XCTAssertEqual(build, 1)
                    dispatches.increment(); return match
                },
                submitTargeted: { id, round, requestID, word, build in
                    XCTAssertEqual(store.storedState.formatVersion, 2)
                    XCTAssertEqual(id, match); XCTAssertEqual(round, 1); XCTAssertEqual(requestID, request)
                    XCTAssertEqual(word, "STONE"); XCTAssertEqual(build, 1)
                    dispatches.increment(); return Self.receipt()
                }
            ), realtime: nil, store: store)
            session.changeAccount(to: UUID())
            await Task.yield()
            XCTAssertEqual(session.phase, .storageUnavailable)
            XCTAssertEqual(dispatches.value, 0)
            XCTAssertEqual(store.storedState, original)
            session.resumeSavedMatch(); session.foregrounded(); session.createMatch(); session.startMatch()
            XCTAssertEqual(dispatches.value, 0)
            store.rejectsWrites = false
            session.retry()
            await eventually { session.phase == .ready && !session.isCommandInFlight }
            XCTAssertEqual(dispatches.value, 2)
            XCTAssertNil(store.storedState.pendingIntent)
            XCTAssertEqual(store.storedState.formatVersion, 2)
            session.leaveToHome()
        }
    }

    func testCreateCountIsDurableAndRetriedWithoutReplacingUUIDOrBuild() async throws {
        for count in [1, 3, 5] {
            let request = UUID(), match = UUID()
            let store = MemoryLiveRecoveryStore()
            let calls = LockedValues<LivePendingIntent>()
            let session = LiveMatchSession(service: LiveServiceMock(createConfigured: { id, roundCount, build in
                let intent = LivePendingIntent.create(requestID: id, roundCount: roundCount, clientBuild: build)
                XCTAssertEqual(store.storedState.pendingIntent, intent)
                calls.append(intent)
                throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, storeFactory: { _ in store }, makeUUID: { request })
            session.changeAccount(to: UUID())
            session.createMatch(roundCount: count)
            await eventually { !session.isCommandInFlight }
            session.retry()
            await eventually { calls.values.count == 2 && !session.isCommandInFlight }
            XCTAssertEqual(calls.values, Array(repeating: .create(requestID: request, roundCount: count, clientBuild: 2), count: 2))
            XCTAssertNil(session.savedMatchID)
            XCTAssertNotEqual(session.savedMatchID, match)
            session.leaveToHome()
        }
    }

    func testUncertainStartRetryKeepsCapturedTargetAndHistorySelectionNeverTargetsCommands() async throws {
        let initial = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        let later = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: initial.match.id))
        let realtime = RealtimeHub()
        let starts = LockedValues<Int>()
        let snapshots = LockedCounter()
        let session = makeSession(service: LiveServiceMock(snapshot: { _ in
            snapshots.increment()
            return initial
        }, startTargeted: { _, round in
            starts.append(round)
            throw LiveMatchServiceError.unavailable
        }), realtime: realtime, store: store,
        timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77), retryBackoff: [.seconds(66)]))
        session.changeAccount(to: UUID()); realtime.send(.ready)
        await eventually { session.phase == .ready }
        session.selectReveal(number: 1)
        session.startMatch()
        session.startMatch()
        await eventually { !session.isCommandInFlight && snapshots.value == 2 }
        session.retry()
        await eventually { !session.isCommandInFlight && starts.values.count == 2 }
        XCTAssertEqual(starts.values, [2, 2])
        XCTAssertEqual(session.snapshot?.round.number, 1)
        XCTAssertEqual(session.displayedReveal?.number, 1)
        session.leaveToHome()
        XCTAssertEqual(later.round.number, 2)
    }

    func testPendingStartRemainsObservableAcrossUnchangedSnapshotAndHomeResume() async throws {
        for (label, target) in [("3-lobby", 1), ("3-round-1-reveal", 2)] {
            let initial = try Phase4LiveFixtures.snapshot(label)
            let original = LiveRecoveryState(matchID: initial.match.id)
            let store = MemoryLiveRecoveryStore(original)
            let realtime = RealtimeHub()
            let starts = LockedValues<Int>()
            let snapshots = LockedCounter()
            let changes = LockedCounter()
            let session = makeSession(service: LiveServiceMock(snapshot: { id in
                XCTAssertEqual(id, initial.match.id)
                snapshots.increment()
                return initial
            }, startTargeted: { id, round in
                XCTAssertEqual(id, initial.match.id)
                XCTAssertEqual(store.storedState, original, "Start must not persist an intent")
                starts.append(round)
                if starts.values.count == 1 { throw LiveMatchServiceError.unavailable }
                return id
            }), realtime: realtime, store: store,
            timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77), retryBackoff: [.seconds(66)]))
            XCTAssertFalse(session.hasPendingStart)
            session.changeAccount(to: UUID()); realtime.send(.ready)
            await eventually { session.phase == .ready }
            XCTAssertFalse(session.hasPendingStart)
            XCTAssertTrue(session.canRetry, "ordinary recovery is not an unresolved Start")
            withObservationTracking {
                XCTAssertFalse(session.hasPendingStart)
            } onChange: { changes.increment() }
            session.startMatch()
            XCTAssertTrue(session.hasPendingStart)
            XCTAssertEqual(changes.value, 1)
            session.startMatch()
            await eventually { !session.isCommandInFlight && snapshots.value >= 2 && session.phase == .ready }
            XCTAssertNil(session.lastError)
            XCTAssertTrue(session.hasPendingStart, "an unchanged success snapshot cannot resolve Start")
            session.startMatch()
            await Task.yield()
            XCTAssertEqual(starts.values, [target], "new Start remains blocked after error-free refresh")
            XCTAssertEqual(store.storedState, original)

            session.leaveToHome()
            XCTAssertNil(session.snapshot)
            XCTAssertTrue(session.hasPendingStart)
            XCTAssertFalse(session.canRetry)
            session.resumeSavedMatch(); realtime.send(.ready)
            await eventually { session.phase == .ready }
            XCTAssertNil(session.lastError)
            XCTAssertTrue(session.hasPendingStart)
            XCTAssertTrue(session.canRetry)
            XCTAssertEqual(starts.values, [target], "Resume must fetch rather than dispatch Start")
            withObservationTracking {
                XCTAssertTrue(session.hasPendingStart)
            } onChange: { changes.increment() }
            session.retry()
            await eventually { !session.isCommandInFlight && !session.hasPendingStart && session.phase == .ready }
            XCTAssertEqual(starts.values, [target, target], "Retry must retain the original match and round")
            XCTAssertEqual(changes.value, 2)
            XCTAssertEqual(session.snapshot, initial, "command success clears the signal before canonical advance")
            XCTAssertEqual(store.storedState, original)
            session.leaveToHome()
        }
    }

    func testPendingStartClearsOnCanonicalAdvanceDefinitiveDenialAndAccountReset() async throws {
        for (label, target) in [("3-lobby", 1), ("3-round-1-reveal", 2)] {
            for resolution in ["target", "later", "denial", "accountReset"] {
                let initial = try Phase4LiveFixtures.snapshot(label)
                let canonical = LockedValues<LiveMatchSnapshot>()
                canonical.append(initial)
                let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: initial.match.id))
                let realtime = RealtimeHub()
                let starts = LockedValues<Int>()
                let snapshots = LockedCounter()
                let session = makeSession(service: LiveServiceMock(snapshot: { _ in
                    snapshots.increment()
                    return canonical.values.last!
                }, startTargeted: { id, round in
                    XCTAssertEqual(id, initial.match.id)
                    starts.append(round)
                    if starts.values.count > 1 { throw LiveMatchServiceError.server(.roundNotActive) }
                    throw LiveMatchServiceError.unavailable
                }), realtime: realtime, store: store,
                timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77), retryBackoff: [.seconds(66)]))
                session.changeAccount(to: UUID()); realtime.send(.ready)
                await eventually { session.phase == .ready }
                session.startMatch()
                await eventually { !session.isCommandInFlight && snapshots.value >= 2 && session.phase == .ready }
                XCTAssertTrue(session.hasPendingStart)
                XCTAssertNil(session.lastError)
                switch resolution {
                case "target", "later":
                    let advanced = try Phase4LiveFixtures.snapshot(
                        resolution == "target" ? "3-round-\(target)-countdown" : "3-round-3-reveal"
                    )
                    canonical.append(advanced)
                    realtime.send(.signal)
                    await eventually { session.snapshot == advanced }
                    XCTAssertEqual(starts.values, [target])
                case "denial":
                    session.retry()
                    await eventually { !session.isCommandInFlight && starts.values.count == 2 }
                    XCTAssertEqual(starts.values, [target, target])
                default:
                    session.changeAccount(to: nil)
                    XCTAssertEqual(session.phase, .inactive)
                    XCTAssertFalse(session.hasSavedMatch)
                    XCTAssertEqual(store.storedState, LiveRecoveryState())
                }
                XCTAssertFalse(session.hasPendingStart, resolution)
                XCTAssertNil(session.pendingIntent)
                session.leaveToHome()
            }
        }
    }

    func testOldGuessReceiptAfterNewRoundClearsExactIntentWithoutChangingBoardDraftOrClock() async throws {
        for succeeds in [false, true] {
            let current = try Phase4LiveFixtures.snapshot("3-round-2-playing")
            let request = UUID()
            let intent = LivePendingIntent.guess(matchID: current.match.id, requestID: request, word: "STONE",
                                                 roundNumber: 1, clientBuild: 1)
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: current.match.id, pendingIntent: intent))
            let realtime = RealtimeHub()
            let attempts = LockedCounter()
            let gate = AsyncGate()
            let clock = UptimeBox(100)
            let session = makeSession(service: LiveServiceMock(snapshot: { _ in current }, submitTargeted: {
                match, round, id, word, build in
                XCTAssertEqual(match, current.match.id); XCTAssertEqual(round, 1)
                XCTAssertEqual(id, request); XCTAssertEqual(word, "STONE"); XCTAssertEqual(build, 1)
                if attempts.increment() == 1 { throw LiveMatchServiceError.server(.requestConflict) }
                await gate.wait()
                if succeeds { return Self.receipt() }
                throw LiveMatchServiceError.server(.wordNotAccepted)
            }), realtime: realtime, store: store, uptime: { clock.value })
            session.changeAccount(to: UUID()); realtime.send(.ready)
            await eventually { session.snapshot?.round.number == 2 && !session.isCommandInFlight }
            XCTAssertEqual(session.pendingIntent, intent, "snapshot is never acknowledgement")
            XCTAssertTrue(session.isInputLocked)
            XCTAssertEqual(session.guessDraft, "")
            session.selectReveal(number: 1)
            session.retry()
            await eventually { attempts.value == 2 }
            clock.value = 105
            XCTAssertEqual(session.displayedServerTime, current.serverTime.addingTimeInterval(5))
            await gate.open()
            await eventually { !session.isCommandInFlight && session.pendingIntent == nil && session.phase == .ready }
            XCTAssertNil(store.storedState.pendingIntent)
            XCTAssertEqual(session.snapshot?.round, current.round)
            XCTAssertEqual(session.guessDraft, "")
            XCTAssertEqual(session.displayedServerTime, current.serverTime)
            XCTAssertEqual(session.selectedRevealNumber, 1)
            XCTAssertNil(session.lastError)
            session.leaveToHome()
        }
    }

    func testNonfinalRevealWatchdogAdvancesWithLostEventsAndFinalResumeCatchesUpOnce() async throws {
        let first = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        let next = try Phase4LiveFixtures.snapshot("3-round-2-countdown")
        let final = try Phase4LiveFixtures.snapshot("3-round-3-reveal")
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: first.match.id))
        let realtime = RealtimeHub()
        let script = SnapshotScript(first: first, later: next, suspendFirst: false)
        let timers = LockedCounter(), fetches = LockedCounter()
        let gate = AsyncGate()
        let session = makeSession(service: LiveServiceMock(snapshot: { _ in
            let call = fetches.increment()
            if call > 2 { return final }
            return try await script.next()
        }), realtime: realtime, store: store,
        timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(50), retryBackoff: [.seconds(66)]),
        sleep: { duration in
            if duration == .seconds(99) { try await Task.sleep(for: duration) }
            else { timers.increment(); await gate.wait() }
        })
        session.changeAccount(to: UUID()); realtime.send(.ready)
        await eventually { session.phase == .ready && timers.value == 1 }
        session.selectReveal(number: 1)
        await gate.open()
        await eventually { session.snapshot?.match.status == .completed }
        XCTAssertNil(session.selectedRevealNumber)
        XCTAssertEqual(session.guessDraft, "")
        let count = fetches.value
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(fetches.value, count)
        session.leaveToHome()
        session.resumeSavedMatch()
        realtime.send(.ready)
        await eventually { session.phase == .ready && fetches.value == count + 1 }
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(fetches.value, count + 1)
        session.leaveToHome()
    }

    func testLowerRevisionIsIgnoredWhileEqualRevisionCanAdvanceCountdownToPlaying() async throws {
        var countdown = try Phase4LiveFixtures.snapshot("3-round-2-countdown")
        var playing = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        playing.revision = countdown.revision
        var stale = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        stale.revision = countdown.revision - 1
        let calls = LockedCounter()
        let realtime = RealtimeHub()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: countdown.match.id))
        countdown.revision = playing.revision
        let initial = countdown, equal = playing, older = stale
        let session = makeSession(service: LiveServiceMock(snapshot: { _ in
            switch calls.increment() { case 1: initial; case 2: older; default: equal }
        }), realtime: realtime, store: store)
        session.changeAccount(to: UUID()); realtime.send(.ready)
        await eventually { session.snapshot?.round.state == .countdown }
        realtime.send(.signal)
        await eventually { calls.value == 2 }
        await Task.yield()
        XCTAssertEqual(session.snapshot?.round, initial.round)
        realtime.send(.signal)
        await eventually { session.snapshot?.round.state == .playing }
        XCTAssertEqual(session.snapshot?.revision, initial.revision)
        session.leaveToHome()
    }

    func testDelayedSnapshotCannotReopenHomeOrReplaceResumedPresentation() async throws {
        let initial = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        let next = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        let script = SnapshotScript(first: initial, later: next)
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: initial.match.id))
        let realtime = RealtimeHub()
        let session = makeSession(service: LiveServiceMock(snapshot: { _ in try await script.next() }),
                                  realtime: realtime, store: store)
        session.changeAccount(to: UUID()); realtime.send(.ready)
        await eventually { await script.callCount == 1 }
        session.leaveToHome()
        session.resumeSavedMatch(); realtime.send(.ready)
        await eventually { session.snapshot?.round.number == 2 }
        await script.releaseFirst()
        await Task.yield()
        XCTAssertEqual(session.snapshot?.round, next.round)
        session.leaveToHome()
        XCTAssertNil(session.snapshot)
    }

    func testPendingConflictAndRateLimitStayExplicitAcrossAdvanceAndRepeatedReadyEvents() async throws {
        for denial in [LiveMatchServerError.requestConflict, .rateLimited] {
            let initial = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
            let next = try Phase4LiveFixtures.snapshot("3-round-2-playing")
            let intent = LivePendingIntent.guess(matchID: initial.match.id, requestID: UUID(), word: "STONE",
                                                 roundNumber: 1, clientBuild: 2)
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: initial.match.id, pendingIntent: intent))
            let realtime = RealtimeHub(), guesses = LockedCounter(), snapshots = LockedCounter()
            let session = makeSession(service: LiveServiceMock(snapshot: { _ in
                snapshots.increment() == 1 ? initial : next
            }, submitTargeted: { _, _, _, _, _ in
                guesses.increment()
                throw LiveMatchServiceError.server(denial)
            }), realtime: realtime, store: store)
            session.changeAccount(to: UUID()); realtime.send(.ready)
            await eventually { session.snapshot?.round.number == 1 && !session.isCommandInFlight }
            realtime.send(.signal)
            await eventually { session.snapshot?.round.number == 2 }
            realtime.send(.ready)
            await eventually { snapshots.value >= 3 }
            XCTAssertEqual(guesses.value, 1)
            XCTAssertEqual(session.lastError, .server(denial))
            XCTAssertEqual(session.pendingIntent, intent)
            XCTAssertEqual(session.phase, .unavailable)
            XCTAssertTrue(session.canRetry)
            XCTAssertTrue(session.isInputLocked)
            session.retry()
            await eventually { guesses.value == 2 && !session.isCommandInFlight }
            XCTAssertEqual(store.storedState.pendingIntent, intent)
            session.discardPendingGuess()
            await eventually { session.phase == .ready }
            XCTAssertNil(store.storedState.pendingIntent)
            session.leaveToHome()
        }
    }

    func testTerminalSnapshotKeepsUncertainReceiptRetryUntilDurablyResolved() async throws {
        for label in ["3-round-3-reveal", "deletion-active-revealed"] {
            let final = try Phase4LiveFixtures.snapshot(label)
            let requestID = UUID()
            let intent = LivePendingIntent.guess(matchID: final.match.id, requestID: requestID, word: "STONE",
                                                 roundNumber: 1, clientBuild: 2)
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: final.match.id, pendingIntent: intent))
            let realtime = RealtimeHub(), attempts = LockedCounter(), fetches = LockedCounter()
            let gate = AsyncGate()
            let session = makeSession(service: LiveServiceMock(snapshot: { _ in
                fetches.increment(); return final
            }, submitTargeted: { matchID, round, id, word, build in
                XCTAssertEqual(matchID, final.match.id); XCTAssertEqual(round, 1)
                XCTAssertEqual(id, requestID); XCTAssertEqual(word, "STONE"); XCTAssertEqual(build, 2)
                if attempts.increment() == 1 { throw LiveMatchServiceError.unavailable }
                return Self.receipt()
            }), realtime: realtime, store: store,
            timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(50), retryBackoff: [.seconds(66)]),
            sleep: { duration in
                if duration == .seconds(99) { try await Task.sleep(for: duration) }
                else { await gate.wait() }
            })
            session.changeAccount(to: UUID()); realtime.send(.ready)
            await eventually { session.snapshot == final && !session.isCommandInFlight }
            XCTAssertEqual(session.pendingIntent, intent)
            await gate.open()
            await eventually { session.pendingIntent == nil && !session.isCommandInFlight }
            XCTAssertEqual(attempts.value, 2)
            XCTAssertNil(store.storedState.pendingIntent)
            let completedFetches = fetches.value
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertEqual(fetches.value, completedFetches)
            session.leaveToHome()
        }
    }

    func testCreateDecisionStaysExplicitAfterHomeResumeAndForeground() async throws {
        for denial in [LiveMatchServerError.requestConflict, .rateLimited] {
            let calls = LockedValues<LivePendingIntent>()
            let store = MemoryLiveRecoveryStore()
            let session = makeSession(service: LiveServiceMock(createConfigured: { id, count, build in
                calls.append(.create(requestID: id, roundCount: count, clientBuild: build))
                throw LiveMatchServiceError.server(denial)
            }), realtime: nil, store: store)
            session.changeAccount(to: UUID())
            session.createMatch(roundCount: 5)
            await eventually { !session.isCommandInFlight }
            let original = try XCTUnwrap(session.pendingIntent)
            session.leaveToHome()
            session.resumeSavedMatch()
            session.backgrounded()
            session.foregrounded()
            await Task.yield()
            XCTAssertEqual(calls.values, [original])
            XCTAssertEqual(session.lastError, .server(denial))
            XCTAssertEqual(session.phase, .unavailable)
            XCTAssertTrue(session.canRetry)
            session.retry()
            await eventually { calls.values.count == 2 && !session.isCommandInFlight }
            XCTAssertEqual(calls.values, [original, original])
            session.discardPendingCreate()
            XCTAssertNil(store.storedState.pendingIntent)
            XCTAssertFalse(session.hasSavedMatch)
        }
    }

    func testHomeResumeRejectsLowerRevisionBeforeRestoringPresentation() async throws {
        let current = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        var old = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        old.revision = current.revision - 1
        let stale = old
        let calls = LockedCounter()
        let realtime = RealtimeHub()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: current.match.id))
        let session = makeSession(service: LiveServiceMock(snapshot: { _ in
            calls.increment() == 2 ? stale : current
        }), realtime: realtime, store: store)
        session.changeAccount(to: UUID()); realtime.send(.ready)
        await eventually { session.snapshot == current }
        session.leaveToHome()
        session.resumeSavedMatch(); realtime.send(.ready)
        await eventually { calls.value == 2 }
        await Task.yield()
        XCTAssertNil(session.snapshot, "a resumed view must not restore an earlier round")
        XCTAssertEqual(session.phase, .recovering)
        realtime.send(.signal)
        await eventually { session.snapshot == current }
        session.leaveToHome()
    }

    func testResumeAtNewRoundClearsDraftFromPreviouslyPresentedRound() async throws {
        let first = try Phase4LiveFixtures.snapshot("3-round-1-playing")
        let next = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        let calls = LockedCounter()
        let realtime = RealtimeHub()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: first.match.id))
        let session = makeSession(service: LiveServiceMock(
            submit: { _, _, _ in throw LiveMatchServiceError.server(.wordNotAccepted) },
            snapshot: { _ in calls.increment() <= 2 ? first : next }
        ), realtime: realtime, store: store)
        session.changeAccount(to: UUID()); realtime.send(.ready)
        await eventually { session.phase == .ready }
        session.submitGuess("XXXXX")
        await eventually { calls.value == 2 && !session.isCommandInFlight && session.phase == .ready }
        XCTAssertEqual(session.guessDraft, "XXXXX")
        session.leaveToHome()
        session.resumeSavedMatch(); realtime.send(.ready)
        await eventually { session.snapshot == next }
        XCTAssertEqual(session.guessDraft, "")
        XCTAssertNil(session.lastError)
        session.leaveToHome()
    }

    private func makeSession(
        service: any LiveMatchServicing,
        realtime: (any LiveMatchRealtimeServicing)?,
        store: MemoryLiveRecoveryStore,
        refreshAuth: @escaping LiveMatchSession.AuthRefresh = { _ in false },
        timing: LiveMatchSessionTiming = .production,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        uptime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) -> LiveMatchSession {
        LiveMatchSession(
            service: service,
            realtime: realtime,
            storeFactory: { _ in store },
            refreshAuth: refreshAuth,
            timing: timing,
            sleep: sleep,
            uptime: uptime
        )
    }

    private func eventually(
        timeout: TimeInterval = 1,
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Condition was not satisfied before timeout")
    }

    nonisolated private static func receipt() -> LiveGuessReceipt {
        LiveGuessReceipt(
            sequence: 1,
            feedback: [.correct, .correct, .correct, .correct, .correct],
            playerState: .solved,
            acceptedGuessCount: 1,
            solveDurationMilliseconds: 500,
            efficiencyPoints: 6,
            serverTime: Date(timeIntervalSince1970: 1_001),
            roundEndTime: Date(timeIntervalSince1970: 1_180)
        )
    }

    nonisolated private static func failedReceipt() -> LiveGuessReceipt {
        LiveGuessReceipt(
            sequence: 6,
            feedback: [.absent, .absent, .absent, .absent, .absent],
            playerState: .failed,
            acceptedGuessCount: 6,
            solveDurationMilliseconds: nil,
            efficiencyPoints: nil,
            serverTime: Date(timeIntervalSince1970: 1_006),
            roundEndTime: Date(timeIntervalSince1970: 1_180)
        )
    }

    nonisolated private static func snapshot(
        matchID: UUID,
        status: LiveMatchStatus,
        round state: LiveRoundState,
        serverTime: Date = Date(timeIntervalSince1970: 1_000),
        endsAt: Date? = Date(timeIntervalSince1970: 1_180),
        selfPlayerState: LivePlayerState? = nil
    ) -> LiveMatchSnapshot {
        let memberID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        return LiveMatchSnapshot(
            serverTime: serverTime,
            match: LiveMatch(
                id: matchID,
                joinCode: "ABC234",
                creatorMemberID: memberID,
                status: status,
                expiresAt: Date(timeIntervalSince1970: 4_600),
                minimumClientBuild: 1
            ),
            members: [
                LiveMatchMember(
                    id: memberID,
                    seat: 1,
                    displayName: "Alex",
                    avatarSeed: "seed",
                    isSelf: true,
                    isDeleted: false
                ),
            ],
            round: LiveRound(
                state: state,
                startsAt: state == .pending ? nil : Date(timeIntervalSince1970: 1_000),
                endsAt: state == .pending ? nil : endsAt,
                completedAt: state == .revealed ? serverTime : nil,
                answer: state == .revealed ? "stone" : nil,
                players: selfPlayerState.map {
                    [
                        LiveRoundPlayer(
                            memberID: memberID,
                            state: $0,
                            acceptedGuessCount: $0 == .failed ? 6 : 0,
                            solveDurationMilliseconds: nil,
                            efficiencyPoints: $0 == .failed ? 0 : nil,
                            placement: nil,
                            board: []
                        ),
                    ]
                } ?? []
            )
        )
    }
}

private struct LiveServiceMock: LiveMatchServicing {
    var create: @Sendable (UUID) async throws -> UUID = { _ in throw LiveMatchServiceError.unavailable }
    var join: @Sendable (String) async throws -> UUID = { _ in throw LiveMatchServiceError.unavailable }
    var start: @Sendable (UUID) async throws -> UUID = { _ in throw LiveMatchServiceError.unavailable }
    var submit: @Sendable (UUID, UUID, String) async throws -> LiveGuessReceipt = { _, _, _ in
        throw LiveMatchServiceError.unavailable
    }
    var snapshot: @Sendable (UUID) async throws -> LiveMatchSnapshot = { _ in
        throw LiveMatchServiceError.unavailable
    }

    var createConfigured: (@Sendable (UUID, Int, Int) async throws -> UUID)?
    var startTargeted: (@Sendable (UUID, Int) async throws -> UUID)?
    var submitTargeted: (@Sendable (UUID, Int, UUID, String, Int) async throws -> LiveGuessReceipt)?

    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID {
        if let createConfigured { return try await createConfigured(requestID, roundCount, clientBuild) }
        return try await create(requestID)
    }
    func joinMatch(code: String) async throws -> UUID { try await join(code) }
    func startMatch(id: UUID, roundNumber: Int) async throws -> UUID {
        if let startTargeted { return try await startTargeted(id, roundNumber) }
        return try await start(id)
    }
    func submitGuess(matchID: UUID, roundNumber: Int, requestID: UUID, guess: String,
                     clientBuild: Int) async throws -> LiveGuessReceipt {
        if let submitTargeted { return try await submitTargeted(matchID, roundNumber, requestID, guess, clientBuild) }
        return try await submit(matchID, requestID, guess)
    }
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot { try await snapshot(matchID) }
}

private final class MemoryLiveRecoveryStore: LiveMatchRecoveryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: LiveRecoveryState
    var rejectsWrites = false
    var rejectsLoads = false
    var rejectsClears = false

    var storedState: LiveRecoveryState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    init(_ state: LiveRecoveryState = LiveRecoveryState()) { self.state = state }

    func load() throws -> LiveRecoveryState {
        lock.lock()
        defer { lock.unlock() }
        if rejectsLoads { throw TestFailure.failed }
        return state
    }

    func save(_ state: LiveRecoveryState) throws {
        lock.lock()
        defer { lock.unlock() }
        if rejectsWrites { throw TestFailure.failed }
        self.state = state
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if rejectsClears { throw TestFailure.failed }
        state = LiveRecoveryState()
        rejectsLoads = false
    }
}

@MainActor
private final class MemoryLiveRecoveryStoreFactory {
    private let stores: [UUID: MemoryLiveRecoveryStore]
    private(set) var requestedAccountIDs: [UUID] = []
    var rejectsConstruction = false

    init(_ stores: [UUID: MemoryLiveRecoveryStore]) { self.stores = stores }

    func make(_ userID: UUID) throws -> any LiveMatchRecoveryStoring {
        requestedAccountIDs.append(userID)
        if rejectsConstruction { throw TestFailure.failed }
        guard let store = stores[userID] else { throw TestFailure.failed }
        return store
    }
}

private final class RealtimeHub: LiveMatchRealtimeServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<LiveMatchRealtimeEvent, Error>.Continuation] = []
    private var matchIDs: [UUID] = []

    var subscribedMatchIDs: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return matchIDs
    }

    var subscriptionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            matchIDs.append(matchID)
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func send(_ event: LiveMatchRealtimeEvent) {
        lock.lock()
        let current = continuations
        lock.unlock()
        current.forEach { $0.yield(event) }
    }

    func finish(throwing error: Error) {
        lock.lock()
        let current = continuations
        lock.unlock()
        current.forEach { $0.finish(throwing: error) }
    }
}

private actor SnapshotScript {
    private let first: LiveMatchSnapshot
    private let later: LiveMatchSnapshot
    private let suspendFirst: Bool
    private var continuation: CheckedContinuation<LiveMatchSnapshot, Never>?
    private(set) var callCount = 0

    init(first: LiveMatchSnapshot, later: LiveMatchSnapshot, suspendFirst: Bool = true) {
        self.first = first
        self.later = later
        self.suspendFirst = suspendFirst
    }

    func next() async throws -> LiveMatchSnapshot {
        callCount += 1
        if callCount == 1 {
            if !suspendFirst { return first }
            return await withCheckedContinuation { continuation = $0 }
        }
        return later
    }

    func releaseFirst() {
        continuation?.resume(returning: first)
        continuation = nil
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

private final class LockedValues<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []
    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    @discardableResult
    func increment() -> Int {
        lock.lock()
        storage += 1
        let value = storage
        lock.unlock()
        return value
    }
}

@MainActor
private final class UptimeBox {
    var value: TimeInterval
    init(_ value: TimeInterval) { self.value = value }
}

private enum TestFailure: Error { case failed }
