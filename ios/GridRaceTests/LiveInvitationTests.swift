import Foundation
import XCTest
@testable import GridRace

final class LiveInvitationParserTests: XCTestCase {
    private let origin = URL(string: "https://Join.Example.test/")!

    func testConfiguredHTTPSOriginAndLowercaseCodeAreCanonicalized() throws {
        let parser = try LiveInvitationParser(allowedOrigins: [origin])
        let invitation = try XCTUnwrap(parser.parse(URL(string: "https://join.example.test/join/a2b3c4")!))

        XCTAssertEqual(invitation.format, PendingLiveInvitation.currentFormat)
        XCTAssertEqual(invitation.origin, "https://join.example.test")
        XCTAssertEqual(invitation.code, "A2B3C4")
        XCTAssertEqual(invitation.replacementGeneration, PendingLiveInvitation.unassignedGeneration)
    }

    func testMalformedOrUnconfiguredLinksAreRejectedWithoutAValue() throws {
        let parser = try LiveInvitationParser(allowedOrigins: [origin])
        let acceptsDefaultHTTPSPort = try XCTUnwrap(
            parser.parse(URL(string: "https://join.example.test:443/join/A2B3C4")!)
        )
        XCTAssertEqual(acceptsDefaultHTTPSPort.origin, "https://join.example.test")

        let malformed = [
            "http://join.example.test/join/A2B3C4",
            "https://other.example.test/join/A2B3C4",
            "https://user:password@join.example.test/join/A2B3C4",
            "https://join.example.test:444/join/A2B3C4",
            "https://join.example.test/join/A2B3C4?source=mail",
            "https://join.example.test/join/A2B3C4#fragment",
            "https://join.example.test/join/A2%32B3C4",
            "https://join.example.test%2F/join/A2B3C4",
            "https://join.example.test/join/A2B3C4/extra",
            "https://join.example.test/join/A2B3C4/",
            "https://join.example.test/JOIN/A2B3C4",
            "https://join.example.test/join/A2B3C5I",
            "https://join.example.test/join/A2B3C",
            "https://join.example.test/join/A2B3C4D",
            "https://join.example.test/join/A2B3C40"
        ]

        for link in malformed {
            XCTAssertNil(URL(string: link).flatMap { parser.parse($0) }, link)
        }
        XCTAssertThrowsError(try LiveInvitationParser(allowedOrigins: [URL(string: "http://join.example.test")!])) { error in
            XCTAssertEqual(error as? LiveInvitationParserError, .invalidConfiguredOrigin)
        }
    }
}

final class PendingLiveInvitationStoreTests: XCTestCase {
    func testRelaunchDuplicateReplacementAndMatchingGenerationClear() throws {
        let persistence = MemoryPendingInvitationPersistence()
        let store = PendingLiveInvitationStore(persistence: persistence)
        let first = PendingLiveInvitation(origin: "https://join.example.test", code: "A2B3C4")

        guard case .saved(let savedFirst) = try store.save(first) else {
            return XCTFail("The first invitation must be persisted")
        }
        XCTAssertNotEqual(savedFirst.replacementGeneration, PendingLiveInvitation.unassignedGeneration)
        let bytesAfterFirst = try XCTUnwrap(persistence.data)

        let relaunched = PendingLiveInvitationStore(persistence: persistence)
        XCTAssertEqual(try relaunched.load(), savedFirst)
        guard case .duplicate(let duplicate) = try relaunched.save(first) else {
            return XCTFail("The same invitation must be a no-op")
        }
        XCTAssertEqual(duplicate, savedFirst)
        XCTAssertEqual(persistence.data, bytesAfterFirst)

        let second = PendingLiveInvitation(origin: "https://alternate.example.test", code: "D5E6F7")
        guard case .replaced(let savedSecond) = try relaunched.save(second) else {
            return XCTFail("A different invitation must be an explicit replacement")
        }
        XCTAssertNotEqual(savedSecond.replacementGeneration, savedFirst.replacementGeneration)
        XCTAssertFalse(try relaunched.clear(matchingGeneration: savedFirst.replacementGeneration))
        XCTAssertEqual(try relaunched.load(), savedSecond)
        XCTAssertTrue(try relaunched.clear(matchingGeneration: savedSecond.replacementGeneration))
        XCTAssertNil(try relaunched.load())

        // Fresh UUID generations cannot be reused after clear, including when
        // a new store instance models process relaunch.
        let third = PendingLiveInvitation(origin: savedFirst.origin, code: "G2H3J4")
        guard case .saved(let savedThird) = try relaunched.save(third) else {
            return XCTFail("A new invitation must be saved after dismissal")
        }
        XCTAssertNotEqual(savedThird.replacementGeneration, savedSecond.replacementGeneration)
        let relaunchedAgain = PendingLiveInvitationStore(persistence: persistence)
        XCTAssertFalse(try relaunchedAgain.clear(matchingGeneration: savedSecond.replacementGeneration))
        XCTAssertEqual(try relaunchedAgain.load(), savedThird)

        let sameCodeFromAnotherOrigin = PendingLiveInvitation(
            origin: "https://alternate.example.test",
            code: savedThird.code
        )
        guard case .duplicate(let sameCode) = try relaunchedAgain.save(sameCodeFromAnotherOrigin) else {
            return XCTFail("The same canonical code must be a no-op across configured origins")
        }
        XCTAssertEqual(sameCode, savedThird)
    }

    func testCorruptAndUnavailablePersistencePreserveSavedStateAndRemainActionable() throws {
        let persistence = MemoryPendingInvitationPersistence()
        let store = PendingLiveInvitationStore(persistence: persistence)
        let invitation = PendingLiveInvitation(origin: "https://join.example.test", code: "A2B3C4")
        _ = try store.save(invitation)
        let savedBytes = try XCTUnwrap(persistence.data)

        persistence.data = Data("not-json".utf8)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? PendingLiveInvitationStoreError, .invalidData)
        }
        XCTAssertEqual(persistence.data, Data("not-json".utf8))
        XCTAssertThrowsError(try store.save(PendingLiveInvitation(origin: invitation.origin, code: "D5E6F7"))) { error in
            XCTAssertEqual(error as? PendingLiveInvitationStoreError, .invalidData)
        }
        XCTAssertEqual(persistence.data, Data("not-json".utf8))

        persistence.data = savedBytes
        persistence.readError = TestPersistenceError.failed
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? PendingLiveInvitationStoreError, .unavailable)
        }
        persistence.readError = nil
        persistence.writeError = TestPersistenceError.failed
        XCTAssertThrowsError(try store.save(PendingLiveInvitation(origin: invitation.origin, code: "D5E6F7"))) { error in
            XCTAssertEqual(error as? PendingLiveInvitationStoreError, .unavailable)
        }
        XCTAssertEqual(try store.load(), invitationPersisted(code: invitation.code, generation: savedGeneration(from: savedBytes)))
        persistence.writeError = nil
        persistence.removeError = TestPersistenceError.failed
        XCTAssertThrowsError(try store.clear()) { error in
            XCTAssertEqual(error as? PendingLiveInvitationStoreError, .unavailable)
        }
        XCTAssertEqual(try store.load(), invitationPersisted(code: invitation.code, generation: savedGeneration(from: savedBytes)))
    }

    func testInvalidCandidateCannotOverwriteExistingInvitation() throws {
        let persistence = MemoryPendingInvitationPersistence()
        let store = PendingLiveInvitationStore(persistence: persistence)
        let existing = PendingLiveInvitation(origin: "https://join.example.test", code: "A2B3C4")
        _ = try store.save(existing)
        let original = persistence.data

        let invalid = PendingLiveInvitation(origin: "https://join.example.test/path", code: "A2B3C4")
        XCTAssertThrowsError(try store.save(invalid)) { error in
            XCTAssertEqual(error as? PendingLiveInvitationStoreError, .invalidData)
        }
        XCTAssertEqual(persistence.data, original)
    }

    private func invitationPersisted(code: String, generation: UUID) -> PendingLiveInvitation {
        PendingLiveInvitation(
            origin: "https://join.example.test",
            code: code,
            replacementGeneration: generation
        )
    }

    private func savedGeneration(from data: Data) -> UUID {
        (try? JSONDecoder().decode(PendingLiveInvitation.self, from: data).replacementGeneration)
            ?? PendingLiveInvitation.unassignedGeneration
    }
}

private enum TestPersistenceError: Error { case failed }

private final class MemoryPendingInvitationPersistence: PendingLiveInvitationPersistence, @unchecked Sendable {
    var data: Data?
    var readError: Error?
    var writeError: Error?
    var removeError: Error?

    func read() throws -> Data? {
        if let readError { throw readError }
        return data
    }

    func write(_ data: Data) throws {
        if let writeError { throw writeError }
        self.data = data
    }

    func remove() throws {
        if let removeError { throw removeError }
        data = nil
    }
}
