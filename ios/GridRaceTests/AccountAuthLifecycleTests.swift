import Foundation
import Security
import Supabase
import UIKit
import XCTest
@testable import GridRace

private final class AuthMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var failures: [String: AuthStorageIssue] = [:]
    private var removals: [String] = []
    private var replacements: [String: Data] = [:]
    private var droppedWrites: Set<String> = []
    func dropWrites(key: String) { lock.withLock { _ = droppedWrites.insert(key) } }
    func replaceWrites(key: String, with bytes: Data) { lock.withLock { replacements[key] = bytes } }
    func fail(_ operation: AuthStorageIssue.Operation, key: String, status: Int32 = errSecInteractionNotAllowed) {
        lock.withLock { failures["\(operation)-\(key)"] = AuthStorageIssue(operation: operation, status: status) }
    }
    func recover() { lock.withLock { failures.removeAll() } }
    func removed(_ key: String) -> Bool { lock.withLock { removals.contains(key) } }
    func store(key: String, value: Data) throws {
        try lock.withLock {
            if let issue = failures["store-\(key)"] { throw issue }
            if !droppedWrites.contains(key) { values[key] = replacements[key] ?? value }
        }
    }
    func retrieve(key: String) throws -> Data? {
        try lock.withLock {
            if let issue = failures["read-\(key)"] { throw issue }
            return values[key]
        }
    }
    func remove(key: String) throws {
        try lock.withLock {
            removals.append(key)
            if let issue = failures["remove-\(key)"] { throw issue }
            values[key] = nil
        }
    }
}

private actor AuthHTTPFixture {
    var userID = UUID()
    var expiry: TimeInterval = 3600
    var failsRefresh = false
    var failsRefreshHTTP = false
    var deletionPayload = Data(#"{"data":{"deleted":true}}"#.utf8)
    var profilePayload: Data?
    var profileSavePayload: Data?
    var profileSaveStatus = 200
    var lastProfileBody: Data?
    var lastProfileURL: URL?
    var holds: Set<String> = []
    var pending: [String: CheckedContinuation<Void, Never>] = [:]
    var requests: [String] = []
    func setUser(_ userID: UUID) { self.userID = userID }
    func setDeletionPayload(_ bytes: Data) { deletionPayload = bytes }
    func setProfilePayload(_ bytes: Data) { profilePayload = bytes }
    func setProfileSaveResponse(_ bytes: Data, status: Int) {
        profileSavePayload = bytes
        profileSaveStatus = status
    }
    func profileRequest() -> (body: Data?, url: URL?) { (lastProfileBody, lastProfileURL) }
    func setExpiry(_ seconds: TimeInterval) { expiry = seconds }
    func failRefresh(_ fail: Bool) { failsRefresh = fail }
    func failRefreshWithoutRetry(_ fail: Bool) { failsRefreshHTTP = fail }
    func hold(_ route: String) { holds.insert(route) }
    func suspended(_ route: String) -> Bool { pending[route] != nil }
    func release(_ route: String) { pending.removeValue(forKey: route)?.resume() }
    func count(_ route: String) -> Int { requests.filter { $0 == route }.count }
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let refresh = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains {
            $0.name == "grant_type" && $0.value == "refresh_token"
        } == true
        let route = refresh ? "refresh" : url.lastPathComponent
        requests.append(route)
        let now = Date(), user = userID, duration = expiry
        let session = Session(accessToken: "synthetic-access-\(requests.count)", tokenType: "bearer", expiresIn: duration,
            expiresAt: now.addingTimeInterval(duration).timeIntervalSince1970,
            refreshToken: "synthetic-refresh-\(requests.count)",
            user: User(id: user, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now))
        if holds.remove(route) != nil { await withCheckedContinuation { pending[route] = $0 } }
        if refresh && failsRefreshHTTP {
            return (Data(#"{"error":"synthetic refresh rejection","error_code":"bad_request"}"#.utf8),
                HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        if refresh && failsRefresh { throw URLError(.notConnectedToInternet) }
        let data: Data
        switch route {
        case "logout": data = Data()
        case "delete-account": data = deletionPayload
        case "create-match":
            data = try JSONSerialization.data(withJSONObject: ["data": ["match_id": user.uuidString]])
        case "profiles":
            if request.httpMethod == "PATCH" {
                lastProfileBody = try body(request)
                lastProfileURL = url
                if let profileSavePayload {
                    if profileSaveStatus != 200 {
                        return (profileSavePayload, HTTPURLResponse(url: url, statusCode: profileSaveStatus,
                            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
                    }
                    profilePayload = profileSavePayload
                }
            }
            if let profilePayload {
                data = profilePayload
            } else {
                let profile = PlayerProfile(userID: user, displayName: "Fixture", avatarSeed: "fixture", setupCompleted: true, createdAt: now, updatedAt: now)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                data = try encoder.encode(profile)
            }
        case "daily_progress", "daily_imported_results": data = Data("[]".utf8)
        default: data = try AuthClient.Configuration.jsonEncoder.encode(session)
        }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                     headerFields: ["Content-Type": "application/json"])!)
    }

    private func body(_ request: URLRequest) throws -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}

private final class AuthFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: AuthHTTPFixture] = [:]
    private var loading: Task<Void, Never>?
    static func install(_ fixture: AuthHTTPFixture, host: String) { lock.withLock { fixtures[host] = fixture } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasPrefix("auth-fixture-") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fixture = Self.lock.withLock { Self.fixtures[request.url!.host!]! }
        loading = Task {
            do {
                let (data, response) = try await fixture.fetch(request)
                try Task.checkCancellation()
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { loading?.cancel() }
}

@MainActor
final class AccountAuthLifecycleTests: XCTestCase {
    private func service(_ fixture: AuthHTTPFixture, storage: AuthMemoryStorage,
                         host: String? = nil, clock: @escaping @Sendable () -> Date = Date.init,
                         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                         notificationCenter: NotificationCenter = NotificationCenter(),
                         beforeChannelRemoval: @escaping @Sendable () async -> Void = {}) -> SupabaseAccountService {
        let host = host ?? "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        AuthFixtureProtocol.install(fixture, host: host)
        return SupabaseAccountService(configuration: .init(urlString: "https://\(host)", publishableKey: "synthetic-public")!,
            storage: storage, network: {
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [AuthFixtureProtocol.self]
                return URLSession(configuration: config)
            }, clock: clock, sleep: sleep, notificationCenter: notificationCenter,
            beforeChannelRemoval: beforeChannelRemoval)
    }
    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 { if await condition() { return }; try await Task.sleep(for: .milliseconds(2)) }
        XCTFail("Controlled Auth condition did not settle")
    }
    private func login(_ service: SupabaseAccountService) async throws -> AccountSession {
        try await service.signInForLocalTesting(email: "fixture@example.invalid", password: "synthetic")
    }

    func testProfileServiceRequiresExplicitBooleanForLoadAndSaveResponses() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let signedIn = try await login(service)
        for completed in [false, true] {
            let bytes = try profileWire(userID: signedIn.userID, completion: completed)
            await http.setProfilePayload(bytes)
            await http.setProfileSaveResponse(bytes, status: 200)
            let loaded = try await service.loadProfile(userID: signedIn.userID)
            let saved = try await service.updateProfile(userID: signedIn.userID, displayName: "Player abcdef", avatarSeed: "fixture")
            XCTAssertEqual(loaded.setupCompleted, completed)
            XCTAssertEqual(saved.setupCompleted, completed)
            XCTAssertEqual(saved.displayName, "Player abcdef")
        }
        let invalidStates: [Any?] = [nil, NSNull(), "true", 1, [], [:]]
        for invalid in invalidStates {
            let bytes = try profileWire(userID: signedIn.userID, completion: invalid)
            await http.setProfilePayload(bytes)
            await http.setProfileSaveResponse(bytes, status: 200)
            do { _ = try await service.loadProfile(userID: signedIn.userID); XCTFail("Malformed profile load accepted") }
            catch { XCTAssertTrue(error is DecodingError) }
            do { _ = try await service.updateProfile(userID: signedIn.userID, displayName: "Player abcdef", avatarSeed: "fixture")
                XCTFail("Malformed profile Save response accepted") }
            catch { XCTAssertTrue(error is DecodingError) }
        }
        _ = await service.signOut()
    }

    func testProductionProfileSameValueSaveFailureRetryAndRestoreUseServerCompletion() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let signedIn = try await login(first)
        await http.setProfilePayload(try profileWire(userID: signedIn.userID, completion: false))
        let model = AccountModel(service: first)
        await model.start()
        try await wait { !model.isLoadingProfile && model.profile != nil }
        XCTAssertTrue(model.needsProfileSetup)
        XCTAssertEqual(model.displayNameDraft, "Player abcdef")

        let requestCount = await http.count("profiles")
        do { _ = try await first.loadProfile(userID: UUID()); XCTFail("Wrong owner profile load dispatched") }
        catch is CancellationError {}
        do { _ = try await first.updateProfile(userID: UUID(), displayName: "Player abcdef", avatarSeed: "fixture")
            XCTFail("Wrong owner profile Save dispatched") }
        catch is CancellationError {}
        let requestsAfterWrongOwner = await http.count("profiles")
        XCTAssertEqual(requestsAfterWrongOwner, requestCount)

        await http.setProfileSaveResponse(Data(#"{"code":"23514","message":"invalid profile"}"#.utf8), status: 400)
        await model.saveProfile()
        XCTAssertTrue(model.needsProfileSetup)
        XCTAssertNotNil(model.errorMessage)
        let unchanged = try await first.loadProfile(userID: signedIn.userID)
        XCTAssertFalse(unchanged.setupCompleted)
        await http.setProfileSaveResponse(try profileWire(userID: signedIn.userID, completion: true), status: 200)
        await model.saveProfile()
        XCTAssertFalse(model.needsProfileSetup)
        XCTAssertEqual(model.profile?.displayName, "Player abcdef")
        let request = await http.profileRequest()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(body, ["display_name": "Player abcdef", "avatar_seed": "fixture"])
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertTrue(query?.contains { $0.name == "id" && $0.value?.lowercased() == "eq.\(signedIn.userID.uuidString.lowercased())" } == true)

        // A fresh production owner restores the same SDK session and reloads the server profile.
        let restoredService = service(http, storage: storage, host: host)
        let restored = AccountModel(service: restoredService)
        await restored.start()
        try await wait { !restored.isLoadingProfile && restored.profile != nil }
        XCTAssertEqual(restored.profile?.setupCompleted, true)
        XCTAssertEqual(restored.profile?.displayName, "Player abcdef")
        XCTAssertFalse(restored.needsProfileSetup)
        _ = await restoredService.signOut()
        _ = await first.signOut()
    }

    private func profileWire(userID: UUID, completion: Any?) throws -> Data {
        var profile: [String: Any] = ["id": userID.uuidString, "display_name": "Player abcdef", "avatar_seed": "fixture",
            "created_at": "2026-10-08T12:00:00Z", "updated_at": "2026-10-08T12:00:00Z"]
        if let completion { profile["setup_completed"] = completion }
        return try JSONSerialization.data(withJSONObject: profile)
    }
    func testHeldRefreshSignOutAndIntentionalSameOrOtherAccount() async throws {
        for sameUser in [true, false] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
            let initial = try await login(service)
            let old = try service.activeBinding()
            await http.hold("refresh")
            let refreshing = Task { try await service.refreshSession() }
            try await wait { await http.suspended("refresh") }
            _ = await service.signOut()
            XCTAssertNil(old.lifetime.client.auth.currentSession)
            XCTAssertNil(try storage.retrieve(key: service.sessionKey))
            XCTAssertThrowsError(try service.activeBinding())
            let next = sameUser ? initial.userID : UUID()
            await http.setUser(next)
            let signedIn = try await login(service)
            await http.release("refresh")
            do { _ = try await refreshing.value; XCTFail("Obsolete result accepted") } catch is CancellationError {}
            XCTAssertEqual(signedIn.userID, next)
            XCTAssertEqual(try service.activeBinding().userID, next)
            XCTAssertNil(old.lifetime.client.auth.currentSession)
            let persisted = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: service.sessionKey)))
            XCTAssertEqual(persisted.user.id, next)
            let refreshed = try await service.refreshSession()
            XCTAssertEqual(refreshed?.userID, next)
            let cloud = try await service.makeDailySyncRemote().pull()
            XCTAssertTrue(cloud.importedResults.isEmpty)
            _ = await service.signOut()
        }
    }
    func testOfflineExpiredColdRestoreKeepsCredentialsAndRetries() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let initial = try await login(first)
        var saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: first.sessionKey)))
        saved.expiresAt = Date().addingTimeInterval(-120).timeIntervalSince1970
        try storage.store(key: first.sessionKey, value: JSONEncoder().encode(saved))
        await http.failRefresh(true)
        let restored = service(http, storage: storage, host: host)
        do { _ = try await restored.restoreSession(); XCTFail("Offline restore should fail") } catch {}
        XCTAssertNotNil(try storage.retrieve(key: restored.sessionKey))
        XCTAssertThrowsError(try restored.activeBinding())
        await http.failRefresh(false)
        let retried = try await restored.restoreSession()
        XCTAssertEqual(retried?.userID, initial.userID)
        XCTAssertEqual(try restored.activeBinding().userID, initial.userID)
        _ = await restored.signOut()
    }
    func testMarkerFailureFencesBeforeLogoutAndAttemptsEveryScopedDelete() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        _ = try await login(service)
        let old = try service.activeBinding()
        let key = service.sessionKey, marker = key + "-gridrace-retired-v1"
        storage.fail(.store, key: marker)
        for target in [key, "supabase.session", key + "-code-verifier"] { storage.fail(.remove, key: target) }
        await http.hold("logout")
        let signingOut = Task { await service.signOut() }
        try await wait { await http.suspended("logout") }
        XCTAssertThrowsError(try old.check())
        XCTAssertThrowsError(try service.activeBinding())
        await http.release("logout")
        let outcome = await signingOut.value
        XCTAssertNotNil(outcome.localRecovery)
        for target in [key, "supabase.session", key + "-code-verifier"] { XCTAssertTrue(storage.removed(target)) }
        XCTAssertNil(old.lifetime.client.auth.currentSession)
        storage.recover()
        let recovered = await service.retrySignedOutCleanup()
        XCTAssertNil(recovered.recovery)
        _ = try await login(service)
        _ = await service.signOut()
    }
    func testFailedDurableCandidateCannotPublishOrLease() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        storage.fail(.store, key: service.sessionKey)
        do { _ = try await login(service); XCTFail("Undurable SDK success must fail") } catch {}
        XCTAssertThrowsError(try service.activeBinding())
        XCTAssertNil(try storage.retrieve(key: service.sessionKey))
        storage.recover()
        _ = await service.retrySignedOutCleanup()
        _ = try await login(service)
        _ = await service.signOut()
    }
    func testConfirmedDeletionCarriesAuthTroubleAndRunsCapturedCleanup() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let session = try await login(service)
        var cleaned: [UUID] = []
        let model = AccountModel(service: service, didDeleteAccount: { cleaned.append($0) })
        await model.start()
        try await wait { model.session?.userID == session.userID }
        storage.fail(.store, key: service.sessionKey + "-gridrace-retired-v1")
        storage.fail(.remove, key: service.sessionKey)
        await model.deleteAccount()
        XCTAssertEqual(cleaned, [session.userID])
        XCTAssertNil(model.session)
        XCTAssertEqual(model.authRecovery?.action, .cleanup)
        XCTAssertTrue(model.errorMessage?.contains("account was deleted") == true)
        storage.recover()
        await model.retryAuthRecovery()
        XCTAssertNil(model.authRecovery)
    }
    func testOwnedAutoTickRetainsRetiredLifetimeAndForegroundLaterSignIn() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let future = Date().addingTimeInterval(3560)
        let service = service(http, storage: storage, clock: { future })
        service.applicationWillResignActive()
        _ = try await login(service)
        let old = try service.activeBinding()
        await http.hold("refresh")
        service.applicationDidBecomeActive()
        try await wait { await http.suspended("refresh") }
        _ = await service.signOut()
        let next = UUID()
        await http.setUser(next)
        await http.release("refresh")
        _ = try await login(service) // Still foreground: no second UIKit event is required.
        try await wait { await http.count("refresh") >= 2 }
        XCTAssertEqual(try service.activeBinding().userID, next)
        XCTAssertNil(old.lifetime.client.auth.currentSession)
        service.applicationWillResignActive()
        _ = await service.signOut()
    }
}

final class SecureAuthStorageTests: XCTestCase {
    func testAbsenceNormalizationExactNamespaceAndDuplicateUpdate() throws {
        var queries: [[String: Any]] = []
        let operations = SecureAuthStorage.Operations(
            read: { query in queries.append(query); return (errSecItemNotFound, nil) },
            add: { query in queries.append(query); return errSecDuplicateItem },
            update: { query, attrs in
                queries.append(query)
                XCTAssertEqual(attrs.count, 1)
                XCTAssertNotNil(attrs[kSecValueData as String])
                return errSecSuccess
            }, delete: { query in queries.append(query); return errSecItemNotFound })
        let storage = SecureAuthStorage(operations: operations)
        XCTAssertNil(try storage.retrieve(key: "canonical"))
        try storage.remove(key: "canonical")
        try storage.store(key: "canonical", value: Data([1]))
        for query in queries {
            XCTAssertEqual(query[kSecAttrService as String] as? String, "supabase.gotrue.swift")
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "canonical")
            XCTAssertNil(query[kSecAttrAccessGroup as String])
            XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        }
        XCTAssertEqual(queries[2][kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String)
    }
    func testUnexpectedStatusAndInvalidDataRemainTypedFailures() {
        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecParam] {
            let storage = SecureAuthStorage(operations: .init(read: { _ in (status, nil) }, add: { _ in status },
                update: { _, _ in status }, delete: { _ in status }))
            XCTAssertThrowsError(try storage.retrieve(key: "test")) { XCTAssertEqual(($0 as? AuthStorageIssue)?.status, status) }
            XCTAssertThrowsError(try storage.remove(key: "test"))
            XCTAssertThrowsError(try storage.store(key: "test", value: Data()))
        }
        let invalid = SecureAuthStorage(operations: .init(read: { _ in (errSecSuccess, nil) }, add: { _ in errSecSuccess },
            update: { _, _ in errSecSuccess }, delete: { _ in errSecSuccess }))
        XCTAssertThrowsError(try invalid.retrieve(key: "test"))
    }
    func testNativeSecurityRunOwnedKeySmokeAndCleanup() throws {
        let storage = SecureAuthStorage()
        let key = "gridrace-u2-smoke-\(UUID().uuidString)"
        XCTAssertNil(try storage.retrieve(key: key))
        defer { try? storage.remove(key: key) }
        try storage.store(key: key, value: Data([1]))
        XCTAssertEqual(try storage.retrieve(key: key), Data([1]))
        try storage.store(key: key, value: Data([2]))
        XCTAssertEqual(try storage.retrieve(key: key), Data([2]))
        try storage.remove(key: key)
        XCTAssertNil(try storage.retrieve(key: key))
        try storage.remove(key: key)
    }
}

@MainActor
extension AccountAuthLifecycleTests {
    func testMalformedCanonicalAndLegacyRemainUntilExplicitCleanup() async throws {
        for legacy in [false, true] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
            let key = legacy ? "supabase.session" : service.sessionKey
            let bytes = Data("{not a session}".utf8)
            try storage.store(key: key, value: bytes)
            try storage.store(key: "unrelated-account-key", value: Data([7]))
            let model = AccountModel(service: service)
            await model.start()
            try await wait { model.authRecovery?.action == .cleanup }
            XCTAssertNil(model.session)
            XCTAssertEqual(try storage.retrieve(key: key), bytes)
            do { _ = try await login(service); XCTFail("Malformed credentials require deliberate cleanup") } catch {}
            XCTAssertEqual(try storage.retrieve(key: key), bytes)
            await model.retryAuthRecovery()
            XCTAssertNil(try storage.retrieve(key: key))
            XCTAssertEqual(try storage.retrieve(key: "unrelated-account-key"), Data([7]))
            _ = try await login(service)
            _ = await service.signOut()
        }
    }
    func testExactLegacyEnvelopeMigratesAtRealSDKBoundary() async throws {
        struct Envelope: Encodable { let session: Session; let expirationDate: Date }
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let account = try await login(first)
        let saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: first.sessionKey)))
        try storage.remove(key: first.sessionKey)
        let legacy = try AuthClient.Configuration.jsonEncoder.encode(Envelope(session: saved,
            expirationDate: Date(timeIntervalSince1970: saved.expiresAt)))
        try storage.store(key: "supabase.session", value: legacy)
        let restored = service(http, storage: storage, host: host)
        let result = try await restored.restoreSession()
        XCTAssertEqual(result?.userID, account.userID)
        XCTAssertNil(try storage.retrieve(key: "supabase.session"))
        XCTAssertNotNil(try storage.retrieve(key: restored.sessionKey))
        _ = await restored.signOut()
    }
    func testExistingOfflineRestoreCanBeDeliberatelyRetiredWithoutGuessedUIIdentity() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let old = try await login(first)
        var saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: first.sessionKey)))
        saved.expiresAt = Date().addingTimeInterval(-120).timeIntervalSince1970
        try storage.store(key: first.sessionKey, value: JSONEncoder().encode(saved))
        await http.failRefresh(true)
        let restored = service(http, storage: storage, host: host)
        var cleaned: [UUID] = []
        let model = AccountModel(service: restored, didSignOut: { cleaned.append($0); return true })
        await model.start()
        try await wait { model.authRecovery?.action == .restore }
        XCTAssertNil(model.session)
        XCTAssertNotNil(try storage.retrieve(key: restored.sessionKey))
        await model.signOut()
        XCTAssertEqual(cleaned, [old.userID])
        XCTAssertNil(try storage.retrieve(key: restored.sessionKey))
        await http.failRefresh(false)
        await http.setUser(UUID())
        _ = try await login(restored)
        _ = await restored.signOut()
    }
    func testBlockedRestorationDoesNotReenablePreblockLease() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let user = try await login(service)
        let oldLease = try service.activeBinding()
        storage.fail(.read, key: service.sessionKey)
        do { _ = try await service.refreshSession(); XCTFail("Storage error must block active consumers") } catch {}
        XCTAssertThrowsError(try oldLease.check())
        storage.recover()
        let result = try await service.restoreSession()
        XCTAssertEqual(result?.userID, user.userID)
        XCTAssertThrowsError(try oldLease.check(), "Same lifetime restoration cannot reopen an older lease generation")
        XCTAssertNoThrow(try service.activeBinding().check())
        _ = await service.signOut()
    }
    func testFailedMarkerRemovalRetiresCandidateAndHasRealRetry() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        storage.fail(.remove, key: service.sessionKey + "-gridrace-retired-v1")
        let model = AccountModel(service: service)
        await model.start()
        await model.signInForLocalTesting(email: "fixture@example.invalid", password: "synthetic")
        try await wait { model.authRecovery?.action == .cleanup }
        XCTAssertNil(model.session)
        XCTAssertThrowsError(try service.activeBinding())
        XCTAssertNil(try storage.retrieve(key: service.sessionKey))
        await model.retryAuthRecovery()
        XCTAssertNotNil(model.authRecovery)
        storage.recover()
        await model.retryAuthRecovery()
        XCTAssertNil(model.authRecovery)
        _ = try await login(service)
        _ = await service.signOut()
    }
}

private final class AuthTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date()
    func advance(_ seconds: TimeInterval) { lock.withLock { now.addTimeInterval(seconds) } }
    func set(_ date: Date) { lock.withLock { now = date } }
    func read() -> Date { lock.withLock { now } }
}

private actor AuthTestSleeper {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var intervals: [Duration] = []
    func sleep(_ duration: Duration) async throws {
        intervals.append(duration)
        await withCheckedContinuation { pending.append($0) }
        try Task.checkCancellation()
    }
    func release() { let captured = pending; pending.removeAll(); for wait in captured { wait.resume() } }
    func count() -> Int { intervals.count }
}

@MainActor
extension AccountAuthLifecycleTests {
    func testCancelledCandidateCannotActivateAfterHeldSDKResponse() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        await http.hold("token")
        let candidate = Task { try await login(service) }
        try await wait { await http.suspended("token") }
        candidate.cancel()
        await http.release("token")
        do { _ = try await candidate.value; XCTFail("Cancelled candidate must not activate") } catch {}
        XCTAssertThrowsError(try service.activeBinding())
        XCTAssertNil(try storage.retrieve(key: service.sessionKey))
        _ = await service.retrySignedOutCleanup()
        _ = try await login(service)
        _ = await service.signOut()
    }

    func testCandidateReadbackMismatchCannotPublishOrLease() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        storage.replaceWrites(key: service.sessionKey, with: Data("{}".utf8))
        do { _ = try await login(service); XCTFail("Mismatched persisted session must not activate") } catch {}
        XCTAssertThrowsError(try service.activeBinding())
        XCTAssertNil(try storage.retrieve(key: service.sessionKey))
    }

    func testHeldProfileCannotReturnAfterRetirementAndLaterLogin() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let first = try await login(service)
        await http.hold("profiles")
        let profile = Task { try await service.loadProfile(userID: first.userID) }
        try await wait { await http.suspended("profiles") }
        _ = await service.signOut()
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        await http.release("profiles")
        do { _ = try await profile.value; XCTFail("Old profile result must fail its captured lease") } catch {}
        XCTAssertEqual(try service.activeBinding().userID, next)
        _ = await service.signOut()
    }

    func testConfirmedOldDeletionDoesNotRetireNewerLogin() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        _ = try await login(service)
        await http.hold("delete-account")
        let deletion = Task { try await service.deleteAccount() }
        try await wait { await http.suspended("delete-account") }
        _ = await service.signOut()
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        await http.release("delete-account")
        let confirmed = try await deletion.value
        XCTAssertNil(confirmed.localRecovery)
        XCTAssertEqual(try service.activeBinding().userID, next)
        XCTAssertNotNil(try storage.retrieve(key: service.sessionKey))
        _ = await service.signOut()
    }

    func testUIKitSchedulerImmediateTickIntervalFailureRetryAndInactiveCancellation() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), clock = AuthTestClock(), sleeper = AuthTestSleeper()
        let notifications = NotificationCenter()
        let service = service(http, storage: storage, clock: { clock.read() },
            sleep: { try await sleeper.sleep($0) }, notificationCenter: notifications)
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        _ = try await login(service)
        let refreshCount0 = await http.count("refresh")
        XCTAssertEqual(refreshCount0, 0)
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await wait { await sleeper.count() == 1 }
        let refreshCount1 = await http.count("refresh")
        XCTAssertEqual(refreshCount1, 0)
        clock.advance(3500) // SDK's integer tick policy includes the <=3-tick window.
        await http.failRefreshWithoutRetry(true)
        await sleeper.release()
        try await wait {
            let requests = await http.count("refresh"), intervals = await sleeper.count()
            return requests == 1 && intervals == 2
        }
        await http.failRefreshWithoutRetry(false)
        await sleeper.release()
        try await wait {
            let requests = await http.count("refresh"), intervals = await sleeper.count()
            return requests == 2 && intervals == 3
        }
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        await sleeper.release()
        await Task.yield()
        let refreshCount2 = await http.count("refresh")
        XCTAssertEqual(refreshCount2, 2)
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await wait {
            let requests = await http.count("refresh"), intervals = await sleeper.count()
            return requests == 3 && intervals == 4
        }
        _ = await service.signOut()
        await sleeper.release()
        await Task.yield()
        let refreshCount3 = await http.count("refresh")
        XCTAssertEqual(refreshCount3, 3)
        let intervals = await sleeper.intervals
        XCTAssertTrue(intervals.allSatisfy { $0 == .seconds(30) })
    }

    func testRealSDKSubscribingChannelRetirementFinishesStreamAndRemovesOwnedChannel() async throws {
        for blockOnly in [false, true] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
            _ = try await login(service)
            let old = try service.activeBinding()
            let events = try service.makeLiveRealtimeService().events(matchID: UUID())
            let consuming = Task { () -> Int in
                var count = 0
                do { for try await _ in events { count += 1 } } catch {}
                return count
            }
            try await wait { old.lifetime.client.realtimeV2.channels.values.contains { $0.status == .subscribing } }
            let channel = try XCTUnwrap(old.lifetime.client.realtimeV2.channels.values.first)
            if blockOnly {
                storage.fail(.read, key: service.sessionKey)
                do { _ = try await service.refreshSession(); XCTFail("Expected reversible storage block") } catch {}
                storage.recover()
            } else { _ = await service.signOut() }
            XCTAssertThrowsError(try old.check())
            try await wait { old.lifetime.client.realtimeV2.channels.isEmpty }
            XCTAssertEqual(channel.status, .unsubscribed)
            let received = await consuming.value
            XCTAssertEqual(received, 0)
            if blockOnly {
                _ = try await service.restoreSession()
                XCTAssertThrowsError(try old.check())
                XCTAssertNoThrow(try service.activeBinding().check())
                _ = await service.signOut()
            }
        }
    }
}

private actor AuthRemovalGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var held = false
    func checkpoint() async {
        guard !held else { return }
        held = true
        await withCheckedContinuation { continuation = $0 }
    }
    func isSuspended() -> Bool { continuation != nil }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
extension AccountAuthLifecycleTests {
    func testRestoreWaitsForCapturedChannelDrainBeforeFreshCapabilityOrEvents() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), removal = AuthRemovalGate()
        let service = service(http, storage: storage, beforeChannelRemoval: { await removal.checkpoint() })
        _ = try await login(service)
        let old = try service.activeBinding()
        let oldEvents = try service.makeLiveRealtimeService().events(matchID: UUID())
        let consuming = Task { do { for try await _ in oldEvents {} } catch {} }
        try await wait { old.lifetime.client.realtimeV2.channels.values.contains { $0.status == .subscribing } }
        storage.fail(.read, key: service.sessionKey)
        do { _ = try await service.refreshSession(); XCTFail("Expected storage block") } catch {}
        try await wait { await removal.isSuspended() }
        storage.recover()
        let restoration = Task { try await service.restoreSession() }
        await Task.yield()
        let saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: service.sessionKey)))
        service.receive(.tokenRefreshed, session: saved, from: old.lifetime) // Simulated queued SDK payload.
        XCTAssertThrowsError(try service.activeBinding(), "Neither explicit restore nor event can bypass the owned drain")
        XCTAssertThrowsError(try old.check())
        await removal.release()
        _ = try await restoration.value
        await consuming.value
        XCTAssertTrue(old.lifetime.client.realtimeV2.channels.isEmpty)
        let fresh = try service.activeBinding()
        let freshEvents = try service.makeLiveRealtimeService().events(matchID: UUID())
        let freshConsuming = Task { do { for try await _ in freshEvents {} } catch {} }
        try await wait { fresh.lifetime.client.realtimeV2.channels.values.contains { $0.status == .subscribing } }
        await Task.yield()
        XCTAssertNoThrow(try fresh.check())
        XCTAssertEqual(fresh.lifetime.client.realtimeV2.channels.count, 1)
        XCTAssertThrowsError(try old.check())
        _ = await service.signOut()
        await freshConsuming.value
    }

    func testQueuedNilAndStalePayloadUseCurrentPersistedSessionWhileActualAbsenceBlocks() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let original = try await login(service), binding = try service.activeBinding()
        let older = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: service.sessionKey)))
        service.receive(.initialSession, session: nil, from: binding.lifetime) // Explicit simulated late initial tuple.
        XCTAssertEqual(try service.activeBinding().userID, original.userID)
        let refreshed = try await service.refreshSession()
        let renewedBytes = try XCTUnwrap(storage.retrieve(key: service.sessionKey))
        service.receive(.tokenRefreshed, session: older, from: binding.lifetime)
        XCTAssertEqual(try storage.retrieve(key: service.sessionKey), renewedBytes)
        XCTAssertEqual(try service.activeBinding().userID, refreshed?.userID)
        try storage.remove(key: service.sessionKey)
        service.receive(.initialSession, session: nil, from: binding.lifetime)
        XCTAssertThrowsError(try service.activeBinding())
        XCTAssertThrowsError(try binding.check())
        _ = await service.signOut()
    }

    func testHeldDailyResultsAreRejectedAfterLaterLoginAndOldAdapterNeverDispatchesAgain() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        _ = try await login(service)
        let remote = try service.makeDailySyncRemote()
        await http.hold("daily_imported_results")
        let pulling = Task { try await remote.pull() }
        try await wait { await http.suspended("daily_imported_results") }
        _ = await service.signOut()
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        await http.release("daily_imported_results")
        do { _ = try await pulling.value; XCTFail("Old Daily page must be rejected") } catch {}
        let oldCount = await http.count("daily_imported_results")
        do { _ = try await remote.pull(); XCTFail("Retired adapter must not dispatch") } catch {}
        let finalCount = await http.count("daily_imported_results")
        XCTAssertEqual(finalCount, oldCount)
        XCTAssertEqual(try service.activeBinding().userID, next)
        _ = await service.signOut()
    }
}

@MainActor
extension AccountAuthLifecycleTests {
    func testCandidateAbsentWrongIdentityAndDifferentValidReadbackAllFailClosed() async throws {
        for variant in ["absent", "identity", "credentials"] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
            if variant == "absent" { storage.dropWrites(key: service.sessionKey) }
            else {
                let id = variant == "identity" ? UUID() : await http.userID
                let now = Date()
                let different = Session(accessToken: "synthetic-other-access", tokenType: "bearer", expiresIn: 3600,
                    expiresAt: now.addingTimeInterval(3600).timeIntervalSince1970, refreshToken: "synthetic-other-refresh",
                    user: User(id: id, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now))
                storage.replaceWrites(key: service.sessionKey, with: try JSONEncoder().encode(different))
            }
            do { _ = try await login(service); XCTFail("Unverified \(variant) candidate must not activate") } catch {}
            XCTAssertThrowsError(try service.activeBinding())
            XCTAssertNil(try storage.retrieve(key: service.sessionKey))
        }
    }

    func testRealLiveCommandCapturedLeaseRejectsHeldResponseAndCannotBorrowNextAccount() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let original = try await login(service), remote = try service.makeLiveMatchService()
        let initialMatch = try await remote.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2)
        XCTAssertEqual(initialMatch, original.userID)
        await http.hold("create-match")
        let creating = Task { try await remote.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2) }
        try await wait { await http.suspended("create-match") }
        _ = await service.signOut()
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        await http.release("create-match")
        do { _ = try await creating.value; XCTFail("Old Live response must fail its immutable binding") }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await http.count("create-match")
        do { _ = try await remote.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2); XCTFail("Retired service cannot dispatch") } catch {}
        let unchanged = await http.count("create-match")
        XCTAssertEqual(unchanged, count)
        let newer = try service.makeLiveMatchService()
        let freshMatch = try await newer.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2)
        XCTAssertEqual(freshMatch, next)
        _ = await service.signOut()
    }

    func testInvalidDeletionConfirmationKeepsEffectiveAccountAndNeverRunsLocalCleanup() async throws {
        for bytes in [Data(#"{"data":{"deleted":false}}"#.utf8), Data("{}".utf8)] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
            let original = try await login(service)
            await http.setDeletionPayload(bytes)
            var deleted: [UUID] = []
            let model = AccountModel(service: service, didDeleteAccount: { deleted.append($0) })
            await model.start()
            try await wait { model.session?.userID == original.userID }
            await model.deleteAccount()
            XCTAssertTrue(deleted.isEmpty)
            XCTAssertEqual(model.session?.userID, original.userID)
            XCTAssertEqual(try service.activeBinding().userID, original.userID)
            XCTAssertNotNil(try storage.retrieve(key: service.sessionKey))
            XCTAssertTrue(model.errorMessage?.contains("No local data was removed") == true)
            _ = await service.signOut()
        }
    }

    func testCancellationAfterDeletionConfirmationStillRunsCapturedLocalCleanup() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let original = try await login(service)
        var deleted: [UUID] = []
        let model = AccountModel(service: service, didDeleteAccount: { deleted.append($0) })
        await model.start()
        try await wait { model.session?.userID == original.userID }
        await http.hold("logout")
        let deleting = Task { await model.deleteAccount() }
        try await wait { await http.suspended("logout") }
        deleting.cancel()
        await http.release("logout")
        await deleting.value
        XCTAssertEqual(deleted, [original.userID])
        XCTAssertNil(model.session)
        XCTAssertThrowsError(try service.activeBinding())
    }

    func testExpiredSDKInitialListenerAndRestoreRemainOwnedAcrossRetirementAndNewLogin() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        first.applicationWillResignActive()
        _ = try await login(first)
        var saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: first.sessionKey)))
        _ = await first.signOut()
        saved.expiresAt = Date().addingTimeInterval(-120).timeIntervalSince1970
        try storage.store(key: first.sessionKey, value: JSONEncoder().encode(saved))
        try storage.remove(key: first.sessionKey + "-gridrace-retired-v1")
        await http.hold("refresh")
        let restored = service(http, storage: storage, host: host)
        restored.applicationWillResignActive()
        let restoring = Task { try await restored.restoreSession() }
        try await wait { await http.suspended("refresh") }
        let retired = await restored.signOut()
        XCTAssertEqual(retired.retiredUserID, saved.user.id)
        let next = UUID(); await http.setUser(next)
        _ = try await login(restored)
        await http.release("refresh")
        do { _ = try await restoring.value; XCTFail("Obsolete initial restore must not activate") } catch {}
        XCTAssertEqual(try restored.activeBinding().userID, next)
        let persisted = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: restored.sessionKey)))
        XCTAssertEqual(persisted.user.id, next)
        _ = await restored.signOut()
    }

    func testHeldAutomaticWorkRetainsOldSDKClientOnlyUntilItSettles() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let service = service(http, storage: storage, clock: { Date().addingTimeInterval(3560) })
        service.applicationWillResignActive()
        _ = try await login(service)
        var old: AuthClientLease? = try service.activeBinding()
        weak var oldClient = old?.lifetime.client
        await http.hold("refresh")
        service.applicationDidBecomeActive()
        try await wait { await http.suspended("refresh") }
        _ = await service.signOut()
        old = nil
        XCTAssertNotNil(oldClient, "Cancelled owner task must retain SDK dependencies while held refresh settles")
        service.applicationWillResignActive()
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        await http.release("refresh")
        try await wait { oldClient == nil }
        XCTAssertEqual(try service.activeBinding().userID, next)
        _ = await service.signOut()
    }
}

@MainActor
extension AccountAuthLifecycleTests {
    func testAutomaticThresholdUsesPinnedIntegerTruncationAndOrdinarySDKRefreshCoalesces() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), clock = AuthTestClock()
        let service = service(http, storage: storage, clock: { clock.read() })
        service.applicationWillResignActive()
        _ = try await login(service)
        var saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: service.sessionKey)))
        clock.set(Date(timeIntervalSince1970: saved.expiresAt - 120))
        service.applicationDidBecomeActive()
        await service.automaticTick()
        let outside = await http.count("refresh")
        XCTAssertEqual(outside, 0)
        clock.set(Date(timeIntervalSince1970: saved.expiresAt - 119.9))
        await service.automaticTick()
        let truncated = await http.count("refresh")
        XCTAssertEqual(truncated, 1)
        saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: service.sessionKey)))
        clock.set(Date(timeIntervalSince1970: saved.expiresAt - 90))
        await service.automaticTick()
        let equality = await http.count("refresh")
        XCTAssertEqual(equality, 2)
        service.applicationWillResignActive()
        await http.hold("refresh")
        let first = Task { try await service.refreshSession() }
        try await wait { await http.suspended("refresh") }
        let second = Task { try await service.refreshSession() }
        await Task.yield()
        await http.release("refresh")
        let firstResult = try await first.value, secondResult = try await second.value
        XCTAssertEqual(firstResult, secondResult)
        let coalesced = await http.count("refresh")
        XCTAssertEqual(coalesced, 3)
        _ = await service.signOut()
    }
}

@MainActor
extension AccountAuthLifecycleTests {
    func testConcurrentRetirementSharesCapturedCleanupAndDoesNotReopenOrRemoveNextLogin() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let original = try await login(service)
        await http.hold("logout")
        let first = Task { await service.signOut() }
        try await wait { await http.suspended("logout") }
        let second = Task { await service.signOut() }
        await Task.yield()
        do { _ = try await login(service); XCTFail("Retirement must finish before intentional next candidate") } catch {}
        await http.release("logout")
        let firstOutcome = await first.value, secondOutcome = await second.value
        XCTAssertEqual(firstOutcome.retiredUserID, original.userID)
        XCTAssertEqual(secondOutcome.retiredUserID, original.userID)
        let logouts = await http.count("logout")
        XCTAssertEqual(logouts, 1)
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        XCTAssertEqual(try service.activeBinding().userID, next)
        XCTAssertNotNil(try storage.retrieve(key: service.sessionKey))
        _ = await service.signOut()
    }

    func testExplicitRetirementDuringHeldCandidatePreventsLateActivationAndKeepsNextLogin() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        await http.hold("token")
        let candidate = Task { try await login(service) }
        try await wait { await http.suspended("token") }
        _ = await service.signOut()
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        await http.release("token")
        do { _ = try await candidate.value; XCTFail("Replaced candidate cannot commit") } catch {}
        XCTAssertEqual(try service.activeBinding().userID, next)
        let saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: service.sessionKey)))
        XCTAssertEqual(saved.user.id, next)
        _ = await service.signOut()
    }
}
