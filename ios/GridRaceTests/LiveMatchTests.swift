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

        let createdID = try await service.createMatch(requestID: requestID, roundCount: 3, clientBuild: 2)
        let joinedID = try await service.joinMatch(code: "abc234")
        let startedID = try await service.startMatch(id: matchID, roundNumber: 1)
        XCTAssertEqual(createdID, matchID)
        XCTAssertEqual(joinedID, matchID)
        XCTAssertEqual(startedID, matchID)
        let receipt = try await service.submitGuess(
            matchID: matchID,
            roundNumber: 1,
            requestID: requestID,
            guess: "STONE", clientBuild: 2
        )
        XCTAssertEqual(receipt.playerState, .solved)
        let snapshot = try await service.snapshot(matchID: matchID)
        XCTAssertEqual(snapshot.match.status, .lobby)

        let invocations = await recorder.values
        XCTAssertEqual(invocations.map(\.function), [
            "create-match", "join-match", "start-match", "submit-guess", "match-snapshot",
        ])
        let bodies = try invocations.map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0.body) as? [String: Any]) }
        XCTAssertEqual(bodies[0]["client_build"] as? Int, 2)
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

    func testFailedGuessReceiptRequiresNullEfficiency() async throws {
        let matchID = UUID(uuidString: "efcb6cfe-dd34-4244-862a-22591c2b2f7f")!
        let valid = SupabaseLiveMatchService { _, _ in Data(Self.failedGuessReceipt.utf8) }

        let receipt = try await valid.submitGuess(
            matchID: matchID,
            roundNumber: 1,
            requestID: UUID(),
            guess: "CRANE", clientBuild: 2
        )

        XCTAssertEqual(receipt.playerState, .failed)
        XCTAssertEqual(receipt.acceptedGuessCount, 6)
        XCTAssertNil(receipt.solveDurationMilliseconds)
        XCTAssertNil(receipt.efficiencyPoints)

        let invalid = SupabaseLiveMatchService { _, _ in
            Data(Self.failedGuessReceipt.replacingOccurrences(
                of: #""efficiency_points":null"#,
                with: #""efficiency_points":0"#
            ).utf8)
        }
        await assertError(.invalidResponse) {
            _ = try await invalid.submitGuess(
                matchID: matchID,
            roundNumber: 1,
                requestID: UUID(),
                guess: "CRANE", clientBuild: 2
            )
        }
    }

    func testSnapshotMapperValidatesCanonicalCompletionTimesIncludingLockInversion() throws {
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
        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Data(
            Self.revealedSnapshot.replacingOccurrences(
                of: completedAt,
                with: #""completed_at":"2026-09-26T19:40:53+00:00""#
            ).utf8
        )))
    }

    func testSnapshotMapperValidatesCanonicalPhaseWindow() throws {
        let serverTime = #""server_time":"2026-09-26T19:40:51.769936+00:00""#
        let countdown = Self.playingSnapshot.replacingOccurrences(
            of: #""round":{"state":"playing""#,
            with: #""round":{"state":"countdown""#
        )

        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Data(
            countdown.replacingOccurrences(
                of: serverTime,
                with: #""server_time":"2026-09-26T19:40:51Z""#
            ).utf8
        )))
        assertInvalid(countdown.replacingOccurrences(
            of: serverTime,
            with: #""server_time":"2026-09-26T19:40:51.514472+00:00""#
        ))
        assertInvalid(countdown.replacingOccurrences(
            of: serverTime,
            with: #""server_time":"2026-09-26T19:40:52Z""#
        ))

        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Data(
            Self.playingSnapshot.replacingOccurrences(
                of: serverTime,
                with: #""server_time":"2026-09-26T19:40:51.514472+00:00""#
            ).utf8
        )))
        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Data(
            Self.playingSnapshot.replacingOccurrences(
                of: serverTime,
                with: #""server_time":"2026-09-26T19:43:51Z""#
            ).utf8
        )))
        assertInvalid(Self.playingSnapshot.replacingOccurrences(
            of: serverTime,
            with: #""server_time":"2026-09-26T19:40:51Z""#
        ))
        assertInvalid(Self.playingSnapshot.replacingOccurrences(
            of: serverTime,
            with: #""server_time":"2026-09-26T19:43:51.514472+00:00""#
        ))
        assertInvalid(Self.playingSnapshot.replacingOccurrences(
            of: serverTime,
            with: #""server_time":"2026-09-26T19:43:52Z""#
        ))
    }

    func testSnapshotMapperRejectsUnsupportedAndSecretLeakingShapes() {
        assertInvalid(Self.lobbySnapshot.replacingOccurrences(of: #""version":2"#, with: #""version":1"#))
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
                _ = try await service.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2)
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
            _ = try await unavailable.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2)
        }

        let malformed = SupabaseLiveMatchService { _, _ in Data(#"{"data":{}}"#.utf8) }
        await assertError(.invalidResponse) {
            _ = try await malformed.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2)
        }

        let mismatched = SupabaseLiveMatchService { _, _ in
            throw FunctionsError.httpError(
                code: 500,
                data: Data(#"{"error":{"code":"not_authenticated","message":"safe"}}"#.utf8)
            )
        }
        await assertError(.unavailable) {
            _ = try await mismatched.createMatch(requestID: UUID(), roundCount: 3, clientBuild: 2)
        }
    }

    func testRealV2GatewaySnapshotsCoverAllCountsHistoryAndDeletionMatrix() throws {
        for (label, json) in Phase4LiveFixtures.json {
            let snapshot = try SupabaseLiveMatchService.decodeSnapshot(Data(json.utf8))
            XCTAssertEqual(snapshot.round.number, snapshot.match.currentRound, label)
            XCTAssertGreaterThan(snapshot.revision, 0, label)
            XCTAssertEqual(snapshot.revealedRounds.map(\.number),
                           Array(1..<(snapshot.revealedRounds.count + 1)), label)
            if snapshot.match.status == .completed {
                XCTAssertEqual(snapshot.match.completedAt, snapshot.round.completedAt, label)
                XCTAssertEqual(snapshot.standings?.isFinal, true, label)
            }
        }
        let exact = try Phase4LiveFixtures.snapshot("3-round-3-reveal")
        XCTAssertEqual(exact.standings?.players.map(\.totalSolveDurationMilliseconds), [4, 5])
        XCTAssertEqual(exact.standings?.players.map(\.placement), [1, 2])
        let tie = try Phase4LiveFixtures.snapshot("3-final-tie")
        XCTAssertEqual(tie.standings?.players.map(\.placement), [1, 1])
    }

    func testCurrentSnapshotRejectsDowngradeAndAcceptsLegacyFloorOneV2Room() async throws {
        let snapshot = try SupabaseLiveMatchService.decodeSnapshot(Data(Self.playingSnapshot.utf8))
        XCTAssertEqual(snapshot.match.minimumClientBuild, 1)
        XCTAssertEqual(snapshot.match.roundCount, 1)
        XCTAssertEqual(snapshot.revision, 1)
        let recorder = InvocationRecorder()
        let service = SupabaseLiveMatchService { function, body in
            await recorder.append(function: function, body: body)
            return Data(Self.playingSnapshot.replacingOccurrences(of: #""version":2"#, with: #""version":1"#).utf8)
        }
        await assertError(.invalidResponse) { _ = try await service.snapshot(matchID: snapshot.match.id) }
        let calls = await recorder.values
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[0].body) as? [String: Any])
        XCTAssertEqual(body["client_build"] as? Int, 2)
    }

    func testV2MapperRejectsMalformedConfigurationHistoryIdentityAndDisclosure() throws {
        try rejectV2("3-lobby") { $0["version"] = 3 }
        try rejectV2("3-lobby") { $0.removeValue(forKey: "standings") }
        try rejectV2("3-lobby") { $0.removeValue(forKey: "revealed_rounds") }
        for field in ["revision", "round_count", "current_round", "started_at", "completed_at", "terminal_reason"] {
            try rejectV2("3-lobby") { data in
                var match = data["match"] as! [String: Any]
                match.removeValue(forKey: field)
                data["match"] = match
            }
        }
        for (field, invalid) in [("round_count", 2), ("current_round", 0), ("revision", 0)] {
            try rejectV2("3-lobby") { data in
                var match = data["match"] as! [String: Any]; match[field] = invalid; data["match"] = match
            }
        }
        try rejectV2("3-round-2-playing") { $0["revealed_rounds"] = [] }
        try rejectV2("3-round-2-playing") { data in
            let history = data["revealed_rounds"] as! [[String: Any]]
            data["revealed_rounds"] = history + history
        }
        try rejectV2("3-round-1-reveal") { data in
            var history = data["revealed_rounds"] as! [[String: Any]]
            history[0]["answer"] = "stone"; data["revealed_rounds"] = history
        }
        for field in ["board", "solve_duration_ms", "efficiency_points", "placement"] {
            try rejectV2("3-round-2-playing") { data in
                var round = data["round"] as! [String: Any]
                var players = round["players"] as! [[String: Any]]
                players[1][field] = field == "board" ? [] : 1
                round["players"] = players; data["round"] = round
            }
        }
        try rejectV2("3-round-2-playing") { data in
            var round = data["round"] as! [String: Any]; round["answer"] = "stone"; data["round"] = round
        }
        try rejectV2("3-round-2-playing") { data in
            var members = data["members"] as! [[String: Any]]
            members[1]["id"] = members[0]["id"]; data["members"] = members
        }
        try rejectV2("3-round-2-playing") { data in
            var round = data["round"] as! [String: Any]; round["number"] = 1; data["round"] = round
        }
    }

    func testV2MapperRejectsEveryImpossibleMatchTimestampReasonAndStandingsBoundary() throws {
        let cases: [(String, String, Any)] = [
            ("3-lobby", "started_at", "2026-10-02T18:00:00Z"),
            ("3-lobby", "terminal_reason", "account_deleted"),
            ("3-round-1-reveal", "status", "completed"),
            ("3-round-1-reveal", "status", "incomplete"),
            ("3-round-2-playing", "started_at", NSNull()),
            ("3-round-2-playing", "completed_at", "2026-10-02T18:00:00Z"),
            ("3-round-2-playing", "terminal_reason", "account_deleted"),
            ("deletion-active", "terminal_reason", NSNull()),
            ("deletion-active", "status", "incomplete"),
            ("deletion-active-revealed", "terminal_reason", NSNull()),
            ("deletion-active-revealed", "status", "in_progress"),
            ("deletion-active-revealed", "completed_at", "2026-10-02T18:00:00Z"),
            ("deletion-final-active", "terminal_reason", "account_deleted"),
            ("deletion-final-active-revealed", "terminal_reason", "account_deleted"),
            ("3-round-3-reveal", "completed_at", "2026-10-02T18:00:00Z"),
            ("3-round-3-reveal", "status", "in_progress"),
            ("3-round-3-reveal", "status", "incomplete"),
        ]
        for (label, field, invalid) in cases {
            try rejectV2(label) { data in
                var match = data["match"] as! [String: Any]; match[field] = invalid; data["match"] = match
            }
        }
        for field in ["through_round", "is_final", "players"] {
            try rejectV2("3-round-1-reveal") { data in
                var totals = data["standings"] as! [String: Any]
                totals[field] = field == "players" ? [] : (field == "is_final" ? true : 3)
                data["standings"] = totals
            }
        }
        for field in ["rounds_solved", "efficiency_points", "total_solve_duration_ms", "placement"] {
            try rejectV2("3-round-3-reveal") { data in
                var totals = data["standings"] as! [String: Any]
                var players = totals["players"] as! [[String: Any]]
                players[0][field] = -1; totals["players"] = players; data["standings"] = totals
            }
        }
    }

    func testCountdownForfeitAndDelayedFinalizerKeepTransactionTimestampSemantics() throws {
        var data = try Phase4LiveFixtures.object("1-round-1-reveal")
        var round = data["round"] as! [String: Any]
        var players = round["players"] as! [[String: Any]]
        for index in players.indices {
            players[index]["state"] = "forfeited"; players[index]["board"] = []
            players[index]["accepted_guess_count"] = 0; players[index]["solve_duration_ms"] = NSNull()
            players[index]["efficiency_points"] = 0; players[index]["placement"] = 1
        }
        var match = data["match"] as! [String: Any]
        round["players"] = players; round["completed_at"] = match["started_at"]
        match["completed_at"] = round["completed_at"]
        data["round"] = round; data["revealed_rounds"] = [round]; data["match"] = match
        var totals = data["standings"] as! [String: Any]
        var standings = totals["players"] as! [[String: Any]]
        for index in standings.indices {
            standings[index]["rounds_solved"] = 0; standings[index]["efficiency_points"] = 0
            standings[index]["total_solve_duration_ms"] = 0; standings[index]["placement"] = 1
        }
        totals["players"] = standings; data["standings"] = totals
        XCTAssertNoThrow(try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(data)))
        // Actual Cron fixture completes after its scheduled deadline without imposing delivery ordering.
        XCTAssertNoThrow(try Phase4LiveFixtures.snapshot("ordinary-cron-nonfinal"))
    }

    func testMapperRejectsPrematureCountdownTimeoutAndRoundWithoutFirstPlacement() throws {
        try rejectV2("3-round-1-countdown") { data in
            var round = data["round"] as! [String: Any]
            var players = round["players"] as! [[String: Any]]
            players[1]["state"] = "timed_out"
            round["players"] = players; data["round"] = round
        }
        try rejectV2("3-round-1-reveal") { data in
            var round = data["round"] as! [String: Any]
            var players = round["players"] as! [[String: Any]]
            for index in players.indices { players[index]["placement"] = 2 }
            round["players"] = players
            data["round"] = round; data["revealed_rounds"] = [round]
        }
    }

    func testLegacyReplayUsesExactOldCreateAndGuessPayloadWhileSnapshotsUseBuild2() async throws {
        let recorder = InvocationRecorder()
        let service = SupabaseLiveMatchService { function, body in
            await recorder.append(function: function, body: body)
            return function == "submit-guess" ? Data(Self.guessReceipt.utf8)
                : Data(#"{"data":{"match_id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f"}}"#.utf8)
        }
        let id = UUID(uuidString: "efcb6cfe-dd34-4244-862a-22591c2b2f7f")!
        _ = try await service.createMatch(requestID: id, roundCount: 1, clientBuild: 1)
        _ = try await service.submitGuess(matchID: id, roundNumber: 1, requestID: id, guess: "STONE", clientBuild: 1)
        _ = try await service.startMatch(id: id, roundNumber: 4)
        let calls = await recorder.values
        let bodies = try calls.map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0.body) as? [String: Any]) }
        XCTAssertEqual(Set(bodies[0].keys), ["client_build", "request_id"])
        XCTAssertEqual(bodies[0]["client_build"] as? Int, 1)
        XCTAssertEqual(bodies[1]["client_build"] as? Int, 1)
        XCTAssertEqual(bodies[1]["round_number"] as? Int, 1)
        XCTAssertEqual(bodies[2]["client_build"] as? Int, 2)
        XCTAssertEqual(bodies[2]["round_number"] as? Int, 4)
    }

    private func rejectV2(_ label: String, edit: (inout [String: Any]) -> Void,
                          file: StaticString = #filePath, line: UInt = #line) throws {
        var data = try Phase4LiveFixtures.object(label)
        edit(&data)
        assertInvalid(String(decoding: try Phase4LiveFixtures.envelope(data), as: UTF8.self), file: file, line: line)
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
        case .invalidGuessFormat, .invalidMatchConfiguration: 400
        case .notAuthenticated: 401
        case .notAMatchMember, .notHost: 403
        case .matchNotJoinable, .roomFull, .notEnoughPlayers, .roundNotActive,
             .roundAlreadyFinished, .requestConflict, .matchIncomplete: 409
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

    private static let failedGuessReceipt = #"""
    {"data":{"accepted":true,"sequence":6,"feedback":[0,0,0,0,0],"player_state":"failed","accepted_guess_count":6,"solve_duration_ms":null,"efficiency_points":null,"server_time":"2026-08-30T12:00:09Z","round_end_time":"2026-08-30T12:03:03Z"}}
    """#

    // Captured v1 boards/timestamps from 2026-09-26, extended with explicit v2 match/history fields.
    private static let lobbySnapshot = #"""
    {"data":{"match":{"id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f","mode":"classic_live_v1","status":"lobby","join_code":"CV5QKT","expires_at":"2026-09-26T20:40:45.124772+00:00","round_count":1,"current_round":1,"creator_member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","minimum_client_build":1,"revision":1,"started_at":null,"completed_at":null,"terminal_reason":null},"round":{"state":"pending","answer":null,"number":1,"ends_at":null,"players":[],"starts_at":null,"completed_at":null},"members":[{"id":"b298a1bb-329b-472e-9c06-c65d7b569afd","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"851066e6-271b-4344-be12-d13c99fdbfac","display_name":"Player b93ff4"}],"version":2,"server_time":"2026-09-26T19:40:45.169589+00:00","revealed_rounds":[],"standings":null}}
    """#

    private static let playingSnapshot = #"""
    {"data":{"match":{"id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f","mode":"classic_live_v1","status":"in_progress","join_code":"CV5QKT","expires_at":"2026-09-26T20:40:45.124772+00:00","round_count":1,"current_round":1,"creator_member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","minimum_client_build":1,"revision":1,"started_at":"2026-09-26T19:40:48.514472+00:00","completed_at":null,"terminal_reason":null},"round":{"state":"playing","answer":null,"number":1,"ends_at":"2026-09-26T19:43:51.514472+00:00","players":[{"board":[],"state":"playing","member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"playing","member_id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-09-26T19:40:51.514472+00:00","completed_at":null},"members":[{"id":"b298a1bb-329b-472e-9c06-c65d7b569afd","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"851066e6-271b-4344-be12-d13c99fdbfac","display_name":"Player b93ff4"},{"id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"5401e7eb-1b44-4c70-b1b4-7aa1cd650b14","display_name":"Player 8ebf0d"}],"version":2,"server_time":"2026-09-26T19:40:51.769936+00:00","revealed_rounds":[],"standings":null}}
    """#

    private static let revealedSnapshot = #"""
    {"data":{"match":{"id":"efcb6cfe-dd34-4244-862a-22591c2b2f7f","mode":"classic_live_v1","status":"completed","join_code":"CV5QKT","expires_at":"2026-09-26T20:40:45.124772+00:00","round_count":1,"current_round":1,"creator_member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","minimum_client_build":1,"revision":1,"started_at":"2026-09-26T19:40:48.514472+00:00","completed_at":"2026-09-26T19:40:52.136429+00:00","terminal_reason":null},"round":{"state":"revealed","answer":"vivid","number":1,"ends_at":"2026-09-26T19:43:51.514472+00:00","players":[{"board":[{"guess":"adore","feedback":[0,1,0,0,0],"sequence":1,"submitted_at":"2026-09-26T19:40:52.004385+00:00"},{"guess":"vivid","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-09-26T19:40:52.136429+00:00"}],"state":"solved","member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","placement":2,"efficiency_points":5,"solve_duration_ms":621,"accepted_guess_count":2},{"board":[{"guess":"vivid","feedback":[2,2,2,2,2],"sequence":1,"submitted_at":"2026-09-26T19:40:52.093102+00:00"}],"state":"solved","member_id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","placement":1,"efficiency_points":6,"solve_duration_ms":578,"accepted_guess_count":1}],"starts_at":"2026-09-26T19:40:51.514472+00:00","completed_at":"2026-09-26T19:40:52.136429+00:00"},"members":[{"id":"b298a1bb-329b-472e-9c06-c65d7b569afd","seat":1,"is_self":false,"is_deleted":false,"avatar_seed":"851066e6-271b-4344-be12-d13c99fdbfac","display_name":"Player b93ff4"},{"id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","seat":2,"is_self":true,"is_deleted":false,"avatar_seed":"5401e7eb-1b44-4c70-b1b4-7aa1cd650b14","display_name":"Player 8ebf0d"}],"version":2,"server_time":"2026-09-26T19:40:52.184739+00:00","revealed_rounds":[{"state":"revealed","answer":"vivid","number":1,"ends_at":"2026-09-26T19:43:51.514472+00:00","players":[{"board":[{"guess":"adore","feedback":[0,1,0,0,0],"sequence":1,"submitted_at":"2026-09-26T19:40:52.004385+00:00"},{"guess":"vivid","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-09-26T19:40:52.136429+00:00"}],"state":"solved","member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","placement":2,"efficiency_points":5,"solve_duration_ms":621,"accepted_guess_count":2},{"board":[{"guess":"vivid","feedback":[2,2,2,2,2],"sequence":1,"submitted_at":"2026-09-26T19:40:52.093102+00:00"}],"state":"solved","member_id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","placement":1,"efficiency_points":6,"solve_duration_ms":578,"accepted_guess_count":1}],"starts_at":"2026-09-26T19:40:51.514472+00:00","completed_at":"2026-09-26T19:40:52.136429+00:00"}],"standings":{"through_round":1,"is_final":true,"players":[{"member_id":"b298a1bb-329b-472e-9c06-c65d7b569afd","rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":621,"placement":2},{"member_id":"989d3c44-b916-4a64-9fda-1d56d03f4c4d","rounds_solved":1,"efficiency_points":6,"total_solve_duration_ms":578,"placement":1}]}}}
    """#
}

private actor InvocationRecorder {
    struct Invocation: Sendable { let function: String; let body: Data }
    private(set) var values: [Invocation] = []
    func append(function: String, body: Data) { values.append(.init(function: function, body: body)) }
}

// Unchanged actual local gateway snapshots captured by P4-B on 2026-10-02.
// Inline fixtures reuse the existing test target without a second resource registration.
enum Phase4LiveFixtures {
    static func object(_ label: String) throws -> [String: Any] {
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(json[label]).utf8)) as? [String: Any])
        return try XCTUnwrap(envelope["data"] as? [String: Any])
    }
    static func envelope(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": object], options: [.sortedKeys])
    }
    static func snapshot(_ label: String) throws -> LiveMatchSnapshot {
        try SupabaseLiveMatchService.decodeSnapshot(Data(try XCTUnwrap(json[label]).utf8))
    }
    static let json: [String: String] = [
        "1-lobby": #"""
        {"data":{"match":{"id":"5f426892-104c-4145-bc2a-6fedbfaf7ddc","mode":"classic_live_v1","status":"lobby","revision":1,"join_code":"353DEG","expires_at":"2026-10-02T19:42:46.401626+00:00","started_at":null,"round_count":1,"completed_at":null,"current_round":1,"terminal_reason":null,"creator_member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","minimum_client_build":2},"round":{"state":"pending","answer":null,"number":1,"ends_at":null,"players":[],"starts_at":null,"completed_at":null},"members":[{"id":"2d8248fb-dc0b-48de-936d-4fcab029f162","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"6b83ce89-6326-4725-8a07-f4d44be4f061","display_name":"Player 5c13a5"}],"version":2,"standings":null,"server_time":"2026-10-02T18:42:46.438624+00:00","revealed_rounds":[]}}
        """#,
        "1-round-1-reveal": #"""
        {"data":{"match":{"id":"5f426892-104c-4145-bc2a-6fedbfaf7ddc","mode":"classic_live_v1","status":"completed","revision":8,"join_code":"353DEG","expires_at":"2026-10-02T19:42:46.401626+00:00","started_at":"2026-10-02T18:42:46.731823+00:00","round_count":1,"completed_at":"2026-10-02T18:42:51.223615+00:00","current_round":1,"terminal_reason":null,"creator_member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","minimum_client_build":2},"round":{"state":"revealed","answer":"charm","number":1,"ends_at":"2026-10-02T18:45:49.731823+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733423+00:00"}],"state":"solved","member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733723+00:00"}],"state":"solved","member_id":"3b8ed621-8a14-44ed-b737-6dac1805066a","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:49.731823+00:00","completed_at":"2026-10-02T18:42:51.223615+00:00"},"members":[{"id":"2d8248fb-dc0b-48de-936d-4fcab029f162","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"6b83ce89-6326-4725-8a07-f4d44be4f061","display_name":"Player 5c13a5"},{"id":"3b8ed621-8a14-44ed-b737-6dac1805066a","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"827b12ae-3878-4aaf-9037-9e678dcbf0d2","display_name":"Player 6fe033"}],"version":2,"standings":{"players":[{"member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","placement":1,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1},{"member_id":"3b8ed621-8a14-44ed-b737-6dac1805066a","placement":2,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1}],"is_final":true,"through_round":1},"server_time":"2026-10-02T18:42:51.432681+00:00","revealed_rounds":[{"state":"revealed","answer":"charm","number":1,"ends_at":"2026-10-02T18:45:49.731823+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733423+00:00"}],"state":"solved","member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733723+00:00"}],"state":"solved","member_id":"3b8ed621-8a14-44ed-b737-6dac1805066a","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:49.731823+00:00","completed_at":"2026-10-02T18:42:51.223615+00:00"}]}}
        """#,
        "1-final-tie": #"""
        {"data":{"match":{"id":"5f426892-104c-4145-bc2a-6fedbfaf7ddc","mode":"classic_live_v1","status":"completed","revision":8,"join_code":"353DEG","expires_at":"2026-10-02T19:42:46.401626+00:00","started_at":"2026-10-02T18:42:46.731823+00:00","round_count":1,"completed_at":"2026-10-02T18:42:51.223615+00:00","current_round":1,"terminal_reason":null,"creator_member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","minimum_client_build":2},"round":{"state":"revealed","answer":"charm","number":1,"ends_at":"2026-10-02T18:45:49.731823+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733423+00:00"}],"state":"solved","member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733423+00:00"}],"state":"solved","member_id":"3b8ed621-8a14-44ed-b737-6dac1805066a","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:49.731823+00:00","completed_at":"2026-10-02T18:42:51.223615+00:00"},"members":[{"id":"2d8248fb-dc0b-48de-936d-4fcab029f162","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"6b83ce89-6326-4725-8a07-f4d44be4f061","display_name":"Player 5c13a5"},{"id":"3b8ed621-8a14-44ed-b737-6dac1805066a","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"827b12ae-3878-4aaf-9037-9e678dcbf0d2","display_name":"Player 6fe033"}],"version":2,"standings":{"players":[{"member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","placement":1,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1},{"member_id":"3b8ed621-8a14-44ed-b737-6dac1805066a","placement":1,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1}],"is_final":true,"through_round":1},"server_time":"2026-10-02T18:42:52.306271+00:00","revealed_rounds":[{"state":"revealed","answer":"charm","number":1,"ends_at":"2026-10-02T18:45:49.731823+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733423+00:00"}],"state":"solved","member_id":"2d8248fb-dc0b-48de-936d-4fcab029f162","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:42:49.732323+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:49.733423+00:00"}],"state":"solved","member_id":"3b8ed621-8a14-44ed-b737-6dac1805066a","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:49.731823+00:00","completed_at":"2026-10-02T18:42:51.223615+00:00"}]}}
        """#,
        "3-lobby": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"lobby","revision":1,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":null,"round_count":3,"completed_at":null,"current_round":1,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"pending","answer":null,"number":1,"ends_at":null,"players":[],"starts_at":null,"completed_at":null},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"}],"version":2,"standings":null,"server_time":"2026-10-02T18:42:52.888058+00:00","revealed_rounds":[]}}
        """#,
        "3-round-1-countdown": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"in_progress","revision":3,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":null,"current_round":1,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"countdown","answer":null,"number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[],"state":"playing","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"playing","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":null},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":null,"server_time":"2026-10-02T18:42:53.58816+00:00","revealed_rounds":[]}}
        """#,
        "3-round-1-playing": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"in_progress","revision":3,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":null,"current_round":1,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"playing","answer":null,"number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[],"state":"playing","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"playing","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":null},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":null,"server_time":"2026-10-02T18:42:56.942261+00:00","revealed_rounds":[]}}
        """#,
        "3-round-1-reveal": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"in_progress","revision":8,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":null,"current_round":1,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2611+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":{"players":[{"member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1},{"member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1}],"is_final":false,"through_round":1},"server_time":"2026-10-02T18:42:57.54224+00:00","revealed_rounds":[{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2611+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"}]}}
        """#,
        "3-round-2-countdown": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"in_progress","revision":9,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":null,"current_round":2,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"countdown","answer":null,"number":2,"ends_at":"2026-10-02T18:46:01.216597+00:00","players":[{"board":[],"state":"playing","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"playing","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:43:01.216597+00:00","completed_at":null},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":{"players":[{"member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1},{"member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1}],"is_final":false,"through_round":1},"server_time":"2026-10-02T18:42:58.900599+00:00","revealed_rounds":[{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2611+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"}]}}
        """#,
        "3-round-2-playing": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"in_progress","revision":9,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":null,"current_round":2,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"playing","answer":null,"number":2,"ends_at":"2026-10-02T18:46:01.216597+00:00","players":[{"board":[],"state":"playing","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"playing","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:43:01.216597+00:00","completed_at":null},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":{"players":[{"member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1},{"member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1}],"is_final":false,"through_round":1},"server_time":"2026-10-02T18:43:02.423731+00:00","revealed_rounds":[{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2611+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"}]}}
        """#,
        "3-round-2-unrevealed-solved-opponent": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"in_progress","revision":11,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":null,"current_round":2,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"playing","answer":null,"number":2,"ends_at":"2026-10-02T18:46:01.216597+00:00","players":[{"board":null,"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":2},{"board":[],"state":"playing","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:43:01.216597+00:00","completed_at":null},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":false,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":true,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":{"players":[{"member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1},{"member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"rounds_solved":1,"efficiency_points":5,"total_solve_duration_ms":1}],"is_final":false,"through_round":1},"server_time":"2026-10-02T18:43:02.849994+00:00","revealed_rounds":[{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2611+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"}]}}
        """#,
        "3-round-2-reveal": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"in_progress","revision":14,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":null,"current_round":2,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"revealed","answer":"train","number":2,"ends_at":"2026-10-02T18:46:01.216597+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218197+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218497+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:01.216597+00:00","completed_at":"2026-10-02T18:43:02.932198+00:00"},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":{"players":[{"member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"rounds_solved":2,"efficiency_points":10,"total_solve_duration_ms":3},{"member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"rounds_solved":2,"efficiency_points":10,"total_solve_duration_ms":3}],"is_final":false,"through_round":2},"server_time":"2026-10-02T18:43:03.040457+00:00","revealed_rounds":[{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2611+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"},{"state":"revealed","answer":"train","number":2,"ends_at":"2026-10-02T18:46:01.216597+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218197+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218497+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:01.216597+00:00","completed_at":"2026-10-02T18:43:02.932198+00:00"}]}}
        """#,
        "3-round-3-reveal": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"completed","revision":20,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":"2026-10-02T18:43:07.78435+00:00","current_round":3,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"revealed","answer":"stone","number":3,"ends_at":"2026-10-02T18:46:06.634358+00:00","players":[{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.635958+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.636258+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:06.634358+00:00","completed_at":"2026-10-02T18:43:07.78435+00:00"},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":{"players":[{"member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"rounds_solved":3,"efficiency_points":15,"total_solve_duration_ms":4},{"member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"rounds_solved":3,"efficiency_points":15,"total_solve_duration_ms":5}],"is_final":true,"through_round":3},"server_time":"2026-10-02T18:43:07.899245+00:00","revealed_rounds":[{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2611+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"},{"state":"revealed","answer":"train","number":2,"ends_at":"2026-10-02T18:46:01.216597+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218197+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218497+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:01.216597+00:00","completed_at":"2026-10-02T18:43:02.932198+00:00"},{"state":"revealed","answer":"stone","number":3,"ends_at":"2026-10-02T18:46:06.634358+00:00","players":[{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.635958+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.636258+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:06.634358+00:00","completed_at":"2026-10-02T18:43:07.78435+00:00"}]}}
        """#,
        "3-final-tie": #"""
        {"data":{"match":{"id":"6c152d9d-5a2b-4f88-8cfd-13ae0fca27e4","mode":"classic_live_v1","status":"completed","revision":20,"join_code":"KEM62A","expires_at":"2026-10-02T19:42:52.838184+00:00","started_at":"2026-10-02T18:42:53.2592+00:00","round_count":3,"completed_at":"2026-10-02T18:43:07.78435+00:00","current_round":3,"terminal_reason":null,"creator_member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","minimum_client_build":2},"round":{"state":"revealed","answer":"stone","number":3,"ends_at":"2026-10-02T18:46:06.634358+00:00","players":[{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.635958+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.635958+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:06.634358+00:00","completed_at":"2026-10-02T18:43:07.78435+00:00"},"members":[{"id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"7e6d6645-ef16-4633-b91d-d3c71b587274","display_name":"Player dae45d"},{"id":"3902e0cc-57d8-4b65-b221-29920a080b49","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"ec267abe-26d5-4d4c-91be-5ecd4a65565a","display_name":"Player 1f9c04"}],"version":2,"standings":{"players":[{"member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"rounds_solved":3,"efficiency_points":15,"total_solve_duration_ms":4},{"member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":1,"rounds_solved":3,"efficiency_points":15,"total_solve_duration_ms":4}],"is_final":true,"through_round":3},"server_time":"2026-10-02T18:43:08.507865+00:00","revealed_rounds":[{"state":"revealed","answer":"crane","number":1,"ends_at":"2026-10-02T18:45:56.2592+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:42:56.2597+00:00"},{"guess":"crane","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:42:56.2608+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:42:56.2592+00:00","completed_at":"2026-10-02T18:42:57.433044+00:00"},{"state":"revealed","answer":"train","number":2,"ends_at":"2026-10-02T18:46:01.216597+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218197+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:01.217097+00:00"},{"guess":"train","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:01.218197+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:01.216597+00:00","completed_at":"2026-10-02T18:43:02.932198+00:00"},{"state":"revealed","answer":"stone","number":3,"ends_at":"2026-10-02T18:46:06.634358+00:00","players":[{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.635958+00:00"}],"state":"solved","member_id":"2aa6900b-d0df-4ddc-a18b-6cb44cbd210c","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[0,0,2,0,2],"sequence":1,"submitted_at":"2026-10-02T18:43:06.634858+00:00"},{"guess":"stone","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:06.635958+00:00"}],"state":"solved","member_id":"3902e0cc-57d8-4b65-b221-29920a080b49","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:06.634358+00:00","completed_at":"2026-10-02T18:43:07.78435+00:00"}]}}
        """#,
        "5-lobby": #"""
        {"data":{"match":{"id":"f374ec38-7323-4ff3-8242-0d48317d193f","mode":"classic_live_v1","status":"lobby","revision":1,"join_code":"ZKARQJ","expires_at":"2026-10-02T19:43:08.973721+00:00","started_at":null,"round_count":5,"completed_at":null,"current_round":1,"terminal_reason":null,"creator_member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","minimum_client_build":2},"round":{"state":"pending","answer":null,"number":1,"ends_at":null,"players":[],"starts_at":null,"completed_at":null},"members":[{"id":"ac72d916-f831-4e5d-b42e-c3539a768488","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"65b5a0ad-9940-4225-811e-6f7e7766397b","display_name":"Player 25172d"}],"version":2,"standings":null,"server_time":"2026-10-02T18:43:09.025398+00:00","revealed_rounds":[]}}
        """#,
        "5-round-5-reveal": #"""
        {"data":{"match":{"id":"f374ec38-7323-4ff3-8242-0d48317d193f","mode":"classic_live_v1","status":"completed","revision":32,"join_code":"ZKARQJ","expires_at":"2026-10-02T19:43:08.973721+00:00","started_at":"2026-10-02T18:43:09.386027+00:00","round_count":5,"completed_at":"2026-10-02T18:43:33.446338+00:00","current_round":5,"terminal_reason":null,"creator_member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","minimum_client_build":2},"round":{"state":"revealed","answer":"charm","number":5,"ends_at":"2026-10-02T18:46:32.280373+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.281973+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.282273+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:32.280373+00:00","completed_at":"2026-10-02T18:43:33.446338+00:00"},"members":[{"id":"ac72d916-f831-4e5d-b42e-c3539a768488","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"65b5a0ad-9940-4225-811e-6f7e7766397b","display_name":"Player 25172d"},{"id":"d723a198-0653-4163-97b9-a7f114028117","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"3f4c6280-2c5e-4684-87d1-035f8ee1738a","display_name":"Player 39204c"}],"version":2,"standings":{"players":[{"member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"rounds_solved":5,"efficiency_points":25,"total_solve_duration_ms":8},{"member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":2,"rounds_solved":5,"efficiency_points":25,"total_solve_duration_ms":9}],"is_final":true,"through_round":5},"server_time":"2026-10-02T18:43:33.548998+00:00","revealed_rounds":[{"state":"revealed","answer":"river","number":1,"ends_at":"2026-10-02T18:46:12.386027+00:00","players":[{"board":[{"guess":"adore","feedback":[0,0,0,1,1],"sequence":1,"submitted_at":"2026-10-02T18:43:12.386527+00:00"},{"guess":"river","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:12.387627+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[0,0,0,1,1],"sequence":1,"submitted_at":"2026-10-02T18:43:12.386527+00:00"},{"guess":"river","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:12.387927+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:12.386027+00:00","completed_at":"2026-10-02T18:43:13.42458+00:00"},{"state":"revealed","answer":"trail","number":2,"ends_at":"2026-10-02T18:46:17.113612+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:17.114112+00:00"},{"guess":"trail","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:17.115212+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:17.114112+00:00"},{"guess":"trail","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:17.115512+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:17.113612+00:00","completed_at":"2026-10-02T18:43:18.354138+00:00"},{"state":"revealed","answer":"coral","number":3,"ends_at":"2026-10-02T18:46:22.377021+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,1,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:22.377521+00:00"},{"guess":"coral","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:22.378621+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,1,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:22.377521+00:00"},{"guess":"coral","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:22.378921+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:22.377021+00:00","completed_at":"2026-10-02T18:43:23.611339+00:00"},{"state":"revealed","answer":"frame","number":4,"ends_at":"2026-10-02T18:46:27.308994+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:43:27.309494+00:00"},{"guess":"frame","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:27.310594+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:43:27.309494+00:00"},{"guess":"frame","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:27.310894+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:27.308994+00:00","completed_at":"2026-10-02T18:43:28.535953+00:00"},{"state":"revealed","answer":"charm","number":5,"ends_at":"2026-10-02T18:46:32.280373+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.281973+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.282273+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":2,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:32.280373+00:00","completed_at":"2026-10-02T18:43:33.446338+00:00"}]}}
        """#,
        "5-final-tie": #"""
        {"data":{"match":{"id":"f374ec38-7323-4ff3-8242-0d48317d193f","mode":"classic_live_v1","status":"completed","revision":32,"join_code":"ZKARQJ","expires_at":"2026-10-02T19:43:08.973721+00:00","started_at":"2026-10-02T18:43:09.386027+00:00","round_count":5,"completed_at":"2026-10-02T18:43:33.446338+00:00","current_round":5,"terminal_reason":null,"creator_member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","minimum_client_build":2},"round":{"state":"revealed","answer":"charm","number":5,"ends_at":"2026-10-02T18:46:32.280373+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.281973+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.281973+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:32.280373+00:00","completed_at":"2026-10-02T18:43:33.446338+00:00"},"members":[{"id":"ac72d916-f831-4e5d-b42e-c3539a768488","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"65b5a0ad-9940-4225-811e-6f7e7766397b","display_name":"Player 25172d"},{"id":"d723a198-0653-4163-97b9-a7f114028117","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"3f4c6280-2c5e-4684-87d1-035f8ee1738a","display_name":"Player 39204c"}],"version":2,"standings":{"players":[{"member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"rounds_solved":5,"efficiency_points":25,"total_solve_duration_ms":8},{"member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":1,"rounds_solved":5,"efficiency_points":25,"total_solve_duration_ms":8}],"is_final":true,"through_round":5},"server_time":"2026-10-02T18:43:34.1593+00:00","revealed_rounds":[{"state":"revealed","answer":"river","number":1,"ends_at":"2026-10-02T18:46:12.386027+00:00","players":[{"board":[{"guess":"adore","feedback":[0,0,0,1,1],"sequence":1,"submitted_at":"2026-10-02T18:43:12.386527+00:00"},{"guess":"river","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:12.387627+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[0,0,0,1,1],"sequence":1,"submitted_at":"2026-10-02T18:43:12.386527+00:00"},{"guess":"river","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:12.387627+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:12.386027+00:00","completed_at":"2026-10-02T18:43:13.42458+00:00"},{"state":"revealed","answer":"trail","number":2,"ends_at":"2026-10-02T18:46:17.113612+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:17.114112+00:00"},{"guess":"trail","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:17.115212+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:17.114112+00:00"},{"guess":"trail","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:17.115212+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:17.113612+00:00","completed_at":"2026-10-02T18:43:18.354138+00:00"},{"state":"revealed","answer":"coral","number":3,"ends_at":"2026-10-02T18:46:22.377021+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,1,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:22.377521+00:00"},{"guess":"coral","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:22.378621+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,1,1,0],"sequence":1,"submitted_at":"2026-10-02T18:43:22.377521+00:00"},{"guess":"coral","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:22.378621+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:22.377021+00:00","completed_at":"2026-10-02T18:43:23.611339+00:00"},{"state":"revealed","answer":"frame","number":4,"ends_at":"2026-10-02T18:46:27.308994+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:43:27.309494+00:00"},{"guess":"frame","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:27.310594+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,1,2],"sequence":1,"submitted_at":"2026-10-02T18:43:27.309494+00:00"},{"guess":"frame","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:27.310594+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:27.308994+00:00","completed_at":"2026-10-02T18:43:28.535953+00:00"},{"state":"revealed","answer":"charm","number":5,"ends_at":"2026-10-02T18:46:32.280373+00:00","players":[{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.281973+00:00"}],"state":"solved","member_id":"ac72d916-f831-4e5d-b42e-c3539a768488","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2},{"board":[{"guess":"adore","feedback":[1,0,0,2,0],"sequence":1,"submitted_at":"2026-10-02T18:43:32.280873+00:00"},{"guess":"charm","feedback":[2,2,2,2,2],"sequence":2,"submitted_at":"2026-10-02T18:43:32.281973+00:00"}],"state":"solved","member_id":"d723a198-0653-4163-97b9-a7f114028117","placement":1,"efficiency_points":5,"solve_duration_ms":1,"accepted_guess_count":2}],"starts_at":"2026-10-02T18:43:32.280373+00:00","completed_at":"2026-10-02T18:43:33.446338+00:00"}]}}
        """#,
        "deletion-active": #"""
        {"data":{"match":{"id":"668faa4a-e676-40be-9b67-c91a1683e6b6","mode":"classic_live_v1","status":"in_progress","revision":4,"join_code":"RCU2PE","expires_at":"2026-10-02T19:43:34.635861+00:00","started_at":"2026-10-02T18:43:34.764397+00:00","round_count":3,"completed_at":null,"current_round":1,"terminal_reason":"account_deleted","creator_member_id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","minimum_client_build":2},"round":{"state":"countdown","answer":null,"number":1,"ends_at":"2026-10-02T18:46:37.764397+00:00","players":[{"board":[],"state":"playing","member_id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"forfeited","member_id":"49758490-332c-4dfe-9903-41e2879a5c9a","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:43:37.764397+00:00","completed_at":null},"members":[{"id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"ebd4a5dc-8689-419c-9a2a-d7bd79f5db09","display_name":"Player a8ac01"},{"id":"49758490-332c-4dfe-9903-41e2879a5c9a","seat":2,"is_self":false,"is_deleted":true,"avatar_seed":"deleted-player","display_name":"Deleted Player"}],"version":2,"standings":null,"server_time":"2026-10-02T18:43:35.294132+00:00","revealed_rounds":[]}}
        """#,
        "deletion-active-revealed": #"""
        {"data":{"match":{"id":"668faa4a-e676-40be-9b67-c91a1683e6b6","mode":"classic_live_v1","status":"incomplete","revision":6,"join_code":"RCU2PE","expires_at":"2026-10-02T19:43:34.635861+00:00","started_at":"2026-10-02T18:40:29.764397+00:00","round_count":3,"completed_at":null,"current_round":1,"terminal_reason":"account_deleted","creator_member_id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","minimum_client_build":2},"round":{"state":"revealed","answer":"pearl","number":1,"ends_at":"2026-10-02T18:43:32.764397+00:00","players":[{"board":[],"state":"timed_out","member_id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"49758490-332c-4dfe-9903-41e2879a5c9a","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:40:32.764397+00:00","completed_at":"2026-10-02T18:44:00.08418+00:00"},"members":[{"id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"ebd4a5dc-8689-419c-9a2a-d7bd79f5db09","display_name":"Player a8ac01"},{"id":"49758490-332c-4dfe-9903-41e2879a5c9a","seat":2,"is_self":false,"is_deleted":true,"avatar_seed":"deleted-player","display_name":"Deleted Player"}],"version":2,"standings":{"players":[{"member_id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0},{"member_id":"49758490-332c-4dfe-9903-41e2879a5c9a","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0}],"is_final":false,"through_round":1},"server_time":"2026-10-02T18:44:00.715701+00:00","revealed_rounds":[{"state":"revealed","answer":"pearl","number":1,"ends_at":"2026-10-02T18:43:32.764397+00:00","players":[{"board":[],"state":"timed_out","member_id":"560c2d9c-0e3b-4474-80e8-01aa44034eaa","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"49758490-332c-4dfe-9903-41e2879a5c9a","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:40:32.764397+00:00","completed_at":"2026-10-02T18:44:00.08418+00:00"}]}}
        """#,
        "deletion-between": #"""
        {"data":{"match":{"id":"7918e3e6-f9ba-4c43-87a4-b5863daf9b10","mode":"classic_live_v1","status":"incomplete","revision":5,"join_code":"B3CSLK","expires_at":"2026-10-02T19:44:01.59799+00:00","started_at":"2026-10-02T18:44:01.745904+00:00","round_count":3,"completed_at":null,"current_round":1,"terminal_reason":"account_deleted","creator_member_id":"6acb5bd1-a07a-462a-80fe-90898ca1987d","minimum_client_build":2},"round":{"state":"revealed","answer":"eager","number":1,"ends_at":"2026-10-02T18:47:04.745904+00:00","players":[{"board":[],"state":"forfeited","member_id":"6acb5bd1-a07a-462a-80fe-90898ca1987d","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"be8fc265-8d72-43cf-bc8f-3f4d5d12e2c9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:44:04.745904+00:00","completed_at":"2026-10-02T18:44:01.781693+00:00"},"members":[{"id":"6acb5bd1-a07a-462a-80fe-90898ca1987d","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"805106c5-296c-4f6a-8cab-2f6f89a11f0c","display_name":"Player 5c21f2"},{"id":"be8fc265-8d72-43cf-bc8f-3f4d5d12e2c9","seat":2,"is_self":false,"is_deleted":true,"avatar_seed":"deleted-player","display_name":"Deleted Player"}],"version":2,"standings":{"players":[{"member_id":"6acb5bd1-a07a-462a-80fe-90898ca1987d","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0},{"member_id":"be8fc265-8d72-43cf-bc8f-3f4d5d12e2c9","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0}],"is_final":false,"through_round":1},"server_time":"2026-10-02T18:44:02.173691+00:00","revealed_rounds":[{"state":"revealed","answer":"eager","number":1,"ends_at":"2026-10-02T18:47:04.745904+00:00","players":[{"board":[],"state":"forfeited","member_id":"6acb5bd1-a07a-462a-80fe-90898ca1987d","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"be8fc265-8d72-43cf-bc8f-3f4d5d12e2c9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:44:04.745904+00:00","completed_at":"2026-10-02T18:44:01.781693+00:00"}]}}
        """#,
        "deletion-final-active": #"""
        {"data":{"match":{"id":"8aabc120-048c-463a-b4d2-3c927d1d05e5","mode":"classic_live_v1","status":"in_progress","revision":8,"join_code":"RBE2JB","expires_at":"2026-10-02T19:44:03.133339+00:00","started_at":"2026-10-02T18:44:03.280999+00:00","round_count":3,"completed_at":null,"current_round":3,"terminal_reason":null,"creator_member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","minimum_client_build":2},"round":{"state":"countdown","answer":null,"number":3,"ends_at":"2026-10-02T18:47:06.546538+00:00","players":[{"board":[],"state":"playing","member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0},{"board":null,"state":"forfeited","member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":null,"efficiency_points":null,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:44:06.546538+00:00","completed_at":null},"members":[{"id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"5540e05c-44ed-49ac-a781-c5a5d087eeda","display_name":"Player e040dd"},{"id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","seat":2,"is_self":false,"is_deleted":true,"avatar_seed":"deleted-player","display_name":"Deleted Player"}],"version":2,"standings":{"players":[{"member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0},{"member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0}],"is_final":false,"through_round":2},"server_time":"2026-10-02T18:44:04.144081+00:00","revealed_rounds":[{"state":"revealed","answer":"toast","number":1,"ends_at":"2026-10-02T18:47:06.280999+00:00","players":[{"board":[],"state":"forfeited","member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:44:06.280999+00:00","completed_at":"2026-10-02T18:44:03.319987+00:00"},{"state":"revealed","answer":"mirth","number":2,"ends_at":"2026-10-02T18:47:06.381141+00:00","players":[{"board":[],"state":"forfeited","member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:44:06.381141+00:00","completed_at":"2026-10-02T18:44:03.440747+00:00"}]}}
        """#,
        "deletion-final-active-revealed": #"""
        {"data":{"match":{"id":"8aabc120-048c-463a-b4d2-3c927d1d05e5","mode":"classic_live_v1","status":"completed","revision":10,"join_code":"RBE2JB","expires_at":"2026-10-02T19:44:03.133339+00:00","started_at":"2026-10-02T18:40:58.280999+00:00","round_count":3,"completed_at":"2026-10-02T18:45:00.04009+00:00","current_round":3,"terminal_reason":null,"creator_member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","minimum_client_build":2},"round":{"state":"revealed","answer":"eager","number":3,"ends_at":"2026-10-02T18:44:01.546538+00:00","players":[{"board":[],"state":"timed_out","member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:41:01.546538+00:00","completed_at":"2026-10-02T18:45:00.04009+00:00"},"members":[{"id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"5540e05c-44ed-49ac-a781-c5a5d087eeda","display_name":"Player e040dd"},{"id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","seat":2,"is_self":false,"is_deleted":true,"avatar_seed":"deleted-player","display_name":"Deleted Player"}],"version":2,"standings":{"players":[{"member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0},{"member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0}],"is_final":true,"through_round":3},"server_time":"2026-10-02T18:45:00.185969+00:00","revealed_rounds":[{"state":"revealed","answer":"toast","number":1,"ends_at":"2026-10-02T18:44:01.280999+00:00","players":[{"board":[],"state":"forfeited","member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:41:01.280999+00:00","completed_at":"2026-10-02T18:40:58.319987+00:00"},{"state":"revealed","answer":"mirth","number":2,"ends_at":"2026-10-02T18:44:01.381141+00:00","players":[{"board":[],"state":"forfeited","member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:41:01.381141+00:00","completed_at":"2026-10-02T18:40:58.440747+00:00"},{"state":"revealed","answer":"eager","number":3,"ends_at":"2026-10-02T18:44:01.546538+00:00","players":[{"board":[],"state":"timed_out","member_id":"c84908dd-44c8-4fe5-ac81-8c5a7f1b9cda","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"89b86bc7-8eb1-43af-ab65-c052b32e73f9","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:41:01.546538+00:00","completed_at":"2026-10-02T18:45:00.04009+00:00"}]}}
        """#,
        "deletion-completed": #"""
        {"data":{"match":{"id":"524e27a2-4acb-47f2-a782-274c3d0792e2","mode":"classic_live_v1","status":"completed","revision":9,"join_code":"NAJTQ9","expires_at":"2026-10-02T19:45:01.444758+00:00","started_at":"2026-10-02T18:45:01.649164+00:00","round_count":3,"completed_at":"2026-10-02T18:45:01.960095+00:00","current_round":3,"terminal_reason":null,"creator_member_id":"63567a27-347c-4abf-bacf-10a8d7cf53d8","minimum_client_build":2},"round":{"state":"revealed","answer":"coral","number":3,"ends_at":"2026-10-02T18:48:04.918425+00:00","players":[{"board":[],"state":"forfeited","member_id":"63567a27-347c-4abf-bacf-10a8d7cf53d8","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"835805b7-cb8c-4ed8-af08-561f975e734e","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:45:04.918425+00:00","completed_at":"2026-10-02T18:45:01.960095+00:00"},"members":[{"id":"63567a27-347c-4abf-bacf-10a8d7cf53d8","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"e7b24265-f663-4688-a55d-c2bd889e6ea3","display_name":"Player e7f0bb"},{"id":"835805b7-cb8c-4ed8-af08-561f975e734e","seat":2,"is_self":false,"is_deleted":true,"avatar_seed":"deleted-player","display_name":"Deleted Player"}],"version":2,"standings":{"players":[{"member_id":"63567a27-347c-4abf-bacf-10a8d7cf53d8","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0},{"member_id":"835805b7-cb8c-4ed8-af08-561f975e734e","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0}],"is_final":true,"through_round":3},"server_time":"2026-10-02T18:45:02.973018+00:00","revealed_rounds":[{"state":"revealed","answer":"magic","number":1,"ends_at":"2026-10-02T18:48:04.649164+00:00","players":[{"board":[],"state":"forfeited","member_id":"63567a27-347c-4abf-bacf-10a8d7cf53d8","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"835805b7-cb8c-4ed8-af08-561f975e734e","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:45:04.649164+00:00","completed_at":"2026-10-02T18:45:01.697454+00:00"},{"state":"revealed","answer":"sugar","number":2,"ends_at":"2026-10-02T18:48:04.771868+00:00","players":[{"board":[],"state":"forfeited","member_id":"63567a27-347c-4abf-bacf-10a8d7cf53d8","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"835805b7-cb8c-4ed8-af08-561f975e734e","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:45:04.771868+00:00","completed_at":"2026-10-02T18:45:01.826541+00:00"},{"state":"revealed","answer":"coral","number":3,"ends_at":"2026-10-02T18:48:04.918425+00:00","players":[{"board":[],"state":"forfeited","member_id":"63567a27-347c-4abf-bacf-10a8d7cf53d8","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"forfeited","member_id":"835805b7-cb8c-4ed8-af08-561f975e734e","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:45:04.918425+00:00","completed_at":"2026-10-02T18:45:01.960095+00:00"}]}}
        """#,
        "ordinary-cron-nonfinal": #"""
        {"data":{"match":{"id":"ef0b4001-0f79-49a5-9fa7-1d92a009d6f0","mode":"classic_live_v1","status":"in_progress","revision":5,"join_code":"SQZUWK","expires_at":"2026-10-02T19:45:06.362244+00:00","started_at":"2026-10-02T18:42:01.591336+00:00","round_count":3,"completed_at":null,"current_round":1,"terminal_reason":null,"creator_member_id":"4f09f293-6dbc-4e95-9fdf-66b56081683f","minimum_client_build":2},"round":{"state":"revealed","answer":"horse","number":1,"ends_at":"2026-10-02T18:45:04.591336+00:00","players":[{"board":[],"state":"timed_out","member_id":"4f09f293-6dbc-4e95-9fdf-66b56081683f","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"timed_out","member_id":"323a1816-95fb-437f-a483-98114620b00f","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:42:04.591336+00:00","completed_at":"2026-10-02T18:46:00.306711+00:00"},"members":[{"id":"4f09f293-6dbc-4e95-9fdf-66b56081683f","seat":1,"is_self":true,"is_deleted":false,"avatar_seed":"ff681e6e-bdd5-4b57-a3e6-fc5ea49f3d74","display_name":"Player 2b83ed"},{"id":"323a1816-95fb-437f-a483-98114620b00f","seat":2,"is_self":false,"is_deleted":false,"avatar_seed":"80eb37f6-58f9-452f-a052-aba4245d1a95","display_name":"Player 63eef1"}],"version":2,"standings":{"players":[{"member_id":"4f09f293-6dbc-4e95-9fdf-66b56081683f","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0},{"member_id":"323a1816-95fb-437f-a483-98114620b00f","placement":1,"rounds_solved":0,"efficiency_points":0,"total_solve_duration_ms":0}],"is_final":false,"through_round":1},"server_time":"2026-10-02T18:46:00.692024+00:00","revealed_rounds":[{"state":"revealed","answer":"horse","number":1,"ends_at":"2026-10-02T18:45:04.591336+00:00","players":[{"board":[],"state":"timed_out","member_id":"4f09f293-6dbc-4e95-9fdf-66b56081683f","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0},{"board":[],"state":"timed_out","member_id":"323a1816-95fb-437f-a483-98114620b00f","placement":1,"efficiency_points":0,"solve_duration_ms":null,"accepted_guess_count":0}],"starts_at":"2026-10-02T18:42:04.591336+00:00","completed_at":"2026-10-02T18:46:00.306711+00:00"}]}}
        """#,
    ]
}
