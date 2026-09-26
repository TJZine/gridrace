import Foundation
import XCTest
@testable import GridRace

final class LiveMatchViewTests: XCTestCase {
    func testJoinCodeNormalizationIsPresentationOnly() {
        XCTAssertEqual(LiveMatchPresentation.normalizedJoinCode("abC234"), "ABC234")
        XCTAssertEqual(LiveMatchPresentation.normalizedJoinCode("abc234extra"), "ABC234")
        XCTAssertEqual(LiveMatchPresentation.normalizedJoinCode("a-b"), "A-B")
    }

    func testCountdownUsesCanonicalDisplayedServerTime() {
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start.addingTimeInterval(-5)), 3)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start.addingTimeInterval(-2.01)), 3)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start.addingTimeInterval(-1)), 1)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start), 0)
    }

    func testStartRequiresCreatorFullCanonicalLobbyBeforeExpiryAndNoCommand() {
        let snapshot = Self.snapshot(status: .lobby, roundState: .pending, selfSeat: 1)
        let now = snapshot.serverTime

        XCTAssertTrue(LiveMatchPresentation.canStart(
            snapshot: snapshot,
            displayedServerTime: now,
            isCommandInFlight: false
        ))
        XCTAssertFalse(LiveMatchPresentation.canStart(
            snapshot: snapshot,
            displayedServerTime: now,
            isCommandInFlight: true
        ))
        XCTAssertFalse(LiveMatchPresentation.canStart(
            snapshot: Self.snapshot(status: .lobby, roundState: .pending, selfSeat: 2),
            displayedServerTime: now,
            isCommandInFlight: false
        ))
        XCTAssertFalse(LiveMatchPresentation.canStart(
            snapshot: snapshot,
            displayedServerTime: snapshot.match.expiresAt,
            isCommandInFlight: false
        ))
    }

    func testOpponentAccessibilityLabelContainsOnlyCoarseProgress() {
        let member = Self.member(seat: 2, isSelf: false)
        let player = LiveRoundPlayer(
            memberID: member.id,
            state: .playing,
            acceptedGuessCount: 3,
            solveDurationMilliseconds: nil,
            efficiencyPoints: nil,
            placement: nil,
            board: nil
        )

        let label = LiveMatchPresentation.opponentAccessibilityLabel(member: member, player: player)

        XCTAssertEqual(label, "Opponent Player 2, 3 guesses submitted, still playing.")
        XCTAssertFalse(label.contains(member.id.uuidString))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("feedback"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("time"))
    }

    func testRevealOrdersSelfFirstThenSeatAndPreservesRows() {
        let snapshot = Self.snapshot(status: .completed, roundState: .revealed, selfSeat: 2)

        let boards = LiveMatchPresentation.revealBoards(snapshot: snapshot)

        XCTAssertEqual(boards.map(\.member.seat), [2, 1])
        XCTAssertEqual(boards[0].rows.map(\.sequence), [1, 2])
        XCTAssertEqual(boards[0].rows.map(\.word), ["adore", "vivid"])
        XCTAssertEqual(boards[1].rows.map(\.sequence), [1])
    }

    func testEveryErrorHasConciseSafePresentation() {
        for error in LiveMatchServerError.allCases {
            let message = LiveMatchPresentation.errorMessage(.server(error))
            XCTAssertNotNil(message)
            XCTAssertLessThan(message?.count ?? .max, 100)
            XCTAssertFalse(message?.contains("ABC234") == true)
            XCTAssertFalse(message?.contains("00000000-") == true)
        }
        XCTAssertNotNil(LiveMatchPresentation.errorMessage(.invalidResponse))
        XCTAssertNotNil(LiveMatchPresentation.errorMessage(.unavailable))
    }

    private static func snapshot(
        status: LiveMatchStatus,
        roundState: LiveRoundState,
        selfSeat: Int
    ) -> LiveMatchSnapshot {
        let first = member(seat: 1, isSelf: selfSeat == 1)
        let second = member(seat: 2, isSelf: selfSeat == 2)
        let now = Date(timeIntervalSince1970: 1_000)
        let revealed = roundState == .revealed
        let firstRows = [guess(sequence: 1, word: "vivid")]
        let secondRows = [guess(sequence: 1, word: "adore"), guess(sequence: 2, word: "vivid")]
        return LiveMatchSnapshot(
            serverTime: now,
            match: LiveMatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                joinCode: "ABC234",
                creatorMemberID: first.id,
                status: status,
                expiresAt: now.addingTimeInterval(60),
                minimumClientBuild: 1
            ),
            members: [first, second],
            round: LiveRound(
                state: roundState,
                startsAt: roundState == .pending ? nil : now.addingTimeInterval(3),
                endsAt: roundState == .pending ? nil : now.addingTimeInterval(183),
                completedAt: revealed ? now : nil,
                answer: revealed ? "vivid" : nil,
                players: revealed ? [
                    player(member: first, rows: firstRows, placement: 1),
                    player(member: second, rows: secondRows, placement: 2),
                ] : []
            )
        )
    }

    private static func member(seat: Int, isSelf: Bool) -> LiveMatchMember {
        LiveMatchMember(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(seat)")!,
            seat: seat,
            displayName: "Player \(seat)",
            avatarSeed: "seed-\(seat)",
            isSelf: isSelf,
            isDeleted: false
        )
    }

    private static func guess(sequence: Int, word: String) -> LiveGuess {
        LiveGuess(
            sequence: sequence,
            word: word,
            feedback: [.correct, .correct, .correct, .correct, .correct],
            submittedAt: Date(timeIntervalSince1970: 1_000 + Double(sequence))
        )
    }

    private static func player(
        member: LiveMatchMember,
        rows: [LiveGuess],
        placement: Int
    ) -> LiveRoundPlayer {
        LiveRoundPlayer(
            memberID: member.id,
            state: .solved,
            acceptedGuessCount: rows.count,
            solveDurationMilliseconds: 500,
            efficiencyPoints: 7 - rows.count,
            placement: placement,
            board: rows
        )
    }
}
