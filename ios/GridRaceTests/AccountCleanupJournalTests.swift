import Foundation
import XCTest
@testable import GridRace

private final class CleanupJournalFaultStore: AccountCleanupJournalStoring {
    var records: [AccountCleanupRecord] = []
    var rejectsRead = false
    var rejectsWrite = false
    var rejectsClear = false
    func load() throws -> [AccountCleanupRecord] {
        if rejectsRead { throw Failure.unavailable }
        return records
    }
    func save(_ records: [AccountCleanupRecord]) throws {
        if rejectsWrite || (records.isEmpty && rejectsClear) { throw Failure.unavailable }
        self.records = records
    }
    private enum Failure: Error { case unavailable }
}

@MainActor
final class AccountCleanupJournalTests: XCTestCase {
    func testPreconfirmationNeverAuthorizesDailyCleanupAndScopesFinishIndependently() throws {
        let storage = CleanupJournalFaultStore(), user = UUID()
        let first = AccountCleanupJournal(storage: storage)
        try first.capture(user, deleting: true)
        let beforeConfirmation = AccountCleanupJournal(storage: storage)
        XCTAssertTrue(beforeConfirmation.dailyUsers.isEmpty)
        XCTAssertEqual(beforeConfirmation.liveUsers, [user])
        try first.confirmDeletion(user)
        try first.completeLive(user)
        let cold = AccountCleanupJournal(storage: storage)
        XCTAssertEqual(cold.dailyUsers, [user])
        XCTAssertTrue(cold.liveUsers.isEmpty)
        try cold.completeDaily(user)
        XCTAssertTrue(AccountCleanupJournal(storage: storage).records.isEmpty)
    }

    func testReadWriteAndFinalClearFailureNeverAcknowledgeLostObligation() throws {
        let storage = CleanupJournalFaultStore(), user = UUID(), other = UUID()
        let journal = AccountCleanupJournal(storage: storage)
        try journal.capture(user, deleting: true)
        try journal.confirmDeletion(user)
        storage.rejectsRead = true
        let unavailable = AccountCleanupJournal(storage: storage)
        XCTAssertTrue(unavailable.isUnavailable)
        XCTAssertThrowsError(try unavailable.capture(other, deleting: false))
        XCTAssertEqual(storage.records.map(\.userID), [user])
        storage.rejectsRead = false
        try unavailable.reload()
        XCTAssertEqual(unavailable.dailyUsers, [user])
        storage.rejectsWrite = true
        XCTAssertThrowsError(try unavailable.completeDaily(user))
        XCTAssertEqual(unavailable.dailyUsers, [user])
        storage.rejectsWrite = false
        try unavailable.completeDaily(user)
        storage.rejectsClear = true
        XCTAssertThrowsError(try unavailable.completeLive(user))
        XCTAssertEqual(AccountCleanupJournal(storage: storage).liveUsers, [user])
        storage.rejectsClear = false
        try unavailable.completeLive(user)
        XCTAssertTrue(storage.records.isEmpty)
    }

    func testVersionedNonsecretJournalSurvivesTargetDirectoryRemovalAndPreservesUnknownOrphans() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CleanupJournal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let user = UUID(), other = UUID()
        let account = root.appending(path: "Accounts/\(user.uuidString.lowercased())")
        let unknown = root.appending(path: "Accounts/\(other.uuidString.lowercased())")
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        let sentinel = Data("retained unknown history".utf8)
        try sentinel.write(to: unknown.appending(path: "sentinel"))
        let file = AccountCleanupJournalFile(directory: root)
        let journal = AccountCleanupJournal(storage: file)
        try journal.capture(user, deleting: true)
        try journal.confirmDeletion(user)
        try FileManager.default.removeItem(at: account)
        let cold = AccountCleanupJournal(storage: file)
        XCTAssertEqual(cold.dailyUsers, [user])
        XCTAssertEqual(cold.liveUsers, [user])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["version", "records"])
        let record = try XCTUnwrap((payload["records"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(record.keys), ["userID", "daily", "live"])
        try cold.completeDaily(user)
        try cold.completeLive(user)
        XCTAssertEqual(try Data(contentsOf: unknown.appending(path: "sentinel")), sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }
}
