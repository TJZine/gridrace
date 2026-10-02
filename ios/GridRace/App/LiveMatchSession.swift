import Foundation
import Observation

enum LiveMatchSessionPhase: Equatable, Sendable {
    case inactive
    case recovering
    case ready
    case unavailable
    case needsSignIn
    case storageUnavailable
}

enum LiveAccountChangeOutcome: Equatable, Sendable {
    case completed
    case recoveryCleanupPending
}

struct LiveMatchSessionTiming: Sendable {
    let requestTimeout: Duration
    let staleAfter: Duration
    let retryBackoff: [Duration]

    static let production = LiveMatchSessionTiming(
        requestTimeout: .seconds(10),
        staleAfter: .seconds(5),
        retryBackoff: [.seconds(5), .seconds(10), .seconds(20), .seconds(30)]
    )
}

@MainActor
@Observable
final class LiveMatchSession {
    typealias StoreFactory = @MainActor (UUID) throws -> any LiveMatchRecoveryStoring
    typealias AuthRefresh = @MainActor @Sendable (UUID) async -> Bool

    private let service: (any LiveMatchServicing)?
    private let realtime: (any LiveMatchRealtimeServicing)?
    private let storeFactory: StoreFactory
    private let refreshAuth: AuthRefresh
    private let timing: LiveMatchSessionTiming
    private let sleep: @Sendable (Duration) async throws -> Void
    private let uptime: @MainActor () -> TimeInterval
    private let makeUUID: @MainActor () -> UUID

    private var accountID: UUID?
    private var requestedAccountID: UUID?
    private var hasRequestedAccountChange = false
    private var store: (any LiveMatchRecoveryStoring)?
    private var recovery = LiveRecoveryState()
    private var generation = 0
    private var commandEpoch = 0
    private var isForeground = true
    private var isOpen = false
    // A durable pointer is resumable, but is not necessarily the current Join target.
    private var isRecoverySelected = false
    private var trailingRefresh = false
    private var failureCount = 0
    private var snapshotUptime: TimeInterval?
    private var commandTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var realtimeRetryTask: Task<Void, Never>?
    private var recoveryTimer: Task<Void, Never>?
    private var realtimeFailureCount = 0

    private(set) var phase = LiveMatchSessionPhase.inactive
    private(set) var snapshot: LiveMatchSnapshot?
    private(set) var lastError: LiveMatchServiceError?
    private(set) var guessDraft = ""
    private(set) var isCommandInFlight = false

    var hasSavedMatch: Bool { recovery.matchID != nil || recovery.pendingIntent != nil }
    var savedMatchID: UUID? { recovery.matchID }
    var pendingIntent: LivePendingIntent? { recovery.pendingIntent }
    var canRetryRecoveryStorage: Bool { phase == .storageUnavailable && accountID != nil }
    var canDiscardRecovery: Bool { canRetryRecoveryStorage }

    var displayedServerTime: Date? {
        guard let snapshot, let snapshotUptime else { return nil }
        return snapshot.serverTime.addingTimeInterval(max(0, uptime() - snapshotUptime))
    }

    var isInputLocked: Bool {
        guard phase == .ready,
              recovery.pendingIntent == nil,
              let snapshot,
              snapshot.round.state == .playing,
              let endsAt = snapshot.round.endsAt,
              let displayedServerTime
        else { return true }
        return displayedServerTime >= endsAt
    }

    init(
        service: (any LiveMatchServicing)?,
        realtime: (any LiveMatchRealtimeServicing)?,
        storeFactory: @escaping StoreFactory = {
            try LiveMatchRecoveryStore.applicationSupport(userID: $0)
        },
        refreshAuth: @escaping AuthRefresh = { _ in false },
        timing: LiveMatchSessionTiming = .production,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        uptime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        makeUUID: @escaping @MainActor () -> UUID = UUID.init
    ) {
        precondition(!timing.retryBackoff.isEmpty)
        self.service = service
        self.realtime = realtime
        self.storeFactory = storeFactory
        self.refreshAuth = refreshAuth
        self.timing = timing
        self.sleep = sleep
        self.uptime = uptime
        self.makeUUID = makeUUID
    }

    isolated deinit {
        cancelTasks()
    }

    @discardableResult
    func changeAccount(to userID: UUID?) -> LiveAccountChangeOutcome {
        guard accountID != userID else {
            if hasRequestedAccountChange {
                requestedAccountID = nil
                hasRequestedAccountChange = false
            }
            return .completed
        }
        let oldAccountID = accountID
        let oldStore = store
        resetRuntime()
        if let oldAccountID {
            do {
                let oldStore = try oldStore ?? storeFactory(oldAccountID)
                try oldStore.clear()
            } catch {
                store = oldStore
                requestedAccountID = userID
                hasRequestedAccountChange = true
                phase = .storageUnavailable
                return .recoveryCleanupPending
            }
        }
        requestedAccountID = nil
        hasRequestedAccountChange = false
        accountID = userID
        loadRecovery()
        return .completed
    }

    func discardRecovery() {
        guard canDiscardRecovery, let accountID else { return }
        do {
            let store = try store ?? storeFactory(accountID)
            try store.clear()
            resetRuntime()
            if hasRequestedAccountChange {
                let userID = requestedAccountID
                requestedAccountID = nil
                hasRequestedAccountChange = false
                self.accountID = userID
                loadRecovery()
            } else {
                self.store = store
            }
        } catch {
            phase = .storageUnavailable
        }
    }

    func createMatch() {
        guard canBeginCommand, recovery.pendingIntent == nil else { return }
        let intent = LivePendingIntent.create(requestID: makeUUID())
        let previous = recovery
        recovery = LiveRecoveryState(pendingIntent: intent)
        guard saveRecovery() else {
            recovery = previous
            return
        }
        isOpen = true
        isRecoverySelected = false
        cancelMatchTasks()
        startCommand { [weak self] in await self?.recoverPendingIntent() }
    }

    func joinMatch(code: String) {
        guard canBeginCommand, recovery.pendingIntent == nil, let service else { return }
        let accountGeneration = generation
        isOpen = true
        isRecoverySelected = false
        snapshot = nil
        snapshotUptime = nil
        cancelMatchTasks()
        beginCommand()
        commandTask = Task { [weak self] in
            guard let self else { return }
            do {
                let matchID = try await request { try await service.joinMatch(code: code) }
                guard isCurrent(accountGeneration) else { return }
                try saveResolvedMatch(matchID)
                open(matchID: matchID)
            } catch {
                guard isCurrent(accountGeneration) else { return }
                handleCommandError(error, uncertainIntent: false)
            }
            finishCommand(accountGeneration)
        }
    }

    func startMatch() {
        guard canBeginCommand, let matchID = recovery.matchID, let service else { return }
        let accountGeneration = generation
        beginCommand()
        commandTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await request { try await service.startMatch(id: matchID) }
            } catch {
                guard isCurrent(accountGeneration) else { return }
                handleCommandError(error, uncertainIntent: false)
            }
            guard isCurrent(accountGeneration) else { return }
            finishCommand(accountGeneration)
            requestRefresh()
        }
    }

    func submitGuess(_ word: String) {
        guard canBeginCommand,
              !isInputLocked,
              let matchID = recovery.matchID,
              recovery.pendingIntent == nil
        else { return }
        let intent = LivePendingIntent.guess(
            matchID: matchID,
            requestID: makeUUID(),
            word: word
        )
        guessDraft = word
        guard persistPending(intent) else { return }
        startCommand { [weak self] in await self?.recoverPendingIntent() }
    }

    func retry() {
        guard accountID != nil else { return }
        if phase == .storageUnavailable {
            if hasRequestedAccountChange {
                changeAccount(to: requestedAccountID)
            } else {
                loadRecovery()
            }
            return
        }
        lastError = nil
        if recovery.pendingIntent != nil, !isCommandInFlight {
            startCommand { [weak self] in await self?.recoverPendingIntent() }
        } else if let matchID = recovery.matchID {
            isOpen = true
            if !isCommandInFlight || recovery.pendingIntent != nil { isRecoverySelected = true }
            phase = .recovering
            startRealtime(matchID: matchID)
        }
    }

    func discardPendingGuess() {
        guard !isCommandInFlight, case .guess = recovery.pendingIntent else { return }
        let previous = recovery
        recovery.pendingIntent = nil
        guard saveRecovery() else {
            recovery = previous
            return
        }
        lastError = nil
        phase = snapshot == nil ? .recovering : .ready
        requestRefresh()
    }

    func discardPendingCreate() {
        guard !isCommandInFlight,
              case .create = recovery.pendingIntent,
              recovery.matchID == nil
        else { return }
        let previous = recovery
        recovery.pendingIntent = nil
        guard saveRecovery() else {
            recovery = previous
            return
        }
        lastError = nil
        isOpen = false
        phase = .inactive
        recoveryTimer?.cancel()
        recoveryTimer = nil
    }

    func leaveToHome() {
        isOpen = false
        isRecoverySelected = false
        snapshot = nil
        snapshotUptime = nil
        if phase != .storageUnavailable { phase = .inactive }
        cancelMatchTasks()
    }

    func resumeSavedMatch() {
        guard phase != .storageUnavailable, hasSavedMatch else { return }
        isOpen = true
        // While Join is unresolved, Resume opens its eventual result, not the old pointer.
        if !isCommandInFlight || recovery.pendingIntent != nil { isRecoverySelected = true }
        phase = .recovering
        beginRecovery()
    }

    func foregrounded() {
        guard !isForeground else { return }
        isForeground = true
        guard isOpen else { return }
        beginRecovery()
    }

    func backgrounded() {
        guard isForeground else { return }
        isForeground = false
        fetchTask?.cancel()
        fetchTask = nil
        trailingRefresh = false
        realtimeTask?.cancel()
        realtimeTask = nil
        realtimeRetryTask?.cancel()
        realtimeRetryTask = nil
        recoveryTimer?.cancel()
        recoveryTimer = nil
    }

    private var canBeginCommand: Bool {
        accountID != nil
            && service != nil
            && phase != .storageUnavailable
            && !isCommandInFlight
    }

    private func beginRecovery() {
        guard phase != .storageUnavailable, isForeground,
              isRecoverySelected || recovery.pendingIntent != nil else { return }
        if recovery.pendingIntent != nil {
            if let matchID = recovery.matchID {
                startRealtime(matchID: matchID)
            } else if !isCommandInFlight {
                startCommand { [weak self] in await self?.recoverPendingIntent() }
            }
        } else if let matchID = recovery.matchID {
            startRealtime(matchID: matchID)
        }
    }

    private func open(matchID: UUID) {
        guard isOpen else { return }
        cancelMatchTasks()
        isRecoverySelected = true
        snapshot = nil
        snapshotUptime = nil
        phase = .recovering
        trailingRefresh = false
        startRealtime(matchID: matchID)
    }

    private func startRealtime(matchID: UUID) {
        guard isRecoverySelected, isForeground, isOpen,
              recovery.matchID == matchID, shouldRecover else { return }
        realtimeRetryTask?.cancel()
        realtimeRetryTask = nil
        realtimeTask?.cancel()
        realtimeTask = nil
        let accountGeneration = generation
        guard let realtime else {
            requestRefresh()
            return
        }
        let events = realtime.events(matchID: matchID)
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in events {
                    guard isCurrent(accountGeneration), recovery.matchID == matchID else { return }
                    guard phase != .storageUnavailable else { continue }
                    switch event {
                    case .ready:
                        realtimeFailureCount = 0
                        phase = .recovering
                        if recovery.pendingIntent != nil, !isCommandInFlight {
                            startCommand { [weak self] in await self?.recoverPendingIntent() }
                        } else {
                            requestRefresh()
                        }
                    case .signal:
                        requestRefresh()
                    case .disconnected:
                        if phase == .ready { phase = .recovering }
                    }
                }
                guard isCurrent(accountGeneration) else { return }
                requestRefresh()
                scheduleRealtimeRestart(matchID: matchID, accountGeneration: accountGeneration)
            } catch {
                guard isCurrent(accountGeneration) else { return }
                requestRefresh()
                scheduleRealtimeRestart(matchID: matchID, accountGeneration: accountGeneration)
            }
        }
    }

    private func scheduleRealtimeRestart(matchID: UUID, accountGeneration: Int) {
        guard shouldRecover else { return }
        realtimeFailureCount += 1
        let index = min(realtimeFailureCount - 1, timing.retryBackoff.count - 1)
        let delay = timing.retryBackoff[index]
        realtimeRetryTask?.cancel()
        realtimeRetryTask = Task { [weak self] in
            guard let self else { return }
            do { try await sleep(delay) } catch { return }
            guard isCurrent(accountGeneration), recovery.matchID == matchID, shouldRecover else {
                return
            }
            startRealtime(matchID: matchID)
        }
    }

    private func startCommand(_ operation: @escaping @MainActor () async -> Void) {
        beginCommand()
        let accountGeneration = generation
        commandTask = Task {
            await operation()
            finishCommand(accountGeneration)
        }
    }

    private func beginCommand() {
        isCommandInFlight = true
        phase = .recovering
        commandEpoch += 1
        trailingRefresh = true
        recoveryTimer?.cancel()
        recoveryTimer = nil
    }

    private func finishCommand(_ accountGeneration: Int) {
        guard isCurrent(accountGeneration) else { return }
        isCommandInFlight = false
        commandTask = nil
        if trailingRefresh, recovery.matchID != nil { requestRefresh() }
    }

    private func recoverPendingIntent() async {
        guard let intent = recovery.pendingIntent, let service else { return }
        let accountGeneration = generation
        do {
            switch intent {
            case .create(let requestID):
                let matchID = try await request {
                    try await service.createMatch(requestID: requestID)
                }
                guard isCurrent(accountGeneration), recovery.pendingIntent == intent else { return }
                try saveResolvedMatch(matchID)
                open(matchID: matchID)
            case .guess(let matchID, let requestID, let word):
                _ = try await request {
                    try await service.submitGuess(
                        matchID: matchID,
                        requestID: requestID,
                        guess: word
                    )
                }
                guard isCurrent(accountGeneration), recovery.pendingIntent == intent else { return }
                let previous = recovery
                recovery.pendingIntent = nil
                guard saveRecovery() else {
                    recovery = previous
                    return
                }
                guessDraft = ""
                requestRefresh()
            }
        } catch {
            guard isCurrent(accountGeneration), recovery.pendingIntent == intent else { return }
            handlePendingError(error, intent: intent)
        }
    }

    private func requestRefresh() {
        guard isRecoverySelected, isForeground, isOpen,
              phase != .storageUnavailable, recovery.matchID != nil else { return }
        if isCommandInFlight || fetchTask != nil {
            trailingRefresh = true
            return
        }
        let accountGeneration = generation
        fetchTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                trailingRefresh = false
                await fetchSnapshot(accountGeneration: accountGeneration)
            } while isCurrent(accountGeneration)
                && phase != .storageUnavailable
                && trailingRefresh
                && !isCommandInFlight
                && isForeground
            guard !Task.isCancelled else { return }
            fetchTask = nil
        }
    }

    private func fetchSnapshot(accountGeneration: Int) async {
        guard let matchID = recovery.matchID, let service else { return }
        let responseEpoch = commandEpoch
        do {
            let received = try await request { try await service.snapshot(matchID: matchID) }
            guard isCurrent(accountGeneration),
                  phase != .storageUnavailable,
                  responseEpoch == commandEpoch,
                  recovery.matchID == matchID
            else { return }
            snapshot = received
            snapshotUptime = uptime()
            let preservesPendingDecision = recovery.pendingIntent != nil
                && (lastError == .server(.requestConflict)
                    || lastError == .server(.rateLimited))
            phase = preservesPendingDecision ? .unavailable : .ready
            if !preservesPendingDecision { lastError = nil }
            failureCount = 0
            scheduleNextRefresh()
        } catch {
            guard isCurrent(accountGeneration), responseEpoch == commandEpoch else { return }
            handleSnapshotError(error)
        }
    }

    private func request<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let requestGeneration = generation
        do {
            return try await timed(operation)
        } catch LiveMatchServiceError.server(.notAuthenticated) {
            guard let accountID,
                  try await timed({ await self.refreshAuth(accountID) }),
                  generation == requestGeneration,
                  self.accountID == accountID
            else { throw LiveMatchServiceError.server(.notAuthenticated) }
            return try await timed(operation)
        }
    }

    private func timed<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await self.sleep(self.timing.requestTimeout)
                throw LiveMatchServiceError.unavailable
            }
            guard let result = try await group.next() else {
                throw LiveMatchServiceError.unavailable
            }
            group.cancelAll()
            return result
        }
    }

    private func handlePendingError(_ error: Error, intent: LivePendingIntent) {
        guard phase != .storageUnavailable else { return }
        let mapped = map(error)
        lastError = mapped
        switch mapped {
        case .unavailable, .invalidResponse, .server(.internalError):
            phase = .unavailable
            scheduleRetry(recoverPending: true)
        case .server(.rateLimited), .server(.requestConflict):
            phase = .unavailable
        case .server(.notAuthenticated):
            phase = .needsSignIn
        default:
            if case .guess(_, _, let word) = intent { guessDraft = word }
            let previous = recovery
            recovery.pendingIntent = nil
            guard saveRecovery() else {
                recovery = previous
                return
            }
            phase = .unavailable
            if recovery.matchID != nil { requestRefresh() }
        }
    }

    private func handleCommandError(_ error: Error, uncertainIntent: Bool) {
        guard phase != .storageUnavailable else { return }
        let mapped = map(error)
        lastError = mapped
        if mapped == .server(.notAuthenticated) {
            phase = .needsSignIn
        } else {
            phase = .unavailable
            if uncertainIntent || mapped == .unavailable || mapped == .server(.internalError) {
                scheduleRetry(recoverPending: false)
            }
        }
    }

    private func handleSnapshotError(_ error: Error) {
        guard phase != .storageUnavailable else { return }
        let mapped = map(error)
        let preservesPendingDecision = recovery.pendingIntent != nil
            && (lastError == .server(.requestConflict) || lastError == .server(.rateLimited))
        if !preservesPendingDecision { lastError = mapped }
        switch mapped {
        case .server(.notAMatchMember), .server(.roomExpired):
            clearSavedMatch()
        case .server(.notAuthenticated):
            phase = .needsSignIn
            stopRecoveryLoop()
        case .server(.clientUpdateRequired), .invalidResponse:
            phase = .unavailable
            stopRecoveryLoop()
        default:
            phase = .unavailable
            scheduleRetry(recoverPending: false)
        }
    }

    private func scheduleNextRefresh() {
        recoveryTimer?.cancel()
        guard shouldRecover, let snapshot, let displayedServerTime else {
            stopRecoveryLoop()
            return
        }
        if snapshot.match.status == .lobby,
           snapshot.serverTime >= snapshot.match.expiresAt {
            stopRecoveryLoop()
            return
        }
        var delay = timing.staleAfter
        let deadline: Date? = switch snapshot.round.state {
        case .pending: snapshot.match.expiresAt
        case .countdown: snapshot.round.startsAt
        case .playing: snapshot.round.endsAt
        case .revealed: nil
        }
        if let deadline {
            let seconds = max(0, deadline.timeIntervalSince(displayedServerTime))
            delay = min(delay, .seconds(seconds))
        }
        scheduleTimer(delay: delay, recoverPending: false)
    }

    private func scheduleRetry(recoverPending: Bool) {
        guard shouldRecover else { return }
        failureCount += 1
        let index = min(failureCount - 1, timing.retryBackoff.count - 1)
        scheduleTimer(delay: timing.retryBackoff[index], recoverPending: recoverPending)
    }

    private func scheduleTimer(delay: Duration, recoverPending: Bool) {
        recoveryTimer?.cancel()
        let accountGeneration = generation
        recoveryTimer = Task { [weak self] in
            guard let self else { return }
            do { try await sleep(delay) } catch { return }
            guard isCurrent(accountGeneration), shouldRecover else { return }
            if recoverPending, recovery.pendingIntent != nil, !isCommandInFlight {
                startCommand { [weak self] in await self?.recoverPendingIntent() }
            } else {
                requestRefresh()
            }
        }
    }

    private var shouldRecover: Bool {
        guard isForeground, isOpen, accountID != nil, phase != .storageUnavailable,
              isRecoverySelected || recovery.pendingIntent != nil else { return false }
        guard let snapshot else { return true }
        if snapshot.match.status == .completed || snapshot.round.state == .revealed { return false }
        return true
    }

    private func persistPending(_ intent: LivePendingIntent) -> Bool {
        let previous = recovery
        recovery.pendingIntent = intent
        guard saveRecovery() else {
            recovery = previous
            return false
        }
        return true
    }

    private func saveResolvedMatch(_ matchID: UUID) throws {
        let previous = recovery
        recovery.matchID = matchID
        recovery.pendingIntent = nil
        guard saveRecovery() else {
            recovery = previous
            throw LiveMatchRecoveryError.unavailable
        }
    }

    private func saveRecovery() -> Bool {
        do {
            try store?.save(recovery)
            return store != nil
        } catch {
            phase = .storageUnavailable
            lastError = nil
            return false
        }
    }

    private func clearSavedMatch() {
        do {
            try store?.clear()
        } catch {
            phase = .storageUnavailable
            stopRecoveryLoop()
            return
        }
        recovery = LiveRecoveryState()
        snapshot = nil
        snapshotUptime = nil
        isOpen = false
        phase = .unavailable
        stopRecoveryLoop()
    }

    private func stopRecoveryLoop() {
        realtimeTask?.cancel()
        realtimeTask = nil
        realtimeRetryTask?.cancel()
        realtimeRetryTask = nil
        recoveryTimer?.cancel()
        recoveryTimer = nil
    }

    private func map(_ error: Error) -> LiveMatchServiceError {
        if let error = error as? LiveMatchServiceError { return error }
        return .unavailable
    }

    private func isCurrent(_ accountGeneration: Int) -> Bool {
        generation == accountGeneration && accountID != nil && !Task.isCancelled
    }

    private func loadRecovery() {
        guard let accountID, service != nil else { return }
        do {
            let store = try storeFactory(accountID)
            self.store = store
            recovery = try store.load()
            phase = .inactive
            guard recovery.matchID != nil || recovery.pendingIntent != nil else { return }
            isOpen = true
            isRecoverySelected = recovery.matchID != nil
            phase = .recovering
            beginRecovery()
        } catch {
            phase = .storageUnavailable
        }
    }

    private func resetRuntime() {
        generation += 1
        commandEpoch += 1
        cancelTasks()
        store = nil
        recovery = LiveRecoveryState()
        snapshot = nil
        snapshotUptime = nil
        guessDraft = ""
        lastError = nil
        phase = .inactive
        isCommandInFlight = false
        trailingRefresh = false
        failureCount = 0
        realtimeFailureCount = 0
        isOpen = false
        isRecoverySelected = false
    }

    private func cancelMatchTasks() {
        fetchTask?.cancel()
        fetchTask = nil
        realtimeTask?.cancel()
        realtimeTask = nil
        realtimeRetryTask?.cancel()
        realtimeRetryTask = nil
        recoveryTimer?.cancel()
        recoveryTimer = nil
        trailingRefresh = false
    }

    private func cancelTasks() {
        commandTask?.cancel()
        commandTask = nil
        cancelMatchTasks()
    }
}
