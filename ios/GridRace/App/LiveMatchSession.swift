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

    private var service: (any LiveMatchServicing)?
    private var realtime: (any LiveMatchRealtimeServicing)?
    private let storeFactory: StoreFactory
    private let cleanupJournal: AccountCleanupJournal?
    private var refreshAuth: AuthRefresh = { _ in false }
    private let timing: LiveMatchSessionTiming
    private let sleep: @Sendable (Duration) async throws -> Void
    private let uptime: @MainActor () -> TimeInterval
    private let makeUUID: @MainActor () -> UUID

    private var accountID: UUID?
    private var transport: LiveAccountTransport?
    private var requestedTransport: LiveAccountTransport?
    private var requestedAccountID: UUID?
    private var hasRequestedAccountChange = false
    private var phaseBeforeCapturedCleanup: LiveMatchSessionPhase?
    private var store: (any LiveMatchRecoveryStoring)?
    private var recovery = LiveRecoveryState()
    private var generation = 0
    private var commandEpoch = 0
    private var isExplicitServiceRetry = false
    private var presentationGeneration = 0
    private var navigationGeneration = UUID()
    private var acceptedSnapshot: LiveMatchSnapshot?
    private var viewerSelectionEpoch: Int64 = 0
    private(set) var resumeConfirmationTarget: LiveMatchSnapshot?
    private(set) var completedInvitationGeneration: UUID?
    private(set) var serviceNeedsUpdate = false
    private var pendingStart: (matchID: UUID, roundNumber: Int)?
    private(set) var selectedRevealNumber: Int?
    private var isForeground = true
    private var isOpen = false
    // A durable pointer is resumable, but is not necessarily the current Join target.
    private var isRecoverySelected = false
    private var trailingRefresh = false
    private var failureCount = 0
    private var snapshotUptime: TimeInterval?
    private var acceptedRevision: (matchID: UUID, revision: Int64, roundNumber: Int)?
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

    var completedInvitationAccountID: UUID? { completedInvitationGeneration == nil ? nil : accountID }

    var hasSavedMatch: Bool { recovery.matchID != nil || recovery.pendingIntent != nil }
    var savedMatchID: UUID? { recovery.matchID }
    var pendingIntent: LivePendingIntent? { recovery.pendingIntent }
    var hasPendingStart: Bool { pendingStart != nil }
    var canRetry: Bool {
        guard accountID != nil, service != nil, !isCommandInFlight,
              phase != .storageUnavailable, phase != .needsSignIn, isForeground, isOpen else { return false }
        if serviceNeedsUpdate { return hasSavedMatch || pendingStart != nil }
        return recovery.pendingIntent != nil || pendingStart != nil
            || (recovery.matchID != nil && shouldRecover)
    }
    private var hasPendingDecision: Bool {
        recovery.pendingIntent != nil
            && (serviceNeedsUpdate || lastError == .server(.requestConflict) || lastError == .server(.rateLimited))
    }
    var canRetryRecoveryStorage: Bool { phase == .storageUnavailable && (accountID != nil || cleanupJournal?.isUnavailable == true || cleanupJournal?.liveUsers.isEmpty == false) }
    var canDiscardRecovery: Bool { canRetryRecoveryStorage }

    var displayedServerTime: Date? {
        guard let snapshot, let snapshotUptime else { return nil }
        return snapshot.serverTime.addingTimeInterval(max(0, uptime() - snapshotUptime))
    }

    /// Eligibility for a new Start. Retrying a captured target uses `canRetry` instead.
    var canStart: Bool {
        guard canBeginCommand, phase == .ready, isOpen, isForeground,
              recovery.pendingIntent == nil, pendingStart == nil,
              let snapshot, snapshot.selection.isSelected, recovery.matchID == snapshot.match.id,
              let displayedServerTime,
              snapshot.match.terminalReason == nil,
              snapshot.members.count == 2,
              snapshot.members.allSatisfy({ !$0.isDeleted }),
              snapshot.members.first(where: \.isSelf)?.id == snapshot.match.creatorMemberID
        else { return false }
        if snapshot.match.status == .lobby {
            return snapshot.round.state == .pending && displayedServerTime < snapshot.match.expiresAt
        }
        return snapshot.match.status == .inProgress && snapshot.round.state == .revealed
            && snapshot.match.currentRound < snapshot.match.roundCount
    }

    var canInput: Bool {
        guard canBeginCommand, isOpen, isForeground, pendingStart == nil,
              !isInputLocked, let snapshot, snapshot.selection.isSelected, recovery.matchID == snapshot.match.id,
              snapshot.match.status == .inProgress,
              let member = snapshot.members.first(where: \.isSelf), !member.isDeleted,
              let player = snapshot.round.players.first(where: { $0.memberID == member.id })
        else { return false }
        return player.state == .playing
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
        storeFactory: @escaping StoreFactory = {
            try LiveMatchRecoveryStore.applicationSupport(userID: $0)
        },
        cleanupJournal: AccountCleanupJournal? = nil,
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
        self.storeFactory = storeFactory
        self.cleanupJournal = cleanupJournal
        self.timing = timing
        self.sleep = sleep
        self.uptime = uptime
        self.makeUUID = makeUUID
        if cleanupJournal?.isUnavailable == true || cleanupJournal?.liveUsers.isEmpty == false {
            phase = .storageUnavailable
        }
    }

    isolated deinit {
        cancelTasks()
    }

    @discardableResult
    func changeAccount(to userID: UUID?, transport next: LiveAccountTransport?) -> LiveAccountChangeOutcome {
        if accountID == userID, transport?.userID == userID, transport?.isValid() == true {
            return .completed
        }
        service = nil
        realtime = nil
        refreshAuth = { _ in false }
        transport = nil
        requestedTransport = next
        return transitionAccount(to: userID)
    }

    func hasPendingAccountCleanup(for userID: UUID) -> Bool {
        (accountID == userID && hasRequestedAccountChange) || cleanupJournal?.liveUsers.contains(userID) == true
    }

    @discardableResult
    func cleanupCapturedAccount(_ userID: UUID) -> LiveAccountChangeOutcome {
        if accountID == userID { resetRuntime() }
        do {
            try cleanupJournal?.capture(userID, deleting: false)
            try storeFactory(userID).clear()
            try cleanupJournal?.completeLive(userID)
            return .completed
        } catch {
            if accountID != userID, !hasRequestedAccountChange, phaseBeforeCapturedCleanup == nil {
                phaseBeforeCapturedCleanup = phase
            }
            phase = .storageUnavailable
            return .recoveryCleanupPending
        }
    }

    private func retryCapturedCleanup() {
        guard let cleanupJournal else { return }
        do { try cleanupJournal.reload() }
        catch { phase = .storageUnavailable; return }
        if let accountID, hasRequestedAccountChange {
            do { try cleanupJournal.capture(accountID, deleting: false) }
            catch { phase = .storageUnavailable; return }
        }
        var failed = false
        for userID in cleanupJournal.liveUsers {
            do {
                try storeFactory(userID).clear()
                try cleanupJournal.completeLive(userID)
            } catch { failed = true }
        }
        guard !failed else { phase = .storageUnavailable; return }
        // A captured old-account obligation can be retried while a later account
        // remains active. Only an actual pending transition may replace its runtime.
        guard hasRequestedAccountChange else {
            if phase == .storageUnavailable, let previousPhase = phaseBeforeCapturedCleanup { phase = previousPhase }
            else if accountID == nil { phase = .inactive }
            phaseBeforeCapturedCleanup = nil
            return
        }
        let userID = requestedAccountID
        resetRuntime()
        accountID = userID
        hasRequestedAccountChange = false
        requestedAccountID = nil
        guard installRequestedTransport(for: userID) else { return }
        loadRecovery()
    }

    private func installRequestedTransport(for userID: UUID?) -> Bool {
        guard let userID else {
            requestedTransport = nil
            return true
        }
        guard let target = requestedTransport, target.userID == userID, target.isValid() else {
            requestedTransport = nil
            phase = .needsSignIn
            return false
        }
        transport = target
        service = target.service
        realtime = target.realtime
        refreshAuth = target.refresh
        requestedTransport = nil
        return true
    }

    @discardableResult
    private func transitionAccount(to userID: UUID?) -> LiveAccountChangeOutcome {
        if let cleanupJournal, cleanupJournal.isUnavailable || !cleanupJournal.liveUsers.isEmpty {
            if hasRequestedAccountChange, requestedAccountID == userID {
                // Repeated Auth notifications retain the captured transition and
                // retry its local cleanup; they never reload the old intent.
                retryCapturedCleanup()
                return hasRequestedAccountChange || cleanupJournal.isUnavailable || !cleanupJournal.liveUsers.isEmpty
                    ? .recoveryCleanupPending : .completed
            }
            // No saved command can dispatch before captured cleanup is resolved,
            // even if Auth later returns to the same UUID.
            resetRuntime()
            requestedAccountID = userID
            hasRequestedAccountChange = true
            phase = .storageUnavailable
            return .recoveryCleanupPending
        }
        guard accountID != userID else {
            if hasRequestedAccountChange {
                requestedAccountID = nil
                hasRequestedAccountChange = false
            }
            if service == nil {
                if phase == .storageUnavailable {
                    // Auth can revert a failed switch without authorizing a storage
                    // retry. Bind only this account; retain its failure until explicit
                    // retry/discard, including when the replacement lease is invalid.
                    _ = installRequestedTransport(for: userID)
                    phase = .storageUnavailable
                } else {
                    resetRuntime()
                    guard installRequestedTransport(for: userID) else { return .completed }
                    loadRecovery()
                }
            }
            return .completed
        }
        let oldAccountID = accountID
        let oldStore = store
        resetRuntime()
        if let oldAccountID {
            do {
                try cleanupJournal?.capture(oldAccountID, deleting: false)
                let oldStore = try oldStore ?? storeFactory(oldAccountID)
                try oldStore.clear()
                try cleanupJournal?.completeLive(oldAccountID)
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
        guard installRequestedTransport(for: userID) else { return .completed }
        loadRecovery()
        return .completed
    }

    func discardRecovery() {
        guard canDiscardRecovery else { return }
        if cleanupJournal?.isUnavailable == true || cleanupJournal?.liveUsers.isEmpty == false {
            retryCapturedCleanup()
            return
        }
        guard let accountID else { return }
        do {
            let store = try store ?? storeFactory(accountID)
            try store.clear()
            resetRuntime()
            if hasRequestedAccountChange {
                let userID = requestedAccountID
                requestedAccountID = nil
                hasRequestedAccountChange = false
                self.accountID = userID
                guard installRequestedTransport(for: userID) else { return }
                loadRecovery()
            } else {
                self.store = store
            }
        } catch {
            phase = .storageUnavailable
        }
    }

    func createMatch(roundCount: Int = 3) {
        guard canBeginCommand, recovery.pendingIntent == nil, pendingStart == nil else { return }
        let intent = LivePendingIntent.create(requestID: makeUUID(), roundCount: roundCount, clientBuild: 3)
        let previous = recovery
        recovery = LiveRecoveryState(pendingIntent: intent, completedInvitationGeneration: previous.completedInvitationGeneration)
        guard saveRecovery() else {
            recovery = previous
            return
        }
        isOpen = true
        isRecoverySelected = false
        snapshot = nil
        snapshotUptime = nil
        guessDraft = ""
        selectedRevealNumber = nil
        pendingStart = nil
        presentationGeneration += 1
        cancelMatchTasks()
        startCommand { [weak self] in await self?.recoverPendingIntent() }
    }

    /// Called only after the presentation owner obtains explicit Join confirmation.
    /// A URL's generation is returned on durable success so replacement URLs survive.
    func joinMatch(code: String, invitationGeneration: UUID? = nil) {
        guard canBeginCommand, recovery.pendingIntent == nil, pendingStart == nil,
              invitationGeneration == nil || recovery.completedInvitationGeneration == nil else { return }
        beginJoin(code: code, expectedMatchID: nil, invitationGeneration: invitationGeneration)
    }

    var requiresResumeConfirmation: Bool {
        isOpen && recovery.pendingIntent == nil
            && (resumeConfirmationTarget != nil || snapshot?.selection.isSelected == false)
    }

    /// Passive Resume reads first. A stale pointer requires this separate confirmation.
    func confirmResumeSavedMatch() {
        guard canBeginCommand, requiresResumeConfirmation, let snapshot else { return }
        let target = resumeConfirmationTarget ?? snapshot
        beginJoin(code: target.match.joinCode, expectedMatchID: target.match.id, invitationGeneration: nil)
    }

    private func beginJoin(code: String, expectedMatchID: UUID?, invitationGeneration: UUID?) {
        let nextNavigation = UUID()
        let command = LiveJoinCommand(requestID: makeUUID(), code: code.uppercased(),
                                      expectedMatchID: expectedMatchID, clientBuild: 3)
        let intent = LivePendingIntent.join(command: command, sourceMatchID: recovery.matchID,
                                            navigationGeneration: nextNavigation,
                                            invitationGeneration: invitationGeneration)
        guard persistPending(intent) else { return }
        setSuccessorFollowAllowed(true)
        guard phase != .storageUnavailable else { return }
        resumeConfirmationTarget = nil
        navigationGeneration = nextNavigation
        isOpen = true
        isRecoverySelected = false
        snapshot = nil
        snapshotUptime = nil
        guessDraft = ""
        selectedRevealNumber = nil
        pendingStart = nil
        presentationGeneration += 1
        cancelMatchTasks()
        startCommand { [weak self] in await self?.recoverPendingIntent() }
    }

    var availableRematchActions: [LiveRematchAction] {
        guard canBeginCommand, phase == .ready, isOpen, isForeground,
              recovery.pendingIntent == nil, pendingStart == nil,
              let snapshot, snapshot.selection.isSelected,
              let rematch = snapshot.rematch,
              let selfID = snapshot.members.first(where: \.isSelf)?.id else { return [] }
        switch rematch.state {
        case .eligible: return rematch.isEligible ? [.offer] : []
        case .closed: return rematch.isEligible && rematch.nextGeneration != nil ? [.offer] : []
        case .offered:
            if rematch.consentingMemberIDs.contains(selfID) { return [.cancel] }
            return rematch.isEligible ? [.accept, .decline] : [.decline]
        case .expired, .unavailable, .accepted: return []
        }
    }

    func performRematch(_ action: LiveRematchAction) {
        guard availableRematchActions.contains(action), let snapshot,
              let rematch = snapshot.rematch else { return }
        let targetGeneration = action == .offer ? (rematch.nextGeneration ?? rematch.generation) : rematch.generation
        let command = LiveRematchCommand(requestID: makeUUID(), predecessorMatchID: snapshot.match.id,
                                         generation: targetGeneration, action: action,
                                         expectedParticipationEpoch: snapshot.selection.epoch, clientBuild: 3)
        let intent = LivePendingIntent.rematch(command: command, sourceMatchID: snapshot.match.id,
                                               navigationGeneration: navigationGeneration)
        guard persistPending(intent) else { return }
        startCommand { [weak self] in await self?.recoverPendingIntent() }
    }

    func discardPendingSelection() {
        guard !isCommandInFlight, let intent = recovery.pendingIntent else { return }
        switch intent {
        case .join, .rematch: break
        default: return
        }
        let previous = recovery
        recovery.pendingIntent = nil
        guard saveRecovery() else { recovery = previous; return }
        lastError = nil
        if serviceNeedsUpdate { phase = .unavailable; return }
        phase = snapshot == nil ? .recovering : .ready
        requestRefresh()
    }

    func startMatch() {
        guard canStart, let snapshot else { return }
        let target = snapshot.round.state == .pending ? 1 : snapshot.match.currentRound + 1
        pendingStart = (snapshot.match.id, target)
        performStart()
    }

    private func performStart() {
        guard let target = pendingStart, let service else { return }
        let accountGeneration = generation
        let presentation = presentationGeneration
        beginCommand()
        commandTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await request {
                    try await service.startMatch(id: target.matchID, roundNumber: target.roundNumber)
                }
                guard isCurrent(accountGeneration) else { return }
                pendingStart = nil
            } catch {
                guard isCurrent(accountGeneration) else { return }
                let mapped = map(error)
                if mapped != .unavailable && mapped != .invalidResponse
                    && mapped != .server(.internalError) && mapped != .server(.notAuthenticated)
                    && mapped != .server(.clientUpdateRequired) {
                    pendingStart = nil
                }
                if presentation == presentationGeneration {
                    handleCommandError(error, uncertainIntent: true)
                }
            }
            guard isCurrent(accountGeneration) else { return }
            if isExplicitServiceRetry, lastError == nil {
                await confirmUpdatedService(accountGeneration: accountGeneration)
            }
            finishCommand(accountGeneration)
            requestRefresh()
        }
    }

    var displayedReveal: LiveRound? {
        guard let snapshot else { return nil }
        if let selectedRevealNumber {
            return snapshot.revealedRounds.first { $0.number == selectedRevealNumber }
        }
        return snapshot.round.state == .revealed ? snapshot.round : nil
    }

    func selectReveal(number: Int?) {
        guard number == nil || snapshot?.revealedRounds.contains(where: { $0.number == number }) == true else { return }
        selectedRevealNumber = number
    }

    func submitGuess(_ word: String) {
        guard canInput, let snapshot, let matchID = recovery.matchID else { return }
        let intent = LivePendingIntent.guess(
            matchID: matchID,
            requestID: makeUUID(),
            word: word,
            roundNumber: snapshot.match.currentRound,
            clientBuild: 3
        )
        guessDraft = word
        guard persistPending(intent) else { return }
        startCommand { [weak self] in await self?.recoverPendingIntent() }
    }

    func retry() {
        if phase == .storageUnavailable, cleanupJournal?.isUnavailable == true || cleanupJournal?.liveUsers.isEmpty == false {
            retryCapturedCleanup()
            return
        }
        guard accountID != nil else { return }
        if phase == .storageUnavailable {
            if hasRequestedAccountChange {
                transitionAccount(to: requestedAccountID)
            } else {
                loadRecovery()
            }
            return
        }
        guard canRetry else { return }
        lastError = nil
        if serviceNeedsUpdate {
            // Keep the mismatch fence raised throughout this user-requested attempt.
            // Receipt replay cannot enable ordinary commands or automatic retries;
            // only a current canonical response proves the service was corrected.
            isExplicitServiceRetry = true
            if pendingStart != nil {
                performStart()
            } else {
                let accountGeneration = generation
                startCommand { [weak self] in
                    guard let self else { return }
                    if recovery.pendingIntent != nil { await recoverPendingIntent() }
                    guard isCurrent(accountGeneration), lastError == nil else { return }
                    await confirmUpdatedService(accountGeneration: accountGeneration)
                }
            }
            return
        }
        if recovery.pendingIntent != nil {
            startCommand { [weak self] in await self?.recoverPendingIntent() }
        } else if pendingStart != nil {
            performStart()
        } else if let matchID = recovery.matchID {
            phase = .recovering
            startRealtime(matchID: matchID)
        }
    }

    private func confirmUpdatedService(accountGeneration: Int) async {
        guard let matchID = recovery.matchID, let service,
              isOpen, isForeground, phase != .storageUnavailable else { return }
        let presentation = presentationGeneration
        do {
            let canonical = try await request { try await service.snapshot(matchID: matchID) }
            guard isCurrent(accountGeneration), presentation == presentationGeneration,
                  isOpen, isForeground, phase != .storageUnavailable,
                  recovery.matchID == matchID else { return }
            serviceNeedsUpdate = false
            acceptSnapshot(canonical)
        } catch {
            guard isCurrent(accountGeneration), presentation == presentationGeneration,
                  phase != .storageUnavailable else { return }
            lastError = map(error)
            phase = lastError == .server(.notAuthenticated) ? .needsSignIn : .unavailable
            stopRecoveryLoop()
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

    /// Invalidate post-match follow when the composition owner presents a newer
    /// invitation/navigation target, even if this result remains underneath it.
    func invitationNavigationChanged() {
        navigationGeneration = UUID()
        resumeConfirmationTarget = nil
        setSuccessorFollowAllowed(false)
    }

    private func setSuccessorFollowAllowed(_ allowed: Bool) {
        guard phase != .storageUnavailable, store != nil, recovery.successorFollowAllowed != allowed else { return }
        let previous = recovery
        recovery.successorFollowAllowed = allowed
        if !saveRecovery() { recovery = previous }
    }

    func leaveToHome() {
        setSuccessorFollowAllowed(false)
        resumeConfirmationTarget = nil
        presentationGeneration += 1
        navigationGeneration = UUID()
        selectedRevealNumber = nil
        isOpen = false
        isRecoverySelected = false
        snapshot = nil
        snapshotUptime = nil
        if phase != .storageUnavailable { phase = .inactive }
        cancelMatchTasks()
    }

    func resumeSavedMatch() {
        guard phase != .storageUnavailable, !serviceNeedsUpdate, hasSavedMatch else { return }
        setSuccessorFollowAllowed(true)
        guard phase != .storageUnavailable else { return }
        resumeConfirmationTarget = nil
        presentationGeneration += 1
        cancelMatchTasks()
        isOpen = true
        // While Join is unresolved, Resume opens its eventual result, not the old pointer.
        if case .join(_, _, let navigation, _) = recovery.pendingIntent {
            navigationGeneration = navigation
            isRecoverySelected = false
        } else if !isCommandInFlight || recovery.pendingIntent != nil { isRecoverySelected = true }
        phase = .recovering
        beginRecovery()
    }

    func foregrounded() {
        guard !isForeground else { return }
        isForeground = true
        presentationGeneration += 1
        guard isOpen else { return }
        beginRecovery()
    }

    func backgrounded() {
        guard isForeground else { return }
        isForeground = false
        presentationGeneration += 1
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
            && !serviceNeedsUpdate
            && !isCommandInFlight
    }

    private func beginRecovery() {
        guard phase != .storageUnavailable, !serviceNeedsUpdate, isForeground,
              isRecoverySelected || recovery.pendingIntent != nil else { return }
        if recovery.pendingIntent != nil {
            if case .join = recovery.pendingIntent {
                if !hasPendingDecision, !isCommandInFlight {
                    startCommand { [weak self] in await self?.recoverPendingIntent() }
                }
            } else if let matchID = recovery.matchID {
                startRealtime(matchID: matchID)
            } else if hasPendingDecision {
                phase = .unavailable
            } else if !isCommandInFlight {
                startCommand { [weak self] in await self?.recoverPendingIntent() }
            }
        } else if let matchID = recovery.matchID {
            if shouldRecover { startRealtime(matchID: matchID) } else { requestRefresh() }
        }
    }

    private func open(matchID: UUID) {
        guard isOpen else { return }
        presentationGeneration += 1
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
        let presentation = presentationGeneration
        guard let realtime else {
            if recovery.pendingIntent != nil, !hasPendingDecision, !isCommandInFlight {
                startCommand { [weak self] in await self?.recoverPendingIntent() }
            } else { requestRefresh() }
            return
        }
        let events = realtime.events(matchID: matchID)
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in events {
                    guard isCurrent(accountGeneration), presentation == presentationGeneration,
                          isForeground, isOpen, recovery.matchID == matchID else { return }
                    guard phase != .storageUnavailable, !serviceNeedsUpdate else { continue }
                    switch event {
                    case .ready:
                        realtimeFailureCount = 0
                        phase = .recovering
                        if recovery.pendingIntent != nil, !hasPendingDecision, !isCommandInFlight {
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
                guard isCurrent(accountGeneration), presentation == presentationGeneration else { return }
                requestRefresh()
                scheduleRealtimeRestart(matchID: matchID, accountGeneration: accountGeneration)
            } catch {
                guard isCurrent(accountGeneration), presentation == presentationGeneration else { return }
                requestRefresh()
                scheduleRealtimeRestart(matchID: matchID, accountGeneration: accountGeneration)
            }
        }
    }

    private func scheduleRealtimeRestart(matchID: UUID, accountGeneration: Int) {
        guard shouldRecover else { return }
        let presentation = presentationGeneration
        realtimeFailureCount += 1
        let index = min(realtimeFailureCount - 1, timing.retryBackoff.count - 1)
        let delay = timing.retryBackoff[index]
        realtimeRetryTask?.cancel()
        realtimeRetryTask = Task { [weak self] in
            guard let self else { return }
            do { try await sleep(delay) } catch { return }
            guard isCurrent(accountGeneration), presentation == presentationGeneration,
                  recovery.matchID == matchID, shouldRecover else {
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
        if isExplicitServiceRetry {
            isExplicitServiceRetry = false
            if serviceNeedsUpdate { stopRecoveryLoop() }
            else { beginRecovery() }
        }
        if trailingRefresh, recovery.matchID != nil { requestRefresh() }
    }

    private func recoverPendingIntent() async {
        guard let intent = recovery.pendingIntent, let service else { return }
        let accountGeneration = generation
        let presentation = presentationGeneration
        do {
            switch intent {
            case .join(let command, let source, let navigation, let invitation):
                let matchID = try await request { try await service.joinMatch(command) }
                guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent,
                      recovery.matchID == source else { return }
                let admitted = try await request { try await service.snapshot(matchID: matchID) }
                guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent,
                      recovery.matchID == source else { return }
                try saveResolvedMatch(matchID, completedInvitationGeneration: invitation)
                if navigation == navigationGeneration, recovery.successorFollowAllowed {
                    open(matchID: matchID)
                    if isOpen, isForeground { acceptSnapshot(admitted) }
                } else {
                    // The admitted room remains resumable, but an older Join
                    // response cannot take over a newer invitation or Home.
                    isRecoverySelected = false
                    phase = .inactive
                }
            case .rematch(let command, let source, let navigation):
                _ = try await request { try await service.rematch(command) }
                guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent,
                      recovery.matchID == source else { return }
                let canonical = try await request { try await service.snapshot(matchID: source) }
                guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent,
                      recovery.matchID == source else { return }
                let predecessor = mergeSnapshot(canonical)
                if navigation == navigationGeneration, isOpen, recovery.successorFollowAllowed,
                   let rematch = predecessor.rematch, rematch.state == .accepted,
                   rematch.successorAvailable, !rematch.selectedElsewhere,
                   let successorID = rematch.successorMatchID {
                    let successor = try await request { try await service.snapshot(matchID: successorID) }
                    guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent,
                          recovery.matchID == source, navigation == navigationGeneration, isOpen else { return }
                    if canFollowSuccessor(successor, from: predecessor) {
                        try saveResolvedMatch(successorID)
                        open(matchID: successorID)
                        if isForeground { acceptSnapshot(successor) }
                    } else {
                        // Settle the original receipt without replacing its source
                        // pointer. A failed save retains the exact pending command.
                        try saveResolvedMatch(source)
                        if isForeground, presentation == presentationGeneration {
                            acceptSnapshot(predecessor)
                            rememberSuccessorConfirmation(successor)
                        }
                    }
                } else {
                    let previous = recovery
                    recovery.pendingIntent = nil
                    guard saveRecovery() else { recovery = previous; return }
                    if isOpen, presentation == presentationGeneration { acceptSnapshot(canonical) }
                }
            case .create(let requestID, let count, let build):
                let matchID = try await request {
                    try await service.createMatch(requestID: requestID, roundCount: count, clientBuild: build)
                }
                guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent else { return }
                try saveResolvedMatch(matchID)
                open(matchID: matchID)
            case .guess(let matchID, let requestID, let word, let round, let build):
                _ = try await request {
                    try await service.submitGuess(
                        matchID: matchID,
                        roundNumber: round,
                        requestID: requestID,
                        guess: word,
                        clientBuild: build
                    )
                }
                guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent else { return }
                let previous = recovery
                recovery.pendingIntent = nil
                guard saveRecovery() else {
                    recovery = previous
                    return
                }
                if presentation == presentationGeneration,
                   snapshot?.round.number == round { guessDraft = "" }
                requestRefresh()
            }
        } catch {
            guard isCurrent(accountGeneration), phase != .storageUnavailable, recovery.pendingIntent == intent else { return }
            handlePendingError(error, intent: intent, presentation: presentation)
        }
    }

    private func requestRefresh() {
        guard isRecoverySelected, isForeground, isOpen,
              phase != .storageUnavailable, !serviceNeedsUpdate, recovery.matchID != nil else { return }
        if isCommandInFlight || fetchTask != nil {
            trailingRefresh = true
            return
        }
        let accountGeneration = generation
        let presentation = presentationGeneration
        fetchTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                trailingRefresh = false
                await fetchSnapshot(accountGeneration: accountGeneration, presentation: presentation)
            } while isCurrent(accountGeneration)
                && presentation == presentationGeneration
                && isOpen
                && phase != .storageUnavailable
                && trailingRefresh
                && !isCommandInFlight
                && isForeground
            guard !Task.isCancelled, presentation == presentationGeneration else { return }
            fetchTask = nil
        }
    }

    private func fetchSnapshot(accountGeneration: Int, presentation: Int) async {
        guard let matchID = recovery.matchID, let service else { return }
        let responseEpoch = commandEpoch
        do {
            let received = try await request { try await service.snapshot(matchID: matchID) }
            guard isCurrent(accountGeneration), presentation == presentationGeneration, isForeground, isOpen,
                  phase != .storageUnavailable,
                  responseEpoch == commandEpoch,
                  recovery.matchID == matchID
            else { return }
            acceptSnapshot(received)
            if recovery.pendingIntent == nil, let rematch = snapshot?.rematch,
               rematch.state == .accepted, rematch.successorAvailable,
               let successorID = rematch.successorMatchID {
                let navigation = navigationGeneration
                let successor = try await request { try await service.snapshot(matchID: successorID) }
                guard isCurrent(accountGeneration), presentation == presentationGeneration, isOpen,
                      phase != .storageUnavailable, responseEpoch == commandEpoch,
                      recovery.matchID == matchID, recovery.pendingIntent == nil,
                      navigation == navigationGeneration else { return }
                if !canFollowSuccessor(successor, from: snapshot ?? received) {
                    rememberSuccessorConfirmation(successor)
                } else {
                    try saveResolvedMatch(successorID)
                    resumeConfirmationTarget = nil
                    open(matchID: successorID)
                    acceptSnapshot(successor)
                }
            }
        } catch {
            guard isCurrent(accountGeneration), presentation == presentationGeneration,
                  isForeground, isOpen, responseEpoch == commandEpoch else { return }
            handleSnapshotError(error)
        }
    }

    /// The second canonical read owns the successor's current selection. Keep an
    /// account-scoped high-water mark so delayed responses cannot undo a newer
    /// selection observed on either room, including across Home and Resume.
    private func canFollowSuccessor(_ successor: LiveMatchSnapshot, from predecessor: LiveMatchSnapshot) -> Bool {
        viewerSelectionEpoch = max(viewerSelectionEpoch, max(predecessor.selection.epoch, successor.selection.epoch))
        return recovery.successorFollowAllowed && predecessor.rematch?.selectedElsewhere == false
            && successor.selection.isSelected && successor.selection.epoch >= viewerSelectionEpoch
    }

    private func rememberSuccessorConfirmation(_ successor: LiveMatchSnapshot) {
        if let current = resumeConfirmationTarget, current.match.id == successor.match.id,
           current.selection.epoch > successor.selection.epoch { return }
        resumeConfirmationTarget = successor
    }

    /// The three server revisions advance independently; a delayed gameplay
    /// projection must still deliver newer consent or viewer selection state.
    private func acceptSnapshot(_ received: LiveMatchSnapshot) {
        let old = acceptedSnapshot?.match.id == received.match.id ? acceptedSnapshot : nil
        if snapshot == nil, let old, received.revision < old.revision,
           (received.rematch?.revision ?? 0) <= (old.rematch?.revision ?? 0),
           received.selection.epoch <= old.selection.epoch {
            scheduleRetry(recoverPending: false)
            return
        }
        let merged = mergeSnapshot(received)
        if acceptedRevision?.matchID != merged.match.id || acceptedRevision?.roundNumber != merged.round.number {
            guessDraft = ""
            selectedRevealNumber = nil
        }
        viewerSelectionEpoch = max(viewerSelectionEpoch, merged.selection.epoch)
        snapshot = merged
        acceptedSnapshot = merged
        acceptedRevision = (merged.match.id, merged.revision, merged.round.number)
        snapshotUptime = uptime()
        if merged.rematch?.state != .accepted || merged.rematch?.successorAvailable != true
            || merged.rematch?.successorMatchID != resumeConfirmationTarget?.match.id {
            resumeConfirmationTarget = nil
        }
        if let target = pendingStart, merged.match.currentRound >= target.roundNumber,
           merged.round.state != .pending { pendingStart = nil }
        phase = hasPendingDecision ? .unavailable : .ready
        if !hasPendingDecision { lastError = nil }
        failureCount = 0
        scheduleNextRefresh()
    }

    private func mergeSnapshot(_ received: LiveMatchSnapshot) -> LiveMatchSnapshot {
        let old = acceptedSnapshot?.match.id == received.match.id ? acceptedSnapshot : nil
        var merged = old.map { received.revision < $0.revision ? $0 : received } ?? received
        merged.serverTime = max(received.serverTime, old?.serverTime ?? received.serverTime)
        merged.selection = old.map { received.selection.epoch < $0.selection.epoch ? $0.selection : received.selection }
            ?? received.selection
        if let prior = old?.rematch, (received.rematch?.revision ?? 0) < prior.revision {
            merged.rematch = prior
        } else { merged.rematch = received.rematch }
        if let nextViewerFlag = received.rematch?.selectedElsewhere,
           received.selection.epoch >= (old?.selection.epoch ?? 0) {
            merged.rematch?.selectedElsewhere = nextViewerFlag
        } else if let priorViewerFlag = old?.rematch?.selectedElsewhere {
            merged.rematch?.selectedElsewhere = priorViewerFlag
        }
        return merged
    }

    private func request<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let requestGeneration = generation
        let boundRefresh = refreshAuth
        do {
            return try await timed(operation)
        } catch LiveMatchServiceError.server(.notAuthenticated) {
            guard let accountID,
                  try await timed({ await boundRefresh(accountID) }),
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

    private func handlePendingError(_ error: Error, intent: LivePendingIntent, presentation: Int) {
        guard phase != .storageUnavailable else { return }
        let mapped = map(error)
        let isCurrentRound: Bool
        if case .guess(_, _, _, let round, _) = intent {
            isCurrentRound = snapshot == nil || snapshot?.round.number == round
        } else { isCurrentRound = true }
        let canPresent = presentation == presentationGeneration && isOpen && isCurrentRound
        if canPresent { lastError = mapped }
        if case .join = intent { lastError = mapped }
        switch mapped {
        case .server(.clientUpdateRequired):
            serviceNeedsUpdate = true
            phase = .unavailable
            stopRecoveryLoop()
        case .unavailable, .invalidResponse, .server(.internalError):
            phase = .unavailable
            scheduleRetry(recoverPending: true)
        case .server(.rateLimited), .server(.requestConflict):
            // This decision belongs to the original durable intent, even after round advance.
            lastError = mapped
            phase = .unavailable
        case .server(.notAuthenticated):
            phase = .needsSignIn
        default:
            if canPresent, case .guess(_, _, let word, _, _) = intent { guessDraft = word }
            let previous = recovery
            recovery.pendingIntent = nil
            guard saveRecovery() else {
                recovery = previous
                return
            }
            phase = .unavailable
            if recovery.matchID != nil { requestRefresh() }
        }
        if !isOpen { phase = .inactive }
    }

    private func handleCommandError(_ error: Error, uncertainIntent: Bool) {
        guard phase != .storageUnavailable else { return }
        let mapped = map(error)
        lastError = mapped
        if mapped == .server(.clientUpdateRequired) {
            serviceNeedsUpdate = true
            phase = .unavailable
            stopRecoveryLoop()
        } else if mapped == .server(.notAuthenticated) {
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
        let preservesPendingDecision = hasPendingDecision
        if !preservesPendingDecision { lastError = mapped }
        switch mapped {
        case .server(.notAMatchMember), .server(.roomExpired):
            clearSavedMatch()
        case .server(.notAuthenticated):
            phase = .needsSignIn
            stopRecoveryLoop()
        case .server(.clientUpdateRequired), .invalidResponse:
            serviceNeedsUpdate = mapped == .server(.clientUpdateRequired)
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
        let roundDeadline: Date? = switch snapshot.round.state {
        case .pending: snapshot.match.expiresAt
        case .countdown: snapshot.round.startsAt
        case .playing: snapshot.round.endsAt
        case .revealed: nil
        }
        let deadline = snapshot.rematch.flatMap {
            [.eligible, .offered, .closed].contains($0.state) ? $0.deadline : nil
        } ?? roundDeadline
        if let deadline {
            let seconds = max(0, deadline.timeIntervalSince(displayedServerTime))
            delay = min(delay, .seconds(seconds))
        }
        scheduleTimer(delay: delay, recoverPending: recovery.pendingIntent != nil && !hasPendingDecision)
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
        let presentation = presentationGeneration
        recoveryTimer = Task { [weak self] in
            guard let self else { return }
            do { try await sleep(delay) } catch { return }
            guard isCurrent(accountGeneration), presentation == presentationGeneration, shouldRecover else { return }
            if recoverPending, recovery.pendingIntent != nil, !hasPendingDecision, !isCommandInFlight {
                startCommand { [weak self] in await self?.recoverPendingIntent() }
            } else {
                requestRefresh()
            }
        }
    }

    private var shouldRecover: Bool {
        guard isForeground, isOpen, accountID != nil, phase != .storageUnavailable, !serviceNeedsUpdate,
              isRecoverySelected || recovery.pendingIntent != nil else { return false }
        guard let snapshot else { return true }
        if recovery.pendingIntent != nil { return true }
        if snapshot.match.status == .completed {
            guard let rematch = snapshot.rematch else { return false }
            return rematch.state == .offered || rematch.state == .eligible || rematch.state == .closed
                || (rematch.state == .accepted && rematch.successorAvailable)
        }
        if snapshot.match.status == .incomplete { return false }
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

    private func saveResolvedMatch(_ matchID: UUID, completedInvitationGeneration invitation: UUID? = nil) throws {
        let previous = recovery
        recovery.matchID = matchID
        recovery.pendingIntent = nil
        if let invitation { recovery.completedInvitationGeneration = invitation }
        guard saveRecovery() else {
            recovery = previous
            throw LiveMatchRecoveryError.unavailable
        }
        completedInvitationGeneration = recovery.completedInvitationGeneration
    }

    /// The caller captures the completion's account before navigation/journal awaits.
    /// True means the matching marker was durably removed, or this generation is
    /// already absent/replaced. False requires retrying the existing storage/account
    /// recovery first; a failed save never publishes an acknowledgment.
    @discardableResult
    func acknowledgeInvitationClear(matchingGeneration invitation: UUID, forAccount expectedAccountID: UUID) -> Bool {
        guard accountID == expectedAccountID, store != nil, !hasRequestedAccountChange,
              phase != .storageUnavailable else { return false }
        guard recovery.completedInvitationGeneration == invitation else { return true }
        let previous = recovery
        recovery.completedInvitationGeneration = nil
        guard saveRecovery() else {
            recovery = previous
            return false
        }
        completedInvitationGeneration = nil
        return true
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
        var retained = recovery
        retained.matchID = nil
        retained.pendingIntent = nil
        do {
            if retained.completedInvitationGeneration != nil { try store?.save(retained) }
            else { try store?.clear() }
        } catch {
            phase = .storageUnavailable
            stopRecoveryLoop()
            return
        }
        recovery = retained
        acceptedRevision = nil
        acceptedSnapshot = nil
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
            completedInvitationGeneration = recovery.completedInvitationGeneration
            switch recovery.pendingIntent {
            case .join(_, _, let navigation, _), .rematch(_, _, let navigation): navigationGeneration = navigation
            default: break
            }
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
        phaseBeforeCapturedCleanup = nil
        generation += 1
        presentationGeneration += 1
        pendingStart = nil
        selectedRevealNumber = nil
        commandEpoch += 1
        isExplicitServiceRetry = false
        cancelTasks()
        store = nil
        recovery = LiveRecoveryState()
        snapshot = nil
        snapshotUptime = nil
        guessDraft = ""
        acceptedRevision = nil
        acceptedSnapshot = nil
        viewerSelectionEpoch = 0
        completedInvitationGeneration = nil
        serviceNeedsUpdate = false
        resumeConfirmationTarget = nil
        navigationGeneration = UUID()
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
