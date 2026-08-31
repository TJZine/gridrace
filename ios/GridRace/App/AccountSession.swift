import Foundation

struct AccountSession: Equatable, Sendable {
    let userID: UUID
    let expiresAt: Date
}

struct PlayerProfile: Codable, Equatable, Sendable {
    let userID: UUID
    var displayName: String
    var avatarSeed: String
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case userID = "id"
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var needsSetup: Bool {
        displayName.range(of: #"^Player [0-9a-f]{6}$"#, options: .regularExpression) != nil
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

@MainActor
protocol AccountServicing: AnyObject {
    var authStateChanges: AsyncStream<AccountSession?> { get }

    func restoreSession() async throws -> AccountSession?
    func refreshSession() async throws -> AccountSession?
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AccountSession
    #if DEBUG
    func signInForLocalTesting(email: String, password: String) async throws -> AccountSession
    #endif
    func loadProfile(userID: UUID) async throws -> PlayerProfile
    func updateProfile(userID: UUID, displayName: String, avatarSeed: String) async throws -> PlayerProfile
    func signOut() async throws
    func deleteAccount() async throws
}
