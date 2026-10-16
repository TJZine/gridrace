import Foundation

struct AccountSession: Equatable, Sendable {
    let userID: UUID
    let expiresAt: Date
}

struct PlayerProfile: Codable, Equatable, Sendable {
    let userID: UUID
    var displayName: String
    var avatarSeed: String
    let setupCompleted: Bool
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case userID = "id"
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
        case setupCompleted = "setup_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var needsSetup: Bool {
        !setupCompleted
    }

    static func normalizedDisplayName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...16).contains(name.count), !name.contains("  ") else { return nil }
        let scalars = name.unicodeScalars
        guard let first = scalars.first, let last = scalars.last,
              first.isASCIIAlphaNumeric, last.isASCIIAlphaNumeric,
              scalars.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == " " || $0 == "'" || $0 == "-" })
        else { return nil }
        return name
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphaNumeric: Bool {
        ("a"..."z").contains(self) || ("A"..."Z").contains(self) || ("0"..."9").contains(self)
    }
}

struct AuthStorageIssue: Error, Equatable, Sendable {
    enum Operation: Sendable { case read, store, remove }
    let operation: Operation
    let status: Int32
}

struct AccountAuthRecovery: Equatable, Sendable {
    enum Action: Sendable { case restore, cleanup, deletion, deletionReauthentication }
    let action: Action
    let storageIssue: AuthStorageIssue?
}

struct AccountAuthState: Equatable, Sendable {
    let session: AccountSession?
    let recovery: AccountAuthRecovery?
    init(session: AccountSession?, recovery: AccountAuthRecovery? = nil) {
        self.session = session
        self.recovery = recovery
    }
}

struct AccountSignOutOutcome: Sendable {
    let localRecovery: AccountAuthRecovery?
    let remoteLogoutFailed: Bool
    let retiredUserID: UUID?
    init(localRecovery: AccountAuthRecovery?, remoteLogoutFailed: Bool, retiredUserID: UUID? = nil) {
        self.localRecovery = localRecovery
        self.remoteLogoutFailed = remoteLogoutFailed
        self.retiredUserID = retiredUserID
    }
}

struct AccountLocalDeletionFailure: Error, Sendable {
    let dailyCacheUserID: UUID?
    let liveRecoveryPending: Bool
}

struct ConfirmedAccountDeletion: Sendable {
    let localRecovery: AccountAuthRecovery?
}

@MainActor
protocol AccountServicing: AnyObject {
    var authStateChanges: AsyncStream<AccountAuthState> { get }
    var pendingDeletionUserID: UUID? { get }
    var deletionNeedsReauthentication: Bool { get }
    var retiredCleanupUserID: UUID? { get }
    func prepareAccountDeletion() throws
    func prepareAccountDeletion(userID: UUID) throws
    func acknowledgeAccountDeletion(userID: UUID) throws

    func restoreSession() async throws -> AccountSession?
    func refreshSession() async throws -> AccountSession?
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AccountSession
    #if DEBUG
    func signInForLocalTesting(email: String, password: String) async throws -> AccountSession
    #endif
    func loadProfile(userID: UUID) async throws -> PlayerProfile
    func updateProfile(userID: UUID, displayName: String, avatarSeed: String) async throws -> PlayerProfile
    func signOut() async -> AccountSignOutOutcome
    func deleteAccount() async throws -> ConfirmedAccountDeletion
    func deleteAccount(userID: UUID) async throws -> ConfirmedAccountDeletion
    func retryAccountDeletion(userID: UUID) async throws -> ConfirmedAccountDeletion
    func retrySignedOutCleanup() async -> AccountAuthState
}

extension AccountServicing {
    var pendingDeletionUserID: UUID? { nil }
    var deletionNeedsReauthentication: Bool { false }
    var retiredCleanupUserID: UUID? { nil }
    func prepareAccountDeletion() throws {}
    func prepareAccountDeletion(userID: UUID) throws { try prepareAccountDeletion() }
    func deleteAccount(userID: UUID) async throws -> ConfirmedAccountDeletion { try await deleteAccount() }
    func retryAccountDeletion(userID: UUID) async throws -> ConfirmedAccountDeletion { try await deleteAccount(userID: userID) }
    func acknowledgeAccountDeletion(userID: UUID) throws {}
}
