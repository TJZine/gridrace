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
    private let didChangeSession: @MainActor (UUID?) -> Void
    private let didSignOut: @MainActor (UUID) async -> Bool
    private let didDeleteAccount: @MainActor (UUID) async throws -> Void
    private let retryDeletedDailyCleanup: (@MainActor (UUID) async throws -> Void)?
    private(set) var pendingDeletedDailyUserIDs: Set<UUID> = []
    var canRetryDeletedDailyData: Bool { !pendingDeletedDailyUserIDs.isEmpty && retryDeletedDailyCleanup != nil }
    private var deletedLiveUserIDs: Set<UUID> = []
    private let hasPendingDeletedLiveCleanup: (@MainActor (UUID) -> Bool)?
    private var authObservation: Task<Void, Never>?
    private var started = false
    private var profileTask: Task<Void, Never>?
    private var restorationGeneration = 0
    // Only the current restore may follow identity-neutral nil notifications.
    // Explicit Auth intent or a real identity transition leaves this receipt invalid.
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
    private var showsDeletionRecovery = false
    private var unknownDeletionCleanupFailure = false
    private(set) var errorMessage: String? {
        get { showsDeletionRecovery ? deletionRecoveryMessage : storedErrorMessage }
        set { showsDeletionRecovery = false; storedErrorMessage = newValue }
    }
    // Per-error event seam: incremented on every error assignment (even when
    // the message string repeats, e.g. retryProfile → loadProfile failing
    // twice with the same text), so `onChange(errorMessage)` coalescing can
    // never swallow a refocus. Success/clear paths leave it unchanged.
    private(set) var errorEvent = 0
    var displayNameDraft = ""
    var avatarSeedDraft = UUID().uuidString.lowercased()

    var isConfigured: Bool { service != nil }
    var isSignedIn: Bool { session != nil }
    var needsProfileSetup: Bool { profile?.needsSetup == true }

    init(
        service: (any AccountServicing)?,
        didChangeSession: @escaping @MainActor (UUID?) -> Void = { _ in },
        didFinishRestoration: @escaping @MainActor (RestorationOutcome) -> Void = { _ in },
        didCompleteSignedOutIntent: @escaping @MainActor () -> Void = {},
        didSignOut: @escaping @MainActor (UUID) async -> Bool = { _ in true },
        didDeleteAccount: @escaping @MainActor (UUID) async throws -> Void = { _ in },
        retryDeletedDailyCleanup: (@MainActor (UUID) async throws -> Void)? = nil,
        hasPendingDeletedLiveCleanup: (@MainActor (UUID) -> Bool)? = nil
    ) {
        self.service = service
        self.didChangeSession = didChangeSession
        self.didFinishRestoration = didFinishRestoration
        self.didCompleteSignedOutIntent = didCompleteSignedOutIntent
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
        // The subscription's initial snapshot predates this restore. Consume it
        // before a successful restore can install a newer account identity.
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
            presentError("Sign in didn't finish. Try again.")
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
            presentError("Local sign in didn't finish. Check the local account and try again.")
        }
    }
    #endif

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
        guard let service, session != nil || authRecovery?.action == .restore, beginWork() else { return }
        let effectiveUserID = session?.userID
        restorationSessionGeneration = nil
        defer { isWorking = false }
        let outcome = await service.signOut()
        clearAccountState()
        authRecovery = outcome.localRecovery
        let retiredUserID = outcome.retiredUserID ?? effectiveUserID
        let removedRecovery = if let retiredUserID { await didSignOut(retiredUserID) } else { true }
        didCompleteSignedOutIntent()
        if outcome.localRecovery != nil {
            presentError("You’re signed out, but saved account credentials need cleanup. Retry account cleanup before signing in again.")
        } else if !removedRecovery {
            presentError("You’re signed out, but saved live recovery data could not be removed. Open Live Race to retry or discard it.")
        } else if outcome.remoteLogoutFailed {
            presentError("You’re signed out on this device. The account server could not confirm sign out while offline.")
        }
    }

    func retryAuthRecovery() async {
        guard let service, let authRecovery, beginWork() else { return }
        defer { isWorking = false }
        if authRecovery.action == .restore {
            await restoreSession()
        } else {
            restorationSessionGeneration = nil
            let state = await service.retrySignedOutCleanup()
            receiveAuthState(state)
            if state.session == nil { didCompleteSignedOutIntent() }
            if self.authRecovery != nil { presentError("Saved account credentials could not be removed. You can keep playing and retry cleanup.") }
        }
    }

    func deleteAccount() async {
        guard let service, let userID = session?.userID, beginWork() else { return }
        restorationSessionGeneration = nil
        defer { isWorking = false }
        do {
            let confirmed = try await service.deleteAccount()
            // Remote deletion is already final. Local Auth trouble never skips captured-user cleanup.
            var unknownLocalFailure = false
            do { try await didDeleteAccount(userID) }
            catch let failure as AccountLocalDeletionFailure {
                if let userID = failure.dailyCacheUserID { pendingDeletedDailyUserIDs.insert(userID) }
                if failure.liveRecoveryPending { deletedLiveUserIDs.insert(userID) }
            } catch { unknownLocalFailure = true }
            clearAccountState()
            authRecovery = confirmed.localRecovery
            didCompleteSignedOutIntent()
            presentDeletionRecovery(unknownLocalFailure: unknownLocalFailure)
        } catch is CancellationError {
        } catch {
            presentError("Your account couldn't be deleted. No local data was removed. Try again.")
        }
    }

    func retryDeletedDailyData() async {
        guard canRetryDeletedDailyData, let retryDeletedDailyCleanup, beginWork() else { return }
        defer { isWorking = false }
        let capturedUsers = pendingDeletedDailyUserIDs
        for userID in capturedUsers {
            do {
                try await retryDeletedDailyCleanup(userID)
                pendingDeletedDailyUserIDs.remove(userID)
            } catch {} // Retain each failed captured account for the next explicit retry.
        }
        presentDeletionRecovery(unknownLocalFailure: false)
    }

    private var deletionRecoveryMessage: String? {
        var actions: [String] = []
        if authRecovery != nil { actions.append("Retry account cleanup to remove saved credentials.") }
        if !pendingDeletedDailyUserIDs.isEmpty { actions.append("Retry Daily cleanup to remove the deleted account’s saved Daily data.") }
        let hasLiveCleanup = deletedLiveUserIDs.contains { hasPendingDeletedLiveCleanup?($0) ?? true }
        if hasLiveCleanup { actions.append("Open Live Race to retry or discard saved live data.") }
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
        // Preserve global session/profile fences. Only this still-current restore
        // can acknowledge a notification that did not change effective identity.
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
            clearAccountState()
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
