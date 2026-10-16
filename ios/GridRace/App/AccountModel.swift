import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AccountModel {
    enum RestorationOutcome: Equatable, Sendable {
        case settled(UUID?)
        case failed
        case cancelled
        case superseded
        case alreadyStarted
        case notConfigured
    }

    private let didFinishRestoration: @MainActor (RestorationOutcome) -> Void
    private let didCompleteSignedOutIntent: @MainActor () -> Void
    private let service: (any AccountServicing)?
    private let cleanupJournal: AccountCleanupJournal?
    private let didChangeSession: @MainActor (UUID?) -> Void
    private let willDepartAccount: @MainActor (UUID?) throws -> Void
    private let didSignOut: @MainActor (UUID) async -> Bool
    private let didDeleteAccount: @MainActor (UUID) async throws -> Void
    private let retryDeletedDailyCleanup: (@MainActor (UUID) async throws -> Void)?
    private var confirmedDeletions: [UUID: ConfirmedAccountDeletion] = [:]
    private var deletingUserID: UUID?
    private var memoryPendingDaily: Set<UUID> = []
    var pendingDeletedDailyUserIDs: Set<UUID> { memoryPendingDaily.union(cleanupJournal?.dailyUsers ?? []) }
    var canRetryDeletedDailyData: Bool { !pendingDeletedDailyUserIDs.isEmpty && retryDeletedDailyCleanup != nil }
    private var deletedLiveUserIDs: Set<UUID> = []
    private let hasPendingDeletedLiveCleanup: (@MainActor (UUID) -> Bool)?
    private var authObservation: Task<Void, Never>?
    private var started = false
    private var profileTask: Task<Void, Never>?
    private var restorationGeneration = 0
    private var restorationSessionGeneration: Int?
    private var sessionGeneration = 0
    private var profileGeneration = 0

    private(set) var authRecovery: AccountAuthRecovery?
    private(set) var session: AccountSession?
    private(set) var profile: PlayerProfile?
    private(set) var isRestoring = false
    private(set) var isWorking = false
    private(set) var isLoadingProfile = false
    private var storedErrorMessage: String?
    private enum SignOutGuidance {
        case credentials
        case live(UUID)
    }
    private var signOutGuidance: SignOutGuidance?
    private var showsDeletionRecovery = false
    private var unknownDeletionCleanupFailure = false
    private(set) var errorMessage: String? {
        get {
            if showsDeletionRecovery { return deletionRecoveryMessage }
            switch signOutGuidance {
            case .credentials where authRecovery == nil: return nil
            case .live(let userID) where hasPendingDeletedLiveCleanup?(userID) == false: return nil
            default: return storedErrorMessage
            }
        }
        set {
            showsDeletionRecovery = false
            signOutGuidance = nil
            storedErrorMessage = newValue
        }
    }
    private(set) var errorEvent = 0
    var displayNameDraft = ""
    var avatarSeedDraft = UUID().uuidString.lowercased()

    var isConfigured: Bool { service != nil }
    var isSignedIn: Bool { session != nil }
    var allowsAccountSignIn: Bool {
        authRecovery == nil || authRecovery?.action == .deletionReauthentication || authRecovery?.action == .deletion
    }
    var needsProfileSetup: Bool { profile?.needsSetup == true }

    init(
        service: (any AccountServicing)?,
        didChangeSession: @escaping @MainActor (UUID?) -> Void = { _ in },
        didFinishRestoration: @escaping @MainActor (RestorationOutcome) -> Void = { _ in },
        didCompleteSignedOutIntent: @escaping @MainActor () -> Void = {},
        willDepartAccount: @escaping @MainActor (UUID?) throws -> Void = { _ in },
        didSignOut: @escaping @MainActor (UUID) async -> Bool = { _ in true },
        didDeleteAccount: @escaping @MainActor (UUID) async throws -> Void = { _ in },
        retryDeletedDailyCleanup: (@MainActor (UUID) async throws -> Void)? = nil,
        hasPendingDeletedLiveCleanup: (@MainActor (UUID) -> Bool)? = nil,
        cleanupJournal: AccountCleanupJournal? = nil
    ) {
        self.service = service
        self.cleanupJournal = cleanupJournal
        memoryPendingDaily = cleanupJournal?.dailyUsers ?? []
        deletedLiveUserIDs = cleanupJournal?.liveUsers ?? []
        self.didChangeSession = didChangeSession
        self.didFinishRestoration = didFinishRestoration
        self.didCompleteSignedOutIntent = didCompleteSignedOutIntent
        self.willDepartAccount = willDepartAccount
        self.didSignOut = didSignOut
        self.didDeleteAccount = didDeleteAccount
        self.retryDeletedDailyCleanup = retryDeletedDailyCleanup
        self.hasPendingDeletedLiveCleanup = hasPendingDeletedLiveCleanup
    }

    isolated deinit {
        authObservation?.cancel()
        profileTask?.cancel()
    }

    @discardableResult
    func start() async -> RestorationOutcome {
        guard !started else { return .alreadyStarted }
        guard let service else {
            didFinishRestoration(.notConfigured)
            return .notConfigured
        }
        started = true
        let changes = service.authStateChanges
        let initialGeneration = sessionGeneration
        await withCheckedContinuation { (initialized: CheckedContinuation<Void, Never>) in
            authObservation = Task { [weak self] in
                var iterator = changes.makeAsyncIterator()
                if let initial = await iterator.next(isolation: MainActor.shared),
                   !Task.isCancelled, self?.sessionGeneration == initialGeneration {
                    self?.receiveAuthState(initial)
                }
                initialized.resume()
                while let state = await iterator.next(isolation: MainActor.shared) {
                    guard !Task.isCancelled else { return }
                    self?.receiveAuthState(state)
                }
            }
        }
        return await restoreSession()
    }

    @discardableResult
    func restoreSession() async -> RestorationOutcome {
        guard let service else {
            didFinishRestoration(.notConfigured)
            return .notConfigured
        }
        restorationGeneration += 1
        let restoration = restorationGeneration
        restorationSessionGeneration = sessionGeneration
        isRestoring = true
        errorMessage = nil
        defer {
            if restorationGeneration == restoration {
                isRestoring = false
                restorationSessionGeneration = nil
            }
        }
        let outcome: RestorationOutcome
        do {
            let restored = try await service.restoreSession()
            if let retiredUserID = service.retiredCleanupUserID {
                try cleanupJournal?.capture(retiredUserID, deleting: false)
                if cleanupJournal != nil {
                    let state = await service.retrySignedOutCleanup()
                    authRecovery = state.recovery
                }
            }
            try Task.checkCancellation()
            if restorationSessionGeneration == sessionGeneration, restorationGeneration == restoration {
                receive(restored)
                outcome = .settled(restored?.userID)
            } else {
                outcome = .superseded
            }
        } catch is CancellationError {
            outcome = .cancelled
        } catch {
            if Task.isCancelled {
                outcome = .cancelled
            } else if restorationSessionGeneration != sessionGeneration || restorationGeneration != restoration {
                outcome = .superseded
            } else {
                presentError("Your account could not be restored. You can keep playing and retry.")
                outcome = .failed
            }
        }
        if restorationGeneration == restoration { didFinishRestoration(outcome) }
        return outcome
    }

    func refreshSession() async {
        guard let service, session != nil else { return }
        let generation = sessionGeneration
        do {
            let refreshed = try await service.refreshSession()
            try Task.checkCancellation()
            guard sessionGeneration == generation else { return }
            receive(refreshed)
        } catch is CancellationError {
        } catch {
            guard sessionGeneration == generation else { return }
            presentError("Your account connection needs attention. Try again when you're online.")
        }
    }

    func signInWithApple(idToken: String, rawNonce: String) async {
        guard let service, beginWork() else { return }
        restorationSessionGeneration = nil
        defer { isWorking = false }
        do {
            let session = try await service.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            try Task.checkCancellation()
            receive(session)
        } catch is CancellationError {
        } catch {
            presentSignInFailure(error, fallback: "Sign in didn't finish. Try again.")
        }
    }

    #if DEBUG
    func signInForLocalTesting(email: String, password: String) async {
        guard let service, beginWork() else { return }
        restorationSessionGeneration = nil
        defer { isWorking = false }
        do {
            let session = try await service.signInForLocalTesting(email: email, password: password)
            try Task.checkCancellation()
            receive(session)
        } catch is CancellationError {
        } catch {
            presentSignInFailure(error, fallback: "Local sign in didn't finish. Check the local account and try again.")
        }
    }
    #endif

    private func presentSignInFailure(_ error: any Error, fallback: String) {
        if (error as? AccountServiceError) == .deletionRequiresSameAccount {
            presentError("Sign in to the same account that requested deletion. A different account cannot replace its deletion authorization.")
        } else if (error as? AccountServiceError) == .deletionAuthorizationPending {
            presentError("Retry the pending account deletion first. A new sign-in cannot replace its original authorization.")
        } else { presentError(fallback) }
    }

    func retryProfile() async {
        guard let session else { return }
        startProfileLoad(for: session)
        await profileTask?.value
    }

    func randomizeAvatar() {
        avatarSeedDraft = UUID().uuidString.lowercased()
    }

    func saveProfile() async {
        guard let service, let session, beginWork() else { return }
        guard let name = PlayerProfile.normalizedDisplayName(displayNameDraft) else {
            presentError("Use 2–16 letters, numbers, spaces, apostrophes, or hyphens.")
            isWorking = false
            return
        }
        invalidateProfileLoad()
        let generation = sessionGeneration
        defer { isWorking = false }
        do {
            let saved = try await service.updateProfile(
                userID: session.userID,
                displayName: name,
                avatarSeed: avatarSeedDraft
            )
            try Task.checkCancellation()
            guard sessionGeneration == generation, self.session?.userID == saved.userID else { return }
            apply(saved)
        } catch is CancellationError {
        } catch {
            guard sessionGeneration == generation else { return }
            presentError("Your profile couldn't be saved. Try again.")
        }
    }

    func signOut() async {
        guard let service, session != nil || authRecovery != nil, beginWork() else { return }
        let effectiveUserID = session?.userID ?? service.pendingDeletionUserID
        defer { isWorking = false }
        do { try willDepartAccount(effectiveUserID) }
        catch { presentError("Saved invitation cleanup could not be completed. Restore storage access and retry sign out."); return }
        restorationSessionGeneration = nil
        clearAccountState()
        didChangeSession(nil)
        let outcome = await service.signOut()
        clearAccountState()
        authRecovery = outcome.localRecovery
        let retiredUserID = outcome.retiredUserID ?? effectiveUserID
        let removedRecovery = if let retiredUserID { await didSignOut(retiredUserID) } else { true }
        if removedRecovery, cleanupJournal != nil, cleanupJournal?.isUnavailable == false {
            authRecovery = await service.retrySignedOutCleanup().recovery
        }
        didCompleteSignedOutIntent()
        if outcome.localRecovery != nil {
            presentError("You’re signed out, but saved account credentials need cleanup. Retry account cleanup before signing in again.")
            signOutGuidance = .credentials
        } else if !removedRecovery {
            presentError("You’re signed out, but saved live recovery data could not be removed. Open Live Race to retry or discard it.")
            if let retiredUserID { signOutGuidance = .live(retiredUserID) }
        } else if outcome.remoteLogoutFailed {
            presentError("You’re signed out on this device. The account server could not confirm sign out while offline.")
        }
    }

    func retryAuthRecovery() async {
        guard let service, let authRecovery else { return }
        if authRecovery.action == .deletion || authRecovery.action == .deletionReauthentication {
            if let userID = service.pendingDeletionUserID ?? deletingUserID {
                await deleteAccount(userID: userID, retryCaptured: true)
            }
            return
        }
        guard beginWork() else { return }
        defer { isWorking = false }
        if authRecovery.action == .restore {
            await restoreSession()
        } else {
            restorationSessionGeneration = nil
            if let retiredUserID = service.retiredCleanupUserID {
                do { try cleanupJournal?.capture(retiredUserID, deleting: false) }
                catch { presentError("Saved cleanup instructions could not be recorded. Restore storage access and retry."); return }
            }
            let state = await service.retrySignedOutCleanup()
            receiveAuthState(state)
            if state.session == nil { didCompleteSignedOutIntent() }
            if self.authRecovery != nil { presentError("Saved account credentials could not be removed. You can keep playing and retry cleanup.") }
        }
    }

    func deleteAccount() async {
        guard let userID = session?.userID ?? deletingUserID ?? service?.pendingDeletionUserID else { return }
        await deleteAccount(userID: userID)
    }
    private func deleteAccount(userID: UUID, retryCaptured: Bool = false) async {
        guard let service, beginWork() else { return }
        defer { isWorking = false }
        do { try willDepartAccount(userID) }
        catch { presentError("Saved invitation cleanup could not be recorded. Restore storage access and retry deletion."); return }
        restorationSessionGeneration = nil
        deletingUserID = userID
        do {
            let hidesCurrentAccount = session == nil || session?.userID == userID
            if hidesCurrentAccount { clearAccountState() }
            do { if !retryCaptured { try service.prepareAccountDeletion(userID: userID) } }
            catch { if hidesCurrentAccount { didChangeSession(nil) }; throw error }
            if hidesCurrentAccount { didChangeSession(nil) }
            try cleanupJournal?.capture(userID, deleting: true)
            let confirmed: ConfirmedAccountDeletion
            if let previous = confirmedDeletions[userID] { confirmed = previous }
            else {
                confirmed = retryCaptured ? try await service.retryAccountDeletion(userID: userID)
                    : try await service.deleteAccount(userID: userID)
                confirmedDeletions[userID] = confirmed
            }
            var durableConfirmation = true
            do { try cleanupJournal?.confirmDeletion(userID) }
            catch { durableConfirmation = false; memoryPendingDaily.insert(userID) }
            memoryPendingDaily.formUnion(cleanupJournal?.dailyUsers ?? [])
            deletedLiveUserIDs.formUnion(cleanupJournal?.liveUsers ?? [])
            var unknownLocalFailure = false
            do { try await didDeleteAccount(userID); memoryPendingDaily.remove(userID) }
            catch let failure as AccountLocalDeletionFailure {
                if let userID = failure.dailyCacheUserID { memoryPendingDaily.insert(userID) }
                else { memoryPendingDaily.remove(userID) }
                if failure.liveRecoveryPending { deletedLiveUserIDs.insert(userID) }
            } catch { unknownLocalFailure = true }
            if session == nil || session?.userID == userID { clearAccountState() }
            authRecovery = confirmed.localRecovery
            do {
                if durableConfirmation {
                    try service.acknowledgeAccountDeletion(userID: userID)
                    confirmedDeletions[userID] = nil
                    if authRecovery?.action == .deletion { authRecovery = nil }
                } else {
                    authRecovery = AccountAuthRecovery(action: .deletion, storageIssue: nil)
                }
            }
            catch { authRecovery = AccountAuthRecovery(action: .deletion, storageIssue: error as? AuthStorageIssue) }
            if durableConfirmation && authRecovery?.action != .deletion { deletingUserID = nil }
            didCompleteSignedOutIntent()
            presentDeletionRecovery(unknownLocalFailure: unknownLocalFailure)
        } catch is CancellationError {
        } catch {
            authRecovery = AccountAuthRecovery(action: service.deletionNeedsReauthentication ? .deletionReauthentication : .deletion,
                                               storageIssue: error as? AuthStorageIssue)
            if service.deletionNeedsReauthentication {
                presentError("Sign in to the same account to finish deletion. The server rejected the original deletion authorization.")
                return
            }
            presentError("Account deletion needs attention. You can keep playing and retry the captured deletion, or sign out on this device.")
        }
    }

    func retryDeletedDailyData() async {
        guard canRetryDeletedDailyData, let retryDeletedDailyCleanup, beginWork() else { return }
        defer { isWorking = false }
        let capturedUsers = pendingDeletedDailyUserIDs
        for userID in capturedUsers {
            do {
                try await retryDeletedDailyCleanup(userID)
                try cleanupJournal?.completeDaily(userID)
                memoryPendingDaily.remove(userID)
            } catch {}
        }
        presentDeletionRecovery(unknownLocalFailure: false)
    }

    private var deletionRecoveryMessage: String? {
        var actions: [String] = []
        if authRecovery != nil { actions.append("Retry account cleanup to remove saved credentials.") }
        if !pendingDeletedDailyUserIDs.isEmpty { actions.append("Retry Daily cleanup to remove the deleted account’s saved Daily data.") }
        let hasLiveCleanup = deletedLiveUserIDs.contains { hasPendingDeletedLiveCleanup?($0) ?? true }
        if hasLiveCleanup { actions.append("Open Live Race to retry or discard saved live data.") }
        if cleanupJournal?.isUnavailable == true { actions.append("Saved cleanup instructions are unavailable. Restore storage access and retry cleanup.") }
        if unknownDeletionCleanupFailure { actions.append("Some local data could not be removed. Use its recovery controls before sharing this device.") }
        return actions.isEmpty ? nil : "Your account was deleted. " + actions.joined(separator: " ")
    }

    private func presentDeletionRecovery(unknownLocalFailure: Bool) {
        unknownDeletionCleanupFailure = unknownLocalFailure
        showsDeletionRecovery = true
        if deletionRecoveryMessage != nil { errorEvent += 1 }
    }

    private func receiveAuthState(_ state: AccountAuthState) {
        let restoration = restorationGeneration
        let neutralNil = isRestoring && session == nil && state.session == nil
            && restorationSessionGeneration == sessionGeneration
        authRecovery = state.recovery
        receive(state.session)
        if neutralNil, restorationGeneration == restoration,
           restorationSessionGeneration != nil {
            restorationSessionGeneration = sessionGeneration
        }
    }

    func appleAuthorizationFailed(_ error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled { return }
        presentError("Sign in didn't finish. Try again.")
    }

    func noncePreparationFailed() {
        presentError("Sign in couldn't start. Try again.")
    }

    func clearError() {
        errorMessage = nil
    }

    private func presentError(_ message: String) {
        errorMessage = message
        errorEvent += 1
    }

    private func beginWork() -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        return true
    }

    private func receive(_ nextSession: AccountSession?) {
        guard let nextSession else {
            let wasSignedOut = session == nil
            let retainedMessage = storedErrorMessage
            let retainedSignOutGuidance = signOutGuidance
            let retainedDeletionPresentation = showsDeletionRecovery
            clearAccountState()
            if wasSignedOut {
                storedErrorMessage = retainedMessage
                signOutGuidance = retainedSignOutGuidance
                showsDeletionRecovery = retainedDeletionPresentation
            }
            didChangeSession(nil)
            return
        }
        let changedIdentity = session?.userID != nextSession.userID
        if changedIdentity {
            invalidateProfileLoad()
            sessionGeneration += 1
            profile = nil
            errorMessage = nil
            displayNameDraft = ""
            avatarSeedDraft = UUID().uuidString.lowercased()
        }
        session = nextSession
        didChangeSession(nextSession.userID)
        if changedIdentity || (profile == nil && profileTask == nil) {
            startProfileLoad(for: nextSession)
        }
    }

    private func startProfileLoad(for session: AccountSession) {
        guard let service else { return }
        invalidateProfileLoad()
        let generation = profileGeneration
        isLoadingProfile = true
        errorMessage = nil
        profileTask = Task { [weak self] in
            do {
                let loaded = try await service.loadProfile(userID: session.userID)
                try Task.checkCancellation()
                guard let self, self.profileGeneration == generation,
                      self.session?.userID == session.userID else { return }
                if loaded.userID == session.userID {
                    self.apply(loaded)
                    self.errorMessage = nil
                } else {
                    self.profile = nil
                    self.presentError("Your profile couldn't be loaded. Try again.")
                }
            } catch is CancellationError {
            } catch {
                guard let self, self.profileGeneration == generation,
                      self.session?.userID == session.userID else { return }
                self.profile = nil
                self.presentError("Your profile couldn't be loaded. Try again.")
            }
            guard let self, self.profileGeneration == generation else { return }
            self.isLoadingProfile = false
            self.profileTask = nil
        }
    }

    private func invalidateProfileLoad() {
        profileGeneration += 1
        profileTask?.cancel()
        profileTask = nil
        isLoadingProfile = false
    }

    private func apply(_ profile: PlayerProfile) {
        self.profile = profile
        displayNameDraft = profile.displayName
        avatarSeedDraft = profile.avatarSeed
    }

    private func clearAccountState() {
        invalidateProfileLoad()
        sessionGeneration += 1
        errorMessage = nil
        session = nil
        profile = nil
        displayNameDraft = ""
        avatarSeedDraft = UUID().uuidString.lowercased()
    }
}
