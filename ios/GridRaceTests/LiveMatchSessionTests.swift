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

    func testUnsupportedRecoveryFormatsPreserveOriginalBytesUntilExplicitClear() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceUnsupportedRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appending(path: "live-recovery-v1.json")
        for version in [0, 1, 2, 4, 99] {
            let bytes = try JSONSerialization.data(withJSONObject: ["formatVersion": version, "matchID": UUID().uuidString])
            try bytes.write(to: file)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
        try store.clear()
        XCTAssertEqual(try store.load(), LiveRecoveryState())
    }


    func testUnsupportedAndInconsistentCurrentRecoveryPreservesOriginalBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceCurrentInvalid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appending(path: "live-recovery-v1.json")
        let match = UUID(), request = UUID()
        let cases: [[String: Any]] = [
            ["formatVersion": 99],
            ["formatVersion": 1, "pendingIntent": ["kind": "create", "requestID": request.uuidString,
                                                  "roundCount": 3, "clientBuild": 3]],
            ["formatVersion": 1, "matchID": match.uuidString,
             "pendingIntent": ["kind": "guess", "matchID": match.uuidString, "requestID": request.uuidString,
                               "word": "STONE", "roundNumber": 2]],
            ["formatVersion": 3, "pendingIntent": ["kind": "create", "requestID": request.uuidString]],
            ["formatVersion": 3, "matchID": match.uuidString,
             "pendingIntent": ["kind": "create", "requestID": request.uuidString, "roundCount": 3, "clientBuild": 3]],
            ["formatVersion": 3, "pendingIntent": ["kind": "create", "requestID": request.uuidString,
                                                  "roundCount": 3, "clientBuild": 1]],
            ["formatVersion": 3, "matchID": match.uuidString,
             "pendingIntent": ["kind": "guess", "matchID": match.uuidString, "requestID": request.uuidString,
                               "word": "STONE", "roundNumber": 2, "clientBuild": 1]],
            ["formatVersion": 3, "matchID": match.uuidString,
             "pendingIntent": ["kind": "guess", "matchID": UUID().uuidString, "requestID": request.uuidString,
                               "word": "STONE", "roundNumber": 2, "clientBuild": 3]],
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
        try Data(#"{"formatVersion":99}"#.utf8).write(
            to: store.directory.appending(path: "live-recovery-v1.json")
        )
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? LiveMatchRecoveryError, .invalidData)
        }
    }
}

@MainActor
final class LiveMatchSessionTests: XCTestCase {
    func testDefinitivelyFailedJoinPreservesPointerUntilExplicitResume() async throws {
        let old = UUID(), store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: UUID()))
        let state = LiveRecoveryState(matchID: old)
        try store.save(state)
        let realtime = RealtimeHub(), joins = LockedCounter()
        let (session, transport) = makeSession(service: LiveServiceMock(join: { _ in
            joins.increment()
            XCTAssertEqual(store.storedState.matchID, old)
            guard case .join = store.storedState.pendingIntent else { XCTFail("Missing durable join"); throw TestFailure.failed }
            throw LiveMatchServiceError.server(.matchNotJoinable)
        }, snapshot: { id in Self.snapshot(matchID: id, status: .lobby, round: .pending) }), realtime: realtime, store: store)
        session.backgrounded(); bindLiveAccount(session, transport: transport(UUID())); session.leaveToHome(); session.foregrounded()
        session.joinMatch(code: "ABC234")
        await eventually { !session.isCommandInFlight }
        XCTAssertEqual(session.savedMatchID, old)
        XCTAssertNil(session.pendingIntent)
        XCTAssertNil(session.snapshot)
        XCTAssertEqual(session.lastError, .server(.matchNotJoinable))
        XCTAssertFalse(session.canRetry)
        XCTAssertEqual(realtime.subscriptionCount, 0)
        session.resumeSavedMatch()
        XCTAssertEqual(realtime.subscriptionCount, 1)
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        XCTAssertEqual(joins.value, 1)
        session.leaveToHome()
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
            let (session, sessionTransport) = makeSession(
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
            bindLiveAccount(session, transport: sessionTransport(UUID()))
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
            XCTAssertEqual(store.storedState.matchID, oldState.matchID)
            XCTAssertNil(store.storedState.pendingIntent)
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
        let (session, sessionTransport) = makeSession(
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
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        XCTAssertEqual(store.storedState.matchID, oldState.matchID)
            XCTAssertNil(store.storedState.pendingIntent)
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
        let (session, sessionTransport) = makeLiveSessionFixture(
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
        session.changeAccount(to: oldAccount, transport: sessionTransport(oldAccount))
        session.leaveToHome()
        session.foregrounded()
        session.joinMatch(code: "ABC234")
        await eventually { joins.value == 1 }

        XCTAssertEqual(session.changeAccount(to: newAccount, transport: sessionTransport(newAccount)), .completed)
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
        let (session, sessionTransport) = makeSession(
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
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        session.leaveToHome()
        session.foregrounded()
        session.joinMatch(code: "ABC234")
        await eventually { joins.value == 1 }
        session.backgrounded()
        await completion.open()
        await eventually { !session.isCommandInFlight }

        XCTAssertEqual(store.storedState, LiveRecoveryState(matchID: newMatchID))
        XCTAssertEqual(realtime.subscriptionCount, 0)
        XCTAssertEqual(snapshots.values, [newMatchID])
        session.foregrounded()
        XCTAssertEqual(realtime.subscribedMatchIDs, [newMatchID])
        XCTAssertEqual(snapshots.values, [newMatchID])
        realtime.send(.ready)
        await eventually { session.phase == .ready }
        XCTAssertEqual(snapshots.values, [newMatchID, newMatchID])
        session.leaveToHome()
    }

    func testVisibleJoinCommitsCanonicalAdmissionThenSubscribesForCatchup() async throws {
        let matchID = UUID()
        let oldMatchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: oldMatchID))
        let realtime = RealtimeHub()
        let snapshots = LockedCounter()
        let (session, sessionTransport) = makeSession(
            service: LiveServiceMock(
                join: { code in
                    XCTAssertEqual(code, "ABC234")
                    return matchID
                },
                snapshot: { requestedID in
                    if store.storedState.pendingIntent == nil { XCTAssertEqual(try store.load().matchID, requestedID) }
                    else { XCTAssertEqual(try store.load().matchID, oldMatchID) }
                    snapshots.increment()
                    return Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
                }
            ),
            realtime: realtime,
            store: store
        )
        session.backgrounded()
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        session.leaveToHome()
        session.foregrounded()

        session.joinMatch(code: "ABC234")

        await eventually { !session.isCommandInFlight && realtime.subscriptionCount == 1 }
        XCTAssertEqual(session.savedMatchID, matchID)
        XCTAssertEqual(try store.load(), LiveRecoveryState(matchID: matchID))
        XCTAssertEqual(realtime.subscribedMatchIDs, [matchID])
        XCTAssertEqual(snapshots.value, 1)
        realtime.send(.ready)
        await eventually { snapshots.value == 2 && session.phase == .ready }
        XCTAssertEqual(session.snapshot?.match.id, matchID)
        session.leaveToHome()
    }

    private func assertDelayedSuccessRespectsHome(
        isCreate: Bool, hasSavedPointer: Bool = false
    ) async throws {
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
            let (session, sessionTransport) = makeLiveSessionFixture(
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
                        XCTAssertEqual(try store.load().matchID, oldState.matchID)
                        XCTAssertNotNil(try store.load().pendingIntent)
                        joins.append(code)
                        await completion.wait()
                        return matchID
                    },
                    snapshot: { requestedID in
                        if isCreate { XCTAssertEqual(try store.load().matchID, requestedID) }
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
            bindLiveAccount(session, transport: sessionTransport(UUID()))
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
            XCTAssertEqual(try store.load().matchID, matchID)
            XCTAssertNil(session.pendingIntent)
            if isCreate || navigation != 1 { XCTAssertNil(session.snapshot) }
            XCTAssertEqual(snapshots.value, isCreate ? 0 : 1)
            XCTAssertEqual(watchdogStarts.value, navigation == 1 && !isCreate ? 1 : 0)
            let resumedInFlight = navigation == 1
            XCTAssertEqual(session.phase, resumedInFlight ? (isCreate ? .recovering : .ready) : .inactive)
            XCTAssertEqual(realtime.subscriptionCount, resumedInFlight ? 1 : 0)

            if !resumedInFlight { session.resumeSavedMatch() }
            await eventually { realtime.subscriptionCount == 1 }
            XCTAssertEqual(realtime.subscribedMatchIDs, [matchID])
            realtime.send(.ready)
            await eventually { session.phase == .ready && snapshots.value == (isCreate ? 1 : 2) }
            XCTAssertEqual(session.snapshot?.match.id, matchID)
            XCTAssertEqual(snapshots.value, isCreate ? 1 : 2)
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: service,
            realtime: nil,
            storeFactory: { _ in store },
            makeUUID: { requestID }
        )
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(
            service: LiveServiceMock(create: { _ in
                creates.increment()
                return UUID()
            }),
            realtime: nil,
            store: store
        )
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        session.leaveToHome()
        store.rejectsWrites = true

        session.createMatch()
        await Task.yield()

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(session.savedMatchID, oldState.matchID)
        XCTAssertNil(session.pendingIntent)
        XCTAssertEqual(store.storedState.matchID, oldState.matchID)
            XCTAssertNil(store.storedState.pendingIntent)
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
        let (session, sessionTransport) = makeSession(
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
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(service: service, realtime: nil, store: store)
        session.changeAccount(to: accountID, transport: sessionTransport(accountID))
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
        session.changeAccount(to: nil, transport: nil)
        session.changeAccount(to: accountID, transport: sessionTransport(accountID))
        session.resumeSavedMatch()
        session.backgrounded()
        session.foregrounded()
        let (relaunched, relaunchedTransport) = makeSession(service: service, realtime: nil, store: store)
        relaunched.changeAccount(to: accountID, transport: relaunchedTransport(accountID))
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
            let (session, sessionTransport) = makeSession(
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
            bindLiveAccount(session, transport: sessionTransport(UUID()))
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
            let (session, sessionTransport) = makeSession(
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
            bindLiveAccount(session, transport: sessionTransport(UUID()))
            await eventually { realtime.subscriptionCount == 1 }
            realtime.send(.ready)
            await eventually { session.snapshot != nil && !session.isCommandInFlight }
            realtime.send(.signal)
            await eventually { snapshots.value == 2 }
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
        for error in [LiveMatchServiceError.unavailable, .server(.internalError)] {
            let requestID = UUID()
            let matchID = UUID()
            let store = MemoryLiveRecoveryStore()
            let creates = LockedValues<UUID>()
            let service = LiveServiceMock(
                create: { receivedRequestID in
                    creates.append(receivedRequestID)
                    if creates.values.count <= 2 { throw error }
                    return matchID
                },
                snapshot: { requestedID in
                    Self.snapshot(matchID: requestedID, status: .lobby, round: .pending)
                }
            )
            let (session, sessionTransport) = makeLiveSessionFixture(
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
            bindLiveAccount(session, transport: sessionTransport(UUID()))

            session.createMatch()
            await eventually { session.phase == .unavailable && !session.isCommandInFlight }
            XCTAssertTrue(session.canRetry)
            XCTAssertEqual(session.lastError, error)
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
            let (resumed, resumedTransport) = makeSession(service: service, realtime: realtime, store: store)
            resumed.backgrounded()
            bindLiveAccount(resumed, transport: resumedTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(service: service, realtime: realtime, store: store)
        session.changeAccount(to: userID, transport: sessionTransport(userID))

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
        let (session, sessionTransport) = makeSession(service: service, realtime: realtime, store: store)

        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(service: service, realtime: realtime, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let lobby = try Self.startSnapshot("3-lobby")
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
        let (session, sessionTransport) = makeSession(service: service, realtime: realtime, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: service,
            realtime: realtime,
            storeFactory: { $0 == firstUser ? firstStore : secondStore }
        )
        XCTAssertEqual(session.changeAccount(to: firstUser, transport: sessionTransport(firstUser)), .completed)
        await eventually { realtime.subscriptionCount == 1 }
        realtime.send(.ready)
        await eventually { await script.callCount == 1 }

        XCTAssertEqual(session.changeAccount(to: secondUser, transport: sessionTransport(secondUser)), .completed)
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { $0 == firstUser ? firstStore : secondStore }
        )
        XCTAssertEqual(session.changeAccount(to: firstUser, transport: sessionTransport(firstUser)), .completed)
        firstStore.rejectsClears = true

        XCTAssertEqual(session.changeAccount(to: secondUser, transport: sessionTransport(secondUser)), .recoveryCleanupPending)
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertNotNil(firstStore.storedState.pendingIntent)

        firstStore.rejectsClears = false
        XCTAssertEqual(session.changeAccount(to: secondUser, transport: sessionTransport(secondUser)), .completed)
        XCTAssertEqual(try firstStore.load(), LiveRecoveryState())
        XCTAssertEqual(session.phase, .inactive)
    }

    func testSelectedRecoveryRetryRequiresAvailableAuthenticationAndForeground() async throws {
        for error in [LiveMatchServiceError.unavailable, .server(.internalError), .server(.notAuthenticated)] {
            let matchID = UUID()
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
            let realtime = RealtimeHub()
            let calls = LockedCounter()
            let (session, sessionTransport) = makeSession(
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
            bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(
            service: service,
            realtime: realtime,
            store: store,
            refreshAuth: { _ in refreshes.increment(); return true }
        )
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(
            service: service,
            realtime: nil,
            store: store,
            timing: .init(
                requestTimeout: .milliseconds(10),
                staleAfter: .seconds(5),
                retryBackoff: [.seconds(100)]
            )
        )
        bindLiveAccount(session, transport: sessionTransport(UUID()))

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
        let (session, sessionTransport) = makeSession(service: service, realtime: nil, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID()))

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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: LiveServiceMock(create: { receivedRequestID in
                creates.append(receivedRequestID)
                return matchID
            }),
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )

        session.changeAccount(to: userID, transport: sessionTransport(userID))
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        session.changeAccount(to: userID, transport: sessionTransport(userID))

        factory.rejectsConstruction = false
        session.discardRecovery()
        session.changeAccount(to: nil, transport: nil)
        session.changeAccount(to: userID, transport: sessionTransport(userID))
        await Task.yield()
        let (relaunched, relaunchedTransport) = makeLiveSessionFixture(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: userID, transport: relaunchedTransport(userID))
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: service,
            realtime: RealtimeHub(),
            storeFactory: { try factory.make($0) }
        )
        session.changeAccount(to: userID, transport: sessionTransport(userID))

        factory.rejectsConstruction = false
        session.discardRecovery()
        session.changeAccount(to: nil, transport: nil)
        session.changeAccount(to: userID, transport: sessionTransport(userID))
        let (relaunched, relaunchedTransport) = makeLiveSessionFixture(
            service: service,
            realtime: RealtimeHub(),
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: userID, transport: relaunchedTransport(userID))
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
        let (switching, switchingTransport) = makeLiveSessionFixture(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { try switchFactory.make($0) }
        )
        switching.changeAccount(to: firstUser, transport: switchingTransport(firstUser))

        switching.changeAccount(to: secondUser, transport: switchingTransport(secondUser))

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
        let (signingOut, signingOutTransport) = makeLiveSessionFixture(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { try signOutFactory.make($0) }
        )
        signingOut.changeAccount(to: firstUser, transport: signingOutTransport(firstUser))

        signingOut.changeAccount(to: nil, transport: nil)

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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) },
            makeUUID: { firstRequestID }
        )
        session.changeAccount(to: firstUser, transport: sessionTransport(firstUser))
        firstStore.rejectsClears = true

        session.changeAccount(to: secondUser, transport: sessionTransport(secondUser))
        session.changeAccount(to: firstUser, transport: sessionTransport(firstUser))

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canRetryRecoveryStorage)
        XCTAssertFalse(session.canRetry)
        XCTAssertEqual(factory.requestedAccountIDs, [firstUser])
        session.createMatch()
        await Task.yield()
        XCTAssertTrue(creates.values.isEmpty, "Auth reversion cannot bypass explicit storage recovery")
        XCTAssertEqual(secondStore.storedState.pendingIntent, .create(requestID: secondRequestID))

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

        let (relaunched, relaunchedTransport) = makeLiveSessionFixture(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: firstUser, transport: relaunchedTransport(firstUser))
        await Task.yield()

        XCTAssertEqual(relaunched.savedMatchID, firstMatchID)
        XCTAssertNil(relaunched.pendingIntent)
        XCTAssertEqual(creates.values, [firstRequestID])
        XCTAssertTrue(factory.requestedAccountIDs.allSatisfy { $0 == firstUser })
        XCTAssertEqual(try firstStore.load().matchID, firstMatchID)
    }

    func testAuthReversionInvalidBindingCannotBypassStorageRetry() async throws {
        for mismatched in [false, true] {
            let a = UUID(), b = UUID(), calls = LockedCounter()
            let oldStore = MemoryLiveRecoveryStore(), newStore = MemoryLiveRecoveryStore()
            let factory = MemoryLiveRecoveryStoreFactory([a: oldStore, b: newStore])
            let (session, transportFor) = makeLiveSessionFixture(
                service: LiveServiceMock(create: { _ in calls.increment(); return UUID() }),
                realtime: nil, storeFactory: factory.make)
            session.changeAccount(to: a, transport: transportFor(a))
            oldStore.rejectsClears = true
            session.changeAccount(to: b, transport: transportFor(b))
            let invalid = LiveAccountTransport(userID: mismatched ? b : a,
                service: LiveServiceMock(create: { _ in calls.increment(); return UUID() }),
                realtime: nil, refresh: { _ in false }, isValid: { mismatched })
            session.changeAccount(to: a, transport: invalid)
            XCTAssertEqual(session.phase, .storageUnavailable)
            XCTAssertEqual(factory.requestedAccountIDs, [a])
            session.createMatch()
            session.retry()
            await Task.yield()
            XCTAssertEqual(calls.value, 0)
            XCTAssertEqual(session.phase, .storageUnavailable)
            XCTAssertEqual(factory.requestedAccountIDs, [a])

            session.changeAccount(to: a, transport: transportFor(a))
            XCTAssertEqual(session.phase, .storageUnavailable, "A fresh binding is not consent to retry storage")
            XCTAssertEqual(factory.requestedAccountIDs, [a])
            session.retry()
            XCTAssertEqual(session.phase, .inactive)
            XCTAssertEqual(factory.requestedAccountIDs, [a, a])
            XCTAssertFalse(factory.requestedAccountIDs.contains(b))
            XCTAssertEqual(calls.value, 0)
            XCTAssertNil(session.pendingIntent)
        }
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) },
            makeUUID: { requestID }
        )
        session.changeAccount(to: userID, transport: sessionTransport(userID))
        store.rejectsClears = true

        session.changeAccount(to: nil, transport: nil)
        session.changeAccount(to: userID, transport: sessionTransport(userID))

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

        let (relaunched, relaunchedTransport) = makeLiveSessionFixture(
            service: service,
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        relaunched.changeAccount(to: userID, transport: relaunchedTransport(userID))
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: LiveServiceMock(),
            realtime: nil,
            storeFactory: { try factory.make($0) }
        )
        session.changeAccount(to: userID, transport: sessionTransport(userID))

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
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(), realtime: nil, store: store)

        bindLiveAccount(session, transport: sessionTransport(UUID()))

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
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(), realtime: nil, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID()))

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
        let (session, sessionTransport) = makeSession(service: service, realtime: nil, store: store)
        let userID = UUID()
        session.changeAccount(to: userID, transport: sessionTransport(userID))

        session.discardRecovery()
        session.changeAccount(to: nil, transport: nil)
        session.changeAccount(to: userID, transport: sessionTransport(userID))
        await Task.yield()
        let (relaunched, relaunchedTransport) = makeSession(service: service, realtime: nil, store: store)
        relaunched.changeAccount(to: userID, transport: relaunchedTransport(userID))
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
        let (session, sessionTransport) = makeLiveSessionFixture(
            service: LiveServiceMock(),
            realtime: RealtimeHub(),
            storeFactory: { $0 == firstUser ? firstStore : secondStore }
        )
        session.changeAccount(to: firstUser, transport: sessionTransport(firstUser))
        firstStore.rejectsClears = true

        session.changeAccount(to: secondUser, transport: sessionTransport(secondUser))

        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertTrue(session.canDiscardRecovery)
        XCTAssertNotNil(firstStore.storedState.pendingIntent)

        session.changeAccount(to: nil, transport: nil)

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
        let (session, sessionTransport) = makeSession(service: service, realtime: nil, store: store)

        bindLiveAccount(session, transport: sessionTransport(UUID()))

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
        let (session, sessionTransport) = makeSession(service: service, realtime: realtime, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(
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
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (rejected, rejectedTransport) = makeSession(
            service: rejectedService,
            realtime: rejectedRealtime,
            store: rejectedStore
        )
        bindLiveAccount(rejected, transport: rejectedTransport(UUID()))
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
        let (conflict, conflictTransport) = makeSession(
            service: conflictService,
            realtime: conflictRealtime,
            store: conflictStore
        )
        bindLiveAccount(conflict, transport: conflictTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(
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
        bindLiveAccount(session, transport: sessionTransport(UUID()))

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
        let (session, sessionTransport) = makeSession(
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
        bindLiveAccount(session, transport: sessionTransport(UUID()))
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

    func testUnsupportedRecoveryBlocksDispatchAndPreservesBytesUntilExplicitDiscard() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceUnsupportedSession-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for format in [1, 2] {
            let user = UUID(), store = LiveMatchRecoveryStore(rootDirectory: root, userID: user)
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let file = store.directory.appending(path: "live-recovery-v1.json")
            let bytes = try JSONSerialization.data(withJSONObject: ["formatVersion": format, "matchID": UUID().uuidString])
            try bytes.write(to: file)
            let calls = LockedCounter()
            let (session, transport) = makeLiveSessionFixture(service: LiveServiceMock(snapshot: { _ in
                calls.increment(); throw TestFailure.failed
            }, createConfigured: { _, _, _ in calls.increment(); throw TestFailure.failed }), realtime: nil, storeFactory: { _ in store })
            bindLiveAccount(session, transport: transport(user))
            XCTAssertEqual(session.phase, .storageUnavailable)
            session.retry(); session.createMatch(); session.resumeSavedMatch()
            await Task.yield()
            XCTAssertEqual(calls.value, 0)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            session.discardRecovery()
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertFalse(session.hasSavedMatch)
            XCTAssertEqual(calls.value, 0)
        }
    }


    func testCreateCountIsDurableAndRetriedWithoutReplacingUUIDOrBuild() async throws {
        for count in [1, 3, 5] {
            let request = UUID(), match = UUID()
            let store = MemoryLiveRecoveryStore()
            let calls = LockedValues<LivePendingIntent>()
            let (session, sessionTransport) = makeLiveSessionFixture(service: LiveServiceMock(createConfigured: { id, roundCount, build in
                let intent = LivePendingIntent.create(requestID: id, roundCount: roundCount, clientBuild: build)
                XCTAssertEqual(store.storedState.pendingIntent, intent)
                calls.append(intent)
                throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, storeFactory: { _ in store }, makeUUID: { request })
            bindLiveAccount(session, transport: sessionTransport(UUID()))
            session.createMatch(roundCount: count)
            await eventually { !session.isCommandInFlight }
            session.retry()
            await eventually { calls.values.count == 2 && !session.isCommandInFlight }
            XCTAssertEqual(calls.values, Array(repeating: .create(requestID: request, roundCount: count, clientBuild: 3), count: 2))
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
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            snapshots.increment()
            return initial
        }, startTargeted: { _, round in
            starts.append(round)
            throw LiveMatchServiceError.unavailable
        }), realtime: realtime, store: store,
        timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77), retryBackoff: [.seconds(66)]))
        bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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
            let initial = try Self.startSnapshot(label)
            let original = LiveRecoveryState(matchID: initial.match.id)
            let store = MemoryLiveRecoveryStore(original)
            let realtime = RealtimeHub()
            let starts = LockedValues<Int>()
            let snapshots = LockedCounter()
            let changes = LockedCounter()
            let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { id in
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
            bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
            await eventually { session.phase == .ready }
            XCTAssertFalse(session.hasPendingStart)
            XCTAssertTrue(session.canRetry, "ordinary recovery is not an unresolved Start")
            withObservationTracking {
                XCTAssertFalse(session.hasPendingStart)
            } onChange: { changes.increment() }
            session.startMatch()
            XCTAssertTrue(session.hasPendingStart)
            XCTAssertFalse(session.canStart)
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
            XCTAssertFalse(session.canStart)
            XCTAssertFalse(session.canRetry)
            session.resumeSavedMatch(); realtime.send(.ready)
            await eventually { session.phase == .ready }
            XCTAssertNil(session.lastError)
            XCTAssertTrue(session.hasPendingStart)
            XCTAssertFalse(session.canStart)
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
                let initial = try Self.startSnapshot(label)
                let canonical = LockedValues<LiveMatchSnapshot>()
                canonical.append(initial)
                let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: initial.match.id))
                let realtime = RealtimeHub()
                let starts = LockedValues<Int>()
                let snapshots = LockedCounter()
                let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
                    snapshots.increment()
                    return canonical.values.last!
                }, startTargeted: { id, round in
                    XCTAssertEqual(id, initial.match.id)
                    starts.append(round)
                    if starts.values.count > 1 { throw LiveMatchServiceError.server(.roundNotActive) }
                    throw LiveMatchServiceError.unavailable
                }), realtime: realtime, store: store,
                timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77), retryBackoff: [.seconds(66)]))
                bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
                await eventually { session.phase == .ready }
                session.startMatch()
                await eventually { !session.isCommandInFlight && snapshots.value >= 2 && session.phase == .ready }
                XCTAssertTrue(session.hasPendingStart)
                XCTAssertFalse(session.canStart)
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
                    session.changeAccount(to: nil, transport: nil)
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
                                                 roundNumber: 1, clientBuild: 3)
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: current.match.id, pendingIntent: intent))
            let realtime = RealtimeHub()
            let attempts = LockedCounter()
            let gate = AsyncGate()
            let clock = UptimeBox(100)
            let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in current }, submitTargeted: {
                match, round, id, word, build in
                XCTAssertEqual(match, current.match.id); XCTAssertEqual(round, 1)
                XCTAssertEqual(id, request); XCTAssertEqual(word, "STONE"); XCTAssertEqual(build, 3)
                if attempts.increment() == 1 { throw LiveMatchServiceError.server(.requestConflict) }
                await gate.wait()
                if succeeds { return Self.receipt() }
                throw LiveMatchServiceError.server(.wordNotAccepted)
            }), realtime: realtime, store: store, uptime: { clock.value })
            bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            let call = fetches.increment()
            if call > 2 { return final }
            return try await script.next()
        }), realtime: realtime, store: store,
        timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(50), retryBackoff: [.seconds(66)]),
        sleep: { duration in
            if duration == .seconds(99) { try await Task.sleep(for: duration) }
            else { timers.increment(); await gate.wait() }
        })
        bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            switch calls.increment() { case 1: initial; case 2: older; default: equal }
        }), realtime: realtime, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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

    func testImmediateResumeRetiresAutomaticPointerFetchWithoutRealtime() async throws {
        for label in ["3-round-2-playing", "3-round-1-reveal", "3-round-3-reveal", "deletion-active-revealed"] {
            for resumeCount in [1, 3] {
                let current = try Phase4LiveFixtures.snapshot(label)
                var old = current
                old.revision = current.revision + 1
                let script = SnapshotScript(first: old, later: current)
                let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: current.match.id))
                let (session, sessionTransport) = makeSession(
                    service: LiveServiceMock(snapshot: { _ in try await script.next() }),
                    realtime: nil, store: store
                )
                bindLiveAccount(session, transport: sessionTransport(UUID()))
                await eventually { await script.callCount == 1 }

                for index in 1...resumeCount {
                    session.resumeSavedMatch()
                    await eventually { await script.callCount == index + 1 }
                    await eventually { session.snapshot == current && session.phase == .ready }
                }
                await script.releaseFirst()
                await Task.yield()
                XCTAssertTrue(session.snapshot == current, label)
                XCTAssertEqual(session.savedMatchID, current.match.id)
                XCTAssertNil(session.pendingIntent)

                session.resumeSavedMatch()
                await eventually { await script.callCount == resumeCount + 2 }
                await eventually { session.snapshot == current && session.phase == .ready }
                session.leaveToHome()
            }
        }
    }

    func testObsoletePointerFetchCannotReleaseRepeatedResumeFetchSlot() async throws {
        let current = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        var old = current
        old.revision = current.revision + 1
        let script = SnapshotScript(first: old, later: current)
        let currentGate = AsyncGate()
        let calls = LockedCounter()
        let oldReturned = LockedCounter()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: current.match.id))
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            if calls.increment() == 1 {
                let received = try await script.next()
                oldReturned.increment()
                return received
            }
            await currentGate.wait()
            return current
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        await eventually { await script.callCount == 1 }
        session.resumeSavedMatch()
        await eventually { calls.value == 2 }
        session.resumeSavedMatch()
        await eventually { calls.value == 3 }

        await script.releaseFirst()
        await eventually { oldReturned.value == 1 }
        await Task.yield()
        XCTAssertNil(session.snapshot)
        session.retry()
        await currentGate.open()
        await eventually { session.snapshot == current && session.phase == .ready }
        await eventually { calls.value == 4 }
        XCTAssertEqual(calls.value, 4, "Retry must coalesce behind the current fetch")
        XCTAssertTrue(session.snapshot == current)
        session.leaveToHome()
    }

    func testDelayedSnapshotCannotReopenHomeOrReplaceResumedPresentation() async throws {
        let initial = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        let next = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        let script = SnapshotScript(first: initial, later: next)
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: initial.match.id))
        let realtime = RealtimeHub()
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in try await script.next() }),
                                  realtime: realtime, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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
                                                 roundNumber: 1, clientBuild: 3)
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: initial.match.id, pendingIntent: intent))
            let realtime = RealtimeHub(), guesses = LockedCounter(), snapshots = LockedCounter()
            let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
                snapshots.increment() == 1 ? initial : next
            }, submitTargeted: { _, _, _, _, _ in
                guesses.increment()
                throw LiveMatchServiceError.server(denial)
            }), realtime: realtime, store: store)
            bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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
                                                 roundNumber: 1, clientBuild: 3)
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: final.match.id, pendingIntent: intent))
            let realtime = RealtimeHub(), attempts = LockedCounter(), fetches = LockedCounter()
            let gate = AsyncGate()
            let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
                fetches.increment(); return final
            }, submitTargeted: { matchID, round, id, word, build in
                XCTAssertEqual(matchID, final.match.id); XCTAssertEqual(round, 1)
                XCTAssertEqual(id, requestID); XCTAssertEqual(word, "STONE"); XCTAssertEqual(build, 3)
                if attempts.increment() == 1 { throw LiveMatchServiceError.unavailable }
                return Self.receipt()
            }), realtime: realtime, store: store,
            timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(50), retryBackoff: [.seconds(66)]),
            sleep: { duration in
                if duration == .seconds(99) { try await Task.sleep(for: duration) }
                else { await gate.wait() }
            })
            bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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
            let (session, sessionTransport) = makeSession(service: LiveServiceMock(createConfigured: { id, count, build in
                calls.append(.create(requestID: id, roundCount: count, clientBuild: build))
                throw LiveMatchServiceError.server(denial)
            }), realtime: nil, store: store)
            bindLiveAccount(session, transport: sessionTransport(UUID()))
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
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            calls.increment() == 2 ? stale : current
        }), realtime: realtime, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(
            submit: { _, _, _ in throw LiveMatchServiceError.server(.wordNotAccepted) },
            snapshot: { _ in calls.increment() <= 2 ? first : next }
        ), realtime: realtime, store: store)
        bindLiveAccount(session, transport: sessionTransport(UUID())); realtime.send(.ready)
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

    nonisolated private static func startSnapshot(_ label: String) throws -> LiveMatchSnapshot {
        guard label == "3-lobby" else { return try Phase4LiveFixtures.snapshot(label) }
        var object = try Phase4LiveFixtures.object(label)
        object["members"] = try Phase4LiveFixtures.object("3-round-1-countdown")["members"]
        return try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(object))
    }

    func testNewStartCapabilityOwnsRosterCreatorExpiryAndRoundPolicy() async throws {
        var cases: [(LiveMatchSnapshot, Bool)] = [
            (try Self.startSnapshot("3-lobby"), true),
            (try Phase4LiveFixtures.snapshot("3-lobby"), false),
            (try Phase4LiveFixtures.snapshot("3-round-1-reveal"), true),
        ]
        for label in ["3-round-2-countdown", "3-round-2-playing", "3-round-3-reveal",
                      "deletion-active", "deletion-between", "deletion-active-revealed"] {
            cases.append((try Phase4LiveFixtures.snapshot(label), false))
        }
        for variant in ["guest", "expired", "deleted"] {
            var object = try Phase4LiveFixtures.object("3-lobby")
            var members = try XCTUnwrap(Phase4LiveFixtures.object("3-round-1-countdown")["members"] as? [[String: Any]])
            if variant == "guest" {
                members[0]["is_self"] = false
                members[1]["is_self"] = true
            }
            object["members"] = members
            var value = try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(object))
            if variant == "deleted" {
                value = LiveMatchSnapshot(serverTime: value.serverTime, match: value.match,
                    members: value.members.map {
                        LiveMatchMember(id: $0.id, seat: $0.seat, displayName: $0.displayName,
                            avatarSeed: $0.avatarSeed, isSelf: $0.isSelf, isDeleted: !$0.isSelf)
                    }, round: value.round, selection: value.selection, rematch: value.rematch)
            } else if variant == "expired" {
                value = LiveMatchSnapshot(serverTime: value.match.expiresAt, match: value.match,
                    members: value.members, round: value.round, selection: value.selection, rematch: value.rematch)
            }
            cases.append((value, false))
        }
        var guestReveal = try Phase4LiveFixtures.object("3-round-1-reveal")
        var guestMembers = try XCTUnwrap(guestReveal["members"] as? [[String: Any]])
        guestMembers[0]["is_self"] = false
        guestMembers[1]["is_self"] = true
        guestReveal["members"] = guestMembers
        cases.append((try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(guestReveal)), false))
        for (snapshot, allowed) in cases {
            let starts = LockedValues<Int>()
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: snapshot.match.id))
            let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in snapshot }, startTargeted: { id, round in
                starts.append(round)
                return id
            }), realtime: nil, store: store, uptime: { 0 })
            XCTAssertFalse(session.canStart)
            bindLiveAccount(session, transport: sessionTransport(UUID()))
            await eventually { session.phase == .ready }
            XCTAssertEqual(session.canStart, allowed)
            if allowed {
                session.backgrounded()
                XCTAssertFalse(session.canStart)
                session.startMatch()
                XCTAssertTrue(starts.values.isEmpty)
                session.foregrounded()
                await eventually { session.phase == .ready }
            }
            session.startMatch()
            if allowed {
                XCTAssertFalse(session.canStart, "duplicate Start is gated during dispatch")
                await eventually { !session.isCommandInFlight && starts.values.count == 1 }
                XCTAssertEqual(starts.values, [snapshot.round.state == .pending ? 1 : snapshot.match.currentRound + 1])
            } else {
                XCTAssertFalse(session.isCommandInFlight)
                XCTAssertTrue(starts.values.isEmpty)
            }
            session.leaveToHome()
            XCTAssertFalse(session.canStart)
        }
        let reveal = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        let late = LiveMatchSnapshot(serverTime: reveal.match.expiresAt.addingTimeInterval(100),
            match: reveal.match, members: reveal.members, round: reveal.round,
            revealedRounds: reveal.revealedRounds, standings: reveal.standings, selection: reveal.selection, rematch: reveal.rematch)
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in late }), realtime: nil,
            store: MemoryLiveRecoveryStore(LiveRecoveryState(matchID: late.match.id)), uptime: { 0 })
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        await eventually { session.phase == .ready }
        XCTAssertTrue(session.canStart)
        session.leaveToHome()
    }

    func testPendingGuessBlocksNewStartAfterCanonicalRevealWithoutReplacingIdentity() async throws {
        let snapshot = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        let pending = LivePendingIntent.guess(matchID: snapshot.match.id, requestID: UUID(),
            word: "CRANE", roundNumber: 1, clientBuild: 3)
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: snapshot.match.id, pendingIntent: pending))
        let starts = LockedValues<Int>()
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in snapshot }, startTargeted: { id, round in
            starts.append(round)
            return id
        }), realtime: nil, store: store,
            timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77), retryBackoff: [.seconds(66)]),
            uptime: { 0 })
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        await eventually { session.phase == .ready && !session.isCommandInFlight }
        XCTAssertFalse(session.canStart)
        XCTAssertFalse(session.canInput)
        session.startMatch()
        XCTAssertTrue(starts.values.isEmpty)
        XCTAssertEqual(store.storedState.pendingIntent, pending)
        session.leaveToHome()
    }

    func testCapturedStartRetryRemainsEligibleAfterLobbyExpiry() async throws {
        let snapshot = try Self.startSnapshot("3-lobby")
        let starts = LockedValues<Int>()
        var clock: TimeInterval = 0
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in snapshot }, startTargeted: { id, round in
            starts.append(round)
            if starts.values.count == 1 { throw LiveMatchServiceError.unavailable }
            return id
        }), realtime: nil, store: MemoryLiveRecoveryStore(LiveRecoveryState(matchID: snapshot.match.id)),
            timing: .init(requestTimeout: .seconds(99), staleAfter: .seconds(77), retryBackoff: [.seconds(66)]),
            uptime: { clock })
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        await eventually { session.phase == .ready }
        session.startMatch()
        await eventually { !session.isCommandInFlight && session.phase == .ready }
        XCTAssertTrue(session.hasPendingStart)
        clock = snapshot.match.expiresAt.timeIntervalSince(snapshot.serverTime)
        XCTAssertFalse(session.canStart)
        XCTAssertTrue(session.canRetry, "new Start policy must not reject an original uncertain target")
        session.startMatch()
        XCTAssertEqual(starts.values, [1])
        session.retry()
        await eventually { !session.isCommandInFlight && starts.values.count == 2 }
        XCTAssertEqual(starts.values, [1, 1])
        session.leaveToHome()
    }

    func testInputCapabilityAndDispatchRequireActiveRequesterBeforeDeadline() async throws {
        let matchID = UUID()
        for state in [LivePlayerState.playing, .solved, .failed, .timedOut, .forfeited] {
            for expired in [false, true] {
                let snapshot = Self.snapshot(matchID: matchID, status: .inProgress, round: .playing,
                    serverTime: Date(timeIntervalSince1970: expired ? 1_180 : 1_000), selfPlayerState: state)
                let calls = LockedCounter()
                let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
                let (session, sessionTransport) = makeSession(service: LiveServiceMock(submit: { _, _, _ in
                    calls.increment()
                    throw LiveMatchServiceError.server(.requestConflict)
                }, snapshot: { _ in snapshot }), realtime: nil, store: store, uptime: { 0 })
                bindLiveAccount(session, transport: sessionTransport(UUID()))
                await eventually { session.phase == .ready }
                let allowed = state == .playing && !expired
                XCTAssertEqual(session.canInput, allowed)
                if allowed {
                    session.backgrounded()
                    XCTAssertFalse(session.canInput)
                    session.submitGuess("STONE")
                    XCTAssertNil(store.storedState.pendingIntent)
                    session.foregrounded()
                    await eventually { session.phase == .ready }
                }
                session.submitGuess("STONE")
                if allowed {
                    XCTAssertFalse(session.canInput, "in-flight and durable pending guesses lock new input")
                    await eventually { !session.isCommandInFlight && calls.value == 1 }
                    XCTAssertNotNil(session.pendingIntent)
                    XCTAssertFalse(session.canInput)
                    XCTAssertFalse(session.canStart)
                    let original = store.storedState.pendingIntent
                    session.submitGuess("CRANE")
                    XCTAssertEqual(store.storedState.pendingIntent, original)
                    XCTAssertEqual(calls.value, 1)
                } else {
                    XCTAssertNil(store.storedState.pendingIntent)
                    XCTAssertEqual(calls.value, 0)
                }
                session.leaveToHome()
                XCTAssertFalse(session.canInput)
            }
        }
    }

    func testDeletionBlockedMatchStillPermitsSurvivorInputInActiveRound() async throws {
        let initial = try Phase4LiveFixtures.snapshot("deletion-active")
        let round = LiveRound(state: .playing, startsAt: initial.round.startsAt,
            endsAt: initial.round.endsAt, completedAt: nil, answer: nil, players: initial.round.players,
            number: initial.round.number)
        let snapshot = LiveMatchSnapshot(serverTime: try XCTUnwrap(round.startsAt), match: initial.match,
            members: initial.members, round: round, revision: initial.revision,
            revealedRounds: initial.revealedRounds, standings: initial.standings, selection: initial.selection, rematch: initial.rematch)
        let (session, sessionTransport) = makeSession(service: LiveServiceMock(snapshot: { _ in snapshot }), realtime: nil,
            store: MemoryLiveRecoveryStore(LiveRecoveryState(matchID: snapshot.match.id)), uptime: { 0 })
        bindLiveAccount(session, transport: sessionTransport(UUID()))
        await eventually { session.phase == .ready }
        XCTAssertTrue(session.canInput, "deletion blocks future Starts, while the survivor finishes this round")
        XCTAssertFalse(session.canStart)
        session.changeAccount(to: nil, transport: nil)
        XCTAssertFalse(session.canInput)
        XCTAssertFalse(session.canStart)
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
    ) -> (LiveMatchSession, (UUID) -> LiveAccountTransport) {
        makeLiveSessionFixture(
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
                minimumClientBuild: 3
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
                players: (selfPlayerState ?? (state == .playing ? .playing : nil)).map {
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
            ), selection: .init(epoch: 1, isSelected: true)
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

    var joinDurable: (@Sendable (LiveJoinCommand) async throws -> UUID)?
    var rematchCommand: @Sendable (LiveRematchCommand) async throws -> LiveRematchReceipt = { _ in throw LiveMatchServiceError.unavailable }
    var createConfigured: (@Sendable (UUID, Int, Int) async throws -> UUID)?
    var startTargeted: (@Sendable (UUID, Int) async throws -> UUID)?
    var submitTargeted: (@Sendable (UUID, Int, UUID, String, Int) async throws -> LiveGuessReceipt)?

    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID {
        if let createConfigured { return try await createConfigured(requestID, roundCount, clientBuild) }
        return try await create(requestID)
    }
    func joinMatch(_ command: LiveJoinCommand) async throws -> UUID {
        if let joinDurable { return try await joinDurable(command) }
        return try await join(command.code)
    }
    func rematch(_ command: LiveRematchCommand) async throws -> LiveRematchReceipt { try await rematchCommand(command) }
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

@MainActor
extension LiveMatchSessionTests {
    func testAccountBoundTransportRemainsFencedDuringCleanupAndInstallsOnlyRequestedTarget() async {
        for discard in [false, true] {
            let a = UUID(), b = UUID(), callsA = LockedCounter(), callsB = LockedCounter()
            let oldStore = MemoryLiveRecoveryStore(), newStore = MemoryLiveRecoveryStore()
            let session = LiveMatchSession(
                storeFactory: { $0 == a ? oldStore : newStore })
            let transportA = LiveAccountTransport(userID: a, service: LiveServiceMock(create: { _ in
                callsA.increment(); throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, refresh: { _ in false }, isValid: { true })
            let transportB = LiveAccountTransport(userID: b, service: LiveServiceMock(create: { _ in
                callsB.increment(); throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, refresh: { _ in false }, isValid: { true })
            session.changeAccount(to: a, transport: transportA)
            oldStore.rejectsClears = true
            XCTAssertEqual(session.changeAccount(to: b, transport: transportB), .recoveryCleanupPending)
            session.createMatch()
            XCTAssertEqual(callsA.value, 0); XCTAssertEqual(callsB.value, 0)
            XCTAssertTrue(session.hasPendingAccountCleanup(for: a))
            oldStore.rejectsClears = false
            if discard { session.discardRecovery() } else { session.retry() }
            XCTAssertFalse(session.hasPendingAccountCleanup(for: a))
            session.createMatch()
            await eventually { callsB.value == 1 && !session.isCommandInFlight }
            XCTAssertEqual(callsA.value, 0)
            session.changeAccount(to: nil, transport: nil)
            session.createMatch()
            XCTAssertEqual(callsB.value, 1)
        }
    }

    func testUnavailableTargetBindingCannotReuseOldTransportAfterCleanup() async {
        let a = UUID(), b = UUID(), calls = LockedCounter(), oldStore = MemoryLiveRecoveryStore()
        let session = LiveMatchSession(storeFactory: { _ in oldStore })
        let old = LiveAccountTransport(userID: a, service: LiveServiceMock(create: { _ in
            calls.increment(); throw LiveMatchServiceError.unavailable
        }), realtime: nil, refresh: { _ in false }, isValid: { true })
        session.changeAccount(to: a, transport: old)
        oldStore.rejectsClears = true
        session.changeAccount(to: b, transport: nil)
        oldStore.rejectsClears = false
        session.discardRecovery()
        XCTAssertEqual(session.phase, .needsSignIn)
        session.createMatch(); await Task.yield()
        XCTAssertEqual(calls.value, 0)
    }
}

@MainActor
extension LiveMatchSessionTests {
    func testCapturedOldAccountCleanupRetryPreservesActiveLaterAccountAndTransport() async throws {
        for discard in [false, true] {
            let root = FileManager.default.temporaryDirectory.appending(path: "CapturedCleanupB-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let a = UUID(), b = UUID(), callsA = LockedCounter(), callsB = LockedCounter()
            let oldStore = MemoryLiveRecoveryStore()
            let laterStore = LiveMatchRecoveryStore(rootDirectory: root, userID: b)
            try laterStore.save(LiveRecoveryState())
            let laterFile = laterStore.directory.appending(path: "live-recovery-v1.json")
            let originalLaterBytes = try Data(contentsOf: laterFile)
            let journal = AccountCleanupJournal(storage: AccountCleanupJournalFile(directory: root))
            let session = LiveMatchSession(
                storeFactory: { userID in
                    if userID == a { return oldStore }
                    return laterStore
                }, cleanupJournal: journal)
            let transportA = LiveAccountTransport(userID: a, service: LiveServiceMock(create: { _ in
                callsA.increment(); throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, refresh: { _ in false }, isValid: { true })
            let transportB = LiveAccountTransport(userID: b, service: LiveServiceMock(create: { _ in
                callsB.increment(); throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, refresh: { _ in false }, isValid: { true })
            XCTAssertEqual(session.changeAccount(to: a, transport: transportA), .completed)
            XCTAssertEqual(session.changeAccount(to: b, transport: transportB), .completed)
            let laterPhase = session.phase
            try oldStore.save(LiveRecoveryState(pendingIntent: .create(requestID: UUID())))
            oldStore.rejectsClears = true
            XCTAssertEqual(session.cleanupCapturedAccount(a), .recoveryCleanupPending)
            XCTAssertTrue(session.hasPendingAccountCleanup(for: a))
            XCTAssertEqual(session.phase, .storageUnavailable)
            oldStore.rejectsClears = false
            if discard { session.discardRecovery() } else { session.retry() }
            XCTAssertEqual(session.phase, laterPhase)
            XCTAssertFalse(session.hasPendingAccountCleanup(for: a))
            XCTAssertEqual(try Data(contentsOf: laterFile), originalLaterBytes)
            XCTAssertEqual(try oldStore.load(), LiveRecoveryState())
            session.createMatch()
            await eventually { callsB.value == 1 && !session.isCommandInFlight }
            XCTAssertEqual(callsA.value, 0)
            XCTAssertEqual(callsB.value, 1, "Retry must retain B's identity and existing usable transport")
        }
    }
}

@MainActor
extension LiveMatchSessionTests {
    func testRepeatedNilTransitionRetriesCapturedJournalCleanupWithoutDispatchingOldIntent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "RepeatedNilJournal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), oldStore = MemoryLiveRecoveryStore(), calls = LockedCounter()
        let journal = AccountCleanupJournal(storage: AccountCleanupJournalFile(directory: root))
        let session = LiveMatchSession(storeFactory: { _ in oldStore }, cleanupJournal: journal)
        let transport = LiveAccountTransport(userID: user, service: LiveServiceMock(create: { _ in
            calls.increment(); throw LiveMatchServiceError.server(.requestConflict)
        }), realtime: nil, refresh: { _ in false }, isValid: { true })
        XCTAssertEqual(session.changeAccount(to: user, transport: transport), .completed)
        try oldStore.save(LiveRecoveryState(pendingIntent: .create(requestID: UUID())))
        oldStore.rejectsClears = true
        XCTAssertEqual(session.changeAccount(to: nil, transport: nil), .recoveryCleanupPending)
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(journal.liveUsers, [user])
        XCTAssertTrue(session.canDiscardRecovery)
        oldStore.rejectsClears = false
        XCTAssertEqual(session.changeAccount(to: nil, transport: nil), .completed)
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertFalse(session.canDiscardRecovery)
        XCTAssertEqual(try oldStore.load(), LiveRecoveryState())
        XCTAssertTrue(AccountCleanupJournal(storage: AccountCleanupJournalFile(directory: root)).records.isEmpty)
        session.createMatch()
        await Task.yield()
        XCTAssertEqual(calls.value, 0)
    }
}

@MainActor
extension LiveMatchSessionTests {
    func testMismatchedOrRevokedTargetTransportCannotDispatch() async {
        for mismatched in [false, true] {
            let user = UUID(), calls = LockedCounter(), store = MemoryLiveRecoveryStore()
            let session = LiveMatchSession(storeFactory: { _ in store })
            let transport = LiveAccountTransport(userID: mismatched ? UUID() : user,
                service: LiveServiceMock(create: { _ in calls.increment(); return UUID() }),
                realtime: nil, refresh: { _ in false }, isValid: { mismatched })
            session.changeAccount(to: user, transport: transport)
            XCTAssertEqual(session.phase, .needsSignIn)
            session.createMatch()
            await Task.yield()
            XCTAssertEqual(calls.value, 0)
            XCTAssertNil(session.pendingIntent)
        }
    }

    func testHeldAccountRefreshCannotRetryAfterAccountSwitch() async {
        let a = UUID(), b = UUID(), callsA = LockedCounter(), callsB = LockedCounter()
        let refreshes = LockedCounter(), refreshReturns = LockedCounter(), refreshGate = AsyncGate()
        let oldStore = MemoryLiveRecoveryStore(), newStore = MemoryLiveRecoveryStore()
        let session = LiveMatchSession(storeFactory: { $0 == a ? oldStore : newStore })
        let old = LiveAccountTransport(userID: a,
            service: LiveServiceMock(create: { _ in
                callsA.increment(); throw LiveMatchServiceError.server(.notAuthenticated)
            }), realtime: nil, refresh: { userID in
                XCTAssertEqual(userID, a)
                refreshes.increment()
                await refreshGate.wait()
                refreshReturns.increment()
                return true
            }, isValid: { true })
        let next = LiveAccountTransport(userID: b,
            service: LiveServiceMock(create: { _ in
                callsB.increment(); throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, refresh: { _ in XCTFail("B must not borrow A's refresh"); return false },
            isValid: { true })
        session.changeAccount(to: a, transport: old)
        session.createMatch()
        await eventually { refreshes.value == 1 }
        session.changeAccount(to: b, transport: next)
        session.createMatch()
        await eventually { callsB.value == 1 && !session.isCommandInFlight }
        let pendingB = session.pendingIntent
        await refreshGate.open()
        await eventually { refreshReturns.value == 1 }
        await Task.yield()
        XCTAssertEqual(callsA.value, 1, "A's held refresh cannot retry its retired command")
        XCTAssertEqual(callsB.value, 1)
        XCTAssertEqual(session.pendingIntent, pendingB)
        XCTAssertEqual(session.lastError, .server(.requestConflict))
        XCTAssertEqual(try? oldStore.load(), LiveRecoveryState())
        session.leaveToHome()
    }

    func testRequestedTransportRevokedDuringCleanupCannotInstall() async {
        let a = UUID(), b = UUID(), calls = LockedCounter(), revoked = LockedCounter()
        let oldStore = MemoryLiveRecoveryStore(), newStore = MemoryLiveRecoveryStore()
        let session = LiveMatchSession(storeFactory: { $0 == a ? oldStore : newStore })
        let old = LiveAccountTransport(userID: a, service: LiveServiceMock(), realtime: nil,
            refresh: { _ in false }, isValid: { true })
        let next = LiveAccountTransport(userID: b,
            service: LiveServiceMock(create: { _ in calls.increment(); return UUID() }),
            realtime: nil, refresh: { _ in false }, isValid: { revoked.value == 0 })
        session.changeAccount(to: a, transport: old)
        oldStore.rejectsClears = true
        XCTAssertEqual(session.changeAccount(to: b, transport: next), .recoveryCleanupPending)
        revoked.increment()
        oldStore.rejectsClears = false
        session.retry()
        XCTAssertEqual(session.phase, .needsSignIn)
        XCTAssertFalse(session.hasPendingAccountCleanup(for: a))
        session.createMatch()
        await Task.yield()
        XCTAssertEqual(calls.value, 0)
        XCTAssertNil(session.pendingIntent)
    }
}

@MainActor
func makeLiveSessionFixture(
    service: any LiveMatchServicing,
    realtime: (any LiveMatchRealtimeServicing)?,
    storeFactory: @escaping LiveMatchSession.StoreFactory,
    cleanupJournal: AccountCleanupJournal? = nil,
    refreshAuth: @escaping LiveMatchSession.AuthRefresh = { _ in false },
    timing: LiveMatchSessionTiming = .production,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    makeUUID: @escaping @MainActor () -> UUID = UUID.init
) -> (LiveMatchSession, (UUID) -> LiveAccountTransport) {
    let session = LiveMatchSession(storeFactory: storeFactory, cleanupJournal: cleanupJournal,
        timing: timing, sleep: sleep, uptime: uptime, makeUUID: makeUUID)
    return (session, { userID in
        LiveAccountTransport(userID: userID, service: service, realtime: realtime,
            refresh: refreshAuth, isValid: { true })
    })
}

@MainActor
@discardableResult
func bindLiveAccount(_ session: LiveMatchSession, transport: LiveAccountTransport) -> LiveAccountChangeOutcome {
    session.changeAccount(to: transport.userID, transport: transport)
}

extension LiveMatchRecoveryStoreTests {
    func testFormat3SelectionIntentsRoundTripAndRejectDowngradeOrBrokenPin() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceV3-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        let match = UUID(), navigation = UUID(), invitation = UUID()
        let join = LiveJoinCommand(requestID: UUID(), code: "ABC234", expectedMatchID: match, clientBuild: 3)
        let rematch = LiveRematchCommand(requestID: UUID(), predecessorMatchID: match, generation: 2,
                                         action: .offer, expectedParticipationEpoch: 9, clientBuild: 3)
        for intent in [LivePendingIntent.join(command: join, sourceMatchID: match,
                                               navigationGeneration: navigation, invitationGeneration: invitation),
                       .rematch(command: rematch, sourceMatchID: match, navigationGeneration: navigation)] {
            let state = LiveRecoveryState(matchID: match, pendingIntent: intent)
            try store.save(state)
            XCTAssertEqual(try store.load(), state)
            let file = store.directory.appending(path: "live-recovery-v1.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            object["formatVersion"] = 2
            let downgraded = try JSONSerialization.data(withJSONObject: object)
            try downgraded.write(to: file)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: file), downgraded)
        }
        XCTAssertThrowsError(try store.save(LiveRecoveryState(matchID: UUID(), pendingIntent:
            .join(command: join, sourceMatchID: match, navigationGeneration: navigation, invitationGeneration: invitation))))
    }


}

extension LiveMatchSessionTests {
    func testInvitationJoinPersistsOriginalPayloadAndCanonicalPointerBeforeGenerationCompletion() async throws {
        let old = UUID(), invitation = UUID(), admitted = try FriendsBetaFixtures.snapshot("successor_lobby")
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: old))
        let calls = LockedValues<LiveJoinCommand>()
        let readGate = AsyncGate()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            await readGate.wait()
            return admitted
        }, joinDurable: { command in
            guard case .join(let saved, let source, _, let savedInvitation) = store.storedState.pendingIntent else {
                XCTFail("Join must be durable before dispatch"); throw LiveMatchServiceError.invalidResponse
            }
            XCTAssertEqual(saved, command); XCTAssertEqual(source, old); XCTAssertEqual(savedInvitation, invitation)
            calls.append(command)
            return admitted.match.id
        }), realtime: nil, store: store)
        session.backgrounded(); bindLiveAccount(session, transport: transport(UUID())); session.leaveToHome(); session.foregrounded()
        session.joinMatch(code: "abc234", invitationGeneration: invitation)
        await eventually { calls.values.count == 1 }
        XCTAssertEqual(session.savedMatchID, old)
        XCTAssertNil(session.completedInvitationGeneration)
        XCTAssertNil(calls.values[0].expectedMatchID)
        await readGate.open()
        await eventually { !session.isCommandInFlight && session.savedMatchID == admitted.match.id }
        XCTAssertNil(store.storedState.pendingIntent)
        XCTAssertEqual(session.completedInvitationGeneration, invitation)
        session.leaveToHome()
    }

    func testJoinReceiptReplayAfterPointerWriteFailureAndRelaunchKeepsExactUUIDAndInvitation() async throws {
        let old = UUID(), invitation = UUID(), admitted = try FriendsBetaFixtures.snapshot("successor_lobby")
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: old))
        let commands = LockedValues<LiveJoinCommand>()
        let service = LiveServiceMock(snapshot: { _ in admitted }, joinDurable: { command in
            commands.append(command)
            if commands.values.count == 1 { store.rejectsWrites = true }
            return admitted.match.id
        })
        let (first, firstTransport) = makeSession(service: service, realtime: nil, store: store)
        let account = UUID()
        first.backgrounded(); bindLiveAccount(first, transport: firstTransport(account)); first.leaveToHome(); first.foregrounded()
        first.joinMatch(code: "ABC234", invitationGeneration: invitation)
        await eventually { first.phase == .storageUnavailable && !first.isCommandInFlight }
        XCTAssertEqual(first.savedMatchID, old)
        XCTAssertNotNil(store.storedState.pendingIntent)
        XCTAssertNil(first.completedInvitationGeneration)
        XCTAssertNil(store.storedState.completedInvitationGeneration)
        first.leaveToHome()
        store.rejectsWrites = false
        let (relaunch, relaunchTransport) = makeSession(service: service, realtime: nil, store: store)
        bindLiveAccount(relaunch, transport: relaunchTransport(account))
        await eventually { relaunch.savedMatchID == admitted.match.id && !relaunch.isCommandInFlight }
        XCTAssertEqual(commands.values.count, 2)
        XCTAssertEqual(commands.values[0], commands.values[1])
        XCTAssertEqual(relaunch.completedInvitationGeneration, invitation)
        relaunch.leaveToHome()
    }

    func testPassiveStalePointerResumeRequiresPinnedJoinConfirmationAndNeverSelectsOnForeground() async throws {
        var stale = try FriendsBetaFixtures.snapshot("eligible")
        stale.selection = .init(epoch: 10, isSelected: false)
        stale.rematch = nil
        let value = stale
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: value.match.id))
        let joins = LockedValues<LiveJoinCommand>()
        let service = LiveServiceMock(snapshot: { _ in value }, joinDurable: { command in
            joins.append(command)
            return value.match.id
        })
        let (session, transport) = makeSession(service: service, realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.phase == .ready }
        XCTAssertTrue(session.requiresResumeConfirmation)
        XCTAssertTrue(session.availableRematchActions.isEmpty)
        XCTAssertTrue(joins.values.isEmpty)
        session.backgrounded(); session.foregrounded()
        await eventually { session.phase == .ready }
        XCTAssertTrue(joins.values.isEmpty)
        session.confirmResumeSavedMatch()
        await eventually { joins.values.count == 1 && !session.isCommandInFlight }
        XCTAssertEqual(joins.values[0].expectedMatchID, value.match.id)
        XCTAssertEqual(joins.values[0].code, value.match.joinCode)
        session.leaveToHome()
    }

    func testAcceptedSuccessorDiscoveryPrecedesPinnedPredecessorSelection() async throws {
        let predecessor = try FriendsBetaFixtures.snapshot("accepted")
        let successor = try FriendsBetaFixtures.snapshot("successor_lobby")
        let reads = LockedValues<UUID>(), joins = LockedCounter()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: predecessor.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            reads.append(id)
            return id == predecessor.match.id ? predecessor : successor
        }, joinDurable: { _ in joins.increment(); return successor.match.id }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.savedMatchID == successor.match.id && session.phase == .ready }
        XCTAssertEqual(Array(reads.values.prefix(2)), [predecessor.match.id, successor.match.id])
        XCTAssertEqual(joins.value, 0)
        session.leaveToHome()
    }

    func testRematchReceiptFirstRecoveryRetainsPredecessorUntilCanonicalSuccessorAndAtomicSave() async throws {
        let predecessor = try FriendsBetaFixtures.snapshot("accepted"), successor = try FriendsBetaFixtures.snapshot("successor_lobby")
        let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: predecessor.match.id,
                                         generation: 1, action: .accept, expectedParticipationEpoch: 4, clientBuild: 3)
        let intent = LivePendingIntent.rematch(command: command, sourceMatchID: predecessor.match.id, navigationGeneration: UUID())
        let completedInvitation = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: predecessor.match.id, pendingIntent: intent, completedInvitationGeneration: completedInvitation))
        let events = LockedValues<String>(), gate = AsyncGate()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            events.append(id == predecessor.match.id ? "predecessor" : "successor")
            if id == successor.match.id { await gate.wait() }
            if store.storedState.pendingIntent != nil {
                XCTAssertEqual(store.storedState.matchID, predecessor.match.id)
                XCTAssertEqual(store.storedState.pendingIntent, intent)
            }
            return id == predecessor.match.id ? predecessor : successor
        }, rematchCommand: { received in
            events.append("receipt"); XCTAssertEqual(received, command)
            return .init(predecessorMatchID: predecessor.match.id, generation: 1, state: .accepted, successorMatchID: successor.match.id)
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { events.values == ["receipt", "predecessor", "successor"] }
        XCTAssertEqual(session.savedMatchID, predecessor.match.id)
        await gate.open()
        await eventually { !session.isCommandInFlight && session.savedMatchID == successor.match.id }
        XCTAssertNil(store.storedState.pendingIntent)
        XCTAssertEqual(store.storedState.completedInvitationGeneration, completedInvitation)
        session.leaveToHome()
    }

    func testHomeDuringRematchReceiptCannotFollowSuccessorUntilExplicitResume() async throws {
        let offered = try FriendsBetaFixtures.snapshot("offered"), accepted = try FriendsBetaFixtures.snapshot("accepted")
        let successor = try FriendsBetaFixtures.snapshot("successor_lobby")
        let gate = AsyncGate(), calls = LockedCounter(), reads = LockedValues<UUID>()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: offered.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            reads.append(id)
            if id == successor.match.id { return successor }
            return calls.value == 0 ? offered : accepted
        }, rematchCommand: { command in
            calls.increment(); await gate.wait()
            return .init(predecessorMatchID: command.predecessorMatchID, generation: command.generation,
                         state: .accepted, successorMatchID: successor.match.id)
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.phase == .ready }
        let action = try XCTUnwrap(session.availableRematchActions.first)
        session.performRematch(action)
        await eventually { calls.value == 1 }
        session.leaveToHome()
        await gate.open()
        await eventually { !session.isCommandInFlight }
        XCTAssertEqual(session.savedMatchID, offered.match.id)
        XCTAssertNil(session.snapshot)
        XCTAssertFalse(reads.values.contains(successor.match.id))
        session.resumeSavedMatch()
        await eventually { session.savedMatchID == successor.match.id }
        session.leaveToHome()
    }

    func testIndependentGameplayRematchAndViewerEpochMergeDelayedSignals() async throws {
        var first = try FriendsBetaFixtures.snapshot("eligible")
        first.revision = 20; first.selection = .init(epoch: 8, isSelected: true)
        var second = try FriendsBetaFixtures.snapshot("offered")
        second.revision = 19; second.selection = .init(epoch: 9, isSelected: false)
        var third = first
        third.revision = 21; third.selection = .init(epoch: 8, isSelected: true)
        let sequence = [first, second, third]
        let count = LockedCounter()
        let realtime = RealtimeHub(), store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: first.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            count.increment(); return sequence[min(count.value - 1, 2)]
        }), realtime: realtime, store: store)
        bindLiveAccount(session, transport: transport(UUID())); realtime.send(.ready)
        await eventually { session.snapshot?.revision == 20 }
        realtime.send(.signal)
        await eventually { session.snapshot?.selection.epoch == 9 }
        XCTAssertEqual(session.snapshot?.revision, 20)
        XCTAssertEqual(session.snapshot?.rematch?.state, .offered)
        realtime.send(.signal)
        await eventually { session.snapshot?.revision == 21 }
        XCTAssertEqual(session.snapshot?.selection.epoch, 9)
        XCTAssertEqual(session.snapshot?.rematch?.state, .offered)
        XCTAssertTrue(session.requiresResumeConfirmation)
        session.leaveToHome()
    }

    func testBuild3ProtocolFailureRetainsOriginalIntentAndSuspendsRetryOnReconnect() async throws {
        let command = LiveJoinCommand(requestID: UUID(), code: "ABC234", expectedMatchID: nil, clientBuild: 3)
        let intent = LivePendingIntent.join(command: command, sourceMatchID: nil, navigationGeneration: UUID(), invitationGeneration: UUID())
        let state = LiveRecoveryState(pendingIntent: intent), store = MemoryLiveRecoveryStore(LiveRecoveryState(pendingIntent: intent))
        let calls = LockedCounter()
        let (session, transport) = makeSession(service: LiveServiceMock(joinDurable: { value in
            XCTAssertEqual(value, command); calls.increment(); throw LiveMatchServiceError.server(.clientUpdateRequired)
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.serviceNeedsUpdate && !session.isCommandInFlight }
        XCTAssertEqual(store.storedState, state)
        XCTAssertTrue(session.canRetry)
        session.backgrounded(); session.foregrounded(); session.resumeSavedMatch()
        await Task.yield()
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(store.storedState, state)
        session.leaveToHome()
    }
}

extension LiveMatchSessionTests {
    func testAcceptedSelectedElsewhereDiscoversReadOnlyTargetAndRequiresExplicitPinnedConfirmation() async throws {
        let predecessor = try FriendsBetaFixtures.snapshot("accepted_selected_elsewhere")
        var lobby = try FriendsBetaFixtures.snapshot("successor_lobby")
        lobby.selection = .init(epoch: 6, isSelected: false)
        let successor = lobby, joins = LockedValues<LiveJoinCommand>()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: predecessor.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            id == predecessor.match.id ? predecessor : successor
        }, joinDurable: { value in joins.append(value); return successor.match.id }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.resumeConfirmationTarget?.match.id == successor.match.id }
        session.leaveToHome(); session.resumeSavedMatch()
        await eventually { session.resumeConfirmationTarget?.match.id == successor.match.id }
        XCTAssertEqual(session.savedMatchID, predecessor.match.id)
        XCTAssertEqual(store.storedState.matchID, predecessor.match.id)
        XCTAssertTrue(session.requiresResumeConfirmation)
        XCTAssertTrue(joins.values.isEmpty)
        XCTAssertEqual(session.resumeConfirmationTarget?.match.joinCode, successor.match.joinCode)
        session.confirmResumeSavedMatch()
        await eventually { !session.isCommandInFlight && session.savedMatchID == successor.match.id }
        XCTAssertEqual(joins.values.count, 1)
        XCTAssertEqual(joins.values[0].expectedMatchID, successor.match.id)
        XCTAssertEqual(joins.values[0].code, successor.match.joinCode)
        session.leaveToHome()
    }

    func testLowerViewerEpochCannotEraseSelectedElsewhereAtEqualRematchRevision() async throws {
        let first = try FriendsBetaFixtures.snapshot("accepted_selected_elsewhere")
        var delayed = try FriendsBetaFixtures.snapshot("accepted")
        delayed.revision = first.revision + 1
        let second = delayed, calls = LockedCounter(), reads = LockedValues<UUID>()
        let successor = try FriendsBetaFixtures.snapshot("successor_lobby")
        let realtime = RealtimeHub(), store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: first.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            reads.append(id)
            if id == successor.match.id { return successor }
            calls.increment(); return calls.value == 1 ? first : second
        }), realtime: realtime, store: store)
        bindLiveAccount(session, transport: transport(UUID())); realtime.send(.ready)
        await eventually { session.resumeConfirmationTarget != nil }
        realtime.send(.signal)
        await eventually { session.snapshot?.revision == second.revision }
        XCTAssertEqual(session.snapshot?.selection.epoch, first.selection.epoch)
        XCTAssertEqual(session.snapshot?.rematch?.selectedElsewhere, true)
        XCTAssertEqual(session.savedMatchID, first.match.id)
        XCTAssertNil(session.pendingIntent)
        session.leaveToHome()
    }

    func testLostJoinReplyRetainsExactIntentAcrossForegroundAndExplicitRetry() async throws {
        let old = UUID(), calls = LockedValues<LiveJoinCommand>()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: old))
        let (session, transport) = makeSession(service: LiveServiceMock(joinDurable: { value in
            calls.append(value); throw LiveMatchServiceError.unavailable
        }), realtime: nil, store: store, timing: .init(requestTimeout: .seconds(10), staleAfter: .seconds(50), retryBackoff: [.seconds(50)]))
        session.backgrounded(); bindLiveAccount(session, transport: transport(UUID())); session.leaveToHome(); session.foregrounded()
        session.joinMatch(code: "ABC234", invitationGeneration: UUID())
        await eventually { !session.isCommandInFlight && calls.values.count == 1 }
        let original = session.pendingIntent
        XCTAssertEqual(session.savedMatchID, old)
        XCTAssertNotNil(original)
        session.retry()
        await eventually { !session.isCommandInFlight && calls.values.count == 2 }
        XCTAssertEqual(calls.values[0], calls.values[1])
        XCTAssertEqual(session.pendingIntent, original)
        session.leaveToHome()
    }
}

extension LiveMatchSessionTests {
    func testEveryCanonicalRematchStateOwnsAvailableActionsAndFreshGeneration() async throws {
        let cases: [(String, [LiveRematchAction])] = [
            ("eligible", [.offer]), ("offered", [.cancel]), ("closed", [.offer]),
            ("expired", []), ("unavailable", []), ("accepted_unavailable", []), ("moved", [])
        ]
        for (name, expected) in cases {
            let value = try FriendsBetaFixtures.snapshot(name)
            let commands = LockedValues<LiveRematchCommand>()
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: value.match.id))
            let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in value }, rematchCommand: { command in
                guard case .rematch(let persisted, let source, _) = store.storedState.pendingIntent else {
                    XCTFail("Consent must be durable before dispatch"); throw TestFailure.failed
                }
                XCTAssertEqual(persisted, command)
                XCTAssertEqual(source, value.match.id)
                commands.append(command)
                throw LiveMatchServiceError.server(.requestConflict)
            }), realtime: nil, store: store)
            bindLiveAccount(session, transport: transport(UUID()))
            await eventually { session.phase == .ready }
            XCTAssertEqual(session.availableRematchActions, expected, name)
            if let action = expected.first {
                session.performRematch(action)
                await eventually { commands.values.count == 1 && !session.isCommandInFlight }
                XCTAssertEqual(commands.values[0].generation, name == "closed" ? 2 : 1)
                XCTAssertEqual(commands.values[0].expectedParticipationEpoch, value.selection.epoch)
                session.retry()
                await eventually { commands.values.count == 2 && !session.isCommandInFlight }
                XCTAssertEqual(commands.values[0], commands.values[1])
            }
            session.leaveToHome()
        }
        var incoming = try FriendsBetaFixtures.snapshot("offered")
        incoming = LiveMatchSnapshot(serverTime: incoming.serverTime, match: incoming.match,
            members: incoming.members.map { .init(id: $0.id, seat: $0.seat, displayName: $0.displayName,
                avatarSeed: $0.avatarSeed, isSelf: !$0.isSelf, isDeleted: $0.isDeleted) },
            round: incoming.round, revision: incoming.revision, revealedRounds: incoming.revealedRounds,
            standings: incoming.standings, selection: incoming.selection, rematch: incoming.rematch)
        let value = incoming, store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: incoming.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in value }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.phase == .ready }
        XCTAssertEqual(session.availableRematchActions, [.accept, .decline])
        session.leaveToHome()
    }

    func testPersistedHomeFencePreventsRematchSuccessorFollowAfterRelaunch() async throws {
        let accepted = try FriendsBetaFixtures.snapshot("accepted"), successor = try FriendsBetaFixtures.snapshot("successor_lobby")
        let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: accepted.match.id,
            generation: 1, action: .accept, expectedParticipationEpoch: 4, clientBuild: 3)
        let state = LiveRecoveryState(matchID: accepted.match.id, pendingIntent:
            .rematch(command: command, sourceMatchID: accepted.match.id, navigationGeneration: UUID()), successorFollowAllowed: false)
        let store = MemoryLiveRecoveryStore(state), reads = LockedValues<UUID>()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            reads.append(id); return id == accepted.match.id ? accepted : successor
        }, rematchCommand: { value in
            XCTAssertEqual(value, command)
            return .init(predecessorMatchID: value.predecessorMatchID, generation: value.generation,
                state: .accepted, successorMatchID: successor.match.id)
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { !session.isCommandInFlight && session.pendingIntent == nil }
        XCTAssertEqual(session.savedMatchID, accepted.match.id)
        XCTAssertFalse(store.storedState.successorFollowAllowed)
        session.resumeSavedMatch()
        await eventually { session.savedMatchID == successor.match.id }
        session.leaveToHome()
    }

    func testRematchSaveFailurePreventsAnyConsentDispatch() async throws {
        let value = try FriendsBetaFixtures.snapshot("eligible"), calls = LockedCounter()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: value.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in value }, rematchCommand: { _ in
            calls.increment(); throw TestFailure.failed
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.phase == .ready }
        store.rejectsWrites = true
        session.performRematch(.offer)
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(calls.value, 0)
        XCTAssertNil(session.pendingIntent)
        XCTAssertEqual(session.savedMatchID, value.match.id)
        session.leaveToHome()
    }
}

extension LiveMatchSessionTests {
    func testRematchLostPointerWriteRetainsOriginalReceiptIdentityForRetry() async throws {
        let accepted = try FriendsBetaFixtures.snapshot("accepted"), successor = try FriendsBetaFixtures.snapshot("successor_lobby")
        let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: accepted.match.id,
            generation: 1, action: .accept, expectedParticipationEpoch: 4, clientBuild: 3)
        let intent = LivePendingIntent.rematch(command: command, sourceMatchID: accepted.match.id, navigationGeneration: UUID())
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: accepted.match.id, pendingIntent: intent))
        let commands = LockedValues<LiveRematchCommand>()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            id == accepted.match.id ? accepted : successor
        }, rematchCommand: { value in
            commands.append(value)
            if commands.values.count == 1 { store.rejectsWrites = true }
            return .init(predecessorMatchID: value.predecessorMatchID, generation: value.generation,
                state: .accepted, successorMatchID: successor.match.id)
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.phase == .storageUnavailable && !session.isCommandInFlight }
        XCTAssertEqual(session.savedMatchID, accepted.match.id)
        XCTAssertEqual(store.storedState.pendingIntent, intent)
        store.rejectsWrites = false
        session.retry()
        await eventually { session.savedMatchID == successor.match.id && !session.isCommandInFlight }
        XCTAssertEqual(commands.values, [command, command])
        XCTAssertNil(store.storedState.pendingIntent)
        session.leaveToHome()
    }

    func testAccountSwitchFencesLateCanonicalSuccessorAndClearsOriginalConsent() async throws {
        let accepted = try FriendsBetaFixtures.snapshot("accepted"), successor = try FriendsBetaFixtures.snapshot("successor_lobby")
        let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: accepted.match.id,
            generation: 1, action: .accept, expectedParticipationEpoch: 4, clientBuild: 3)
        let old = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: accepted.match.id, pendingIntent:
            .rematch(command: command, sourceMatchID: accepted.match.id, navigationGeneration: UUID())))
        let next = MemoryLiveRecoveryStore(), firstUser = UUID(), nextUser = UUID(), gate = AsyncGate()
        let waiting = LockedCounter(), returned = LockedCounter()
        let (session, transport) = makeLiveSessionFixture(service: LiveServiceMock(snapshot: { id in
            if id == successor.match.id { waiting.increment(); await gate.wait(); returned.increment() }
            return id == accepted.match.id ? accepted : successor
        }, rematchCommand: { value in
            .init(predecessorMatchID: value.predecessorMatchID, generation: value.generation,
                state: .accepted, successorMatchID: successor.match.id)
        }), realtime: nil, storeFactory: { $0 == firstUser ? old : next })
        bindLiveAccount(session, transport: transport(firstUser))
        await eventually { waiting.value == 1 }
        session.changeAccount(to: nextUser, transport: transport(nextUser))
        await gate.open()
        await eventually { returned.value == 1 }
        XCTAssertEqual(old.storedState, LiveRecoveryState())
        XCTAssertEqual(next.storedState, LiveRecoveryState())
        XCTAssertNil(session.savedMatchID)
        XCTAssertNil(session.pendingIntent)
        XCTAssertNil(session.snapshot)
        XCTAssertEqual(session.phase, .inactive)
    }
}

extension LiveMatchSessionTests {
    func testNewInvitationGenerationCannotBeTakenOverByOlderCanonicalJoinResponse() async throws {
        let admitted = try FriendsBetaFixtures.snapshot("successor_lobby"), gate = AsyncGate()
        let invitation = UUID(), calls = LockedCounter(), store = MemoryLiveRecoveryStore()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in admitted }, joinDurable: { _ in
            calls.increment(); await gate.wait(); return admitted.match.id
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        session.joinMatch(code: "ABC234", invitationGeneration: invitation)
        await eventually { calls.value == 1 }
        session.invitationNavigationChanged()
        await gate.open()
        await eventually { !session.isCommandInFlight }
        XCTAssertEqual(session.completedInvitationGeneration, invitation, "Composition clears only this original UUID")
        XCTAssertEqual(session.savedMatchID, admitted.match.id, "The admitted room remains explicitly resumable")
        XCTAssertNil(session.snapshot, "A newer invitation keeps its presentation")
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertFalse(store.storedState.successorFollowAllowed)
        session.leaveToHome()
    }
}

extension LiveMatchSessionTests {
    func testHomeFencePersistenceFailureCannotBeOverwrittenByLateJoinReceipt() async throws {
        let admitted = try FriendsBetaFixtures.snapshot("successor_lobby"), gate = AsyncGate()
        let store = MemoryLiveRecoveryStore(), calls = LockedCounter()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in admitted }, joinDurable: { _ in
            calls.increment(); await gate.wait(); return admitted.match.id
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        session.joinMatch(code: "ABC234", invitationGeneration: UUID())
        await eventually { calls.value == 1 }
        let original = store.storedState
        store.rejectsWrites = true
        session.leaveToHome()
        XCTAssertEqual(session.phase, .storageUnavailable)
        store.rejectsWrites = false
        await gate.open()
        await eventually { !session.isCommandInFlight }
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(store.storedState, original)
        XCTAssertNil(session.completedInvitationGeneration)
        XCTAssertNil(session.savedMatchID)
        XCTAssertNil(session.snapshot)
        session.discardRecovery()
        XCTAssertNil(session.pendingIntent)
    }
}

extension LiveMatchSessionTests {
    func testExplicitServiceRetryResolvesOriginalJoinAfterBackendCorrection() async throws {
        let admitted = try FriendsBetaFixtures.snapshot("successor_lobby")
        let invitation = UUID(), source = UUID(), navigation = UUID()
        let command = LiveJoinCommand(requestID: UUID(), code: "ABC234", expectedMatchID: nil, clientBuild: 3)
        let original = LiveRecoveryState(matchID: source, pendingIntent: .join(command: command,
            sourceMatchID: source, navigationGeneration: navigation, invitationGeneration: invitation))
        let store = MemoryLiveRecoveryStore(original), calls = LockedValues<LiveJoinCommand>()
        let canonicalGate = AsyncGate(), canonicalReads = LockedCounter()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            canonicalReads.increment()
            await canonicalGate.wait()
            return admitted
        }, joinDurable: { value in
            calls.append(value)
            XCTAssertEqual(store.storedState, original)
            if calls.values.count == 1 { throw LiveMatchServiceError.server(.clientUpdateRequired) }
            return admitted.match.id
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.serviceNeedsUpdate && !session.isCommandInFlight }
        XCTAssertTrue(session.canRetry)
        session.retry()
        await eventually { canonicalReads.value == 1 }
        XCTAssertTrue(session.serviceNeedsUpdate, "A receipt alone cannot remove the deployment fence")
        XCTAssertFalse(session.canRetry, "The explicit attempt must stay single-flight")
        XCTAssertEqual(session.savedMatchID, source)
        session.createMatch(); session.joinMatch(code: "DEF567")
        XCTAssertEqual(calls.values, [command, command])
        XCTAssertEqual(store.storedState, original)
        await canonicalGate.open()
        await eventually { !session.isCommandInFlight && !session.serviceNeedsUpdate && session.phase == .ready }
        XCTAssertEqual(session.savedMatchID, admitted.match.id)
        XCTAssertNil(session.pendingIntent)
        XCTAssertEqual(session.completedInvitationGeneration, invitation)
        XCTAssertEqual(calls.values, [command, command])
        session.leaveToHome()
    }

    func testPersistentServiceMismatchAllowsOnlyBoundedExplicitOriginalPayloadAttempts() async throws {
        let source = UUID(), invitation = UUID()
        let command = LiveJoinCommand(requestID: UUID(), code: "ABC234", expectedMatchID: source, clientBuild: 3)
        let original = LiveRecoveryState(matchID: source, pendingIntent: .join(command: command,
            sourceMatchID: source, navigationGeneration: UUID(), invitationGeneration: invitation))
        let store = MemoryLiveRecoveryStore(original), calls = LockedValues<LiveJoinCommand>()
        let timers = LockedCounter()
        let (session, transport) = makeSession(service: LiveServiceMock(joinDurable: { value in
            calls.append(value)
            throw LiveMatchServiceError.server(.clientUpdateRequired)
        }), realtime: nil, store: store, timing: .init(requestTimeout: .seconds(10), staleAfter: .milliseconds(1), retryBackoff: [.milliseconds(1)]), sleep: { delay in
            if delay != .seconds(10) { timers.increment() }
            try await Task.sleep(for: delay)
        })
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.serviceNeedsUpdate && !session.isCommandInFlight }
        session.retry(); session.retry()
        await eventually { calls.values.count == 2 && !session.isCommandInFlight }
        XCTAssertTrue(session.serviceNeedsUpdate)
        XCTAssertTrue(session.canRetry)
        session.backgrounded(); session.foregrounded(); session.resumeSavedMatch()
        session.createMatch(); session.joinMatch(code: "DEF567")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(calls.values, [command, command])
        XCTAssertEqual(timers.value, 0, "Neither failed explicit attempt may install an automatic retry timer")
        XCTAssertEqual(store.storedState, original)
        XCTAssertNil(session.completedInvitationGeneration)
        session.leaveToHome()
    }

    func testExplicitSnapshotRetryRemovesMismatchOnlyAfterCompatibleCanonicalResponse() async throws {
        let value = try FriendsBetaFixtures.snapshot("successor_lobby")
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: value.match.id))
        let realtime = RealtimeHub(), reads = LockedCounter()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            reads.increment()
            if reads.value == 1 { throw LiveMatchServiceError.server(.clientUpdateRequired) }
            return value
        }), realtime: realtime, store: store)
        bindLiveAccount(session, transport: transport(UUID())); realtime.send(.ready)
        await eventually { session.serviceNeedsUpdate }
        XCTAssertTrue(session.canRetry)
        realtime.send(.signal); realtime.send(.ready); realtime.send(.disconnected)
        session.backgrounded(); session.foregrounded()
        await Task.yield()
        XCTAssertEqual(reads.value, 1, "Realtime and foreground recovery cannot probe a known mismatch")
        session.retry()
        await eventually { !session.serviceNeedsUpdate && !session.isCommandInFlight && session.phase == .ready }
        XCTAssertGreaterThanOrEqual(reads.value, 2, "Normal refresh may resume only after the compatible response")
        XCTAssertEqual(session.savedMatchID, value.match.id)
        XCTAssertNil(session.pendingIntent)
        session.leaveToHome()
    }

    func testUncertainExplicitServiceRetryRemainsBlockedWithoutAutomaticReplay() async throws {
        let command = LiveJoinCommand(requestID: UUID(), code: "ABC234", expectedMatchID: nil, clientBuild: 3)
        let original = LiveRecoveryState(pendingIntent: .join(command: command, sourceMatchID: nil,
            navigationGeneration: UUID(), invitationGeneration: UUID()))
        let store = MemoryLiveRecoveryStore(original), calls = LockedValues<LiveJoinCommand>()
        let (session, transport) = makeSession(service: LiveServiceMock(joinDurable: { value in
            calls.append(value)
            throw calls.values.count == 1 ? LiveMatchServiceError.server(.clientUpdateRequired) : .unavailable
        }), realtime: nil, store: store, timing: .init(requestTimeout: .seconds(10), staleAfter: .milliseconds(1), retryBackoff: [.milliseconds(1)]))
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { session.serviceNeedsUpdate && !session.isCommandInFlight }
        session.retry()
        await eventually { calls.values.count == 2 && !session.isCommandInFlight }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(session.serviceNeedsUpdate)
        XCTAssertTrue(session.canRetry)
        XCTAssertEqual(calls.values, [command, command])
        XCTAssertEqual(store.storedState, original)
        session.leaveToHome()
    }
}

extension LiveMatchRecoveryStoreTests {
    func testCompletedInvitationMarkerRoundTripsWithoutAddingAnotherRecoveryFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceInvitationCompletion-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        let marker = UUID(), state = LiveRecoveryState(matchID: UUID(), completedInvitationGeneration: marker)
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        let file = store.directory.appending(path: "live-recovery-v1.json")
        let data = try Data(contentsOf: file)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(UUID(uuidString: try XCTUnwrap(object["completedInvitationGeneration"] as? String)), marker)
        object["formatVersion"] = 2
        let invalid = try JSONSerialization.data(withJSONObject: object)
        try invalid.write(to: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: file), invalid)
        object.removeValue(forKey: "completedInvitationGeneration")
        object["formatVersion"] = 3
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        XCTAssertNil(try store.load().completedInvitationGeneration, "A current envelope may have no completed invitation")
    }
}

extension LiveMatchSessionTests {
    func testColdRecoveryRestoresCompletedInvitationAfterPointerCommitWithoutAnotherJoin() async throws {
        let admitted = try FriendsBetaFixtures.snapshot("successor_lobby"), invitation = UUID(), account = UUID()
        let joins = LockedCounter(), firstStore = MemoryLiveRecoveryStore()
        let service = LiveServiceMock(snapshot: { _ in admitted }, joinDurable: { _ in
            joins.increment(); return admitted.match.id
        })
        let (first, firstTransport) = makeSession(service: service, realtime: nil, store: firstStore)
        bindLiveAccount(first, transport: firstTransport(account))
        first.joinMatch(code: "ABC234", invitationGeneration: invitation)
        await eventually { !first.isCommandInFlight && first.savedMatchID == admitted.match.id }
        let committed = firstStore.storedState
        XCTAssertEqual(committed.completedInvitationGeneration, invitation)
        XCTAssertNil(committed.pendingIntent)
        let restoredStore = MemoryLiveRecoveryStore(committed)
        let (restored, restoredTransport) = makeSession(service: service, realtime: nil, store: restoredStore)
        restored.backgrounded()
        bindLiveAccount(restored, transport: restoredTransport(account))
        XCTAssertEqual(restored.completedInvitationGeneration, invitation)
        XCTAssertEqual(restored.completedInvitationAccountID, account)
        XCTAssertEqual(restored.savedMatchID, admitted.match.id)
        XCTAssertEqual(joins.value, 1)
        first.leaveToHome(); restored.leaveToHome()
    }

    func testInvitationAcknowledgmentIsAccountBoundMatchingAndIdempotent() throws {
        let account = UUID(), invitation = UUID(), nextInvitation = UUID(), match = UUID()
        let guess = LivePendingIntent.guess(matchID: match, requestID: UUID(), word: "STONE", roundNumber: 1, clientBuild: 3)
        let original = LiveRecoveryState(matchID: match, pendingIntent: guess,
            successorFollowAllowed: false, completedInvitationGeneration: invitation)
        let store = MemoryLiveRecoveryStore(original)
        let (session, transport) = makeSession(service: LiveServiceMock(), realtime: nil, store: store)
        session.backgrounded(); bindLiveAccount(session, transport: transport(account))
        XCTAssertTrue(session.acknowledgeInvitationClear(matchingGeneration: nextInvitation, forAccount: account))
        XCTAssertEqual(store.storedState, original)
        XCTAssertFalse(session.acknowledgeInvitationClear(matchingGeneration: invitation, forAccount: UUID()))
        XCTAssertEqual(store.storedState, original)
        XCTAssertTrue(session.acknowledgeInvitationClear(matchingGeneration: invitation, forAccount: account))
        var expected = original; expected.completedInvitationGeneration = nil
        XCTAssertEqual(store.storedState, expected)
        XCTAssertNil(session.completedInvitationGeneration)
        XCTAssertTrue(session.acknowledgeInvitationClear(matchingGeneration: invitation, forAccount: account))
        XCTAssertEqual(store.storedState, expected)
        let newer = MemoryLiveRecoveryStore(LiveRecoveryState(completedInvitationGeneration: nextInvitation))
        let (later, laterTransport) = makeSession(service: LiveServiceMock(), realtime: nil, store: newer)
        later.backgrounded(); bindLiveAccount(later, transport: laterTransport(account))
        XCTAssertTrue(later.acknowledgeInvitationClear(matchingGeneration: invitation, forAccount: account))
        XCTAssertEqual(later.completedInvitationGeneration, nextInvitation)
        XCTAssertEqual(newer.storedState.completedInvitationGeneration, nextInvitation)
    }

    func testFailedInvitationAcknowledgmentPreservesProtectedBytesUntilStorageRetry() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GridRaceInvitationAckFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), invitation = UUID()
        let disk = LiveMatchRecoveryStore(rootDirectory: root, userID: account)
        let original = LiveRecoveryState(completedInvitationGeneration: invitation)
        try disk.save(original)
        let file = disk.directory.appending(path: "live-recovery-v1.json"), bytes = try Data(contentsOf: file)
        let controlled = InvitationAcknowledgmentStore(disk)
        let (session, transport) = makeLiveSessionFixture(service: LiveServiceMock(), realtime: nil, storeFactory: { _ in controlled })
        session.backgrounded(); bindLiveAccount(session, transport: transport(account))
        controlled.rejectsWrites = true
        XCTAssertFalse(session.acknowledgeInvitationClear(matchingGeneration: invitation, forAccount: account))
        XCTAssertEqual(session.phase, .storageUnavailable)
        XCTAssertEqual(session.completedInvitationGeneration, invitation)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        controlled.rejectsWrites = false
        session.retry()
        XCTAssertEqual(session.completedInvitationGeneration, invitation)
        XCTAssertTrue(session.acknowledgeInvitationClear(matchingGeneration: invitation, forAccount: account))
        XCTAssertNil(try disk.load().completedInvitationGeneration)
        XCTAssertNil(session.completedInvitationGeneration)
    }

    func testLateInvitationAcknowledgmentCannotClearSameGenerationForAnotherAccount() {
        let firstAccount = UUID(), nextAccount = UUID(), invitation = UUID()
        let firstStore = MemoryLiveRecoveryStore(LiveRecoveryState(completedInvitationGeneration: invitation))
        let nextState = LiveRecoveryState(completedInvitationGeneration: invitation)
        let nextStore = MemoryLiveRecoveryStore(nextState)
        let (session, transport) = makeLiveSessionFixture(service: LiveServiceMock(), realtime: nil,
            storeFactory: { $0 == firstAccount ? firstStore : nextStore })
        session.backgrounded(); bindLiveAccount(session, transport: transport(firstAccount))
        let capturedAccount = session.completedInvitationAccountID
        XCTAssertEqual(capturedAccount, firstAccount)
        session.changeAccount(to: nextAccount, transport: transport(nextAccount))
        XCTAssertEqual(firstStore.storedState, LiveRecoveryState())
        XCTAssertEqual(session.completedInvitationAccountID, nextAccount)
        XCTAssertFalse(session.acknowledgeInvitationClear(matchingGeneration: invitation, forAccount: firstAccount))
        XCTAssertEqual(nextStore.storedState, nextState)
        XCTAssertEqual(session.completedInvitationGeneration, invitation)
    }

    func testUnacknowledgedCompletionSurvivesNewCreateAndAutomaticPointerRemoval() async throws {
        for removesPointer in [false, true] {
            let invitation = UUID(), original = LiveRecoveryState(matchID: removesPointer ? UUID() : nil,
                completedInvitationGeneration: invitation)
            let store = MemoryLiveRecoveryStore(original)
            let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in
                throw LiveMatchServiceError.server(.notAMatchMember)
            }, createConfigured: { _, _, _ in throw LiveMatchServiceError.server(.requestConflict) }), realtime: nil, store: store)
            bindLiveAccount(session, transport: transport(UUID()))
            if !removesPointer { session.createMatch() }
            await eventually { !session.isCommandInFlight && session.phase == .unavailable }
            XCTAssertEqual(store.storedState.completedInvitationGeneration, invitation)
            XCTAssertEqual(session.completedInvitationGeneration, invitation)
            XCTAssertNil(session.savedMatchID)
            if removesPointer { XCTAssertNil(session.pendingIntent) }
            else { XCTAssertNotNil(session.pendingIntent) }
            session.leaveToHome()
        }
    }
}

private final class InvitationAcknowledgmentStore: LiveMatchRecoveryStoring, @unchecked Sendable {
    private let disk: LiveMatchRecoveryStore
    var rejectsWrites = false
    init(_ disk: LiveMatchRecoveryStore) { self.disk = disk }
    func load() throws -> LiveRecoveryState { try disk.load() }
    func save(_ state: LiveRecoveryState) throws {
        if rejectsWrites { throw LiveMatchRecoveryError.unavailable }
        try disk.save(state)
    }
    func clear() throws { try disk.clear() }
}

extension LiveMatchSessionTests {
    func testUnacknowledgedMarkerBlocksNewInvitationButSurvivesManualJoin() async throws {
        let admitted = try FriendsBetaFixtures.snapshot("successor_lobby"), account = UUID()
        let originalMarker = UUID(), nextInvitation = UUID(), joins = LockedCounter()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(completedInvitationGeneration: originalMarker))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in admitted }, joinDurable: { _ in
            joins.increment(); return admitted.match.id
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(account))
        session.joinMatch(code: "ABC234", invitationGeneration: nextInvitation)
        XCTAssertEqual(joins.value, 0)
        XCTAssertNil(session.pendingIntent)
        session.joinMatch(code: "ABC234")
        await eventually { !session.isCommandInFlight && session.savedMatchID == admitted.match.id }
        XCTAssertEqual(joins.value, 1)
        XCTAssertEqual(session.completedInvitationGeneration, originalMarker)
        XCTAssertEqual(store.storedState.completedInvitationGeneration, originalMarker)
        XCTAssertTrue(session.acknowledgeInvitationClear(matchingGeneration: originalMarker, forAccount: account))
        session.joinMatch(code: "ABC234", invitationGeneration: nextInvitation)
        await eventually { !session.isCommandInFlight && session.completedInvitationGeneration == nextInvitation }
        XCTAssertEqual(joins.value, 2)
        XCTAssertEqual(store.storedState.completedInvitationGeneration, nextInvitation)
        session.leaveToHome()
    }
}

extension LiveMatchSessionTests {
    func testPassiveSuccessorFollowRechecksSelectionAfterBetweenReadDeparture() async throws {
        for sourceWasSelected in [false, true] {
            var source = try FriendsBetaFixtures.snapshot("accepted")
            source.selection = .init(epoch: sourceWasSelected ? 6 : 5, isSelected: sourceWasSelected)
            let predecessor = source
            var candidate = try FriendsBetaFixtures.snapshot("successor_lobby")
            candidate.selection = .init(epoch: source.selection.epoch + 1, isSelected: false)
            let unselected = candidate
            candidate.selection = .init(epoch: unselected.selection.epoch + 1, isSelected: true)
            let confirmed = candidate
            let gate = AsyncGate(), waiting = LockedCounter(), joins = LockedValues<LiveJoinCommand>()
            let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: predecessor.match.id))
            let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
                if id == predecessor.match.id { return predecessor }
                if joins.values.isEmpty { waiting.increment(); await gate.wait(); return unselected }
                return confirmed
            }, joinDurable: { value in joins.append(value); return confirmed.match.id }), realtime: nil, store: store)
            bindLiveAccount(session, transport: transport(UUID()))
            await eventually { waiting.value == 1 }
            XCTAssertEqual(session.savedMatchID, predecessor.match.id)
            await gate.open()
            await eventually { session.resumeConfirmationTarget?.selection.epoch == unselected.selection.epoch }
            XCTAssertEqual(session.savedMatchID, predecessor.match.id)
            XCTAssertEqual(store.storedState.matchID, predecessor.match.id)
            XCTAssertTrue(session.requiresResumeConfirmation, "Even a formerly selected predecessor needs explicit target confirmation")
            XCTAssertTrue(joins.values.isEmpty)
            session.confirmResumeSavedMatch()
            await eventually { !session.isCommandInFlight && session.savedMatchID == confirmed.match.id }
            XCTAssertEqual(joins.values.count, 1)
            XCTAssertEqual(joins.values[0].expectedMatchID, confirmed.match.id)
            XCTAssertEqual(joins.values[0].code, confirmed.match.joinCode)
            session.leaveToHome()
        }
    }

    func testPendingRematchRetainsPredecessorWhenSelectionMovesDuringSuccessorRead() async throws {
        let predecessor = try FriendsBetaFixtures.snapshot("accepted")
        var candidate = try FriendsBetaFixtures.snapshot("successor_lobby")
        candidate.selection = .init(epoch: 6, isSelected: false)
        let successor = candidate, gate = AsyncGate(), waiting = LockedCounter()
        let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: predecessor.match.id,
            generation: 1, action: .accept, expectedParticipationEpoch: 4, clientBuild: 3)
        let intent = LivePendingIntent.rematch(command: command, sourceMatchID: predecessor.match.id, navigationGeneration: UUID())
        let completion = UUID(), commands = LockedValues<LiveRematchCommand>()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: predecessor.match.id,
            pendingIntent: intent, completedInvitationGeneration: completion))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            if id == predecessor.match.id { return predecessor }
            waiting.increment(); await gate.wait(); return successor
        }, rematchCommand: { value in
            commands.append(value)
            return .init(predecessorMatchID: value.predecessorMatchID, generation: value.generation,
                state: .accepted, successorMatchID: successor.match.id)
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { waiting.value == 1 }
        XCTAssertEqual(store.storedState.pendingIntent, intent)
        await gate.open()
        await eventually { !session.isCommandInFlight && session.resumeConfirmationTarget != nil }
        XCTAssertEqual(commands.values, [command])
        XCTAssertEqual(session.savedMatchID, predecessor.match.id)
        XCTAssertEqual(store.storedState.matchID, predecessor.match.id)
        XCTAssertNil(store.storedState.pendingIntent, "The committed receipt is durably settled without moving its pointer")
        XCTAssertEqual(store.storedState.completedInvitationGeneration, completion)
        XCTAssertTrue(session.requiresResumeConfirmation)
        XCTAssertEqual(session.resumeConfirmationTarget?.match.id, successor.match.id)
        session.leaveToHome()
    }

    func testRematchNoFollowSaveFailureRetainsExactIntentAndRejectsStaleSelectedSuccessorOnRetry() async throws {
        let predecessor = try FriendsBetaFixtures.snapshot("accepted"), canonical = try FriendsBetaFixtures.snapshot("successor_lobby")
        var candidate = canonical; candidate.selection = .init(epoch: 6, isSelected: false)
        let unselected = candidate
        let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: predecessor.match.id,
            generation: 1, action: .accept, expectedParticipationEpoch: 4, clientBuild: 3)
        let intent = LivePendingIntent.rematch(command: command, sourceMatchID: predecessor.match.id, navigationGeneration: UUID())
        let original = LiveRecoveryState(matchID: predecessor.match.id, pendingIntent: intent, completedInvitationGeneration: UUID())
        let store = MemoryLiveRecoveryStore(original), gate = AsyncGate(), waiting = LockedCounter()
        let commands = LockedValues<LiveRematchCommand>()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            if id == predecessor.match.id { return predecessor }
            if commands.values.count == 1 { waiting.increment(); await gate.wait(); return unselected }
            return canonical
        }, rematchCommand: { value in
            commands.append(value)
            return .init(predecessorMatchID: value.predecessorMatchID, generation: value.generation,
                state: .accepted, successorMatchID: canonical.match.id)
        }), realtime: nil, store: store)
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { waiting.value == 1 }
        store.rejectsWrites = true; await gate.open()
        await eventually { session.phase == .storageUnavailable && !session.isCommandInFlight }
        XCTAssertEqual(store.storedState, original)
        XCTAssertEqual(session.pendingIntent, intent)
        XCTAssertEqual(session.savedMatchID, predecessor.match.id)
        store.rejectsWrites = false; session.retry()
        await eventually { commands.values.count == 2 && !session.isCommandInFlight && session.resumeConfirmationTarget != nil }
        XCTAssertEqual(commands.values, [command, command])
        XCTAssertEqual(session.savedMatchID, predecessor.match.id)
        XCTAssertEqual(store.storedState.matchID, predecessor.match.id)
        XCTAssertNil(session.pendingIntent)
        XCTAssertEqual(store.storedState.completedInvitationGeneration, original.completedInvitationGeneration)
        XCTAssertTrue(session.requiresResumeConfirmation)
        session.leaveToHome()
    }

    func testPassiveFollowRejectsOlderSuccessorEpochAndAllowsCurrentSelectedEpoch() async throws {
        let predecessor = try FriendsBetaFixtures.snapshot("accepted")
        let canonical = try FriendsBetaFixtures.snapshot("successor_lobby")
        var candidate = canonical; candidate.selection = .init(epoch: 6, isSelected: false)
        let unselected = candidate
        candidate.selection = .init(epoch: 7, isSelected: true)
        let selected = candidate
        let gates = [AsyncGate(), AsyncGate(), AsyncGate()], reads = LockedCounter(), realtime = RealtimeHub()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: predecessor.match.id))
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { id in
            if id == predecessor.match.id { return predecessor }
            let index = reads.increment() - 1
            if index < gates.count { await gates[index].wait() }
            return index == 0 ? unselected : (index == 1 ? canonical : selected)
        }), realtime: realtime, store: store)
        bindLiveAccount(session, transport: transport(UUID())); realtime.send(.ready)
        await eventually { reads.value == 1 }; await gates[0].open()
        await eventually { session.resumeConfirmationTarget?.selection.epoch == 6 }
        realtime.send(.signal)
        await eventually { reads.value == 2 }; await gates[1].open()
        realtime.send(.signal)
        await eventually { reads.value == 3 }
        XCTAssertEqual(session.savedMatchID, predecessor.match.id)
        XCTAssertEqual(session.resumeConfirmationTarget?.selection.epoch, 6, "A stale candidate cannot erase the newer confirmation projection")
        XCTAssertTrue(session.requiresResumeConfirmation)
        await gates[2].open()
        await eventually { session.savedMatchID == selected.match.id }
        XCTAssertNil(session.pendingIntent, "Canonical current selection can follow without a new selection command")
        session.leaveToHome()
    }
}

extension LiveMatchSessionTests {
    func testUnavailableCancelAndDeclineReceiptsSettleOriginalPendingCommands() async throws {
        let canonical = try FriendsBetaFixtures.snapshot("unavailable")
        for action in [LiveRematchAction.cancel, .decline] {
            let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: canonical.match.id,
                generation: 1, action: action, expectedParticipationEpoch: 4, clientBuild: 3)
            let intent = LivePendingIntent.rematch(command: command, sourceMatchID: canonical.match.id, navigationGeneration: UUID())
            let original = LiveRecoveryState(matchID: canonical.match.id, pendingIntent: intent, completedInvitationGeneration: UUID())
            let store = MemoryLiveRecoveryStore(original), commands = LockedValues<LiveRematchCommand>()
            let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in canonical }, rematchCommand: { value in
                commands.append(value)
                return .init(predecessorMatchID: value.predecessorMatchID, generation: value.generation,
                    state: .unavailable, successorMatchID: nil)
            }), realtime: nil, store: store)
            bindLiveAccount(session, transport: transport(UUID()))
            await eventually { !session.isCommandInFlight && session.phase == .ready }
            XCTAssertEqual(commands.values, [command])
            XCTAssertNil(session.pendingIntent)
            XCTAssertEqual(session.savedMatchID, canonical.match.id)
            XCTAssertEqual(session.snapshot?.rematch?.state, .unavailable)
            XCTAssertNil(session.lastError)
            XCTAssertEqual(store.storedState.completedInvitationGeneration, original.completedInvitationGeneration)
            XCTAssertFalse(session.canRetry)
            session.backgrounded(); session.foregrounded()
            await Task.yield()
            XCTAssertEqual(commands.values, [command], "Committed unavailable closure is not an uncertain retry")
            session.leaveToHome()
        }
    }

    func testUnavailableClosureCanonicalReadLossRetriesExactOriginalCommandThenSettles() async throws {
        let canonical = try FriendsBetaFixtures.snapshot("unavailable")
        let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: canonical.match.id,
            generation: 1, action: .cancel, expectedParticipationEpoch: 4, clientBuild: 3)
        let intent = LivePendingIntent.rematch(command: command, sourceMatchID: canonical.match.id, navigationGeneration: UUID())
        let original = LiveRecoveryState(matchID: canonical.match.id, pendingIntent: intent)
        let store = MemoryLiveRecoveryStore(original), commands = LockedValues<LiveRematchCommand>(), reads = LockedCounter()
        let (session, transport) = makeSession(service: LiveServiceMock(snapshot: { _ in
            reads.increment()
            if commands.values.count == 1 { throw LiveMatchServiceError.unavailable }
            return canonical
        }, rematchCommand: { value in
            commands.append(value)
            return .init(predecessorMatchID: value.predecessorMatchID, generation: value.generation,
                state: .unavailable, successorMatchID: nil)
        }), realtime: nil, store: store, timing: .init(requestTimeout: .seconds(10), staleAfter: .seconds(50), retryBackoff: [.seconds(50)]))
        bindLiveAccount(session, transport: transport(UUID()))
        await eventually { !session.isCommandInFlight && session.lastError == .unavailable }
        XCTAssertEqual(store.storedState, original)
        session.retry()
        await eventually { !session.isCommandInFlight && session.pendingIntent == nil && session.phase == .ready }
        XCTAssertEqual(commands.values, [command, command])
        XCTAssertEqual(session.savedMatchID, canonical.match.id)
        XCTAssertNil(session.lastError)
        session.leaveToHome()
    }
}
