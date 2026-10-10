import Foundation
import Observation

@MainActor
@Observable
final class DailyAccountCoordinator {
    private let now: @MainActor () -> Date
    private let dailyPack: DailyWordPack
    private let guestStore: DailyClassicStore
    private let guestDaily: DailyClassicModel
    private enum StartupState: Equatable { case notStarted, restoring, settled, retryable }
    private var startupState = StartupState.notStarted
    private let accountModelService: (any AccountServicing)?
    private let dailyRemoteFactory: ((UUID) throws -> any DailySyncRemote)?
    private let liveTransportFactory: ((UUID) throws -> LiveAccountTransport)?
    private let accountStoreFactory: (UUID) throws -> AccountDailyClassicStore
    private var accountStore: AccountDailyClassicStore?
    private var syncEngine: DailySyncEngine?
    private var syncLifecycle: DailySyncLifecycle?
    private var currentUserID: UUID?
    private var activationUserID: UUID?
    private var syncTask: Task<Void, Never>?
    private struct PendingGuestImport {
        let userID: UUID
        let engine: DailySyncEngine
    }
    private var pendingGuestImport: PendingGuestImport?

    private(set) var daily: DailyClassicModel
    let tutorial: TutorialModel
    let live: LiveMatchSession
    private(set) var syncStatus = DailySyncStatus.idle
    private(set) var conflicts: [DailySyncConflict] = []
    private var choices: [DailySyncChoice] = []
    var firstConflictID: UUID? { choices.first?.id }
    private(set) var canImportGuestHistory = false
    private(set) var isDailyPlayable = true

    @ObservationIgnored
    lazy var account = AccountModel(
        service: accountModelService,
        didChangeSession: { [weak self] userID in self?.sessionChanged(to: userID) },
        didFinishRestoration: { [weak self] outcome in self?.restorationFinished(outcome) },
        didCompleteSignedOutIntent: { [weak self] in self?.signedOutIntentCompleted() },
        didSignOut: { [weak self] _ in self?.activateGuest() == .completed },
        didDeleteAccount: { [weak self] userID in
            guard let self else { throw AccountLocalDeletionFailure(dailyCacheUserID: userID, liveRecoveryPending: false) }
            try self.deleteLocalAccount(userID)
        },
        retryDeletedDailyCleanup: { [weak self] userID in
            guard let self else { throw AccountLocalDeletionFailure(dailyCacheUserID: userID, liveRecoveryPending: false) }
            try self.removeDeletedDailyCache(userID)
        },
        hasPendingDeletedLiveCleanup: { [weak self] userID in
            self?.live.hasPendingAccountCleanup(for: userID) ?? true
        }
    )

    init(
        dailyPack: DailyWordPack,
        tutorialPack: WordPack,
        guestStore: DailyClassicStore,
        accountService: SupabaseAccountService? = SupabaseAccountService.configured(),
        accountModelService: (any AccountServicing)? = nil,
        dailyRemoteFactory: ((UUID) -> any DailySyncRemote)? = nil,
        accountStoreFactory: @escaping (UUID) throws -> AccountDailyClassicStore = {
            try AccountDailyClassicStore.applicationSupport(userID: $0)
        },
        liveTransportFactory: ((UUID) throws -> LiveAccountTransport)? = nil,
        liveStoreFactory: @escaping LiveMatchSession.StoreFactory = {
            try LiveMatchRecoveryStore.applicationSupport(userID: $0)
        },
        now: @escaping @MainActor () -> Date = { Date() }
    ) throws {
        self.now = now
        self.liveTransportFactory = liveTransportFactory ?? accountService.map { service in
            { userID in try service.makeLiveTransport(userID: userID) }
        }
        self.dailyPack = dailyPack
        self.guestStore = guestStore
        self.dailyRemoteFactory = dailyRemoteFactory ?? accountService.map { service in
            { userID in try service.makeDailySyncRemote(userID: userID) }
        }
        self.accountModelService = accountModelService ?? accountService
        self.accountStoreFactory = accountStoreFactory
        live = LiveMatchSession(service: nil, realtime: nil, storeFactory: liveStoreFactory)
        let guestDaily = try DailyClassicModel(
            pack: dailyPack, store: guestStore,
            persistenceStartup: self.accountModelService == nil ? .active : .prepared,
            now: now)
        self.guestDaily = guestDaily
        daily = guestDaily
        tutorial = TutorialModel(acceptedWords: Set(tutorialPack.words))
        configureDailyCallback()
    }

    isolated deinit {
        syncLifecycle?.invalidate()
        syncTask?.cancel()
    }

    func start() async {
        switch startupState {
        case .restoring, .settled: return
        case .notStarted:
            startupState = .restoring
            await account.start()
        case .retryable:
            startupState = .restoring
            await account.restoreSession()
        }
    }

    private func restorationFinished(_ outcome: AccountModel.RestorationOutcome) {
        switch outcome {
        case .cancelled, .superseded:
            if startupState == .restoring {
                startupState = account.session != nil || currentUserID != nil || activationUserID != nil
                    ? .settled : .retryable
            }
        case .alreadyStarted:
            break
        case .settled(let userID):
            startupState = .settled
            if userID == nil { activateGuestFallback() }
        case .failed, .notConfigured:
            startupState = .settled
            activateGuestFallback()
        }
    }

    private func signedOutIntentCompleted() {
        guard account.session == nil,
              currentUserID == nil, activationUserID == nil, daily === guestDaily else { return }
        startupState = .settled
        // The completed Auth intent owns fallback; an obsolete restore does not.
        // Existing stream/captured-user callbacks retain Live cleanup ownership.
        if !guestDaily.isPersistenceActive {
            guestDaily.activatePersistence()
            guestDaily.refreshForCurrentDay()
        }
    }

    private func activateGuestFallback() {
        guard !Task.isCancelled, account.session == nil,
              currentUserID == nil, activationUserID == nil else { return }
        activateGuest()
    }

    func sessionChanged(to userID: UUID?) {
        guard let userID else {
            if currentUserID != nil || activationUserID != nil {
                activateGuest()
            } else {
                // Daily may already be guest while live recovery cleanup is pending.
                changeLiveAccount(to: nil)
            }
            return
        }
        changeLiveAccount(to: userID)
        guard userID != currentUserID || activationUserID != nil else { return }
        activateAccount(userID)
    }

    @discardableResult
    private func changeLiveAccount(to userID: UUID?) -> LiveAccountChangeOutcome {
        guard let liveTransportFactory else { return live.changeAccount(to: userID) }
        let binding = userID.flatMap { try? liveTransportFactory($0) }
        return live.changeAccount(to: userID, transport: binding)
    }

    private func activateAccount(_ userID: UUID) {
        guard let dailyRemoteFactory else { return }
        syncLifecycle?.invalidate()
        syncTask?.cancel()
        pendingGuestImport = nil
        syncStatus = .pending
        isDailyPlayable = false

        if activationUserID != userID {
            let isolatedDate = Date(
                timeIntervalSince1970: TimeInterval(guestDaily.puzzle.day * 86_400 + 1)
            )
            guard let isolated = try? DailyClassicModel(
                pack: dailyPack,
                store: IsolatedDailyClassicStore(),
                now: { isolatedDate }
            ) else {
                syncStatus = .failed(.invalidData)
                return
            }
            daily = isolated
            configureDailyCallback()
        }
        activationUserID = userID
        currentUserID = nil
        syncEngine = nil
        syncLifecycle = nil
        accountStore = nil
        conflicts = []
        choices = []
        canImportGuestHistory = false

        do {
            let store = try accountStoreFactory(userID)
            let lifecycle = DailySyncLifecycle()
            let engine = DailySyncEngine(
                userID: userID,
                store: store,
                remote: try dailyRemoteFactory(userID),
                lifecycle: lifecycle
            )
            let accountDaily = try DailyClassicModel(pack: dailyPack, store: store, now: now)
            let metadata = try store.loadSyncMetadata()
            accountStore = store
            syncEngine = engine
            syncLifecycle = lifecycle
            currentUserID = userID
            activationUserID = nil
            isDailyPlayable = true
            daily = accountDaily
            configureDailyCallback()
            canImportGuestHistory = metadata.guestImportDecision == nil && hasGuestDailyData()
            schedule { await self.synchronize(using: engine, userID: userID) }
        } catch {
            syncStatus = .failed(.invalidData)
        }
    }

    func foregrounded() {
        live.foregrounded()
        if isDailyPlayable { daily.refreshForCurrentDay() }
        guard account.session != nil else { return }
        schedule {
            await self.account.refreshSession()
            await self.synchronizeCurrent()
        }
    }

    func backgrounded() {
        live.backgrounded()
    }

    func retrySync() {
        if let userID = activationUserID ?? account.session?.userID,
           currentUserID != userID {
            activateAccount(userID)
            return
        }
        schedule { await self.synchronizeCurrent() }
    }

    func importGuestHistory() {
        guard let engine = syncEngine, let userID = currentUserID else { return }
        schedule {
            do {
                self.pendingGuestImport = nil
                guard self.daily.flushAcceptedState() else {
                    self.syncStatus = .failed(.unavailable)
                    return
                }
                let staged = try engine.stageGuestImport(from: self.guestStore)
                try self.daily.reloadReconciledState()
                self.pendingGuestImport = PendingGuestImport(userID: userID, engine: engine)
                self.syncStatus = staged
                if case .conflict(let found) = staged {
                    try self.present(found, using: engine, isGuestImport: true)
                    return
                }
                await self.synchronize(using: engine, userID: userID)
            } catch is CancellationError {
            } catch {
                // Staging can save history/progress before metadata fails.
                // Adopt only durable writes; dirty accepted play still owns retry.
                self.reloadAccountDaily()
                self.syncStatus = .failed(.invalidData)
            }
        }
    }

    func skipGuestHistory() {
        guard let accountStore, var metadata = try? accountStore.loadSyncMetadata() else { return }
        metadata.guestImportDecision = .skipped
        do { try accountStore.save(metadata) } catch {
            syncStatus = .failed(.invalidData)
            return
        }
        pendingGuestImport = nil
        canImportGuestHistory = false
    }

    func resolveConflict(id: UUID, useCloud: Bool) {
        guard let preview = choices.first, preview.id == id,
              let engine = syncEngine, let userID = currentUserID else { return }
        schedule {
            guard self.currentUserID == userID, self.syncEngine === engine,
                  self.firstConflictID == id else { return }
            do {
                guard self.daily.flushAcceptedState() else {
                    self.syncStatus = .failed(.unavailable)
                    return
                }
                let outcome = try engine.resolve(preview, with: useCloud ? .useCloud : .keepDevice)
                switch outcome {
                case .applied, .noLongerApplicable:
                    self.choices.removeFirst()
                case .refreshed(let updated):
                    self.choices[0] = updated
                }
                self.conflicts = self.choices.map(\.conflict)
                self.reloadAccountDaily()
                if self.conflicts.isEmpty {
                    await self.synchronize(using: engine, userID: userID)
                } else {
                    self.syncStatus = .conflict(self.conflicts)
                }
            } catch {
                self.syncStatus = .failed(.invalidData)
                self.reloadAccountDaily()
            }
        }
    }

    private func present(_ conflicts: [DailySyncConflict], using engine: DailySyncEngine,
                         isGuestImport: Bool = false) throws {
        choices = try conflicts.map { try engine.choice(for: $0, isGuestImport: isGuestImport) }
        self.conflicts = conflicts
    }

    var syncMessage: String? {
        guard account.isSignedIn else { return nil }
        if !isDailyPlayable {
            return "Couldn't sync · Account storage needs attention."
        }
        return switch syncStatus {
        case .idle: "Ready to sync"
        case .pending: "Pending"
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named)))."
        case .conflict: "Couldn't sync · Choose an attempt."
        case .failed(.invalidData): "Couldn't sync · Your game is unchanged."
        case .failed: "Couldn't sync"
        }
    }

    var showsRetry: Bool {
        switch syncStatus {
        case .pending, .failed: true
        default: false
        }
    }

    private func dailyAcceptedStateChanged() {
        guard let engine = syncEngine, let userID = currentUserID else { return }
        schedule {
            do {
                if let result = self.daily.game.completedResult {
                    try engine.markResultPending(result.puzzleID)
                } else {
                    try engine.markProgressPending()
                }
                self.syncStatus = .pending
                await self.synchronize(using: engine, userID: userID)
            } catch is CancellationError {
            } catch {
                self.syncStatus = .failed(.unavailable)
            }
        }
    }

    private func synchronizeCurrent() async {
        guard let engine = syncEngine, let userID = currentUserID else { return }
        await synchronize(using: engine, userID: userID)
    }

    private func synchronize(using engine: DailySyncEngine, userID: UUID) async {
        // An import conflict needs an explicit choice; a generic retry cannot
        // turn successful synchronization of the account attempt into consent.
        if let pendingGuestImport, pendingGuestImport.userID == userID,
           pendingGuestImport.engine === engine, !conflicts.isEmpty {
            syncStatus = .conflict(conflicts)
            return
        }
        if !daily.flushAcceptedState() {
            let owner = daily
            let result = try? await engine.authoritativeCompletion(for: owner.game.progress)
            guard currentUserID == userID, syncEngine === engine,
                  daily === owner, !Task.isCancelled else { return }
            if let result { try? owner.adoptAuthoritativeCompletion(result) }
            guard owner.flushAcceptedState() else {
                syncStatus = .failed(.unavailable)
                return
            }
        }
        let status = (try? await engine.synchronize()) ?? .failed(.unavailable)
        guard currentUserID == userID, syncEngine === engine, !Task.isCancelled else { return }
        syncStatus = status
        if case .conflict(let found) = status {
            do { try present(found, using: engine) } catch { syncStatus = .failed(.invalidData) }
        } else {
            conflicts = []
            choices = []
        }
        if case .synced = status, let pendingGuestImport,
           pendingGuestImport.userID == userID, pendingGuestImport.engine === engine,
           let accountStore {
            do {
                var metadata = try accountStore.loadSyncMetadata()
                metadata.guestImportDecision = .imported
                try accountStore.save(metadata)
                self.pendingGuestImport = nil
                canImportGuestHistory = false
            } catch {
                syncStatus = .failed(.invalidData)
            }
        }
        reloadAccountDaily()
    }

    private func reloadAccountDaily() {
        do { try daily.reloadReconciledState() }
        catch { syncStatus = .failed(.invalidData) }
    }

    private func configureDailyCallback() {
        daily.acceptedStateChanged = { [weak self] in self?.dailyAcceptedStateChanged() }
    }

    @discardableResult
    private func activateGuest() -> LiveAccountChangeOutcome {
        let liveOutcome = changeLiveAccount(to: nil)
        syncLifecycle?.invalidate()
        syncTask?.cancel()
        currentUserID = nil
        activationUserID = nil
        syncEngine = nil
        syncLifecycle = nil
        accountStore = nil
        conflicts = []
        choices = []
        syncStatus = .idle
        canImportGuestHistory = false
        pendingGuestImport = nil
        isDailyPlayable = true
        daily = guestDaily
        daily.activatePersistence()
        daily.refreshForCurrentDay()
        configureDailyCallback()
        return liveOutcome
    }

    private func deleteLocalAccount(_ userID: UUID) throws {
        let liveOutcome = activateGuest()
        var dailyFailed = false
        do { try removeDeletedDailyCache(userID) } catch { dailyFailed = true }
        if dailyFailed || liveOutcome == .recoveryCleanupPending {
            throw AccountLocalDeletionFailure(dailyCacheUserID: dailyFailed ? userID : nil,
                                               liveRecoveryPending: liveOutcome == .recoveryCleanupPending)
        }
    }

    private func removeDeletedDailyCache(_ userID: UUID) throws {
        try accountStoreFactory(userID).deleteAccountCache()
    }

    private func hasGuestDailyData() -> Bool {
        let hasResults = ((try? guestStore.loadHistory().completedResults.isEmpty) == false)
        let hasRows = ((try? guestStore.loadProgress()?.acceptedGuesses.isEmpty) == false)
        return hasResults || hasRows
    }

    private func schedule(_ operation: @escaping @MainActor () async -> Void) {
        syncTask?.cancel()
        syncTask = Task {
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}

private struct IsolatedDailyClassicStore: DailyClassicStoring, Sendable {
    func loadProgress() throws -> DailyClassicProgress? { nil }
    func save(_ progress: DailyClassicProgress) throws { throw StorageUnavailable() }
    func discardProgress() throws { throw StorageUnavailable() }
    func loadHistory() throws -> DailyClassicHistory { DailyClassicHistory() }
    func save(_ history: DailyClassicHistory) throws { throw StorageUnavailable() }

    private struct StorageUnavailable: Error {}
}
