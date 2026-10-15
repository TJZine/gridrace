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
    private var writes: [String] = []
    private var skippedFailures: [String: Int] = [:]
    private var droppedRemovals: Set<String> = []
    private var replacements: [String: Data] = [:]
    private var droppedWrites: Set<String> = []
    func dropRemovals(key: String) { lock.withLock { _ = droppedRemovals.insert(key) } }
    func writeCount(_ key: String) -> Int { lock.withLock { writes.filter { $0 == key }.count } }
    func dropWrites(key: String) { lock.withLock { _ = droppedWrites.insert(key) } }
    func replaceWrites(key: String, with bytes: Data) { lock.withLock { replacements[key] = bytes } }
    func fail(_ operation: AuthStorageIssue.Operation, key: String, status: Int32 = errSecInteractionNotAllowed,
              afterSuccessfulCalls: Int = 0) {
        lock.withLock {
            let target = "\(operation)-\(key)"
            failures[target] = AuthStorageIssue(operation: operation, status: status)
            skippedFailures[target] = afterSuccessfulCalls
        }
    }
    func recover() {
        lock.withLock {
            failures.removeAll()
            skippedFailures.removeAll()
            droppedWrites.removeAll()
            replacements.removeAll()
            droppedRemovals.removeAll()
        }
    }
    private func checkFailure(_ operation: AuthStorageIssue.Operation, key: String) throws {
        let target = "\(operation)-\(key)"
        guard let issue = failures[target] else { return }
        if let remaining = skippedFailures[target], remaining > 0 { skippedFailures[target] = remaining - 1 }
        else { throw issue }
    }
    func removed(_ key: String) -> Bool { lock.withLock { removals.contains(key) } }
    func store(key: String, value: Data) throws {
        try lock.withLock {
            writes.append(key)
            try checkFailure(.store, key: key)
            if !droppedWrites.contains(key) { values[key] = replacements[key] ?? value }
        }
    }
    func retrieve(key: String) throws -> Data? {
        try lock.withLock {
            try checkFailure(.read, key: key)
            return values[key]
        }
    }
    func remove(key: String) throws {
        try lock.withLock {
            removals.append(key)
            try checkFailure(.remove, key: key)
            if !droppedRemovals.contains(key) { values[key] = nil }
        }
    }
}

private final class AuthClientConstructionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var constructions = 0
    var count: Int { lock.withLock { constructions } }
    func record() { lock.withLock { constructions += 1 } }
}

private struct AuthLegacyEnvelope: Encodable {
    let session: Session
    let expirationDate: Date
}

private actor AuthHTTPFixture {
    var userID = UUID()
    var expiry: TimeInterval = 3600
    var failsRefresh = false
    var failsRefreshHTTP = false
    var deletionHeaders: [String] = []
    var losesDeletionResponses = 0
    func loseNextDeletionResponse() { losesDeletionResponses += 1 }
    func deletionAuthorizations() -> [String] { deletionHeaders }
    var deletionStatus = 200
    func setDeletionResponse(_ bytes: Data, status: Int) { deletionPayload = bytes; deletionStatus = status }
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
        if route == "delete-account" { deletionHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "") }
        let now = Date(), user = userID, duration = expiry
        let session = Session(accessToken: "synthetic-access-\(requests.count)", tokenType: "bearer", expiresIn: duration,
            expiresAt: now.addingTimeInterval(duration).timeIntervalSince1970,
            refreshToken: "synthetic-refresh-\(requests.count)",
            user: User(id: user, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now))
        if holds.remove(route) != nil { await withCheckedContinuation { pending[route] = $0 } }
        if route == "delete-account", losesDeletionResponses > 0 {
            losesDeletionResponses -= 1
            throw URLError(.networkConnectionLost)
        }
        if refresh && failsRefreshHTTP {
            return (Data(#"{"error":"synthetic refresh rejection","error_code":"bad_request"}"#.utf8),
                HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        if refresh && failsRefresh { throw URLError(.notConnectedToInternet) }
        let data: Data
        switch route {
        case "logout": data = Data()
        case "delete-account":
            return (deletionPayload, HTTPURLResponse(url: url, statusCode: deletionStatus, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!)
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
                         beforeChannelRemoval: @escaping @Sendable () async -> Void = {},
                         constructionProbe: AuthClientConstructionProbe? = nil) -> SupabaseAccountService {
        let host = host ?? "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        AuthFixtureProtocol.install(fixture, host: host)
        return SupabaseAccountService(configuration: .init(urlString: "https://\(host)", publishableKey: "synthetic-public")!,
            storage: storage, network: {
                constructionProbe?.record()
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [AuthFixtureProtocol.self]
                return URLSession(configuration: config)
            }, clock: clock, sleep: sleep, notificationCenter: notificationCenter,
            beforeChannelRemoval: beforeChannelRemoval)
    }
    private func wait(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 { if await condition() { return }; try await Task.sleep(for: .milliseconds(2)) }
        XCTFail("Controlled Auth condition did not settle")
        throw URLError(.timedOut)
    }
    private func login(_ service: SupabaseAccountService) async throws -> AccountSession {
        try await service.signInForLocalTesting(email: "fixture@example.invalid", password: "synthetic")
    }
    private func savedSession() -> Session {
        let now = Date()
        return Session(accessToken: "synthetic-saved-access", tokenType: "bearer", expiresIn: 3600,
            expiresAt: now.addingTimeInterval(3600).timeIntervalSince1970, refreshToken: "synthetic-saved-refresh",
            user: User(id: UUID(), appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now))
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
        _ = try await login(service)
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
        let originalStorage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: originalStorage, host: host)
        let account = try await login(first)
        let saved = try JSONDecoder().decode(Session.self, from: XCTUnwrap(originalStorage.retrieve(key: first.sessionKey)))
        let retirement = await first.signOut()
        XCTAssertNil(retirement.localRecovery)
        XCTAssertNil(try originalStorage.retrieve(key: first.sessionKey))
        let storage = AuthMemoryStorage()
        let legacy = try AuthClient.Configuration.jsonEncoder.encode(AuthLegacyEnvelope(session: saved,
            expirationDate: Date(timeIntervalSince1970: saved.expiresAt)))
        try storage.store(key: "supabase.session", value: legacy)
        let restored = service(http, storage: storage, host: host)
        let result = try await restored.restoreSession()
        XCTAssertEqual(result?.userID, account.userID)
        XCTAssertNil(try storage.retrieve(key: "supabase.session"))
        let canonical = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: restored.sessionKey)))
        XCTAssertEqual(canonical.user.id, saved.user.id)
        XCTAssertEqual(canonical.accessToken, saved.accessToken)
        XCTAssertEqual(canonical.refreshToken, saved.refreshToken)
        XCTAssertEqual(canonical.expiresAt, saved.expiresAt)
        _ = await restored.signOut()
    }
    func testDefaultCanonicalRestorePreservesExactBytesWithoutWriting() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), restored = service(http, storage: storage)
        let saved = savedSession()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(saved)
        try storage.store(key: restored.sessionKey, value: bytes)
        storage.fail(.store, key: restored.sessionKey)
        let result = try await restored.restoreSession()
        XCTAssertEqual(result?.userID, saved.user.id)
        XCTAssertEqual(try storage.retrieve(key: restored.sessionKey), bytes)
        XCTAssertEqual(storage.writeCount(restored.sessionKey), 1)
        storage.recover()
        _ = await restored.signOut()
    }
    func testSupportedStoredFormatsNormalizeWithLegacyKeyPrecedence() async throws {
        for format in ["canonicalWire", "canonicalEnvelope", "legacyDefault", "legacyWire", "bothValid"] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), restored = service(http, storage: storage)
            let selected = savedSession()
            let wire = try AuthClient.Configuration.jsonEncoder.encode(selected)
            switch format {
            case "canonicalWire": try storage.store(key: restored.sessionKey, value: wire)
            case "canonicalEnvelope":
                let envelope = AuthLegacyEnvelope(session: selected, expirationDate: Date(timeIntervalSince1970: selected.expiresAt))
                try storage.store(key: restored.sessionKey, value: AuthClient.Configuration.jsonEncoder.encode(envelope))
            case "legacyDefault": try storage.store(key: "supabase.session", value: JSONEncoder().encode(selected))
            case "legacyWire": try storage.store(key: "supabase.session", value: wire)
            default:
                try storage.store(key: restored.sessionKey, value: JSONEncoder().encode(savedSession()))
                try storage.store(key: "supabase.session", value: wire)
            }
            let result = try await restored.restoreSession()
            XCTAssertEqual(result?.userID, selected.user.id, format)
            let canonical = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: restored.sessionKey)))
            XCTAssertEqual(canonical.user.id, selected.user.id, format)
            XCTAssertEqual(canonical.accessToken, selected.accessToken, format)
            XCTAssertEqual(canonical.refreshToken, selected.refreshToken, format)
            XCTAssertEqual(canonical.expiresAt, selected.expiresAt, format)
            XCTAssertNil(try storage.retrieve(key: "supabase.session"), format)
            _ = await restored.signOut()
        }
    }
    func testBothCredentialBlobsAreValidatedBeforeAnyMigrationOrClient() async throws {
        for malformedCanonical in [false, true] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), probe = AuthClientConstructionProbe()
            let restored = service(http, storage: storage, constructionProbe: probe)
            let valid = try AuthClient.Configuration.jsonEncoder.encode(savedSession())
            let malformed = Data("{not a session}".utf8)
            let canonical = malformedCanonical ? malformed : valid
            let legacy = malformedCanonical ? valid : malformed
            try storage.store(key: restored.sessionKey, value: canonical)
            try storage.store(key: "supabase.session", value: legacy)
            var states = restored.authStateChanges.makeAsyncIterator()
            _ = await states.next(isolation: MainActor.shared)
            do { _ = try await restored.restoreSession(); XCTFail("Malformed shadow credentials accepted") }
            catch { XCTAssertEqual(error as? AuthStorageIssue, AuthStorageIssue(operation: .read, status: errSecDecode)) }
            let blocked = await states.next(isolation: MainActor.shared)
            XCTAssertEqual(blocked?.recovery?.action, .cleanup)
            XCTAssertEqual(probe.count, 0)
            XCTAssertEqual(try storage.retrieve(key: restored.sessionKey), canonical)
            XCTAssertEqual(try storage.retrieve(key: "supabase.session"), legacy)
            XCTAssertEqual(storage.writeCount(restored.sessionKey), 1)
            XCTAssertEqual(storage.writeCount("supabase.session"), 1)
            XCTAssertFalse(storage.removed("supabase.session"))
            XCTAssertThrowsError(try restored.activeBinding())
        }
    }
    func testLegacyPreparationStorageFailuresRetainCredentialsAndRetryBeforeCreatingClient() async throws {
        for failure in ["initialRead", "store", "droppedWrite", "replacedWrite", "readback", "remove", "droppedRemoval", "removalReadback"] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), probe = AuthClientConstructionProbe()
            let restored = service(http, storage: storage, constructionProbe: probe)
            let saved = savedSession()
            let envelope = AuthLegacyEnvelope(session: saved, expirationDate: Date(timeIntervalSince1970: saved.expiresAt))
            let legacy = try AuthClient.Configuration.jsonEncoder.encode(envelope)
            try storage.store(key: "supabase.session", value: legacy)
            let expected: AuthStorageIssue
            switch failure {
            case "initialRead":
                storage.fail(.read, key: "supabase.session", status: errSecAuthFailed)
                expected = AuthStorageIssue(operation: .read, status: errSecAuthFailed)
            case "store":
                storage.fail(.store, key: restored.sessionKey, status: errSecAuthFailed)
                expected = AuthStorageIssue(operation: .store, status: errSecAuthFailed)
            case "droppedWrite":
                storage.dropWrites(key: restored.sessionKey)
                expected = AuthStorageIssue(operation: .store, status: errSecInternalComponent)
            case "replacedWrite":
                storage.replaceWrites(key: restored.sessionKey, with: try JSONEncoder().encode(savedSession()))
                expected = AuthStorageIssue(operation: .store, status: errSecInternalComponent)
            case "readback":
                storage.fail(.read, key: restored.sessionKey, status: errSecAuthFailed, afterSuccessfulCalls: 1)
                expected = AuthStorageIssue(operation: .read, status: errSecAuthFailed)
            case "remove":
                storage.fail(.remove, key: "supabase.session", status: errSecAuthFailed)
                expected = AuthStorageIssue(operation: .remove, status: errSecAuthFailed)
            case "droppedRemoval":
                storage.dropRemovals(key: "supabase.session")
                expected = AuthStorageIssue(operation: .remove, status: errSecInternalComponent)
            default:
                storage.fail(.read, key: "supabase.session", status: errSecAuthFailed, afterSuccessfulCalls: 1)
                expected = AuthStorageIssue(operation: .read, status: errSecAuthFailed)
            }
            var states = restored.authStateChanges.makeAsyncIterator()
            _ = await states.next(isolation: MainActor.shared)
            do { _ = try await restored.restoreSession(); XCTFail("Unverified migration accepted: \(failure)") }
            catch { XCTAssertEqual(error as? AuthStorageIssue, expected, failure) }
            let blocked = await states.next(isolation: MainActor.shared)
            XCTAssertEqual(blocked?.recovery, AccountAuthRecovery(action: .restore, storageIssue: expected), failure)
            XCTAssertNil(blocked?.session, failure)
            XCTAssertThrowsError(try restored.activeBinding())
            XCTAssertEqual(probe.count, 0, failure)
            storage.recover()
            if failure != "removalReadback" {
                XCTAssertEqual(try storage.retrieve(key: "supabase.session"), legacy, failure)
            } else {
                let canonical = try JSONDecoder().decode(Session.self, from: XCTUnwrap(storage.retrieve(key: restored.sessionKey)))
                XCTAssertEqual(canonical.user.id, saved.user.id)
            }
            let result = try await restored.restoreSession()
            XCTAssertEqual(result?.userID, saved.user.id, failure)
            XCTAssertEqual(probe.count, 1, failure)
            XCTAssertNil(try storage.retrieve(key: "supabase.session"), failure)
            _ = await restored.signOut()
        }
    }
    func testPreparationRecoverySignOutFencesColdRestoreAndRetainsKnownCleanupScope() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), probe = AuthClientConstructionProbe()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let restored = service(http, storage: storage, host: host, constructionProbe: probe)
        let saved = savedSession()
        let legacy = AuthLegacyEnvelope(session: saved, expirationDate: Date(timeIntervalSince1970: saved.expiresAt))
        try storage.store(key: "supabase.session", value: AuthClient.Configuration.jsonEncoder.encode(legacy))
        storage.fail(.remove, key: "supabase.session")
        do { _ = try await restored.restoreSession(); XCTFail("Preparation removal should fail") } catch {}
        storage.fail(.remove, key: restored.sessionKey)
        let outcome = await restored.signOut()
        XCTAssertEqual(outcome.retiredUserID, saved.user.id)
        XCTAssertEqual(restored.retiredCleanupUserID, saved.user.id)
        XCTAssertEqual(outcome.localRecovery?.action, .cleanup)
        XCTAssertEqual(probe.count, 0)
        storage.recover()
        XCTAssertNotNil(try storage.retrieve(key: restored.sessionKey))
        XCTAssertNotNil(try storage.retrieve(key: "supabase.session"))
        let markerBytes = try XCTUnwrap(storage.retrieve(key: restored.sessionKey + "-gridrace-retired-v1"))
        let marker = try XCTUnwrap(JSONSerialization.jsonObject(with: markerBytes) as? [String: Any])
        XCTAssertEqual(marker["userID"] as? String, saved.user.id.uuidString)
        let cold = service(http, storage: storage, host: host, constructionProbe: probe)
        var states = cold.authStateChanges.makeAsyncIterator()
        _ = await states.next(isolation: MainActor.shared)
        let result = try await cold.restoreSession()
        XCTAssertNil(result)
        let blocked = await states.next(isolation: MainActor.shared)
        XCTAssertEqual(blocked?.recovery?.action, .cleanup)
        XCTAssertEqual(cold.retiredCleanupUserID, saved.user.id)
        XCTAssertThrowsError(try cold.activeBinding())
        XCTAssertEqual(probe.count, 0)
        let cleanup = await cold.retrySignedOutCleanup()
        XCTAssertNil(cleanup.recovery)
        XCTAssertNil(try storage.retrieve(key: cold.sessionKey))
        XCTAssertNil(try storage.retrieve(key: "supabase.session"))
    }
    func testPreparationRecoverySignOutHandsValidatedScopeToAccountModelCleanup() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), probe = AuthClientConstructionProbe()
        let restored = service(http, storage: storage, constructionProbe: probe)
        let saved = savedSession()
        try storage.store(key: "supabase.session", value: AuthClient.Configuration.jsonEncoder.encode(saved))
        storage.fail(.store, key: restored.sessionKey)
        var cleaned: [UUID] = []
        let model = AccountModel(service: restored, didSignOut: { cleaned.append($0); return true })
        await model.start()
        try await wait { model.authRecovery?.action == .restore }
        XCTAssertNil(model.session)
        await model.signOut()
        XCTAssertEqual(cleaned, [saved.user.id])
        XCTAssertEqual(restored.retiredCleanupUserID, saved.user.id)
        XCTAssertNil(model.authRecovery)
        XCTAssertEqual(probe.count, 0)
        XCTAssertNil(try storage.retrieve(key: restored.sessionKey))
        XCTAssertNil(try storage.retrieve(key: "supabase.session"))
        XCTAssertNotNil(try storage.retrieve(key: restored.sessionKey + "-gridrace-retired-v1"))
    }
    func testUnreadablePreparationIdentityUsesGenericSignOutFenceWithoutGuessing() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), probe = AuthClientConstructionProbe()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let restored = service(http, storage: storage, host: host, constructionProbe: probe)
        try storage.store(key: "supabase.session", value: AuthClient.Configuration.jsonEncoder.encode(savedSession()))
        storage.fail(.read, key: restored.sessionKey)
        do { _ = try await restored.restoreSession(); XCTFail("Preparation read should fail") } catch {}
        for key in [restored.sessionKey, "supabase.session"] { storage.fail(.remove, key: key) }
        let outcome = await restored.signOut()
        XCTAssertNil(outcome.retiredUserID)
        XCTAssertNil(restored.retiredCleanupUserID)
        XCTAssertEqual(outcome.localRecovery?.action, .cleanup)
        storage.recover()
        let markerBytes = try XCTUnwrap(storage.retrieve(key: restored.sessionKey + "-gridrace-retired-v1"))
        let marker = try XCTUnwrap(JSONSerialization.jsonObject(with: markerBytes) as? [String: Any])
        XCTAssertNil(marker["userID"])
        let cold = service(http, storage: storage, host: host, constructionProbe: probe)
        let result = try await cold.restoreSession()
        XCTAssertNil(result)
        XCTAssertNil(cold.retiredCleanupUserID)
        XCTAssertThrowsError(try cold.activeBinding())
        XCTAssertEqual(probe.count, 0)
        _ = await cold.retrySignedOutCleanup()
    }
    func testPreparationSignOutReportsFailureWhenMarkerAndCredentialCleanupCannotPersist() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), probe = AuthClientConstructionProbe()
        let restored = service(http, storage: storage, constructionProbe: probe)
        let saved = savedSession()
        let legacy = try AuthClient.Configuration.jsonEncoder.encode(saved)
        try storage.store(key: "supabase.session", value: legacy)
        storage.fail(.store, key: restored.sessionKey)
        do { _ = try await restored.restoreSession(); XCTFail("Preparation store should fail") } catch {}
        let marker = restored.sessionKey + "-gridrace-retired-v1"
        storage.fail(.store, key: marker)
        for key in [restored.sessionKey, "supabase.session", restored.sessionKey + "-code-verifier"] {
            storage.fail(.remove, key: key)
        }
        let outcome = await restored.signOut()
        XCTAssertEqual(outcome.retiredUserID, saved.user.id)
        XCTAssertEqual(outcome.localRecovery?.action, .cleanup)
        XCTAssertTrue(restored.lastRetirementIssues.contains(AuthStorageIssue(operation: .store, status: errSecInteractionNotAllowed)))
        XCTAssertTrue(restored.lastRetirementIssues.contains(AuthStorageIssue(operation: .remove, status: errSecInteractionNotAllowed)))
        XCTAssertEqual(probe.count, 0)
        storage.recover()
        XCTAssertNil(try storage.retrieve(key: marker))
        XCTAssertEqual(try storage.retrieve(key: "supabase.session"), legacy)
        _ = await restored.retrySignedOutCleanup()
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
        clock.advance(3500)
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
        service.receive(.tokenRefreshed, session: saved, from: old.lifetime)
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
        service.receive(.initialSession, session: nil, from: binding.lifetime)
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
        let initialMatch = try await remote.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 3)
        XCTAssertEqual(initialMatch, original.userID)
        await http.hold("create-match")
        let creating = Task { try await remote.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 3) }
        try await wait { await http.suspended("create-match") }
        _ = await service.signOut()
        let next = UUID(); await http.setUser(next)
        _ = try await login(service)
        await http.release("create-match")
        do { _ = try await creating.value; XCTFail("Old Live response must fail its immutable binding") }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await http.count("create-match")
        do { _ = try await remote.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 3); XCTFail("Retired service cannot dispatch") } catch {}
        let unchanged = await http.count("create-match")
        XCTAssertEqual(unchanged, count)
        let newer = try service.makeLiveMatchService()
        let freshMatch = try await newer.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 3)
        XCTAssertEqual(freshMatch, next)
        _ = await service.signOut()
    }

    func testInvalidDeletionConfirmationFencesAccountAndRetainsOriginalOperationUntilConfirmed() async throws {
        for bytes in [Data(#"{"data":{"deleted":false}}"#.utf8), Data("{}".utf8)] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
            let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
            let service = service(http, storage: storage, host: host)
            let original = try await login(service), originalLease = try service.activeBinding()
            await http.setDeletionPayload(bytes)
            var deleted: [UUID] = []
            let model = AccountModel(service: service, didDeleteAccount: { deleted.append($0) })
            await model.start()
            try await wait { model.session?.userID == original.userID }
            await http.hold("delete-account")
            let deleting = Task { await model.deleteAccount() }
            try await wait { await http.suspended("delete-account") }
            let captured = try XCTUnwrap(storage.retrieve(key: service.deletionKey))
            let capturedObject = try JSONSerialization.jsonObject(with: captured)
            let canonicalCaptured = try JSONSerialization.data(withJSONObject: capturedObject, options: .sortedKeys)
            await http.release("delete-account")
            await deleting.value
            XCTAssertTrue(deleted.isEmpty, "An invalid response must never acknowledge remote deletion")
            XCTAssertNil(model.session, "An invalid response cannot establish continued account authority")
            XCTAssertThrowsError(try service.activeBinding())
            XCTAssertThrowsError(try originalLease.check())
            XCTAssertNotNil(try storage.retrieve(key: service.sessionKey))
            XCTAssertEqual(model.authRecovery?.action, .deletion)
            XCTAssertTrue(model.errorMessage?.contains("deletion needs attention") == true)
            await model.retryAuthRecovery()
            XCTAssertTrue(deleted.isEmpty)
            let cold = self.service(http, storage: storage, host: host)
            let coldModel = AccountModel(service: cold, didDeleteAccount: { deleted.append($0) })
            await coldModel.start()
            try await wait { coldModel.authRecovery?.action == .deletion }
            XCTAssertNil(coldModel.session)
            XCTAssertThrowsError(try cold.activeBinding())
            XCTAssertEqual(coldModel.authRecovery?.action, .deletion)
            await coldModel.retryAuthRecovery()
            XCTAssertTrue(deleted.isEmpty)
            let retained = try XCTUnwrap(storage.retrieve(key: cold.deletionKey))
            let retainedObject = try JSONSerialization.jsonObject(with: retained)
            let canonicalRetained = try JSONSerialization.data(withJSONObject: retainedObject, options: .sortedKeys)
            XCTAssertTrue(canonicalCaptured == canonicalRetained, "Compare operation identity privately, without printing its bearer")
            await http.setDeletionPayload(Data(#"{"data":{"deleted":true}}"#.utf8))
            await coldModel.retryAuthRecovery()
            XCTAssertEqual(deleted, [original.userID])
            XCTAssertNil(try storage.retrieve(key: cold.deletionKey))
            await coldModel.retryAuthRecovery()
            XCTAssertEqual(deleted, [original.userID], "Confirmed local handoff must run only once")
            let headers = await http.deletionAuthorizations()
            XCTAssertEqual(headers.count, 4)
            let firstHeader = try XCTUnwrap(headers.first)
            XCTAssertFalse(firstHeader.isEmpty)
            XCTAssertTrue(headers.allSatisfy { $0 == firstHeader }, "Invalid responses must never replace captured authorization")
            let signIns = await http.count("token")
            XCTAssertEqual(signIns, 1)
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

@MainActor
extension AccountAuthLifecycleTests {
    func testDeletionRetryPreservesCapturedHeaderWithAndWithoutIssuedRefresh() async throws {
        for refresh in [false, true] {
            let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
            let user = try await login(service)
            let lease = try service.activeBinding()
            var refreshing: Task<AccountSession?, Error>?
            if refresh {
                await http.hold("refresh")
                refreshing = Task { try await service.refreshSession() }
                try await wait { await http.suspended("refresh") }
            }
            await http.loseNextDeletionResponse()
            do { _ = try await service.deleteAccount(); XCTFail("Expected controlled loss") } catch {}
            XCTAssertThrowsError(try lease.check(), "Pending deletion fences every old consumer")
            if refresh {
                await http.release("refresh")
                do { _ = try await refreshing?.value; XCTFail("Refresh cannot reactivate deleting A") }
                catch is CancellationError {}
            }
            let confirmed = try await service.deleteAccount()
            XCTAssertNil(confirmed.localRecovery)
            let headers = await http.deletionAuthorizations()
            XCTAssertEqual(headers.count, 2)
            XCTAssertFalse(headers[0].isEmpty)
            XCTAssertTrue(headers[0] == headers[1], "Compare privately; never print bearer values")
            try service.acknowledgeAccountDeletion(userID: user.userID)
            XCTAssertNil(try storage.retrieve(key: service.deletionKey))
        }
    }

    func testDeletionSecureWriteFailureStopsDispatchAndRetryPersistsBeforeSending() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let user = try await login(service), lease = try service.activeBinding()
        storage.fail(.store, key: service.deletionKey)
        do { _ = try await service.deleteAccount(); XCTFail("Secure write failure accepted") } catch {}
        let count = await http.count("delete-account")
        XCTAssertEqual(count, 0)
        XCTAssertThrowsError(try lease.check())
        storage.recover()
        _ = try await service.deleteAccount()
        try service.acknowledgeAccountDeletion(userID: user.userID)
    }

    func testUncertainDeletionColdRestoreKeepsAuthorizationWithoutConsumerLease() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let user = try await login(first)
        await http.loseNextDeletionResponse()
        do { _ = try await first.deleteAccount(); XCTFail("Expected response loss") } catch {}
        let cold = service(http, storage: storage, host: host)
        let restored = try await cold.restoreSession()
        XCTAssertNil(restored)
        XCTAssertEqual(cold.pendingDeletionUserID, user.userID)
        XCTAssertThrowsError(try cold.activeBinding())
        _ = try await cold.deleteAccount()
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 2)
        XCTAssertTrue(headers[0] == headers[1])
        try cold.acknowledgeAccountDeletion(userID: user.userID)
    }

    func testConfirmedSecureWriteFailureAndColdReadFailureRetainOriginalRecovery() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let user = try await login(first)
        await http.hold("delete-account")
        let deleting = Task { try await first.deleteAccount() }
        try await wait { await http.suspended("delete-account") }
        storage.fail(.store, key: first.deletionKey)
        await http.release("delete-account")
        let confirmed = try await deleting.value
        XCTAssertEqual(confirmed.localRecovery?.action, .deletion)
        storage.recover()
        _ = try await first.deleteAccount()
        let count = await http.count("delete-account")
        XCTAssertEqual(count, 1)
        storage.fail(.read, key: first.deletionKey)
        let cold = service(http, storage: storage, host: host)
        do { _ = try await cold.restoreSession(); XCTFail("Unavailable secure record was ignored") } catch {}
        XCTAssertThrowsError(try cold.activeBinding())
        storage.recover()
        let restored = try await cold.restoreSession()
        XCTAssertNil(restored)
        XCTAssertEqual(cold.pendingDeletionUserID, user.userID)
        _ = try await cold.deleteAccount()
        let afterCold = await http.count("delete-account")
        XCTAssertEqual(afterCold, 1, "Persisted confirmed state never repeats server deletion")
        try cold.acknowledgeAccountDeletion(userID: user.userID)
    }

    func testColdOriginalDeletionDoesNotHideOrRetireLaterAccountCredentials() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let original = try await login(first)
        await http.loseNextDeletionResponse()
        do { _ = try await first.deleteAccount(); XCTFail("Expected loss") } catch {}
        _ = await first.signOut()
        let later = UUID()
        await http.setUser(later)
        _ = try await login(first)
        let savedLater = try XCTUnwrap(storage.retrieve(key: first.sessionKey))
        let cold = service(http, storage: storage, host: host)
        let restored = try await cold.restoreSession()
        XCTAssertEqual(restored?.userID, later)
        _ = try await cold.deleteAccount(userID: original.userID)
        XCTAssertEqual(try cold.activeBinding().userID, later)
        XCTAssertTrue(try storage.retrieve(key: cold.sessionKey) == savedLater)
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 2)
        XCTAssertTrue(headers[0] == headers[1])
        try cold.acknowledgeAccountDeletion(userID: original.userID)
        XCTAssertEqual(try cold.activeBinding().userID, later)
        _ = await cold.signOut()
    }

    func testExpiredMissingReceiptRequiresExplicitSameAccountProofAcrossColdRestore() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let original = try await login(first)
        let sdkSession = try XCTUnwrap(try first.activeBinding().lifetime.client.auth.currentSession)
        await http.loseNextDeletionResponse()
        do { _ = try await first.deleteAccount(); XCTFail("Expected uncertainty") } catch {}
        let expired = Session(accessToken: sdkSession.accessToken, tokenType: sdkSession.tokenType,
            expiresIn: sdkSession.expiresIn, expiresAt: Date().addingTimeInterval(-60).timeIntervalSince1970,
            refreshToken: sdkSession.refreshToken, user: sdkSession.user)
        try storage.store(key: first.sessionKey, value: JSONEncoder().encode(expired))
        let cold = service(http, storage: storage, host: host)
        let restored = try await cold.restoreSession()
        XCTAssertNil(restored)
        XCTAssertFalse(cold.deletionNeedsReauthentication, "Device expiry is not missing-receipt proof")
        await http.setDeletionResponse(Data(#"{"error":{"code":"not_authenticated","message":"Sign in and try again."}}"#.utf8), status: 401)
        do { _ = try await cold.deleteAccount(); XCTFail("Original authorization should be rejected") }
        catch { XCTAssertEqual(error as? AccountServiceError, .deletionRequiresSameAccount) }
        XCTAssertTrue(cold.deletionNeedsReauthentication)
        let originalHeaders = await http.deletionAuthorizations()
        XCTAssertEqual(originalHeaders.count, 2)
        XCTAssertTrue(originalHeaders[0] == originalHeaders[1])
        let afterRejection = service(http, storage: storage, host: host)
        let coldRejectedSession = try await afterRejection.restoreSession()
        XCTAssertNil(coldRejectedSession)
        XCTAssertTrue(afterRejection.deletionNeedsReauthentication)
        let later = UUID()
        await http.setUser(later)
        let signedInB = try await login(afterRejection)
        XCTAssertEqual(signedInB.userID, later)
        do { _ = try await afterRejection.deleteAccount(userID: original.userID); XCTFail("B cannot replace A's rejected operation") }
        catch { XCTAssertEqual(error as? AccountServiceError, .deletionRequiresSameAccount) }
        XCTAssertEqual(afterRejection.pendingDeletionUserID, original.userID)
        XCTAssertTrue(afterRejection.deletionNeedsReauthentication)
        XCTAssertEqual(try afterRejection.activeBinding().userID, later)
        _ = await afterRejection.signOut()
        await http.setUser(original.userID)
        let fresh = try await login(afterRejection)
        XCTAssertEqual(fresh.userID, original.userID)
        XCTAssertEqual(try afterRejection.activeBinding().userID, original.userID)
        let requestsBeforeExplicitDelete = await http.count("delete-account")
        XCTAssertEqual(requestsBeforeExplicitDelete, 2, "Fresh sign-in must not dispatch deletion")
        await http.setDeletionResponse(Data(#"{"data":{"deleted":true}}"#.utf8), status: 200)
        _ = try await afterRejection.deleteAccount()
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 3)
        XCTAssertTrue(headers[0] != headers[2], "Only explicit new operation uses fresh same-A proof")
        try afterRejection.acknowledgeAccountDeletion(userID: original.userID)
    }

    func testTypedDeletionReauthenticationModelEnablesSameAccountSignInWithoutAutomaticDelete() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let user = try await login(service)
        var cleaned: [UUID] = []
        let model = AccountModel(service: service, didDeleteAccount: { cleaned.append($0) })
        await model.start()
        await http.setDeletionResponse(Data(#"{"error":{"code":"not_authenticated","message":"Sign in and try again."}}"#.utf8), status: 401)
        await model.deleteAccount()
        XCTAssertNil(model.session)
        XCTAssertEqual(model.authRecovery?.action, .deletionReauthentication)
        XCTAssertTrue(model.allowsAccountSignIn)
        XCTAssertTrue(cleaned.isEmpty)
        await model.signInForLocalTesting(email: "fixture@example.invalid", password: "synthetic")
        XCTAssertEqual(model.session?.userID, user.userID)
        let beforeExplicitDelete = await http.count("delete-account")
        XCTAssertEqual(beforeExplicitDelete, 1)
        await http.setDeletionResponse(Data(#"{"data":{"deleted":true}}"#.utf8), status: 200)
        await model.deleteAccount()
        XCTAssertEqual(cleaned, [user.userID])
        XCTAssertNil(model.session)
        XCTAssertNil(model.authRecovery)
        XCTAssertNil(try storage.retrieve(key: service.deletionKey))
    }

    func testExpiredCommittedReceiptKeepsOriginalAuthorizationAcrossColdRestore() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let user = try await login(first)
        let original = try XCTUnwrap(try first.activeBinding().lifetime.client.auth.currentSession)
        await http.loseNextDeletionResponse()
        do { _ = try await first.deleteAccount(); XCTFail("Expected lost response") } catch {}
        let expired = Session(accessToken: original.accessToken, tokenType: original.tokenType,
            expiresIn: original.expiresIn, expiresAt: Date().addingTimeInterval(-60).timeIntervalSince1970,
            refreshToken: original.refreshToken, user: original.user)
        try storage.store(key: first.sessionKey, value: JSONEncoder().encode(expired))
        let cold = service(http, storage: storage, host: host)
        let restored = try await cold.restoreSession()
        XCTAssertNil(restored)
        _ = try await cold.deleteAccount()
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 2)
        XCTAssertTrue(headers[0] == headers[1])
        XCTAssertFalse(cold.deletionNeedsReauthentication)
        try cold.acknowledgeAccountDeletion(userID: user.userID)
    }

    func testGeneric401AndFailedTypedRejectionPersistenceNeverPermitBearerReplacement() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let user = try await login(service)
        await http.setDeletionResponse(Data(#"{"message":"Unauthorized"}"#.utf8), status: 401)
        do { _ = try await service.deleteAccount(); XCTFail("Expected generic rejection") } catch {}
        XCTAssertFalse(service.deletionNeedsReauthentication)
        await http.setDeletionResponse(Data(#"{"error":{"code":"not_authenticated","message":"Sign in and try again."}}"#.utf8), status: 401)
        await http.hold("delete-account")
        let rejected = Task { try await service.deleteAccount() }
        try await wait { await http.suspended("delete-account") }
        storage.fail(.store, key: service.deletionKey)
        await http.release("delete-account")
        do { _ = try await rejected.value; XCTFail("Undurable rejection accepted") } catch {}
        XCTAssertFalse(service.deletionNeedsReauthentication)
        storage.recover()
        do { _ = try await service.deleteAccount(); XCTFail("Expected typed rejection") } catch {}
        XCTAssertTrue(service.deletionNeedsReauthentication)
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 3)
        XCTAssertTrue(headers[0] == headers[1] && headers[1] == headers[2])
        XCTAssertEqual(service.pendingDeletionUserID, user.userID)
        _ = await service.signOut()
        XCTAssertTrue(service.deletionNeedsReauthentication, "Sign-out must retain authoritative rejection scope")
        await http.setUser(user.userID)
        _ = try await login(service)
        let priorRecord = try storage.retrieve(key: service.deletionKey)
        storage.fail(.store, key: service.deletionKey)
        do { _ = try await service.deleteAccount(); XCTFail("Undurable fresh operation dispatched") } catch {}
        XCTAssertTrue(service.deletionNeedsReauthentication)
        XCTAssertTrue(try storage.retrieve(key: service.deletionKey) == priorRecord)
        let beforeRetry = await http.count("delete-account")
        XCTAssertEqual(beforeRetry, 3)
        storage.recover()
        _ = await service.signOut()
        _ = try await login(service)
        await http.setDeletionResponse(Data(#"{"data":{"deleted":true}}"#.utf8), status: 200)
        _ = try await service.deleteAccount()
        try service.acknowledgeAccountDeletion(userID: user.userID)
    }

    func testUncertainAAllowsBModelOwnDeletionAndAcknowledgmentRetainsAThroughColdRecovery() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let service = service(http, storage: storage, host: host)
        let original = try await login(service)
        await http.loseNextDeletionResponse()
        do { _ = try await service.deleteAccount(); XCTFail("Expected A uncertainty") } catch {}
        let capturedABytes = try XCTUnwrap(storage.retrieve(key: service.deletionKey))
        _ = await service.signOut()
        let later = UUID()
        await http.setUser(later)
        _ = try await login(service)
        var cleaned: [UUID] = []
        let model = AccountModel(service: service, didDeleteAccount: { cleaned.append($0) })
        await model.start()
        XCTAssertEqual(model.session?.userID, later)
        await model.deleteAccount()
        XCTAssertEqual(cleaned, [later], "Current B's Delete action must never target captured A")
        XCTAssertNil(model.session)
        let remaining = try XCTUnwrap(storage.retrieve(key: service.deletionKey))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: remaining) as? [String: Any])
        let records = try XCTUnwrap(document["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["userID"] as? String, original.userID.uuidString)
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: capturedABytes) as? [String: Any])
        let originalRecords = try XCTUnwrap(before["records"] as? [[String: Any]])
        XCTAssertTrue(records[0]["bearer"] as? String == originalRecords[0]["bearer"] as? String)
        let cold = self.service(http, storage: storage, host: host)
        let restored = try await cold.restoreSession()
        XCTAssertNil(restored)
        XCTAssertEqual(cold.pendingDeletionUserID, original.userID)
        await http.setDeletionResponse(Data(#"{"error":{"code":"not_authenticated","message":"Sign in and try again."}}"#.utf8), status: 401)
        do { _ = try await cold.deleteAccount(userID: original.userID); XCTFail("Expected missing A receipt") } catch {}
        XCTAssertTrue(cold.deletionNeedsReauthentication)
        await http.setUser(original.userID)
        _ = try await login(cold)
        await http.setDeletionResponse(Data(#"{"data":{"deleted":true}}"#.utf8), status: 200)
        _ = try await cold.deleteAccount(userID: original.userID)
        try cold.acknowledgeAccountDeletion(userID: original.userID)
        XCTAssertNil(try storage.retrieve(key: cold.deletionKey))
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 4)
        XCTAssertTrue(headers[0] != headers[1])
        XCTAssertTrue(headers[0] == headers[2])
        XCTAssertTrue(headers[0] != headers[3])
    }

    func testHeldADeletionNeverSuppliesBConfirmationOrLosesEitherSecureRecord() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let original = try await login(service)
        await http.hold("delete-account")
        let deletingA = Task { try await service.deleteAccount(userID: original.userID) }
        try await wait { await http.suspended("delete-account") }
        _ = await service.signOut()
        let later = UUID()
        await http.setUser(later)
        _ = try await login(service)
        _ = try await service.deleteAccount(userID: later)
        let beforeARelease = await http.count("delete-account")
        XCTAssertEqual(beforeARelease, 2, "B needs its own dispatch, not A's held task")
        try service.acknowledgeAccountDeletion(userID: later)
        XCTAssertEqual(service.pendingDeletionUserID, original.userID)
        await http.release("delete-account")
        _ = try await deletingA.value
        try service.acknowledgeAccountDeletion(userID: original.userID)
        XCTAssertNil(try storage.retrieve(key: service.deletionKey))
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 2)
        XCTAssertTrue(headers[0] != headers[1])
    }

    func testLegacySingleSecureDeletionRecordMigratesWithoutChangingOriginalAuthorization() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let user = try await login(first)
        await http.loseNextDeletionResponse()
        do { _ = try await first.deleteAccount(); XCTFail("Expected response loss") } catch {}
        let bytes = try XCTUnwrap(storage.retrieve(key: first.deletionKey))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let legacy = try XCTUnwrap((document["records"] as? [[String: Any]])?.first)
        try storage.store(key: first.deletionKey, value: JSONSerialization.data(withJSONObject: legacy))
        let cold = service(http, storage: storage, host: host)
        let restored = try await cold.restoreSession()
        XCTAssertNil(restored)
        _ = try await cold.deleteAccount(userID: user.userID)
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 2)
        XCTAssertTrue(headers[0] == headers[1])
        try cold.acknowledgeAccountDeletion(userID: user.userID)
    }

    func testLatePredecessorReceiptSurvivesSuccessorAndColdRestoreWithoutRetiringB() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture()
        let host = "auth-fixture-\(UUID().uuidString.lowercased()).invalid"
        let first = service(http, storage: storage, host: host)
        let original = try await login(first)
        await http.loseNextDeletionResponse()
        do { _ = try await first.deleteAccount(userID: original.userID); XCTFail("Expected lost response") } catch {}
        await http.setDeletionResponse(Data(#"{"error":{"code":"not_authenticated","message":"Sign in and try again."}}"#.utf8), status: 401)
        do { _ = try await first.deleteAccount(userID: original.userID); XCTFail("Expected typed missing-auth observation") } catch {}
        XCTAssertTrue(first.deletionNeedsReauthentication)
        await http.setUser(original.userID)
        _ = try await login(first)
        try first.prepareAccountDeletion(userID: original.userID)
        do { _ = try await first.deleteAccount(userID: original.userID); XCTFail("Successor should lack Auth") } catch {}
        let later = UUID()
        await http.setUser(later)
        _ = try await login(first)
        let savedB = try XCTUnwrap(storage.retrieve(key: first.sessionKey))
        let cold = service(http, storage: storage, host: host)
        let restored = try await cold.restoreSession()
        XCTAssertEqual(restored?.userID, later)
        await http.setDeletionResponse(Data(#"{"data":{"deleted":true}}"#.utf8), status: 200)
        _ = try await cold.retryAccountDeletion(userID: original.userID)
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 4)
        XCTAssertTrue(headers[0] == headers[1])
        XCTAssertTrue(headers[0] != headers[2])
        XCTAssertTrue(headers[0] == headers[3], "Cold receipt check must retain the predecessor authorization")
        XCTAssertEqual(try cold.activeBinding().userID, later)
        XCTAssertTrue(try storage.retrieve(key: cold.sessionKey) == savedB)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.retrieve(key: cold.deletionKey))) as? [String: Any])
        let record = try XCTUnwrap((document["records"] as? [[String: Any]])?.first)
        XCTAssertEqual(record["confirmed"] as? Bool, true)
        XCTAssertEqual((record["predecessors"] as? [[String: Any]])?.count, 1,
                       "Confirmed ancestry stays secure until durable local handoff")
        storage.fail(.remove, key: cold.deletionKey)
        XCTAssertThrowsError(try cold.acknowledgeAccountDeletion(userID: original.userID))
        storage.recover()
        try cold.acknowledgeAccountDeletion(userID: original.userID)
        XCTAssertNil(try storage.retrieve(key: cold.deletionKey))
        XCTAssertEqual(try cold.activeBinding().userID, later)
        _ = await cold.signOut()
    }

    func testTypedRejectionStillAllowsExplicitCapturedReceiptCheckWithoutFreshSignIn() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let user = try await login(service)
        var cleaned: [UUID] = []
        let model = AccountModel(service: service, didDeleteAccount: { cleaned.append($0) })
        await model.start()
        await http.setDeletionResponse(Data(#"{"error":{"code":"not_authenticated","message":"Sign in and try again."}}"#.utf8), status: 401)
        await model.deleteAccount()
        XCTAssertEqual(model.authRecovery?.action, .deletionReauthentication)
        await http.setDeletionResponse(Data(#"{"data":{"deleted":true}}"#.utf8), status: 200)
        await model.retryAuthRecovery()
        XCTAssertEqual(cleaned, [user.userID])
        let signIns = await http.count("token")
        XCTAssertEqual(signIns, 1)
        let headers = await http.deletionAuthorizations()
        XCTAssertEqual(headers.count, 2)
        XCTAssertTrue(headers[0] == headers[1])
        XCTAssertNil(try storage.retrieve(key: service.deletionKey))
    }

    func testConcurrentDeletionAndCancellationShareOneDispatchAndRetainConfirmation() async throws {
        let storage = AuthMemoryStorage(), http = AuthHTTPFixture(), service = service(http, storage: storage)
        let user = try await login(service)
        await http.hold("delete-account")
        let first = Task { try await service.deleteAccount() }
        try await wait { await http.suspended("delete-account") }
        let second = Task { try await service.deleteAccount() }
        first.cancel()
        await http.release("delete-account")
        _ = try await first.value
        _ = try await second.value
        let count = await http.count("delete-account")
        XCTAssertEqual(count, 1)
        _ = try await service.deleteAccount()
        let after = await http.count("delete-account")
        XCTAssertEqual(after, 1)
        storage.fail(.remove, key: service.deletionKey)
        XCTAssertThrowsError(try service.acknowledgeAccountDeletion(userID: user.userID))
        storage.recover()
        try service.acknowledgeAccountDeletion(userID: user.userID)
    }
}

private actor DeletionReceiptProxy {
    private let upstream = URLSession(configuration: .ephemeral)
    private var refreshContinuation: CheckedContinuation<Void, Never>?
    private var heldRefresh = false
    private var deletionHeaders: [String] = []
    private var droppedCommittedResponse = false
    private var refreshChangedBearer = false
    private var initialBearer: String?
    func isRefreshHeld() -> Bool { heldRefresh }
    func releaseRefresh() { refreshContinuation?.resume(); refreshContinuation = nil }
    func proof() -> (same: Bool, count: Int, dropped: Bool, refreshed: Bool) {
        (deletionHeaders.count == 2 && !deletionHeaders[0].isEmpty && deletionHeaders[0] == deletionHeaders[1],
         deletionHeaders.count, droppedCommittedResponse, refreshChangedBearer)
    }
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // URLSession may represent a body as a stream at this boundary.
        var forwarded = request
        if forwarded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data(), buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            forwarded.httpBodyStream = nil
            forwarded.httpBody = bytes
        }
        let url = request.url!
        let refresh = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains {
            $0.name == "grant_type" && $0.value == "refresh_token"
        } == true
        let deletion = url.lastPathComponent == "delete-account"
        if deletion {
            let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
            deletionHeaders.append(header)
            initialBearer = header
        }
        let result = try await upstream.data(for: forwarded)
        if refresh {
            guard let response = result.1 as? HTTPURLResponse, response.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: result.0) as? [String: Any],
                  let issued = body["access_token"] as? String else { throw ProbeFailure.refreshRejected }
            heldRefresh = true
            await withCheckedContinuation { refreshContinuation = $0 }
            refreshChangedBearer = initialBearer != nil && initialBearer != "Bearer " + issued
        }
        if deletion, !droppedCommittedResponse {
            guard let response = result.1 as? HTTPURLResponse, response.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: result.0) as? [String: Any],
                  let data = body["data"] as? [String: Any], data["deleted"] as? Bool == true else {
                throw ProbeFailure.deletionRejected
            }
            droppedCommittedResponse = true
            throw URLError(.networkConnectionLost)
        }
        return result
    }
    private enum ProbeFailure: Error { case refreshRejected, deletionRejected }
}

private final class DeletionReceiptProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixture: (origin: String, proxy: DeletionReceiptProxy)?
    private var loading: Task<Void, Never>?
    static func install(origin: String, proxy: DeletionReceiptProxy) { lock.withLock { fixture = (origin, proxy) } }
    static func uninstall() { lock.withLock { fixture = nil } }
    override class func canInit(with request: URLRequest) -> Bool {
        lock.withLock { fixture.map { request.url?.absoluteString.hasPrefix($0.origin + "/") == true } ?? false }
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let proxy = Self.lock.withLock({ Self.fixture?.proxy }) else { return }
        let outgoing = request
        loading = Task { @Sendable [self, proxy, outgoing] in
            do {
                let (data, response) = try await proxy.fetch(outgoing)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch { self.client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { loading?.cancel() }
}

@MainActor
extension AccountAuthLifecycleTests {
    func testLocalCommittedDeletionReceiptAfterLostResponseAndIssuedRefreshWhenConfigured() async throws {
        let admission = try LocalIntegrationAdmission.admit(environment: ProcessInfo.processInfo.environment, purpose: .daily)
        let proxy = DeletionReceiptProxy()
        DeletionReceiptProtocol.install(origin: admission.configuration.projectURL.absoluteString, proxy: proxy)
        defer { DeletionReceiptProtocol.uninstall() }
        let service = SupabaseAccountService(configuration: admission.configuration, storage: AuthMemoryStorage(), network: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DeletionReceiptProtocol.self]
            return URLSession(configuration: configuration)
        })
        let user = try await service.signInForLocalTesting(email: admission.email, password: admission.password)
        do { try admission.validateIdentity(user.userID) }
        catch { _ = await service.signOut(); throw error }
        try await Task.sleep(for: .seconds(1.1))
        let refresh = Task { try await service.refreshSession() }
        do {
            try await wait { await proxy.isRefreshHeld() }
            do { _ = try await service.deleteAccount(); XCTFail("Committed first response was not lost") }
            catch let error as URLError { XCTAssertEqual(error.code, .networkConnectionLost) }
            await proxy.releaseRefresh()
            do { _ = try await refresh.value; XCTFail("Deleting consumer regained authority") }
            catch is CancellationError {}
            _ = try await service.deleteAccount()
            let proof = await proxy.proof()
            XCTAssertEqual(proof.count, 2)
            XCTAssertTrue(proof.same)
            XCTAssertTrue(proof.dropped)
            XCTAssertTrue(proof.refreshed)
            guard proof.count == 2, proof.same, proof.dropped, proof.refreshed else {
                throw AccountServiceError.invalidResponse
            }
            try service.acknowledgeAccountDeletion(userID: user.userID)
            print("GRIDRACE_P4_ORIGINAL_BEARER_RECEIPT_PASS")
        } catch {
            await proxy.releaseRefresh()
            refresh.cancel()
            _ = await service.signOut()
            throw error
        }
    }
}
