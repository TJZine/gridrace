import Foundation
import Observation

@MainActor
@Observable
final class DailyAccountCoordinator {
    private let dailyPack: DailyWordPack
    private let guestStore: DailyClassicStore
    private let guestDaily: DailyClassicModel
    private let accountService: SupabaseAccountService?
    private let accountStoreFactory: (UUID) throws -> AccountDailyClassicStore
    private var accountStore: AccountDailyClassicStore?
    private var syncEngine: DailySyncEngine?
    private var currentUserID: UUID?
    private var activationUserID: UUID?
    private var syncTask: Task<Void, Never>?
    private var guestImportInFlight = false

    private(set) var daily: DailyClassicModel
    let tutorial: TutorialModel
    private(set) var syncStatus = DailySyncStatus.idle
    private(set) var conflicts: [DailySyncConflict] = []
    private(set) var canImportGuestHistory = false

    @ObservationIgnored
    lazy var account = AccountModel(
        service: accountService,
        didChangeSession: { [weak self] userID in self?.sessionChanged(to: userID) },
        didSignOut: { [weak self] _ in self?.activateGuest() },
        didDeleteAccount: { [weak self] userID in try self?.deleteLocalAccount(userID) }
    )

    init(
        dailyPack: DailyWordPack,
        tutorialPack: WordPack,
        guestStore: DailyClassicStore,
        accountService: SupabaseAccountService? = SupabaseAccountService.configured(),
        accountStoreFactory: @escaping (UUID) throws -> AccountDailyClassicStore = {
            try AccountDailyClassicStore.applicationSupport(userID: $0)
        }
    ) throws {
        self.dailyPack = dailyPack
        self.guestStore = guestStore
        self.accountService = accountService
        self.accountStoreFactory = accountStoreFactory
        let guestDaily = try DailyClassicModel(pack: dailyPack, store: guestStore)
        self.guestDaily = guestDaily
        daily = guestDaily
        tutorial = TutorialModel(acceptedWords: Set(tutorialPack.words))
        configureDailyCallback()
    }

    isolated deinit {
        syncTask?.cancel()
    }

    func start() async {
        await account.start()
    }

    func sessionChanged(to userID: UUID?) {
        guard userID != currentUserID else { return }
        syncTask?.cancel()
        guard let userID else {
            activateGuest()
            return
        }
        activateAccount(userID)
    }

    private func activateAccount(_ userID: UUID) {
        guard let accountService else { return }
        syncTask?.cancel()

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
        accountStore = nil
        conflicts = []
        canImportGuestHistory = false

        do {
            let store = try accountStoreFactory(userID)
            let engine = DailySyncEngine(
                userID: userID,
                store: store,
                remote: accountService.makeDailySyncRemote()
            )
            let accountDaily = try DailyClassicModel(pack: dailyPack, store: store)
            let metadata = try store.loadSyncMetadata()
            accountStore = store
            syncEngine = engine
            currentUserID = userID
            activationUserID = nil
            daily = accountDaily
            configureDailyCallback()
            canImportGuestHistory = metadata.guestImportDecision == nil && hasGuestDailyData()
            schedule { await self.synchronize(using: engine, userID: userID) }
        } catch {
            syncStatus = .failed(.invalidData)
        }
    }

    func foregrounded() {
        daily.refreshForCurrentDay()
        guard account.session != nil else { return }
        schedule {
            await self.account.refreshSession()
            await self.synchronizeCurrent()
        }
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
                self.guestImportInFlight = true
                let staged = try await engine.stageGuestImport(from: self.guestStore)
                self.syncStatus = staged
                if case .conflict(let found) = staged {
                    self.conflicts = found
                    return
                }
                await self.synchronize(using: engine, userID: userID)
            } catch is CancellationError {
            } catch {
                self.syncStatus = .failed(.invalidData)
            }
        }
    }

    func skipGuestHistory() {
        guard var metadata = try? accountStore?.loadSyncMetadata() else { return }
        metadata.guestImportDecision = .skipped
        try? accountStore?.save(metadata)
        guestImportInFlight = false
        canImportGuestHistory = false
    }

    func resolveFirstConflict(useCloud: Bool) {
        guard let conflict = conflicts.first,
              let engine = syncEngine,
              let userID = currentUserID else { return }
        schedule {
            do {
                try await engine.resolve(conflict, with: useCloud ? .useCloud : .keepDevice)
                self.conflicts.removeFirst()
                if self.conflicts.isEmpty {
                    await self.synchronize(using: engine, userID: userID)
                } else {
                    self.syncStatus = .conflict(self.conflicts)
                    self.reloadAccountDaily()
                }
            } catch {
                self.syncStatus = .failed(.invalidData)
            }
        }
    }

    var syncMessage: String? {
        guard account.isSignedIn else { return nil }
        return switch syncStatus {
        case .idle: "Ready to sync."
        case .pending: "Your progress is waiting to sync. You can keep playing."
        case .synced(let date): "Synced \(date.formatted(.relative(presentation: .named)))."
        case .conflict: "Two devices have different attempts. Choose which one to keep on this device."
        case .failed(.invalidData): "Some saved data could not be synchronized. Your local game is unchanged."
        case .failed: "Sync is unavailable. Your game is saved on this device; try again when you're online."
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
                    try await engine.markResultPending(result.puzzleID)
                } else {
                    try await engine.markProgressPending()
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
        let status = (try? await engine.synchronize()) ?? .failed(.unavailable)
        guard currentUserID == userID, !Task.isCancelled else { return }
        syncStatus = status
        if case .conflict(let found) = status { conflicts = found } else { conflicts = [] }
        if case .synced = status, guestImportInFlight,
           var metadata = try? accountStore?.loadSyncMetadata() {
            metadata.guestImportDecision = .imported
            try? accountStore?.save(metadata)
            guestImportInFlight = false
            canImportGuestHistory = false
        }
        reloadAccountDaily()
    }

    private func reloadAccountDaily() {
        guard let store = accountStore,
              let reloaded = try? DailyClassicModel(pack: dailyPack, store: store)
        else { return }
        daily = reloaded
        configureDailyCallback()
    }

    private func configureDailyCallback() {
        daily.acceptedStateChanged = { [weak self] in self?.dailyAcceptedStateChanged() }
    }

    private func activateGuest() {
        syncTask?.cancel()
        currentUserID = nil
        activationUserID = nil
        syncEngine = nil
        accountStore = nil
        conflicts = []
        syncStatus = .idle
        canImportGuestHistory = false
        guestImportInFlight = false
        daily = guestDaily
        configureDailyCallback()
    }

    private func deleteLocalAccount(_ userID: UUID) throws {
        syncTask?.cancel()
        let store = try accountStoreFactory(userID)
        try store.deleteAccountCache()
        if currentUserID == userID { activateGuest() }
    }

    private func hasGuestDailyData() -> Bool {
        let hasResults = ((try? guestStore.loadHistory().completedResults.isEmpty) == false)
        let hasRows = ((try? guestStore.loadProgress()?.acceptedGuesses.isEmpty) == false)
        return hasResults || hasRows
    }

    private func schedule(_ operation: @escaping @MainActor () async -> Void) {
        syncTask?.cancel()
        syncTask = Task { await operation() }
    }
}

private struct IsolatedDailyClassicStore: DailyClassicStoring, Sendable {
    func loadProgress() throws -> DailyClassicProgress? { nil }
    func save(_ progress: DailyClassicProgress) throws {}
    func discardProgress() throws {}
    func loadHistory() throws -> DailyClassicHistory { DailyClassicHistory() }
    func save(_ history: DailyClassicHistory) throws {}
}
