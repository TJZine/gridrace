import Foundation
import XCTest
@testable import GridRace

@MainActor
final class LocalIntegrationAdmissionTests: XCTestCase {
    private let fixtureTime = Date(timeIntervalSince1970: 1_800_000_000)

    func testUnsafeEntriesNeverReachTransport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let run = UUID(), user = UUID(), now = fixtureTime
        let filename = "fixture-\(run.uuidString).json"
        let path = directory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [AdmissionCountingTransport.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        for purpose in [LocalIntegrationAdmission.Purpose.daily, .live] {
            let receipt = LocalIntegrationAdmission.Receipt(
                version: 1, runID: run, endpoint: "http://127.0.0.1:55421", unlinked: true,
                createdAt: now, purpose: purpose, userID: user, email: "owned@example.test")
            try encoder.encode(receipt).write(to: path)
            let prefix = purpose == .daily ? "GRIDRACE_LOCAL_SYNC" : "GRIDRACE_LIVE"
            let valid = ["GRIDRACE_LOCAL_INTEGRATION": "1", "GRIDRACE_LOCAL_SUPABASE_URL": receipt.endpoint,
                         "GRIDRACE_LOCAL_SUPABASE_KEY": "sb_publishable_test_fixture_key",
                         "GRIDRACE_FIXTURE_RUN_ID": run.uuidString, "GRIDRACE_FIXTURE_RECEIPT": filename,
                         prefix + "_EMAIL": receipt.email, prefix + "_PASSWORD": "test-password",
                         "GRIDRACE_LIVE_ROLE": "host", "GRIDRACE_LIVE_SCENARIO": "product",
                         "GRIDRACE_LIVE_ROUND_COUNT": "1", "GRIDRACE_LIVE_ROUND_NUMBER": "1",
                         "GRIDRACE_LIVE_FAILED_GUESS": "zzzzz"]
            let admitted = try LocalIntegrationAdmission.admit(environment: valid, purpose: purpose, now: now, receiptDirectory: directory)
            try admitted.validateIdentity(user)
            XCTAssertThrowsError(try admitted.validateIdentity(UUID()))
            var cases: [[String: String]] = []
            for endpoint in ["https://example.com", "not a url", "http://127.0.0.1:55421/path",
                             "http://localhost:55421", "http://user@127.0.0.1:55421",
                             "http://127.0.0.1:55421?x=1", "http://127.0.0.1:0"] {
                var invalid = valid; invalid["GRIDRACE_LOCAL_SUPABASE_URL"] = endpoint; cases.append(invalid)
            }
            for missing in ["GRIDRACE_LOCAL_INTEGRATION", "GRIDRACE_FIXTURE_RUN_ID", "GRIDRACE_FIXTURE_RECEIPT"] {
                var invalid = valid; invalid.removeValue(forKey: missing); cases.append(invalid)
            }
            for privileged in ["SERVICE_ROLE_KEY", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY",
                               "DB_URL", "DATABASE_URL", "JWT_SECRET", "SUPABASE_DB_PASSWORD"] {
                var invalid = valid; invalid[privileged] = ""; cases.append(invalid)
            }
            var secretKey = valid; secretKey["GRIDRACE_LOCAL_SUPABASE_KEY"] = "sb_secret_fixture"; cases.append(secretKey)
            var nonexistent = valid; nonexistent["GRIDRACE_FIXTURE_RECEIPT"] = path.path + ".missing"; cases.append(nonexistent)
            let servicePayload = Data("{\"role\":\"service_role\"}".utf8).base64EncodedString()
            var privilegedJWT = valid; privilegedJWT["GRIDRACE_LOCAL_SUPABASE_KEY"] = "header." + servicePayload + ".signature"; cases.append(privilegedJWT)
            var wrongRun = valid; wrongRun["GRIDRACE_FIXTURE_RUN_ID"] = UUID().uuidString; cases.append(wrongRun)
            if purpose == .live {
                for key in ["GRIDRACE_LIVE_ROLE", "GRIDRACE_LIVE_SCENARIO", "GRIDRACE_LIVE_ROUND_COUNT",
                            "GRIDRACE_LIVE_ROUND_NUMBER"] {
                    var invalid = valid; invalid[key] = "invalid"; cases.append(invalid)
                }
            }
            for invalid in cases {
                do {
                    let admission = try LocalIntegrationAdmission.admit(environment: invalid, purpose: purpose, now: now, receiptDirectory: directory)
                    _ = try await session.data(from: admission.configuration.projectURL)
                    XCTFail("Unsafe integration entry was admitted")
                } catch is XCTSkip { } catch is LocalIntegrationAdmission.Refusal { }
                catch {
                    XCTFail("Admission reached transport or threw an unexpected error")
                }
                XCTAssertEqual(AdmissionCountingTransport.requestCount, 0)
            }
            for badReceipt in [
                LocalIntegrationAdmission.Receipt(version: 1, runID: run, endpoint: receipt.endpoint,
                    unlinked: false, createdAt: now, purpose: purpose, userID: user, email: receipt.email),
                LocalIntegrationAdmission.Receipt(version: 1, runID: run, endpoint: receipt.endpoint,
                    unlinked: true, createdAt: now.addingTimeInterval(-21601), purpose: purpose,
                    userID: user, email: receipt.email),
                LocalIntegrationAdmission.Receipt(version: 1, runID: run, endpoint: receipt.endpoint,
                    unlinked: true, createdAt: now.addingTimeInterval(-21600), purpose: purpose,
                    userID: user, email: receipt.email),
                LocalIntegrationAdmission.Receipt(version: 1, runID: run, endpoint: receipt.endpoint,
                    unlinked: true, createdAt: now.addingTimeInterval(1), purpose: purpose,
                    userID: user, email: receipt.email)
            ] {
                try encoder.encode(badReceipt).write(to: path)
                XCTAssertThrowsError(try LocalIntegrationAdmission.admit(environment: valid, purpose: purpose, now: now, receiptDirectory: directory))
                XCTAssertEqual(AdmissionCountingTransport.requestCount, 0)
            }
            let stillFresh = LocalIntegrationAdmission.Receipt(version: 1, runID: run, endpoint: receipt.endpoint,
                unlinked: true, createdAt: now.addingTimeInterval(-21599), purpose: purpose,
                userID: user, email: receipt.email)
            try encoder.encode(stillFresh).write(to: path)
            _ = try LocalIntegrationAdmission.admit(environment: valid, purpose: purpose, now: now, receiptDirectory: directory)
        }
    }

    func testReceiptDeliveryResolvesCurrentContainerAndRejectsHostPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let former = root.appendingPathComponent("former-container")
        let current = root.appendingPathComponent("current-container")
        for directory in [former, current] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let run = UUID(), user = UUID(), now = fixtureTime
        let filename = "fixture-\(run.uuidString).json"
        let receipt = LocalIntegrationAdmission.Receipt(version: 1, runID: run,
            endpoint: "http://127.0.0.1:55421", unlinked: true, createdAt: now,
            purpose: .daily, userID: user, email: "owned@example.test")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let original = former.appendingPathComponent(filename)
        try encoder.encode(receipt).write(to: original)
        var environment = ["GRIDRACE_LOCAL_INTEGRATION": "1",
            "GRIDRACE_LOCAL_SUPABASE_URL": receipt.endpoint,
            "GRIDRACE_LOCAL_SUPABASE_KEY": "sb_publishable_test_fixture_key",
            "GRIDRACE_FIXTURE_RUN_ID": run.uuidString, "GRIDRACE_FIXTURE_RECEIPT": filename,
            "GRIDRACE_LOCAL_SYNC_EMAIL": receipt.email, "GRIDRACE_LOCAL_SYNC_PASSWORD": "test-password"]
        try FileManager.default.moveItem(at: original, to: current.appendingPathComponent(filename))
        let admitted = try LocalIntegrationAdmission.admit(environment: environment, purpose: .daily,
            now: now, receiptDirectory: current)
        try admitted.validateIdentity(user)
        XCTAssertThrowsError(try LocalIntegrationAdmission.admit(environment: environment, purpose: .daily,
            now: now, receiptDirectory: former))
        environment["GRIDRACE_FIXTURE_RECEIPT"] = current.appendingPathComponent(filename).path
        XCTAssertThrowsError(try LocalIntegrationAdmission.admit(environment: environment, purpose: .daily,
            now: now, receiptDirectory: current))
        environment["GRIDRACE_FIXTURE_RECEIPT"] = "../" + filename
        XCTAssertThrowsError(try LocalIntegrationAdmission.admit(environment: environment, purpose: .daily,
            now: now, receiptDirectory: current))
    }

    func testStrictLoopbackOrigins() {
        XCTAssertTrue(LocalIntegrationAdmission.isLoopbackOrigin("http://localhost:55421"))
        XCTAssertTrue(LocalIntegrationAdmission.isLoopbackOrigin("http://127.0.0.1:54321"))
        for value in ["http://localhost", "http://127.0.0.1:54321/", "http://127.1:54321",
                      "http://localhost.:54321", "http://localhost:99999", "http://localhost:054321",
                      "http://localhost:54321#fragment", "https://localhost:54321"] {
            XCTAssertFalse(LocalIntegrationAdmission.isLoopbackOrigin(value), value)
        }
    }
}

private final class AdmissionCountingTransport: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}
