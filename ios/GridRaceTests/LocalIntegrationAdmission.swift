import Foundation
import XCTest
@testable import GridRace

struct LocalIntegrationAdmission {
    enum Purpose: String, Codable { case daily, live }
    struct Receipt: Codable {
        let version: Int
        let runID: UUID
        let endpoint: String
        let unlinked: Bool
        let createdAt: Date
        let purpose: Purpose
        let userID: UUID
        let email: String
    }
    enum Refusal: Error { case unsafeConfiguration, invalidReceipt, wrongIdentity }

    let receipt: Receipt
    let configuration: SupabaseAccountService.Configuration
    let email: String
    let password: String

    @MainActor
    static func admit(environment: [String: String], purpose: Purpose,
                      now: Date = Date(), receiptDirectory: URL? = nil) throws -> Self {
        guard environment["GRIDRACE_LOCAL_INTEGRATION"] == "1" else {
            throw XCTSkip("Disposable local integration is not explicitly enabled")
        }
        let privileged = ["SERVICE_ROLE_KEY", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY",
                          "DB_URL", "DATABASE_URL", "JWT_SECRET", "SUPABASE_DB_PASSWORD"]
        guard privileged.allSatisfy({ environment[$0] == nil }),
              let endpoint = environment["GRIDRACE_LOCAL_SUPABASE_URL"],
              isLoopbackOrigin(endpoint),
              let key = environment["GRIDRACE_LOCAL_SUPABASE_KEY"], isPublicKey(key),
              let configuration = SupabaseAccountService.Configuration(
                urlString: endpoint, publishableKey: key)
        else { throw Refusal.unsafeConfiguration }

        let prefix = purpose == .daily ? "GRIDRACE_LOCAL_SYNC" : "GRIDRACE_LIVE"
        guard let email = environment[prefix + "_EMAIL"], !email.isEmpty,
              let password = environment[prefix + "_PASSWORD"], !password.isEmpty
        else { throw receiptRefusal(.credentialsMissing) }
        guard let runID = environment["GRIDRACE_FIXTURE_RUN_ID"].flatMap(UUID.init(uuidString:))
        else { throw receiptRefusal(.runIDInvalid) }
        let filename = "fixture-\(runID.uuidString).json"
        guard environment["GRIDRACE_FIXTURE_RECEIPT"] == filename
        else { throw receiptRefusal(.receiptNameInvalid) }
        guard let support = receiptDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GridRaceIntegration", isDirectory: true)
        else { throw receiptRefusal(.receiptDirectoryUnavailable) }
        let path = support.appendingPathComponent(filename).path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else { throw receiptRefusal(.receiptAttributesUnavailable) }
        guard attributes[.type] as? FileAttributeType == .typeRegular
        else { throw receiptRefusal(.receiptNotRegular) }
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 4096
        else { throw receiptRefusal(.receiptSizeInvalid) }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { throw receiptRefusal(.receiptReadUnavailable) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let receipt = try? decoder.decode(Receipt.self, from: data),
              receipt.version == 1, receipt.runID == runID, receipt.endpoint == endpoint,
              receipt.unlinked, receipt.purpose == purpose, receipt.email == email,
              receipt.createdAt <= now, now.timeIntervalSince(receipt.createdAt) < 6 * 60 * 60
        else { throw receiptRefusal(.receiptContentInvalid) }
        if purpose == .live {
            guard ["host", "guest", "resume", "survivor", "advance-host", "advance-guest",
                   "solve-host", "solve-guest", "friends-both", "friends-recover", "friends-select", "friends-stale", "friends-resume", "friends-race", "friends-offer", "friends-cancel", "friends-decline", "friends-close-disabled", "friends-signal-host", "friends-signal-guest", "invitation-root"].contains(environment["GRIDRACE_LIVE_ROLE"] ?? ""),
                  ["product", "mixed", "cron", "deletion", "friends", "invitation"].contains(environment["GRIDRACE_LIVE_SCENARIO"] ?? ""),
                  let count = Int(environment["GRIDRACE_LIVE_ROUND_COUNT"] ?? ""), [1, 3, 5].contains(count),
                  let round = Int(environment["GRIDRACE_LIVE_ROUND_NUMBER"] ?? ""), (1...count).contains(round),
                  let guess = environment["GRIDRACE_LIVE_FAILED_GUESS"],
                  guess.utf8.count == 5, guess.utf8.allSatisfy({ (97...122).contains($0) })
            else { throw Refusal.unsafeConfiguration }
        }
        return Self(receipt: receipt, configuration: configuration, email: email, password: password)
    }

    private enum ReceiptRefusalReason: String {
        case credentialsMissing = "credentials-missing"
        case runIDInvalid = "run-id-invalid"
        case receiptNameInvalid = "receipt-name-invalid"
        case receiptDirectoryUnavailable = "receipt-directory-unavailable"
        case receiptAttributesUnavailable = "receipt-attributes-unavailable"
        case receiptNotRegular = "receipt-not-regular"
        case receiptSizeInvalid = "receipt-size-invalid"
        case receiptReadUnavailable = "receipt-read-unavailable"
        case receiptContentInvalid = "receipt-content-invalid"
    }

    private static func receiptRefusal(_ reason: ReceiptRefusalReason) -> Refusal {
        print("GRIDRACE_INTEGRATION_ADMISSION_REFUSED \(reason.rawValue)")
        return .invalidReceipt
    }

    func validateIdentity(_ userID: UUID) throws {
        guard userID == receipt.userID else { throw Refusal.wrongIdentity }
    }

    static func isLoopbackOrigin(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "http",
              let host = url.host, ["127.0.0.1", "localhost"].contains(host),
              let port = url.port, (1...65535).contains(port),
              url.user == nil, url.password == nil, url.path.isEmpty,
              url.query == nil, url.fragment == nil
        else { return false }
        return value == "http://\(host):\(port)"
    }

    private static func isPublicKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_"), key.count > 20 { return true }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["role"] as? String == "anon"
    }
}
