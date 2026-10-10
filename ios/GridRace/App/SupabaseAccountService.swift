import Foundation
import Supabase
import UIKit

@MainActor
final class SupabaseAccountService: AccountServicing {
    struct Configuration: Equatable, Sendable {
        let projectURL: URL
        let publishableKey: String
        init?(urlString: String?, publishableKey: String?) {
            guard let urlString, let publishableKey,
                  !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let projectURL = URL(string: urlString),
                  ["http", "https"].contains(projectURL.scheme?.lowercased()), projectURL.host() != nil
            else { return nil }
            self.projectURL = projectURL
            self.publishableKey = publishableKey
        }
    }
    private enum Phase { case restoring, candidate, active, retiring }
    private struct Retirement {
        let id: UUID
        let lifetime: AuthClientLifetime
        let task: Task<AccountSignOutOutcome, Never>
    }
    private var retirement: Retirement?
    private let configuration: Configuration
    private let backend: any AuthLocalStorage
    private let network: @Sendable () -> URLSession
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let clientBuild: Int
    private let notificationCenter: NotificationCenter
    private let beforeChannelRemoval: @Sendable () async -> Void
    private var notifications: [NSObjectProtocol] = []
    private var current: AuthClientLifetime?
    private var phase: Phase?
    private var verified: Session?
    private var logoutSnapshot: Session?
    private var recovery: AccountAuthRecovery?
    private var observation: Task<Void, Never>?
    private var teardown: Task<Void, Never>?
    private var teardownID: UUID?
    private var scheduler: Task<Void, Never>?
    private var schedulerID: UUID?
    private var appActive: Bool
    private var streams: [UUID: AsyncStream<AccountAuthState>.Continuation] = [:]
    private(set) var lastRetirementIssues: [AuthStorageIssue] = []
    var sessionKey: String { "sb-\(configuration.projectURL.host()!.split(separator: ".")[0])-auth-token" }
    private var markerKey: String { sessionKey + "-gridrace-retired-v1" }
    private var credentialKeys: [String] { [sessionKey, "supabase.session", sessionKey + "-code-verifier"] }
    static func configured(bundle: Bundle = .main, clientBuild: Int = 2) -> SupabaseAccountService? {
        guard let configuration = Configuration(
            urlString: bundle.object(forInfoDictionaryKey: "GridRaceSupabaseURL") as? String,
            publishableKey: bundle.object(forInfoDictionaryKey: "GridRaceSupabasePublishableKey") as? String
        ) else { return nil }
        return SupabaseAccountService(configuration: configuration, clientBuild: clientBuild)
    }
    init(configuration: Configuration, clientBuild: Int = 2,
         storage: any AuthLocalStorage = SecureAuthStorage(),
         network: @escaping @Sendable () -> URLSession = { URLSession(configuration: .default) },
         clock: @escaping @Sendable () -> Date = Date.init,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         notificationCenter: NotificationCenter = .default,
         beforeChannelRemoval: @escaping @Sendable () async -> Void = {}) {
        self.configuration = configuration
        self.clientBuild = clientBuild
        self.backend = storage
        self.network = network
        self.clock = clock
        self.sleep = sleep
        self.notificationCenter = notificationCenter
        self.beforeChannelRemoval = beforeChannelRemoval
        appActive = UIApplication.shared.applicationState == .active
        notifications = [
            notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applicationDidBecomeActive() }
            },
            notificationCenter.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applicationWillResignActive() }
            }
        ]
    }
    isolated deinit {
        observation?.cancel()
        scheduler?.cancel()
        for token in notifications { notificationCenter.removeObserver(token) }
        for stream in streams.values { stream.finish() }
    }
    private var projectedState: AccountAuthState {
        AccountAuthState(session: phase == .active ? verified.map(Self.accountSession) : nil, recovery: recovery)
    }
    var authStateChanges: AsyncStream<AccountAuthState> {
        let id = UUID()
        return AsyncStream { continuation in
            streams[id] = continuation
            continuation.yield(projectedState)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.streams[id] = nil }
            }
        }
    }
    private func publish() { for stream in streams.values { stream.yield(projectedState) } }
    private func storageIssue(_ error: any Error, operation: AuthStorageIssue.Operation) -> AuthStorageIssue {
        (error as? AuthStorageIssue) ?? AuthStorageIssue(operation: operation, status: -2070)
    }
    private struct LegacyStoredSession: Decodable {
        let session: Session
        let expirationDate: Date
    }
    private func validateStoredCredentials() throws {
        for key in [sessionKey, "supabase.session"] {
            guard let bytes = try backend.retrieve(key: key) else { continue }
            let direct = (try? JSONDecoder().decode(Session.self, from: bytes))
                ?? (try? AuthClient.Configuration.jsonDecoder.decode(Session.self, from: bytes))
            let envelope = try? AuthClient.Configuration.jsonDecoder.decode(LegacyStoredSession.self, from: bytes)
            guard direct != nil || envelope != nil else {
                throw AuthStorageIssue(operation: .read, status: -26275)
            }
        }
    }
    private func makeLifetime(phase: Phase) -> AuthClientLifetime {
        let gate = AuthStorageGate(backend: backend, sessionKey: sessionKey)
        let client = SupabaseClient(supabaseURL: configuration.projectURL, supabaseKey: configuration.publishableKey,
            options: .init(auth: .init(storage: gate, storageKey: sessionKey, autoRefreshToken: false,
                                       emitLocalSessionAsInitialSession: false),
                           global: .init(session: network()),
                           realtime: .init(handleAppLifecycle: false)))
        let lifetime = AuthClientLifetime(client: client, storage: gate, beforeChannelRemoval: beforeChannelRemoval)
        current = lifetime
        self.phase = phase
        observation?.cancel()
        let changes = client.auth.authStateChanges
        observation = Task { [weak self, lifetime] in
            for await (event, session) in changes {
                guard !Task.isCancelled else { return }
                self?.receive(event, session: session, from: lifetime)
            }
        }
        return lifetime
    }
    private func sameSession(_ lhs: Session, _ rhs: Session) -> Bool {
        lhs.user.id == rhs.user.id && lhs.accessToken == rhs.accessToken && lhs.refreshToken == rhs.refreshToken
            && lhs.expiresAt == rhs.expiresAt
    }
    private func persisted(_ lifetime: AuthClientLifetime) throws -> Session? {
        if let issue = lifetime.storage.issue { throw issue }
        guard let bytes = try backend.retrieve(key: sessionKey) else { return nil }
        return try JSONDecoder().decode(Session.self, from: bytes)
    }
    private func commit(_ session: Session, from lifetime: AuthClientLifetime) throws -> AccountSession {
        guard current === lifetime, phase != .retiring, teardown == nil else { throw CancellationError() }
        try Task.checkCancellation()
        try lifetime.bindIdentity(session.user.id)
        guard let saved = try persisted(lifetime), sameSession(saved, session), !saved.isExpired else {
            // An older result cannot clear a newer, already validated active session.
            if phase == .active, let verified, let saved = try persisted(lifetime), sameSession(saved, verified) {
                return Self.accountSession(verified)
            }
            throw AccountServiceError.invalidResponse
        }
        try Task.checkCancellation()
        try backend.remove(key: markerKey)
        try lifetime.activate()
        verified = saved
        logoutSnapshot = saved
        phase = .active
        recovery = nil
        publish()
        startScheduler()
        return Self.accountSession(saved)
    }
    func receive(_ event: AuthChangeEvent, session: Session?, from lifetime: AuthClientLifetime) {
        guard current === lifetime, phase != .retiring, phase != .candidate else { return }
        guard [.initialSession, .signedIn, .tokenRefreshed, .userUpdated, .signedOut].contains(event) else { return }
        do {
            guard let saved = try persisted(lifetime) else {
                if phase == .active { blockForRestore(lifetime, issue: nil) }
                return
            }
            // Event payloads may be queued before newer storage/commit. Storage owns meaning.
            if !saved.isExpired { _ = try commit(saved, from: lifetime) }
        } catch is CancellationError {
        } catch {
            blockForRestore(lifetime, issue: storageIssue(error, operation: .read))
        }
    }
    private func blockForRestore(_ lifetime: AuthClientLifetime, issue: AuthStorageIssue?) {
        guard current === lifetime, phase != .retiring, phase != .candidate else { return }
        let channels = lifetime.block()
        let previous = teardown
        teardownID = UUID()
        teardown = Task {
            await previous?.value
            await lifetime.finishRetirement(channels)
        }
        phase = .restoring
        verified = nil
        cancelScheduler()
        recovery = AccountAuthRecovery(action: .restore, storageIssue: issue)
        publish()
    }
    func restoreSession() async throws -> AccountSession? {
        if phase == .active, let verified { return Self.accountSession(verified) }
        guard phase != .candidate, phase != .retiring else { throw CancellationError() }
        if current == nil {
            do {
                if let marker = try backend.retrieve(key: markerKey) {
                    guard marker == Data([1]) else { throw AccountServiceError.invalidResponse }
                    let remaining = try credentialKeys.contains { try backend.retrieve(key: $0) != nil }
                    recovery = remaining ? AccountAuthRecovery(action: .cleanup, storageIssue: nil) : nil
                    publish()
                    return nil
                }
                try validateStoredCredentials()
            } catch {
                recovery = AccountAuthRecovery(action: .cleanup, storageIssue: storageIssue(error, operation: .read))
                publish()
                throw error
            }
            _ = makeLifetime(phase: .restoring)
        }
        guard let lifetime = current else { return nil }
        // Complete old channel removal before this same client can gain a new lease.
        while let pending = teardown {
            let id = teardownID
            await pending.value
            guard current === lifetime, phase != .retiring else { throw CancellationError() }
            if teardownID == id { teardown = nil; teardownID = nil }
        }
        lifetime.storage.resetIssue()
        guard let stored = lifetime.client.auth.currentSession else {
            if let issue = lifetime.storage.issue { blockForRestore(lifetime, issue: issue); throw issue }
            // SDK decoders also swallow malformed/migration-failed bytes. Absence is explicit.
            if try [sessionKey, "supabase.session"].contains(where: { try backend.retrieve(key: $0) != nil }) {
                let issue = AuthStorageIssue(operation: .read, status: -26275)
                blockForRestore(lifetime, issue: issue)
                throw issue
            }
            lifetime.storage.close()
            _ = lifetime.retireConsumers()
            observation?.cancel()
            current = nil
            phase = nil
            recovery = nil
            publish()
            return nil
        }
        try lifetime.bindIdentity(stored.user.id)
        logoutSnapshot = stored
        do {
            let session = try await lifetime.client.auth.session
            return try commit(session, from: lifetime)
        } catch {
            // Offline existing restore keeps credentials and this blocked lifetime for retry.
            if current === lifetime, phase != .active { blockForRestore(lifetime, issue: lifetime.storage.issue) }
            throw error
        }
    }
    func refreshSession() async throws -> AccountSession? {
        guard let lifetime = current, phase == .active else { return nil }
        do {
            let session = try await lifetime.client.auth.refreshSession()
            return try commit(session, from: lifetime)
        } catch {
            if let issue = lifetime.storage.issue { blockForRestore(lifetime, issue: issue) }
            throw error
        }
    }
    private func signIn(_ operation: (SupabaseClient) async throws -> Session) async throws -> AccountSession {
        guard current == nil, recovery == nil else { throw AccountServiceError.needsRecovery }
        let cleanup = cleanupCredentials()
        guard cleanup.isEmpty else {
            recovery = AccountAuthRecovery(action: .cleanup, storageIssue: cleanup.first)
            publish()
            throw cleanup[0]
        }
        let lifetime = makeLifetime(phase: .candidate)
        var issued: Session?
        do {
            let session = try await operation(lifetime.client)
            issued = session
            return try commit(session, from: lifetime)
        } catch {
            if current === lifetime {
                let outcome = await retire(lifetime, snapshot: issued)
                if outcome.localRecovery == nil, let issue = error as? AuthStorageIssue {
                    recovery = AccountAuthRecovery(action: .cleanup, storageIssue: issue)
                    publish()
                }
            }
            throw error
        }
    }
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AccountSession {
        try await signIn { client in
            try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce))
        }
    }
    #if DEBUG
    func signInForLocalTesting(email: String, password: String) async throws -> AccountSession {
        try await signIn { try await $0.auth.signIn(email: email, password: password) }
    }
    #endif
    func activeBinding(expectedUserID: UUID? = nil) throws -> AuthClientLease {
        guard phase == .active, let current, let verified,
              expectedUserID == nil || expectedUserID == verified.user.id else { throw CancellationError() }
        return try AuthClientLease(lifetime: current, userID: verified.user.id)
    }
    func loadProfile(userID: UUID) async throws -> PlayerProfile {
        try await activeBinding(expectedUserID: userID).perform { client in
            try await client.from("profiles").select().eq("id", value: userID).single().execute().value
        }
    }
    func updateProfile(userID: UUID, displayName: String, avatarSeed: String) async throws -> PlayerProfile {
        guard let displayName = PlayerProfile.normalizedDisplayName(displayName), (1...64).contains(avatarSeed.count)
        else { throw AccountServiceError.invalidProfile }
        return try await activeBinding(expectedUserID: userID).perform { client in
            try await client.from("profiles").update(ProfileUpdate(displayName: displayName, avatarSeed: avatarSeed))
                .eq("id", value: userID).select().single().execute().value
        }
    }
    private func cleanupCredentials() -> [AuthStorageIssue] {
        var issues: [AuthStorageIssue] = []
        for key in credentialKeys {
            do { try backend.remove(key: key) } catch { issues.append(storageIssue(error, operation: .remove)) }
        }
        for key in credentialKeys {
            do {
                if try backend.retrieve(key: key) != nil { issues.append(AuthStorageIssue(operation: .remove, status: -2070)) }
            } catch { issues.append(storageIssue(error, operation: .read)) }
        }
        return issues
    }
    private func retire(_ lifetime: AuthClientLifetime, snapshot: Session?) async -> AccountSignOutOutcome {
        if let retirement, retirement.lifetime === lifetime { return await retirement.task.value }
        guard current === lifetime else {
            return AccountSignOutOutcome(localRecovery: nil, remoteLogoutFailed: false, retiredUserID: snapshot?.user.id)
        }
        // Nothing fallible precedes consumer/event/socket/scheduler fences.
        phase = .retiring
        verified = nil
        logoutSnapshot = nil
        cancelScheduler() // Does not pretend UIKit became inactive.
        let channels = lifetime.retireConsumers()
        observation?.cancel()
        lifetime.storage.beginLogout(snapshot: snapshot)
        recovery = nil
        publish()
        var markerIssues: [AuthStorageIssue] = []
        do { try backend.store(key: markerKey, value: Data([1])) }
        catch { markerIssues.append(storageIssue(error, operation: .store)) }
        let id = UUID()
        let task = Task {
            await finishRetirement(lifetime, snapshot: snapshot, channels: channels, markerIssues: markerIssues)
        }
        retirement = Retirement(id: id, lifetime: lifetime, task: task)
        let outcome = await task.value
        if retirement?.id == id { retirement = nil }
        return outcome
    }
    private func finishRetirement(_ lifetime: AuthClientLifetime, snapshot: Session?,
                                  channels: [AuthClientLifetime.ChannelRegistration],
                                  markerIssues: [AuthStorageIssue]) async -> AccountSignOutOutcome {
        // A held logout must not leave an SDK subscribe/reconnect task running.
        await teardown?.value
        teardown = nil
        teardownID = nil
        await lifetime.finishRetirement(channels)
        var remoteFailed = false
        do { try await lifetime.client.auth.signOut() } catch { remoteFailed = true }
        lifetime.storage.close()
        if current === lifetime { current = nil; phase = nil }
        let issues = cleanupCredentials()
        lastRetirementIssues = markerIssues + issues
        recovery = issues.first.map { AccountAuthRecovery(action: .cleanup, storageIssue: $0) }
        publish()
        let localRecovery = recovery
        return AccountSignOutOutcome(localRecovery: localRecovery, remoteLogoutFailed: remoteFailed,
                                     retiredUserID: snapshot?.user.id)
    }
    func signOut() async -> AccountSignOutOutcome {
        guard let lifetime = current else {
            return AccountSignOutOutcome(localRecovery: recovery, remoteLogoutFailed: false)
        }
        return await retire(lifetime, snapshot: logoutSnapshot)
    }
    func deleteAccount() async throws -> ConfirmedAccountDeletion {
        let lease = try activeBinding()
        // No generic result/cancellation fence may discard a received confirmed deletion.
        let response: CommandEnvelope<DeleteResponse> = try await lease.lifetime.client.functions.invoke(
            "delete-account", options: .init(body: DeleteRequest(clientBuild: clientBuild)))
        guard response.data.deleted else { throw AccountServiceError.invalidResponse }
        // A confirmed old-account response still requires local data cleanup, but
        // cannot retire a later lifetime installed while the request was in flight.
        guard current === lease.lifetime else { return ConfirmedAccountDeletion(localRecovery: nil) }
        let snapshot = logoutSnapshot
        let outcome = await retire(lease.lifetime, snapshot: snapshot)
        return ConfirmedAccountDeletion(localRecovery: outcome.localRecovery)
    }
    func retrySignedOutCleanup() async -> AccountAuthState {
        guard current == nil else { return projectedState }
        var issues = cleanupCredentials()
        // Only explicit recovery may clear the marker after every credential is proven absent.
        if issues.isEmpty {
            do { try backend.remove(key: markerKey) }
            catch { issues.append(storageIssue(error, operation: .remove)) }
        }
        recovery = issues.first.map { AccountAuthRecovery(action: .cleanup, storageIssue: $0) }
        publish()
        return projectedState
    }
    func makeDailySyncRemote(userID: UUID? = nil) throws -> SupabaseDailySyncRemote {
        SupabaseDailySyncRemote(lease: try activeBinding(expectedUserID: userID))
    }
    func makeLiveMatchService() throws -> SupabaseLiveMatchService {
        SupabaseLiveMatchService(lease: try activeBinding(), clientBuild: clientBuild)
    }
    func makeLiveRealtimeService() throws -> SupabaseMatchRealtimeService {
        SupabaseMatchRealtimeService(lease: try activeBinding())
    }
    func makeLiveTransport(userID: UUID) throws -> LiveAccountTransport {
        let lease = try activeBinding(expectedUserID: userID)
        return LiveAccountTransport(userID: userID,
            service: SupabaseLiveMatchService(lease: lease, clientBuild: clientBuild),
            realtime: SupabaseMatchRealtimeService(lease: lease), refresh: { [weak self, lease] userID in
                guard userID == lease.userID, (try? lease.check()) != nil,
                      let refreshed = try? await self?.refreshSession() else { return false }
                return (try? lease.check()) != nil && refreshed.userID == userID
            }, isValid: { (try? lease.check()) != nil })
    }
    func applicationDidBecomeActive() { appActive = true; cancelScheduler(); startScheduler() }
    func applicationWillResignActive() { appActive = false; cancelScheduler() }
    private func cancelScheduler() { schedulerID = nil; scheduler?.cancel(); scheduler = nil }
    private func startScheduler() {
        guard appActive, phase == .active else { return }
        // Ordinary refresh does not repeatedly restart the tick interval.
        guard schedulerID == nil else { return }
        let id = UUID()
        schedulerID = id
        scheduler = Task { [weak self, sleep] in
            while !Task.isCancelled {
                guard self?.schedulerID == id else { return }
                await self?.automaticTick()
                do { try await sleep(.seconds(30)) } catch { return }
            }
        }
    }
    func automaticTick() async {
        guard appActive, phase == .active, let lifetime = current, let verified else { return }
        let ticks = Int((verified.expiresAt - clock().timeIntervalSince1970) / 30)
        guard ticks <= 3 else { return }
        do {
            let session = try await lifetime.client.auth.refreshSession()
            _ = try commit(session, from: lifetime)
        } catch {
            if let issue = lifetime.storage.issue { blockForRestore(lifetime, issue: issue) }
        }
    }
    private static func accountSession(_ session: Session) -> AccountSession {
        AccountSession(userID: session.user.id, expiresAt: Date(timeIntervalSince1970: session.expiresAt))
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
    case needsRecovery
}
