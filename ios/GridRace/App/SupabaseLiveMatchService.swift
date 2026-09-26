import Foundation
import Supabase

actor SupabaseLiveMatchService: LiveMatchServicing {
    typealias Invoke = @Sendable (_ function: String, _ body: Data) async throws -> Data

    private let clientBuild: Int
    private let invoke: Invoke

    init(client: SupabaseClient, clientBuild: Int = 1) {
        self.clientBuild = clientBuild
        invoke = { function, body in
            try await client.functions.invoke(
                function,
                options: .init(headers: ["Content-Type": "application/json"], body: body),
                decode: { data, _ in data }
            )
        }
    }

    init(clientBuild: Int = 1, invoke: @escaping Invoke) {
        self.clientBuild = clientBuild
        self.invoke = invoke
    }

    func createMatch(requestID: UUID) async throws -> UUID {
        try await matchID(
            function: "create-match",
            request: CreateRequest(clientBuild: clientBuild, requestID: requestID)
        )
    }

    func joinMatch(code: String) async throws -> UUID {
        try await matchID(
            function: "join-match",
            request: JoinRequest(clientBuild: clientBuild, joinCode: code.uppercased())
        )
    }

    func startMatch(id: UUID) async throws -> UUID {
        let returnedID = try await matchID(
            function: "start-match",
            request: MatchRequest(clientBuild: clientBuild, matchID: id)
        )
        guard returnedID == id else { throw LiveMatchServiceError.invalidResponse }
        return returnedID
    }

    func submitGuess(
        matchID: UUID,
        requestID: UUID,
        guess: String
    ) async throws -> LiveGuessReceipt {
        let response: GuessResponse = try await command(
            function: "submit-guess",
            request: GuessRequest(
                clientBuild: clientBuild,
                matchID: matchID,
                roundNumber: 1,
                requestID: requestID,
                guess: guess
            )
        )
        guard response.accepted,
              (1...6).contains(response.sequence),
              response.feedback.count == 5,
              response.acceptedGuessCount == response.sequence,
              response.roundEndTime >= response.serverTime,
              Self.validGuessReceipt(response)
        else { throw LiveMatchServiceError.invalidResponse }
        return LiveGuessReceipt(
            sequence: response.sequence,
            feedback: response.feedback,
            playerState: response.playerState,
            acceptedGuessCount: response.acceptedGuessCount,
            solveDurationMilliseconds: response.solveDurationMilliseconds,
            efficiencyPoints: response.efficiencyPoints,
            serverTime: response.serverTime,
            roundEndTime: response.roundEndTime
        )
    }

    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot {
        let response: SnapshotResponse = try await command(
            function: "match-snapshot",
            request: MatchRequest(clientBuild: clientBuild, matchID: matchID)
        )
        let snapshot = try Self.map(response)
        guard snapshot.match.id == matchID else { throw LiveMatchServiceError.invalidResponse }
        return snapshot
    }

    private func matchID<Request: Encodable & Sendable>(
        function: String,
        request: Request
    ) async throws -> UUID {
        let response: MatchIDResponse = try await command(function: function, request: request)
        return response.matchID
    }

    private func command<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        function: String,
        request: Request
    ) async throws -> Response {
        do {
            let body = try JSONEncoder().encode(request)
            let data = try await invoke(function, body)
            return try Self.makeDecoder().decode(CommandEnvelope<Response>.self, from: data).data
        } catch let error as LiveMatchServiceError {
            throw error
        } catch FunctionsError.httpError(let status, let data) {
            throw Self.serverError(status: status, data: data) ?? .unavailable
        } catch is CancellationError {
            throw CancellationError()
        } catch is EncodingError {
            throw LiveMatchServiceError.invalidResponse
        } catch is DecodingError {
            throw LiveMatchServiceError.invalidResponse
        } catch {
            throw LiveMatchServiceError.unavailable
        }
    }

    static func serverError(status: Int, data: Data) -> LiveMatchServiceError? {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
              !envelope.error.message.isEmpty,
              let code = LiveMatchServerError(rawValue: envelope.error.code),
              valid(status: status, for: code)
        else { return nil }
        return .server(code)
    }

    private static func valid(status: Int, for code: LiveMatchServerError) -> Bool {
        switch code {
        case .invalidGuessFormat: status == 400
        case .notAuthenticated: status == 401
        case .notAMatchMember, .notHost: status == 403
        case .matchNotJoinable, .roomFull, .notEnoughPlayers, .roundNotActive,
             .roundAlreadyFinished, .requestConflict: status == 409
        case .roomExpired: status == 410
        case .wordNotAccepted: status == 422
        case .clientUpdateRequired: status == 426
        case .rateLimited: status == 429
        case .internalError: status == 400 || status == 405 || status == 500
        }
    }

    static func decodeSnapshot(_ data: Data) throws -> LiveMatchSnapshot {
        do {
            return try map(makeDecoder().decode(CommandEnvelope<SnapshotResponse>.self, from: data).data)
        } catch let error as LiveMatchServiceError {
            throw error
        } catch {
            throw LiveMatchServiceError.invalidResponse
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard value.range(
                of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|\+00:00)$"#,
                options: .regularExpression
            ) != nil else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Timestamp must be RFC 3339 UTC with at most microseconds"
                )
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value) ?? whole.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Invalid RFC 3339 timestamp"
                )
            }
            return date
        }
        return decoder
    }

    private static func map(_ value: SnapshotResponse) throws -> LiveMatchSnapshot {
        let members = value.members
        let memberIDs = Set(members.map(\.id))
        let seats = members.map(\.seat)
        guard value.version == 1,
              value.match.mode == "classic_live_v1",
              value.match.roundCount == 1,
              value.match.currentRound == 1,
              value.match.minimumClientBuild > 0,
              (1...2).contains(members.count),
              memberIDs.count == members.count,
              Set(seats).count == members.count,
              seats == Array(1...members.count),
              members.filter(\.isSelf).count == 1,
              members.allSatisfy({ !$0.isDeleted || !$0.isSelf }),
              members.allSatisfy({
                  !$0.isDeleted
                      || ($0.displayName == "Deleted Player" && $0.avatarSeed == "deleted-player")
              }),
              memberIDs.contains(value.match.creatorMemberID),
              value.match.joinCode.utf8.count == 6,
              value.match.joinCode.utf8.allSatisfy({
                  (65...72).contains($0) || (74...78).contains($0)
                      || (80...90).contains($0) || (50...57).contains($0)
              }),
              value.round.number == 1
        else { throw LiveMatchServiceError.invalidResponse }

        let selfID = members.first(where: \.isSelf)!.id
        switch value.match.status {
        case .lobby:
            guard value.round.state == .pending,
                  value.round.players.isEmpty,
                  value.round.startsAt == nil,
                  value.round.endsAt == nil,
                  value.round.completedAt == nil,
                  value.round.answer == nil
            else { throw LiveMatchServiceError.invalidResponse }
        case .inProgress, .completed:
            guard members.count == 2,
                  value.round.players.count == 2,
                  value.round.players.map(\.memberID) == members.map(\.id),
                  let startsAt = value.round.startsAt,
                  let endsAt = value.round.endsAt,
                  abs(endsAt.timeIntervalSince(startsAt) - 180) < 0.000_001
            else { throw LiveMatchServiceError.invalidResponse }

            let revealed = value.round.state == .revealed
            guard revealed == (value.match.status == .completed),
                  revealed || value.round.state == .countdown || value.round.state == .playing,
                  value.round.state != .countdown || value.serverTime < startsAt,
                  value.round.state != .playing
                      || (value.serverTime >= startsAt && value.serverTime < endsAt),
                  revealed == (value.round.completedAt != nil),
                  revealed == (value.round.answer != nil),
                  value.round.answer.map(validWord) ?? !revealed
            else { throw LiveMatchServiceError.invalidResponse }

            if value.round.state == .countdown,
               !value.round.players.allSatisfy({ $0.acceptedGuessCount == 0 }) {
                throw LiveMatchServiceError.invalidResponse
            }

            for player in value.round.players {
                let isSelf = player.memberID == selfID
                if !revealed && !isSelf {
                    guard player.board == nil,
                          player.solveDurationMilliseconds == nil,
                          player.efficiencyPoints == nil,
                          player.placement == nil,
                          validHiddenPlayerState(
                              player.state,
                              count: player.acceptedGuessCount
                          )
                    else { throw LiveMatchServiceError.invalidResponse }
                    continue
                }
                guard let board = player.board,
                      validPlayerResult(
                          state: player.state,
                          count: player.acceptedGuessCount,
                          duration: player.solveDurationMilliseconds,
                          efficiency: player.efficiencyPoints,
                          placement: player.placement,
                          revealed: revealed
                      ),
                      board.count == player.acceptedGuessCount,
                      board.enumerated().allSatisfy({ offset, guess in
                          guess.sequence == offset + 1
                              && validWord(guess.guess)
                              && guess.feedback.count == 5
                              && guess.submittedAt >= startsAt
                              && guess.submittedAt <= endsAt
                      }),
                      player.state != .solved || board.last?.feedback.allSatisfy({ $0 == .correct }) == true,
                      player.state == .solved || !board.contains(where: {
                          $0.feedback.allSatisfy { $0 == .correct }
                      }),
                      player.state != .solved || !board.dropLast().contains(where: {
                          $0.feedback.allSatisfy { $0 == .correct }
                      }),
                      !revealed || player.state != .solved
                          || board.last?.guess.lowercased() == value.round.answer?.lowercased()
                else { throw LiveMatchServiceError.invalidResponse }
            }
            if revealed && !value.round.players.allSatisfy({ $0.state.isTerminal }) {
                throw LiveMatchServiceError.invalidResponse
            }
            if let completedAt = value.round.completedAt,
               completedAt < startsAt || completedAt > value.serverTime {
                throw LiveMatchServiceError.invalidResponse
            }
        }

        return LiveMatchSnapshot(
            serverTime: value.serverTime,
            match: LiveMatch(
                id: value.match.id,
                joinCode: value.match.joinCode,
                creatorMemberID: value.match.creatorMemberID,
                status: value.match.status,
                expiresAt: value.match.expiresAt,
                minimumClientBuild: value.match.minimumClientBuild
            ),
            members: members.map {
                LiveMatchMember(
                    id: $0.id,
                    seat: $0.seat,
                    displayName: $0.displayName,
                    avatarSeed: $0.avatarSeed,
                    isSelf: $0.isSelf,
                    isDeleted: $0.isDeleted
                )
            },
            round: LiveRound(
                state: value.round.state,
                startsAt: value.round.startsAt,
                endsAt: value.round.endsAt,
                completedAt: value.round.completedAt,
                answer: value.round.answer,
                players: value.round.players.map {
                    LiveRoundPlayer(
                        memberID: $0.memberID,
                        state: $0.state,
                        acceptedGuessCount: $0.acceptedGuessCount,
                        solveDurationMilliseconds: $0.solveDurationMilliseconds,
                        efficiencyPoints: $0.efficiencyPoints,
                        placement: $0.placement,
                        board: $0.board?.map {
                            LiveGuess(
                                sequence: $0.sequence,
                                word: $0.guess,
                                feedback: $0.feedback,
                                submittedAt: $0.submittedAt
                            )
                        }
                    )
                }
            )
        )
    }

    private static func validPlayerResult(
        state: LivePlayerState,
        count: Int,
        duration: Int?,
        efficiency: Int?,
        placement: Int?,
        revealed: Bool
    ) -> Bool {
        guard (0...6).contains(count), placement.map({ (1...2).contains($0) }) ?? true else {
            return false
        }
        switch state {
        case .playing:
            return count <= 5 && duration == nil && efficiency == nil && placement == nil
        case .solved:
            return (1...6).contains(count)
                && duration.map({ $0 >= 0 }) == true
                && efficiency == 7 - count
                && (revealed ? placement != nil : placement == nil)
        case .failed:
            return count == 6 && duration == nil && efficiency == 0
                && (revealed ? placement != nil : placement == nil)
        case .timedOut, .forfeited:
            return count <= 5 && duration == nil && efficiency == 0
                && (revealed ? placement != nil : placement == nil)
        }
    }

    private static func validGuessReceipt(_ response: GuessResponse) -> Bool {
        switch response.playerState {
        case .playing:
            return response.acceptedGuessCount <= 5
                && response.solveDurationMilliseconds == nil
                && response.efficiencyPoints == nil
        case .solved:
            return (1...6).contains(response.acceptedGuessCount)
                && response.solveDurationMilliseconds.map({ $0 >= 0 }) == true
                && response.efficiencyPoints == 7 - response.acceptedGuessCount
        case .failed:
            return response.acceptedGuessCount == 6
                && response.solveDurationMilliseconds == nil
                && response.efficiencyPoints == nil
        case .timedOut, .forfeited:
            return false
        }
    }

    private static func validHiddenPlayerState(_ state: LivePlayerState, count: Int) -> Bool {
        switch state {
        case .playing: (0...5).contains(count)
        case .solved: (1...6).contains(count)
        case .failed: count == 6
        case .timedOut, .forfeited: (0...5).contains(count)
        }
    }

    private static func validWord(_ value: String) -> Bool {
        value.utf8.count == 5 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0)
        }
    }
}

private struct CreateRequest: Encodable, Sendable {
    let clientBuild: Int
    let requestID: String
    init(clientBuild: Int, requestID: UUID) {
        self.clientBuild = clientBuild
        self.requestID = requestID.uuidString.lowercased()
    }
    enum CodingKeys: String, CodingKey { case clientBuild = "client_build", requestID = "request_id" }
}

private struct JoinRequest: Encodable, Sendable {
    let clientBuild: Int
    let joinCode: String
    enum CodingKeys: String, CodingKey { case clientBuild = "client_build", joinCode = "join_code" }
}

private struct MatchRequest: Encodable, Sendable {
    let clientBuild: Int
    let matchID: String
    init(clientBuild: Int, matchID: UUID) {
        self.clientBuild = clientBuild
        self.matchID = matchID.uuidString.lowercased()
    }
    enum CodingKeys: String, CodingKey { case clientBuild = "client_build", matchID = "match_id" }
}

private struct GuessRequest: Encodable, Sendable {
    let clientBuild: Int
    let matchID: String
    let roundNumber: Int
    let requestID: String
    let guess: String
    init(clientBuild: Int, matchID: UUID, roundNumber: Int, requestID: UUID, guess: String) {
        self.clientBuild = clientBuild
        self.matchID = matchID.uuidString.lowercased()
        self.roundNumber = roundNumber
        self.requestID = requestID.uuidString.lowercased()
        self.guess = guess
    }
    enum CodingKeys: String, CodingKey {
        case guess
        case clientBuild = "client_build"
        case matchID = "match_id"
        case roundNumber = "round_number"
        case requestID = "request_id"
    }
}

private struct CommandEnvelope<Value: Decodable & Sendable>: Decodable, Sendable { let data: Value }
private struct MatchIDResponse: Decodable, Sendable {
    let matchID: UUID
    enum CodingKeys: String, CodingKey { case matchID = "match_id" }
}
private struct ErrorEnvelope: Decodable { let error: ErrorBody }
private struct ErrorBody: Decodable { let code: String; let message: String }

private struct GuessResponse: Decodable, Sendable {
    let accepted: Bool
    let sequence: Int
    let feedback: [Feedback]
    let playerState: LivePlayerState
    let acceptedGuessCount: Int
    let solveDurationMilliseconds: Int?
    let efficiencyPoints: Int?
    let serverTime: Date
    let roundEndTime: Date

    enum CodingKeys: String, CodingKey {
        case accepted, sequence, feedback
        case playerState = "player_state"
        case acceptedGuessCount = "accepted_guess_count"
        case solveDurationMilliseconds = "solve_duration_ms"
        case efficiencyPoints = "efficiency_points"
        case serverTime = "server_time"
        case roundEndTime = "round_end_time"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try values.decode(Bool.self, forKey: .accepted)
        sequence = try values.decode(Int.self, forKey: .sequence)
        feedback = try values.decode([Feedback].self, forKey: .feedback)
        playerState = try values.decode(LivePlayerState.self, forKey: .playerState)
        acceptedGuessCount = try values.decode(Int.self, forKey: .acceptedGuessCount)
        solveDurationMilliseconds = try values.decodeRequiredIfPresent(Int.self, forKey: .solveDurationMilliseconds)
        efficiencyPoints = try values.decodeRequiredIfPresent(Int.self, forKey: .efficiencyPoints)
        serverTime = try values.decode(Date.self, forKey: .serverTime)
        roundEndTime = try values.decode(Date.self, forKey: .roundEndTime)
    }
}

private struct SnapshotResponse: Decodable, Sendable {
    let version: Int
    let serverTime: Date
    let match: MatchDTO
    let members: [MemberDTO]
    let round: RoundDTO
    enum CodingKeys: String, CodingKey { case version, match, members, round; case serverTime = "server_time" }
}

private struct MatchDTO: Decodable, Sendable {
    let id: UUID
    let joinCode: String
    let creatorMemberID: UUID
    let mode: String
    let roundCount: Int
    let currentRound: Int
    let status: LiveMatchStatus
    let expiresAt: Date
    let minimumClientBuild: Int
    enum CodingKeys: String, CodingKey {
        case id, mode, status
        case joinCode = "join_code"
        case creatorMemberID = "creator_member_id"
        case roundCount = "round_count"
        case currentRound = "current_round"
        case expiresAt = "expires_at"
        case minimumClientBuild = "minimum_client_build"
    }
}

private struct MemberDTO: Decodable, Sendable {
    let id: UUID
    let seat: Int
    let displayName: String
    let avatarSeed: String
    let isSelf: Bool
    let isDeleted: Bool
    enum CodingKeys: String, CodingKey {
        case id, seat
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
        case isSelf = "is_self"
        case isDeleted = "is_deleted"
    }
}

private struct RoundDTO: Decodable, Sendable {
    let number: Int
    let state: LiveRoundState
    let startsAt: Date?
    let endsAt: Date?
    let completedAt: Date?
    let answer: String?
    let players: [PlayerDTO]
    enum CodingKeys: String, CodingKey {
        case number, state, answer, players
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case completedAt = "completed_at"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        number = try values.decode(Int.self, forKey: .number)
        state = try values.decode(LiveRoundState.self, forKey: .state)
        startsAt = try values.decodeRequiredIfPresent(Date.self, forKey: .startsAt)
        endsAt = try values.decodeRequiredIfPresent(Date.self, forKey: .endsAt)
        completedAt = try values.decodeRequiredIfPresent(Date.self, forKey: .completedAt)
        answer = try values.decodeRequiredIfPresent(String.self, forKey: .answer)
        players = try values.decode([PlayerDTO].self, forKey: .players)
    }
}

private struct PlayerDTO: Decodable, Sendable {
    let memberID: UUID
    let state: LivePlayerState
    let acceptedGuessCount: Int
    let solveDurationMilliseconds: Int?
    let efficiencyPoints: Int?
    let placement: Int?
    let board: [GuessDTO]?
    enum CodingKeys: String, CodingKey {
        case state, placement, board
        case memberID = "member_id"
        case acceptedGuessCount = "accepted_guess_count"
        case solveDurationMilliseconds = "solve_duration_ms"
        case efficiencyPoints = "efficiency_points"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try values.decode(UUID.self, forKey: .memberID)
        state = try values.decode(LivePlayerState.self, forKey: .state)
        acceptedGuessCount = try values.decode(Int.self, forKey: .acceptedGuessCount)
        solveDurationMilliseconds = try values.decodeRequiredIfPresent(Int.self, forKey: .solveDurationMilliseconds)
        efficiencyPoints = try values.decodeRequiredIfPresent(Int.self, forKey: .efficiencyPoints)
        placement = try values.decodeRequiredIfPresent(Int.self, forKey: .placement)
        board = try values.decodeRequiredIfPresent([GuessDTO].self, forKey: .board)
    }
}

private struct GuessDTO: Decodable, Sendable {
    let sequence: Int
    let guess: String
    let feedback: [Feedback]
    let submittedAt: Date
    enum CodingKeys: String, CodingKey { case sequence, guess, feedback; case submittedAt = "submitted_at" }
}

private extension KeyedDecodingContainer {
    func decodeRequiredIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: codingPath, debugDescription: "Required nullable field is missing")
            )
        }
        return try decodeIfPresent(type, forKey: key)
    }
}

extension LiveMatchStatus: Decodable {}
extension LiveRoundState: Decodable {}
extension LivePlayerState: Decodable {}
