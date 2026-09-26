import Foundation
import Supabase
import XCTest
@testable import GridRace

final class LiveMatchServiceTests: XCTestCase {
    func testAllMatchCommandsUseFrozenNamesAndRequestShapes() async throws {
        let recorder = InvocationRecorder()
        let matchID = UUID(uuidString: "efcb6cfe-dd34-4244-862a-22591c2b2f7f")!
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000200")!
        let service = SupabaseLiveMatchService { function, body in
            await recorder.append(function: function, body: body)
            if function == "submit-guess" {
                return Data(Self.guessReceipt.utf8)
            }
            if function == "match-snapshot" {
                return Data(Self.lobbySnapshot.utf8)
            }
            return Data(#"{"data":{"match_id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f"}}"#.utf8)
        }

        let createdID = try await service.createMatch(requestID: requestID)
        let joinedID = try await service.joinMatch(code: "abc234")
        let startedID = try await service.startMatch(id: matchID)
        XCTAssertEqual(createdID, matchID)
        XCTAssertEqual(joinedID, matchID)
        XCTAssertEqual(startedID, matchID)
        let receipt = try await service.submitGuess(
            matchID: matchID,
            requestID: requestID,
            guess: "STONE"
        )
        XCTAssertEqual(receipt.playerState, .solved)
        let snapshot = try await service.snapshot(matchID: matchID)
        XCTAssertEqual(snapshot.match.status, .lobby)

        let invocations = await recorder.values
        XCTAssertEqual(invocations.map(\.function), [
            "create-match", "join-match", "start-match", "submit-guess", "match-snapshot",
        ])
        let bodies = try invocations.map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0.body) as? [String: Any]) }
        XCTAssertEqual(bodies[0]["client_build"] as? Int, 1)
        XCTAssertEqual(bodies[0]["request_id"] as? String, requestID.uuidString.lowercased())
        XCTAssertEqual(bodies[1]["join_code"] as? String, "ABC234")
        XCTAssertEqual(bodies[2]["match_id"] as? String, matchID.uuidString.lowercased())
        XCTAssertEqual(bodies[3]["round_number"] as? Int, 1)
        XCTAssertEqual(bodies[3]["guess"] as? String, "STONE")
    }

    func testCapturedLobbyPlayingAndRevealFixturesDecode() throws {
        let lobby = try SupabaseLiveMatchService.decodeSnapshot(Data(Self.lobbySnapshot.utf8))
        XCTAssertEqual(lobby.members.count, 1)
        XCTAssertEqual(lobby.round.state, .pending)

        let playing = try SupabaseLiveMatchService.decodeSnapshot(Data(Self.playingSnapshot.utf8))
        XCTAssertEqual(playing.match.status, .inProgress)
        XCTAssertEqual(playing.round.players[0].board, [])
        XCTAssertNil(playing.round.players[1].board)

        let revealed = try SupabaseLiveMatchService.decodeSnapshot(Data(Self.revealedSnapshot.utf8))
        XCTAssertEqual(revealed.match.status, .completed)
        XCTAssertEqual(revealed.round.answer, "vivid")
        XCTAssertEqual(revealed.round.players.map(\.placement), [2, 1])
        XCTAssertTrue(revealed.round.players.allSatisfy { $0.board != nil })
    }

    func testSnapshotMapperValidatesCanonicalCompletionWindow() throws {
        let completedAt = #""completed_at":"2026-09-26T19:40:52.136429+00:00""#

        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Data(
            Self.revealedSnapshot
                .replacingOccurrences(
                    of: completedAt,
                    with: #""completed_at":"2026-09-26T19:43:52+00:00""#
                )
                .replacingOccurrences(
                    of: #""server_time":"2026-09-26T19:40:52.184739+00:00""#,
                    with: #""server_time":"2026-09-26T19:43:53+00:00""#
                )
                .utf8
        )))
        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Data(
            Self.revealedSnapshot.replacingOccurrences(
                of: completedAt,
                with: #""completed_at":"2026-09-26T19:40:51.514472+00:00""#
            ).utf8
        )))
        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Data(
            Self.revealedSnapshot.replacingOccurrences(
                of: completedAt,
                with: #""completed_at":"2026-09-26T19:40:52.184739+00:00""#
            ).utf8
        )))

        assertInvalid(Self.revealedSnapshot.replacingOccurrences(
            of: completedAt,
            with: #""completed_at":"2026-09-26T19:40:50+00:00""#
        ))
        assertInvalid(Self.revealedSnapshot.replacingOccurrences(
            of: completedAt,
            with: #""completed_at":"2026-09-26T19:40:53+00:00""#
        ))
    }

    func testSnapshotMapperRejectsUnsupportedAndSecretLeakingShapes() {
        assertInvalid(Self.lobbySnapshot.replacingOccurrences(of: #""version":1"#, with: #""version":2"#))
        assertInvalid(Self.lobbySnapshot.replacingOccurrences(of: #""is_self":true"#, with: #""is_self":null"#))
        assertInvalid(Self.lobbySnapshot.replacingOccurrences(of: #""completed_at":null"#, with: #""completed_at_omitted":null"#))
        assertInvalid(Self.lobbySnapshot.replacingOccurrences(of: #""status":"lobby""#, with: #""status":"waiting""#))
        assertInvalid(Self.playingSnapshot.replacingOccurrences(of: #""board":null"#, with: #""board":[]"#))
        assertInvalid(Self.playingSnapshot.replacingOccurrences(of: #""accepted_guess_count":0"#, with: #""accepted_guess_count":1"#))
        assertInvalid(Self.revealedSnapshot.replacingOccurrences(of: #""answer":"vivid""#, with: #""answer":null"#))
        assertInvalid(Self.revealedSnapshot.replacingOccurrences(of: #""placement":2"#, with: #""placement":null"#))
    }

    func testEveryStableServerErrorMapsFromNonSuccessResponse() async {
        for code in LiveMatchServerError.allCases {
            let service = SupabaseLiveMatchService { _, _ in
                throw FunctionsError.httpError(
                    code: Self.httpStatus(for: code),
                    data: Data(#"{"error":{"code":"\#(code.rawValue)","message":"safe"}}"#.utf8)
                )
            }
            do {
                _ = try await service.createMatch(requestID: UUID())
                XCTFail("Expected \(code.rawValue)")
            } catch let error as LiveMatchServiceError {
                XCTAssertEqual(error, .server(code))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnknownHTTPAndMalformedSuccessFailClosed() async {
        let unavailable = SupabaseLiveMatchService { _, _ in
            throw FunctionsError.httpError(code: 502, data: Data("gateway".utf8))
        }
        await assertError(.unavailable) {
            _ = try await unavailable.createMatch(requestID: UUID())
        }

        let malformed = SupabaseLiveMatchService { _, _ in Data(#"{"data":{}}"#.utf8) }
        await assertError(.invalidResponse) {
            _ = try await malformed.createMatch(requestID: UUID())
        }

        let mismatched = SupabaseLiveMatchService { _, _ in
            throw FunctionsError.httpError(
                code: 500,
                data: Data(#"{"error":{"code":"not_authenticated","message":"safe"}}"#.utf8)
            )
        }
        await assertError(.unavailable) {
            _ = try await mismatched.createMatch(requestID: UUID())
        }
    }

    private func assertInvalid(_ json: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(
            try SupabaseLiveMatchService.decodeSnapshot(Data(json.utf8)),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? LiveMatchServiceError, .invalidResponse, file: file, line: line)
        }
    }

    private func assertError(
        _ expected: LiveMatchServiceError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as LiveMatchServiceError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func httpStatus(for code: LiveMatchServerError) -> Int {
        switch code {
        case .invalidGuessFormat: 400
        case .notAuthenticated: 401
        case .notAMatchMember, .notHost: 403
        case .matchNotJoinable, .roomFull, .notEnoughPlayers, .roundNotActive,
             .roundAlreadyFinished, .requestConflict: 409
        case .roomExpired: 410
        case .wordNotAccepted: 422
        case .clientUpdateRequired: 426
        case .rateLimited: 429
        case .internalError: 500
        }
    }

    private static let guessReceipt = #"""
    {"data":{"accepted":true,"sequence":1,"feedback":[2,2,2,2,2],"player_state":"solved","accepted_guess_count":1,"solve_duration_ms":1250,"efficiency_points":6,"server_time":"2026-08-30T12:00:04.250123+00:00","round_end_time":"2026-08-30T12:03:03Z"}}
    """#

    // Captured from the local Edge/SQL integration harness on 2026-09-26.
    private static let lobbySnapshot = #"""
    {"data":{"match":{"id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f","mode":"classic_live_v1","status":"lobby","join_code":"CV5QKT","expires_at":"2026-09-26T20:40:45.124772+00:00","round_count":1,"current_round":1,"creator_member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","minimum_client_build":1},"round":{"state":"pending","answer":null,"number":1,"ends_at":null,"players":[],"starts_at":null,"completed_at":null},"members":[{"id":"b298a1bb-329b-472e-9c06-c65d7b569afd","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"851066e6-271b-4344-be12-d13c99fdbfac","display_name":"Player b93ff4"}],"version":1,"server_time":"2026-09-26T19:40:45.169589+00:00"}}
    """#

    private static let playingSnapshot = #"""
    {"data":{"match":{"id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f","mode":"classic_live_v1","status":"in_progress","join_code":"CV5QKT","expires_at":"2026-09-26T20:40:45.124772+00:00","round_count":1,"current_round":1,"creator_member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","minimum_client_build":1},"round":{"state":"playing","answer":null,"number":1,"ends_at":"2026-09-26T19:43:51.514472+00:00","players":[{"board":[],"state":"playing","member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"playing","member_id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-09-26T19:40:51.514472+00:00","completed_at":null},"members":[{"id":"b298a1bb-329b-472e-9c06-c65d7b569afd","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"851066e6-271b-4344-be12-d13c99fdbfac","display_name":"Player b93ff4"},{"id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"5401e7eb-1b44-4c70-b1b4-7aa1cd650b14","display_name":"Player 8ebf0d"}],"version":1,"server_time":"2026-09-26T19:40:51.769936+00:00"}}
    """#

    private static let revealedSnapshot = #"""
    {"data":{"match":{"id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f","mode":"classic_live_v1","status":"completed","join_code":"CV5QKT","expires_at":"2026-09-26T20:40:45.124772+00:00","round_count":1,"current_round":1,"creator_member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","minimum_client_build":1},"round":{"state":"revealed","answer":"vivid","number":1,"ends_at":"2026-09-26T19:43:51.514472+00:00","players":[{"board":[{"guess":"adore","feedback":[0,1,0,0,0],"sequence":1,"submitted_at":"2026-09-26T19:40:52.004385+00:00"},{"guess":"vivid","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-09-26T19:40:52.136429+00:00"}],"state":"solved","member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","placement":2,"efficiency_points":5,"solve_duration_ms":621,"accepted_guess_count":2},{"board":[{"guess":"vivid","feedback":[2,2,2,2,2],"sequence":1,"submitted_at":"2026-09-26T19:40:52.093102+00:00"}],"state":"solved","member_id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","placement":1,"efficiency_points":6,"solve_duration_ms":578,"accepted_guess_count":1}],"starts_at":"2026-09-26T19:40:51.514472+00:00","completed_at":"2026-09-26T19:40:52.136429+00:00"},"members":[{"id":"b298a1bb-329b-472e-9c06-c65d7b569afd","seat":1,"is_self":false,"is_deleted":false,"avatar_seed":"851066e6-271b-4344-be12-d13c99fdbfac","display_name":"Player b93ff4"},{"id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","seat":2,"is_self":true,"is_deleted":false,"avatar_seed":"5401e7eb-1b44-4c70-b1b4-7aa1cd650b14","display_name":"Player 8ebf0d"}],"version":1,"server_time":"2026-09-26T19:40:52.184739+00:00"}}
    """#
}

private actor InvocationRecorder {
    struct Invocation: Sendable { let function: String; let body: Data }
    private(set) var values: [Invocation] = []
    func append(function: String, body: Data) { values.append(.init(function: function, body: body)) }
}
