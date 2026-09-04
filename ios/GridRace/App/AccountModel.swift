import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AccountModel {
    private let service: (any AccountServicing)?
    private let didChangeSession: @MainActor (UUID?) -> Void
    private let didSignOut: @MainActor (UUID) async -> Void
    private let didDeleteAccount: @MainActor (UUID) async throws -> Void
    private var authObservation: Task<Void, Never>?
    private var started = false

    private(set) var session: AccountSession?
    private(set) var profile: PlayerProfile?
    private(set) var isRestoring = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?
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
        didSignOut: @escaping @MainActor (UUID) async -> Void = { _ in },
        didDeleteAccount: @escaping @MainActor (UUID) async throws -> Void = { _ in }
    ) {
        self.service = service
        self.didChangeSession = didChangeSession
        self.didSignOut = didSignOut
        self.didDeleteAccount = didDeleteAccount
    }

    isolated deinit {
        authObservation?.cancel()
    }

    func start() async {
        guard !started, let service else { return }
        started = true
        let changes = service.authStateChanges
        authObservation = Task { [weak self] in
            for await session in changes {
                guard !Task.isCancelled else { return }
                await self?.receive(session)
            }
        }
        await restoreSession()
    }

    func restoreSession() async {
        guard let service else { return }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }
        do {
            let restored = try await service.restoreSession()
            try Task.checkCancellation()
            await receive(restored)
        } catch is CancellationError {
        } catch {
            presentError("Your account could not be restored. You can keep playing and retry.")
        }
    }

    func refreshSession() async {
        guard let service, session != nil else { return }
        do {
            let refreshed = try await service.refreshSession()
            try Task.checkCancellation()
            await receive(refreshed)
        } catch is CancellationError {
        } catch {
            presentError("Your account connection needs attention. Try again when you're online.")
        }
    }

    func signInWithApple(idToken: String, rawNonce: String) async {
        guard let service, beginWork() else { return }
        defer { isWorking = false }
        do {
            let session = try await service.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            try Task.checkCancellation()
            await receive(session)
        } catch is CancellationError {
        } catch {
            presentError("Sign in didn't finish. Try again.")
        }
    }

    #if DEBUG
    func signInForLocalTesting(email: String, password: String) async {
        guard let service, beginWork() else { return }
        defer { isWorking = false }
        do {
            let session = try await service.signInForLocalTesting(email: email, password: password)
            try Task.checkCancellation()
            await receive(session)
        } catch is CancellationError {
        } catch {
            presentError("Local sign in didn't finish. Check the local account and try again.")
        }
    }
    #endif

    func retryProfile() async {
        guard let session else { return }
        await loadProfile(for: session)
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
        defer { isWorking = false }
        do {
            let saved = try await service.updateProfile(
                userID: session.userID,
                displayName: name,
                avatarSeed: avatarSeedDraft
            )
            try Task.checkCancellation()
            guard self.session?.userID == saved.userID else { return }
            apply(saved)
        } catch is CancellationError {
        } catch {
            presentError("Your profile couldn't be saved. Try again.")
        }
    }

    func signOut() async {
        guard let service, let userID = session?.userID, beginWork() else { return }
        defer { isWorking = false }
        do {
            try await service.signOut()
            clearAccountState()
            await didSignOut(userID)
        } catch is CancellationError {
        } catch {
            presentError("Sign out didn't finish. Try again.")
        }
    }

    func deleteAccount() async {
        guard let service, let userID = session?.userID, beginWork() else { return }
        defer { isWorking = false }
        do {
            try await service.deleteAccount()
            do {
                try await didDeleteAccount(userID)
            } catch {
                clearAccountState()
                didChangeSession(nil)
                presentError("Your account was deleted, but its local data could not be removed. Reinstall GridRace before sharing this device.")
                return
            }
            clearAccountState()
        } catch is CancellationError {
        } catch {
            presentError("Your account couldn't be deleted. No local data was removed. Try again.")
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

    private func receive(_ nextSession: AccountSession?) async {
        guard let nextSession else {
            clearAccountState()
            didChangeSession(nil)
            return
        }
        let needsLoad = session?.userID != nextSession.userID || profile == nil
        if session?.userID != nextSession.userID {
            profile = nil
            displayNameDraft = ""
            avatarSeedDraft = UUID().uuidString.lowercased()
        }
        session = nextSession
        didChangeSession(nextSession.userID)
        if needsLoad { await loadProfile(for: nextSession) }
    }

    private func loadProfile(for session: AccountSession) async {
        guard let service else { return }
        do {
            let loaded = try await service.loadProfile(userID: session.userID)
            try Task.checkCancellation()
            guard self.session?.userID == loaded.userID else { return }
            apply(loaded)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            guard self.session?.userID == session.userID else { return }
            profile = nil
            presentError("Your profile couldn't be loaded. Try again.")
        }
    }

    private func apply(_ profile: PlayerProfile) {
        self.profile = profile
        displayNameDraft = profile.displayName
        avatarSeedDraft = profile.avatarSeed
    }

    private func clearAccountState() {
        session = nil
        profile = nil
        displayNameDraft = ""
        avatarSeedDraft = UUID().uuidString.lowercased()
    }
}
