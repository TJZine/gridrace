import Foundation
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

    func testCorruptOrInconsistentRecoveryFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GridRaceLiveRecoveryCorrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LiveMatchRecoveryStore(rootDirectory: root, userID: UUID())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":2}"#.utf8).write(
            to: store.directory.appending(path: "live-recovery-v1.json")
        )
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? LiveMatchRecoveryError, .invalidData)
        }
    }
}

@MainActor
final class LiveMatchSessionTests: XCTestCase {
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

        await eventually { session.hasSavedMatch }
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

    func testSignalsCoalesceAndPreCommandSnapshotCannotOverwriteCommandRecovery() async throws {
        let matchID = UUID()
        let store = MemoryLiveRecoveryStore(LiveRecoveryState(matchID: matchID))
        let realtime = RealtimeHub()
        let script = SnapshotScript(
            first: Self.snapshot(matchID: matchID, status: .lobby, round: .pending),
            later: Self.snapshot(matchID: matchID, status: .inProgress, round: .playing)
        )
        let service = LiveServiceMock(
            start: { $0 },
            snapshot: { _ in try await script.next() }
        )
        let session = makeSession(service: service, realtime: realtime, store: store)
        session.changeAccount(to: UUID())
        await eventually { realtime.subscriptionCount == 1 }
        realtime.send(.ready)
        await eventually { await script.callCount == 1 }

        session.startMatch()
        realtime.send(.signal)
        realtime.send(.signal)
        await eventually { !session.isCommandInFlight }
        await script.releaseFirst()

        await eventually { await script.callCount == 2 }
        await eventually { session.phase == .ready }
        XCTAssertEqual(session.snapshot?.match.status, .inProgress)
        let finalCallCount = await script.callCount
        XCTAssertEqual(finalCallCount, 2)
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
        session.changeAccount(to: firstUser)
        await eventually { realtime.subscriptionCount == 1 }
        realtime.send(.ready)
        await eventually { await script.callCount == 1 }

        session.changeAccount(to: secondUser)
        await script.releaseFirst()
        await Task.yield()

        XCTAssertNil(session.snapshot)
        XCTAssertEqual(session.phase, .inactive)
        XCTAssertEqual(try firstStore.load(), LiveRecoveryState())
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
        let conflictService = LiveServiceMock(submit: { _, _, _ in
            throw LiveMatchServiceError.server(.requestConflict)
        })
        let conflict = makeSession(
            service: conflictService,
            realtime: conflictRealtime,
            store: conflictStore
        )
        conflict.changeAccount(to: UUID())
        await eventually { conflictRealtime.subscriptionCount == 1 }
        conflictRealtime.send(.ready)
        await eventually { !conflict.isCommandInFlight && conflict.lastError != nil }
        XCTAssertEqual(
            conflict.pendingIntent,
            .guess(matchID: matchID, requestID: conflictRequest, word: "STONE")
        )
        XCTAssertEqual(conflict.lastError, .server(.requestConflict))
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

    nonisolated private static func snapshot(
        matchID: UUID,
        status: LiveMatchStatus,
        round state: LiveRoundState,
        serverTime: Date = Date(timeIntervalSince1970: 1_000),
        endsAt: Date? = Date(timeIntervalSince1970: 1_180)
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
                players: []
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

    func createMatch(requestID: UUID) async throws -> UUID { try await create(requestID) }
    func joinMatch(code: String) async throws -> UUID { try await join(code) }
    func startMatch(id: UUID) async throws -> UUID { try await start(id) }
    func submitGuess(matchID: UUID, requestID: UUID, guess: String) async throws -> LiveGuessReceipt {
        try await submit(matchID, requestID, guess)
    }
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot { try await snapshot(matchID) }
}

private final class MemoryLiveRecoveryStore: LiveMatchRecoveryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: LiveRecoveryState
    var rejectsWrites = false

    init(_ state: LiveRecoveryState = LiveRecoveryState()) { self.state = state }

    func load() throws -> LiveRecoveryState {
        lock.lock()
        defer { lock.unlock() }
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
        state = LiveRecoveryState()
    }
}

private final class RealtimeHub: LiveMatchRealtimeServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<LiveMatchRealtimeEvent, Error>.Continuation] = []

    var subscriptionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
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
