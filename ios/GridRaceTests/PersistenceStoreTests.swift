import Foundation
import XCTest
@testable import GridRace

final class PersistenceStoreTests: XCTestCase {
    func testMissingFilesAndRemovalAreIdempotent() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root)
        let account = AccountDailyClassicStore(rootDirectory: root, userID: UUID())
        let live = LiveMatchRecoveryStore(rootDirectory: root, userID: account.userID)
        XCTAssertNil(try guest.loadProgress())
        XCTAssertEqual(try guest.loadHistory(), DailyClassicHistory())
        XCTAssertEqual(try account.loadSyncMetadata(), DailySyncMetadata())
        XCTAssertEqual(try live.load(), LiveRecoveryState())
        for _ in 0..<2 {
            try guest.discardProgress()
            try guest.resetGuestDailyData()
            try live.clear()
            try account.deleteAccountCache()
        }
    }

    func testReadableCorruptAndWrongTypeRemainDistinctFromMissing() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root)
        let account = AccountDailyClassicStore(rootDirectory: root, userID: UUID())
        let live = LiveMatchRecoveryStore(rootDirectory: root, userID: account.userID)
        let progress = DailyClassicProgress(puzzle: DailyPuzzle(id: "fixture", number: 1,
            day: 20_696, answer: "adore", wordPackID: "daily-classic-en-US-v1", scheduleVersion: 1),
            hardModeEnabled: false)
        try guest.save(progress)
        try guest.save(DailyClassicHistory())
        XCTAssertEqual(try guest.loadProgress(), progress)
        try account.save(DailySyncMetadata(pendingProgress: true))
        let state = LiveRecoveryState(matchID: UUID())
        try live.save(state)
        XCTAssertEqual(try guest.loadHistory(), DailyClassicHistory())
        XCTAssertTrue(try account.loadSyncMetadata().pendingProgress)
        XCTAssertEqual(try live.load(), state)
        let paths = [
            root.appending(path: "daily-progress-v1.json"),
            root.appending(path: "daily-history-v1.json"),
            account.directory.appending(path: "daily-sync-metadata-v1.json"),
            live.directory.appending(path: "live-recovery-v1.json")
        ]
        for path in paths { try Data("{broken".utf8).write(to: path) }
        XCTAssertThrowsError(try guest.loadProgress()) { XCTAssertEqual($0 as? DailyClassicError, .invalidSavedGame) }
        XCTAssertThrowsError(try guest.loadHistory()) { XCTAssertTrue($0 is DecodingError) }
        XCTAssertThrowsError(try account.loadSyncMetadata()) { XCTAssertEqual($0 as? DailySyncError, .invalidLocalData) }
        XCTAssertThrowsError(try live.load()) { XCTAssertEqual($0 as? LiveMatchRecoveryError, .invalidData) }
        for path in paths {
            try FileManager.default.removeItem(at: path)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        }
        let reads: [() throws -> Void] = [
            { _ = try guest.loadProgress() }, { _ = try guest.loadHistory() },
            { _ = try account.loadSyncMetadata() }, { _ = try live.load() }
        ]
        for read in reads {
            XCTAssertThrowsError(try read()) { XCTAssertFalse(PersistenceFile.isNotFound($0)) }
        }
    }

    func testWrongTypeRemovalRetainsUnexpectedDirectories() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root)
        let account = AccountDailyClassicStore(rootDirectory: root, userID: UUID())
        let live = LiveMatchRecoveryStore(rootDirectory: root, userID: account.userID)
        let paths = [root.appending(path: "daily-progress-v1.json"),
                     live.directory.appending(path: "live-recovery-v1.json")]
        for path in paths {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try Data("survivor".utf8).write(to: path.appending(path: "sentinel"))
        }
        XCTAssertThrowsError(try guest.discardProgress())
        XCTAssertThrowsError(try live.clear())
        for path in paths {
            XCTAssertEqual(try Data(contentsOf: path.appending(path: "sentinel")), Data("survivor".utf8))
        }
        try FileManager.default.removeItem(at: account.directory)
        try Data("wrong cache type".utf8).write(to: account.directory)
        XCTAssertThrowsError(try account.deleteAccountCache())
        XCTAssertEqual(try Data(contentsOf: account.directory), Data("wrong cache type".utf8))
    }

    func testExplicitGuestResetRemovesMalformedEntriesAndPreservesSiblingScopes() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root)
        let account = AccountDailyClassicStore(rootDirectory: root, userID: UUID())
        try account.save(DailySyncMetadata(pendingProgress: true))
        let accountPath = account.directory.appending(path: "daily-sync-metadata-v1.json")
        let accountBytes = try Data(contentsOf: accountPath)
        let sibling = root.appending(path: "sibling.txt")
        let siblingBytes = Data("preserved sibling".utf8)
        try siblingBytes.write(to: sibling)
        for filename in ["daily-progress-v1.json", "daily-history-v1.json"] {
            let malformed = root.appending(path: filename)
            try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: false)
            try Data("malformed guest entry".utf8).write(to: malformed.appending(path: "nested.txt"))
        }
        XCTAssertThrowsError(try guest.discardProgress(), "Ordinary discard still rejects malformed directories")
        try guest.resetGuestDailyData()
        XCTAssertNil(try guest.loadProgress())
        XCTAssertEqual(try guest.loadHistory(), DailyClassicHistory())
        XCTAssertEqual(try Data(contentsOf: accountPath), accountBytes)
        XCTAssertEqual(try Data(contentsOf: sibling), siblingBytes)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType, .typeDirectory)
        try guest.resetGuestDailyData()
    }

    func testDeniedAncestorRetainsBytesAndRestoredRetryPreservesOtherScopes() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let protected = root.appending(path: "owned-denied")
        let guest = DailyClassicStore(directory: protected)
        let account = AccountDailyClassicStore(rootDirectory: protected, userID: UUID())
        let live = LiveMatchRecoveryStore(rootDirectory: protected, userID: account.userID)
        let survivor = AccountDailyClassicStore(rootDirectory: root, userID: UUID())
        let survivorGuest = DailyClassicStore(directory: root)
        try survivor.save(DailySyncMetadata(pendingProgress: true))
        try survivorGuest.save(DailyClassicHistory())
        try guest.save(DailyClassicHistory())
        let progressURL = protected.appending(path: "daily-progress-v1.json")
        try Data("{broken".utf8).write(to: progressURL)
        try account.save(DailySyncMetadata(pendingProgress: true))
        try live.save(LiveRecoveryState(matchID: UUID()))
        let paths = [progressURL, protected.appending(path: "daily-history-v1.json"),
                     account.directory.appending(path: "daily-sync-metadata-v1.json"),
                     live.directory.appending(path: "live-recovery-v1.json")]
        let bytes = try paths.map { try Data(contentsOf: $0) }
        let survivorPath = survivor.directory.appending(path: "daily-sync-metadata-v1.json")
        let survivorBytes = try Data(contentsOf: survivorPath)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: protected.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path) }
        // A platform that bypasses chmod cannot establish this premise.
        if (try? Data(contentsOf: progressURL)) != nil {
            throw XCTSkip("Runtime bypasses owned ancestor permission denial")
        }
        let operations: [() throws -> Void] = [
            { _ = try guest.loadProgress() }, { _ = try guest.loadHistory() },
            { _ = try account.loadSyncMetadata() }, { _ = try live.load() },
            { try guest.discardProgress() }, { try guest.resetGuestDailyData() },
            { try live.clear() }, { try account.deleteAccountCache() }
        ]
        for operation in operations {
            XCTAssertThrowsError(try operation()) { XCTAssertFalse(PersistenceFile.isNotFound($0)) }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path)
        XCTAssertEqual(try paths.map { try Data(contentsOf: $0) }, bytes)
        try guest.resetGuestDailyData()
        try live.clear()
        try account.deleteAccountCache()
        XCTAssertNil(try guest.loadProgress())
        XCTAssertEqual(try live.load(), LiveRecoveryState())
        XCTAssertEqual(try Data(contentsOf: survivorPath), survivorBytes)
        XCTAssertEqual(try survivorGuest.loadHistory(), DailyClassicHistory())
    }

    func testReadableFilesWithDeniedRemovalRemainForRetry() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root.appending(path: "Guest"))
        let account = AccountDailyClassicStore(rootDirectory: root, userID: UUID())
        let live = LiveMatchRecoveryStore(rootDirectory: root, userID: account.userID)
        try guest.save(DailyClassicHistory())
        try account.save(DailySyncMetadata(pendingProgress: true))
        let state = LiveRecoveryState(matchID: UUID())
        try live.save(state)
        let accountsRoot = account.directory.deletingLastPathComponent()
        let deniedDirectories = [guest.directory, live.directory, accountsRoot]
        for directory in deniedDirectories {
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        }
        defer {
            for directory in deniedDirectories {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            }
        }
        XCTAssertEqual(try guest.loadHistory(), DailyClassicHistory())
        XCTAssertTrue(try account.loadSyncMetadata().pendingProgress)
        XCTAssertEqual(try live.load(), state)
        XCTAssertThrowsError(try guest.resetGuestDailyData())
        XCTAssertThrowsError(try live.clear())
        XCTAssertThrowsError(try account.deleteAccountCache())
        XCTAssertEqual(try live.load(), state)
        XCTAssertTrue(try account.loadSyncMetadata().pendingProgress)
        for directory in deniedDirectories {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        try guest.resetGuestDailyData()
        try live.clear()
        try account.deleteAccountCache()
        XCTAssertEqual(try live.load(), LiveRecoveryState())
    }

    func testNonDirectoryAncestorDoesNotBecomeAbsent() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("wrong ancestor type".utf8).write(to: root)
        let guest = DailyClassicStore(directory: root)
        let account = AccountDailyClassicStore(rootDirectory: root, userID: UUID())
        let live = LiveMatchRecoveryStore(rootDirectory: root, userID: account.userID)
        let operations: [() throws -> Void] = [
            { _ = try guest.loadProgress() }, { _ = try guest.loadHistory() },
            { _ = try account.loadSyncMetadata() }, { _ = try live.load() },
            { try guest.discardProgress() }, { try guest.resetGuestDailyData() },
            { try live.clear() }, { try account.deleteAccountCache() }
        ]
        for operation in operations {
            XCTAssertThrowsError(try operation()) { XCTAssertFalse(PersistenceFile.isNotFound($0)) }
        }
        XCTAssertEqual(try Data(contentsOf: root), Data("wrong ancestor type".utf8))
    }

    func testPartialGuestResetReportsRemainingImmutableHistoryAndRetries() throws {
        let root = ownedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = DailyClassicStore(directory: root)
        try guest.save(DailyClassicHistory())
        let progress = root.appending(path: "daily-progress-v1.json")
        let history = root.appending(path: "daily-history-v1.json")
        try Data("retained progress".utf8).write(to: progress)
        let before = try Data(contentsOf: history)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: history.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: history.path) }
        XCTAssertThrowsError(try guest.resetGuestDailyData())
        XCTAssertNil(try guest.loadProgress())
        XCTAssertEqual(try Data(contentsOf: history), before)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: history.path)
        try guest.resetGuestDailyData()
        XCTAssertEqual(try guest.loadHistory(), DailyClassicHistory())
    }

    func testOnlyDocumentedNotFoundCodesMeanAbsent() {
        for code in [CocoaError.fileReadNoSuchFile.rawValue, CocoaError.fileNoSuchFile.rawValue] {
            XCTAssertTrue(PersistenceFile.isNotFound(NSError(domain: NSCocoaErrorDomain, code: code)))
        }
        XCTAssertTrue(PersistenceFile.isNotFound(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
        for code in [EACCES, EPERM, ENOTDIR, EISDIR] {
            XCTAssertFalse(PersistenceFile.isNotFound(NSError(domain: NSPOSIXErrorDomain, code: Int(code))))
        }
        for code in [EACCES, EPERM, ENOTDIR, EISDIR] {
            XCTAssertFalse(PersistenceFile.isNotFound(NSError(domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadNoSuchFile.rawValue,
                userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(code))])))
        }
        XCTAssertFalse(PersistenceFile.isNotFound(NSError(domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadNoPermission.rawValue,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))])))
    }

    private func ownedRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "GridRacePersistenceTests-\(UUID())")
    }
}
