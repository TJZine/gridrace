import Foundation
import Security
import Supabase

/// Matches the SDK's existing Apple Keychain namespace, but makes absence a normal result.
final class SecureAuthStorage: AuthLocalStorage, @unchecked Sendable {
    struct Operations: @unchecked Sendable {
        var read: ([String: Any]) -> (OSStatus, Data?)
        var add: ([String: Any]) -> OSStatus
        var update: ([String: Any], [String: Any]) -> OSStatus
        var delete: ([String: Any]) -> OSStatus
        static let live = Operations(
            read: { query in
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return (status, result as? Data)
            },
            add: { SecItemAdd($0 as CFDictionary, nil) },
            update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
            delete: { SecItemDelete($0 as CFDictionary) }
        )
    }
    private let operations: Operations
    private let service: String
    init(service: String = "supabase.gotrue.swift", operations: Operations = .live) {
        self.service = service
        self.operations = operations
    }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    func retrieve(key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = operations.read(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthStorageIssue(operation: .read, status: status) }
        guard let data else { throw AuthStorageIssue(operation: .read, status: errSecDecode) }
        return data
    }
    func store(key: String, value: Data) throws {
        var addition = query(key)
        addition[kSecValueData as String] = value
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = operations.add(addition)
        if status == errSecDuplicateItem {
            let updated = operations.update(query(key), [kSecValueData as String: value])
            guard updated == errSecSuccess else { throw AuthStorageIssue(operation: .store, status: updated) }
        } else if status != errSecSuccess {
            throw AuthStorageIssue(operation: .store, status: status)
        }
    }
    func remove(key: String) throws {
        let status = operations.delete(query(key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthStorageIssue(operation: .remove, status: status)
        }
    }
}

/// Irreversible SDK storage authority. Old SDK migration removes cannot erase a later login.
final class AuthStorageGate: AuthLocalStorage, @unchecked Sendable {
    private enum Mode { case open, logout(Data?), retired }
    private let lock = NSLock()
    private var mode = Mode.open
    private var failure: AuthStorageIssue?
    private let backend: any AuthLocalStorage
    let sessionKey: String
    init(backend: any AuthLocalStorage, sessionKey: String) {
        self.backend = backend
        self.sessionKey = sessionKey
    }
    var issue: AuthStorageIssue? { lock.withLock { failure } }
    func resetIssue() { lock.withLock { failure = nil } }
    func beginLogout(snapshot: Session?) {
        lock.withLock { mode = .logout(snapshot.flatMap { try? JSONEncoder().encode($0) }) }
    }
    func close() { lock.withLock { mode = .retired } }
    private func record(_ error: any Error, operation: AuthStorageIssue.Operation) -> AuthStorageIssue {
        let issue = (error as? AuthStorageIssue) ?? AuthStorageIssue(operation: operation, status: errSecInternalComponent)
        if failure == nil { failure = issue }
        return issue
    }
    func retrieve(key: String) throws -> Data? {
        try lock.withLock {
            switch mode {
            case .retired: return nil
            case .logout(let snapshot): return key == sessionKey ? snapshot : nil
            case .open:
                do { return try backend.retrieve(key: key) }
                catch { throw record(error, operation: .read) }
            }
        }
    }
    func store(key: String, value: Data) throws {
        try lock.withLock {
            guard case .open = mode else { throw CancellationError() }
            do { try backend.store(key: key, value: value) }
            catch { throw record(error, operation: .store) }
        }
    }
    func remove(key: String) throws {
        try lock.withLock {
            switch mode {
            case .retired: return
            case .logout:
                guard key == sessionKey else { return }
                mode = .retired // SDK has acquired its logout bearer before this remove.
            case .open: break
            }
            do { try backend.remove(key: key) }
            catch { throw record(error, operation: .remove) }
        }
    }
}

final class AuthClientLifetime: @unchecked Sendable {
    struct ChannelRegistration: Sendable {
        let id: UUID
        let channel: RealtimeChannelV2
        let finish: @Sendable () -> Void
    }
    let client: SupabaseClient
    let storage: AuthStorageGate
    private let lock = NSLock()
    private var valid = false
    private var retired = false
    private var generation = 0
    private var intendedUserID: UUID?
    private var channels: [UUID: ChannelRegistration] = [:]
    private let beforeChannelRemoval: @Sendable () async -> Void
    init(client: SupabaseClient, storage: AuthStorageGate,
         beforeChannelRemoval: @escaping @Sendable () async -> Void = {}) {
        self.client = client
        self.storage = storage
        self.beforeChannelRemoval = beforeChannelRemoval
    }
    func bindIdentity(_ userID: UUID) throws {
        try lock.withLock {
            guard intendedUserID == nil || intendedUserID == userID else { throw CancellationError() }
            intendedUserID = userID
        }
    }
    func activate() throws {
        try lock.withLock {
            guard !retired else { throw CancellationError() }
            valid = true
        }
    }
    func leaseGeneration() throws -> Int {
        try lock.withLock {
            guard valid && !retired else { throw CancellationError() }
            return generation
        }
    }
    func check(generation expected: Int) throws {
        try lock.withLock { guard valid && !retired && generation == expected else { throw CancellationError() } }
    }
    func registerChannel(topic: String, generation expected: Int, finish: @escaping @Sendable () -> Void) throws -> ChannelRegistration {
        try lock.withLock {
            guard valid && !retired else { throw CancellationError() }
            guard generation == expected else { throw CancellationError() }
            let registration = ChannelRegistration(id: UUID(), channel: client.channel(topic), finish: finish)
            channels[registration.id] = registration // Registered BEFORE any subscription await.
            return registration
        }
    }
    func block() -> [ChannelRegistration] {
        let owned = lock.withLock {
            valid = false
            generation += 1
            let owned = Array(channels.values)
            channels.removeAll()
            return owned
        }
        client.realtimeV2.disconnect()
        for registration in owned { registration.finish() }
        return owned
    }
    /// Disconnect is synchronous and precedes all storage/logout suspensions.
    func retireConsumers() -> [ChannelRegistration] {
        let owned = lock.withLock {
            valid = false
            retired = true
            generation += 1
            let owned = Array(channels.values)
            channels.removeAll()
            return owned
        }
        client.realtimeV2.disconnect()
        for registration in owned { registration.finish() }
        return owned
    }
    func removeChannel(_ registration: ChannelRegistration) async {
        let owns = lock.withLock { channels.removeValue(forKey: registration.id) != nil }
        guard owns else { return }
        await registration.channel.unsubscribe() // Also cancels SDK .subscribing task.
        await client.removeChannel(registration.channel)
    }
    func finishRetirement(_ owned: [ChannelRegistration]) async {
        for registration in owned {
            await beforeChannelRemoval()
            await registration.channel.unsubscribe()
            client.realtimeV2.disconnect()
            await client.removeChannel(registration.channel)
        }
        client.realtimeV2.disconnect()
    }
}

struct AuthClientLease: Sendable {
    let lifetime: AuthClientLifetime
    let userID: UUID
    let generation: Int
    init(lifetime: AuthClientLifetime, userID: UUID) throws {
        self.lifetime = lifetime
        self.userID = userID
        generation = try lifetime.leaseGeneration()
    }
    func check() throws { try lifetime.check(generation: generation) }
    func perform<Value: Sendable>(
        _ operation: @Sendable (SupabaseClient) async throws -> Value
    ) async throws -> Value {
        try check()
        let value = try await operation(lifetime.client)
        try check()
        try Task.checkCancellation()
        return value
    }
}

struct LiveAccountTransport: Sendable {
    let userID: UUID
    let service: any LiveMatchServicing
    let realtime: (any LiveMatchRealtimeServicing)?
    let refresh: @MainActor @Sendable (UUID) async -> Bool
    let isValid: @Sendable () -> Bool
}
