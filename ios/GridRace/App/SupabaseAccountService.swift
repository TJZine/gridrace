import Foundation
import Supabase

@MainActor
final class SupabaseAccountService: AccountServicing {
    struct Configuration: Equatable, Sendable {
        let projectURL: URL
        let publishableKey: String

        init?(urlString: String?, publishableKey: String?) {
            guard let urlString, let publishableKey,
                  !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let projectURL = URL(string: urlString),
                  ["http", "https"].contains(projectURL.scheme?.lowercased())
            else { return nil }
            self.projectURL = projectURL
            self.publishableKey = publishableKey
        }
    }

    private let client: SupabaseClient
    private let clientBuild: Int

    static func configured(bundle: Bundle = .main, clientBuild: Int = 1) -> SupabaseAccountService? {
        guard let configuration = Configuration(
            urlString: bundle.object(forInfoDictionaryKey: "GridRaceSupabaseURL") as? String,
            publishableKey: bundle.object(forInfoDictionaryKey: "GridRaceSupabasePublishableKey") as? String
        ) else { return nil }
        return SupabaseAccountService(configuration: configuration, clientBuild: clientBuild)
    }

    init(configuration: Configuration, clientBuild: Int = 1) {
        // Supabase's Apple-platform default persists Auth sessions in KeychainLocalStorage.
        client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey
        )
        self.clientBuild = clientBuild
    }

    var authStateChanges: AsyncStream<AccountSession?> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (_, session) in changes {
                    guard !Task.isCancelled else { break }
                    continuation.yield(session.map(Self.accountSession))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func restoreSession() async throws -> AccountSession? {
        guard client.auth.currentSession != nil else { return nil }
        return Self.accountSession(try await client.auth.session)
    }

    func refreshSession() async throws -> AccountSession? {
        guard client.auth.currentSession != nil else { return nil }
        return Self.accountSession(try await client.auth.refreshSession())
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AccountSession {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
        )
        return Self.accountSession(session)
    }

    #if DEBUG
    func signInForLocalTesting(email: String, password: String) async throws -> AccountSession {
        Self.accountSession(try await client.auth.signIn(email: email, password: password))
    }
    #endif

    func loadProfile(userID: UUID) async throws -> PlayerProfile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }

    func updateProfile(
        userID: UUID,
        displayName: String,
        avatarSeed: String
    ) async throws -> PlayerProfile {
        guard let displayName = PlayerProfile.normalizedDisplayName(displayName),
              (1...64).contains(avatarSeed.count)
        else { throw AccountServiceError.invalidProfile }

        return try await client
            .from("profiles")
            .update(ProfileUpdate(displayName: displayName, avatarSeed: avatarSeed))
            .eq("id", value: userID)
            .select()
            .single()
            .execute()
            .value
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func deleteAccount() async throws {
        let response: CommandEnvelope<DeleteResponse> = try await client.functions.invoke(
            "delete-account",
            options: .init(body: DeleteRequest(clientBuild: clientBuild))
        )
        guard response.data.deleted else { throw AccountServiceError.invalidResponse }
        // Supabase removes its Keychain-backed local session before the logout request.
        // Deletion is already final once the authenticated Edge Function succeeds.
        try? await client.auth.signOut()
    }

    func makeDailySyncRemote() -> SupabaseDailySyncRemote {
        SupabaseDailySyncRemote(client: client)
    }

    private static func accountSession(_ session: Session) -> AccountSession {
        AccountSession(
            userID: session.user.id,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
    }
}

private struct ProfileUpdate: Encodable {
    let displayName: String
    let avatarSeed: String

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
    }
}

private struct DeleteRequest: Encodable {
    let clientBuild: Int

    private enum CodingKeys: String, CodingKey {
        case clientBuild = "client_build"
    }
}

private struct CommandEnvelope<Value: Decodable>: Decodable {
    let data: Value
}

private struct DeleteResponse: Decodable {
    let deleted: Bool
}

enum AccountServiceError: Error {
    case invalidProfile
    case invalidResponse
}
