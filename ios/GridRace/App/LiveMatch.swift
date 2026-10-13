import Foundation

enum LiveMatchStatus: String, Sendable {
    case lobby
    case inProgress = "in_progress"
    case completed
    case incomplete
}

enum LiveRoundState: String, Sendable {
    case pending
    case countdown
    case playing
    case revealed
}

enum LivePlayerState: String, Sendable {
    case playing
    case solved
    case failed
    case timedOut = "timed_out"
    case forfeited

    var isTerminal: Bool { self != .playing }
}

enum LiveMatchTerminalReason: String, Sendable {
    case accountDeleted = "account_deleted"
}

struct LiveMatch: Equatable, Sendable {
    let id: UUID
    let joinCode: String
    let creatorMemberID: UUID
    let status: LiveMatchStatus
    let expiresAt: Date
    let minimumClientBuild: Int
    var roundCount = 1
    var currentRound = 1
    var startedAt: Date?
    var completedAt: Date?
    var terminalReason: LiveMatchTerminalReason?
    var admission = LiveMatchAdmission.code
}

struct LiveMatchMember: Equatable, Sendable {
    let id: UUID
    let seat: Int
    let displayName: String
    let avatarSeed: String
    let isSelf: Bool
    let isDeleted: Bool
}

struct LiveGuess: Equatable, Sendable {
    let sequence: Int
    let word: String
    let feedback: [Feedback]
    let submittedAt: Date
}

struct LiveRoundPlayer: Equatable, Sendable {
    let memberID: UUID
    let state: LivePlayerState
    let acceptedGuessCount: Int
    let solveDurationMilliseconds: Int?
    let efficiencyPoints: Int?
    let placement: Int?
    let board: [LiveGuess]?
}

struct LiveRound: Equatable, Sendable {
    let state: LiveRoundState
    let startsAt: Date?
    let endsAt: Date?
    let completedAt: Date?
    let answer: String?
    let players: [LiveRoundPlayer]
    var number = 1
}

struct LiveMatchSnapshot: Equatable, Sendable {
    var serverTime: Date
    let match: LiveMatch
    let members: [LiveMatchMember]
    let round: LiveRound
    var revision: Int64 = 1
    var revealedRounds: [LiveRound] = []
    var standings: LiveMatchStandings?
    var selection: LiveMatchSelection
    var rematch: LiveRematch?
}

struct LiveMatchStandings: Equatable, Sendable {
    let throughRound: Int
    let isFinal: Bool
    let players: [LiveMatchStanding]
}

struct LiveMatchStanding: Equatable, Sendable {
    let memberID: UUID
    let roundsSolved: Int
    let efficiencyPoints: Int
    let totalSolveDurationMilliseconds: Int
    let placement: Int
}

struct LiveGuessReceipt: Equatable, Sendable {
    let sequence: Int
    let feedback: [Feedback]
    let playerState: LivePlayerState
    let acceptedGuessCount: Int
    let solveDurationMilliseconds: Int?
    let efficiencyPoints: Int?
    let serverTime: Date
    let roundEndTime: Date
}

enum LiveMatchServerError: String, Error, CaseIterable, Sendable {
    case notAuthenticated = "not_authenticated"
    case notAMatchMember = "not_a_match_member"
    case matchNotJoinable = "match_not_joinable"
    case roomFull = "room_full"
    case roomExpired = "room_expired"
    case notHost = "not_host"
    case notEnoughPlayers = "not_enough_players"
    case roundNotActive = "round_not_active"
    case roundAlreadyFinished = "round_already_finished"
    case invalidGuessFormat = "invalid_guess_format"
    case wordNotAccepted = "word_not_accepted"
    case rateLimited = "rate_limited"
    case clientUpdateRequired = "client_update_required"
    case requestConflict = "request_conflict"
    case invalidMatchConfiguration = "invalid_match_configuration"
    case matchIncomplete = "match_incomplete"
    case rematchUnavailable = "rematch_unavailable"
    case rematchExpired = "rematch_expired"
    case answerPoolUnavailable = "answer_pool_unavailable"
    case participationChanged = "participation_changed"
    case internalError = "internal_error"
}

enum LiveMatchServiceError: Error, Equatable, Sendable {
    case server(LiveMatchServerError)
    case invalidResponse
    case unavailable
}

protocol LiveMatchServicing: Sendable {
    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID
    func joinMatch(_ command: LiveJoinCommand) async throws -> UUID
    func rematch(_ command: LiveRematchCommand) async throws -> LiveRematchReceipt
    func startMatch(id: UUID, roundNumber: Int) async throws -> UUID
    func submitGuess(matchID: UUID, roundNumber: Int, requestID: UUID, guess: String, clientBuild: Int) async throws -> LiveGuessReceipt
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot
}


enum LiveMatchAdmission: String, Codable, Sendable { case code, rematch }
struct LiveMatchSelection: Codable, Equatable, Sendable {
    let epoch: Int64
    let isSelected: Bool
    enum CodingKeys: String, CodingKey { case epoch, isSelected = "is_selected" }
}
enum LiveRematchState: String, Codable, Sendable { case eligible, offered, closed, expired, unavailable, accepted }
enum LiveRematchReason: String, Codable, Sendable {
    case cancelled, declined, expired, ineligible
    case participationChanged = "participation_changed"
    case accountDeleted = "account_deleted"
    case featureDisabled = "feature_disabled"
}
enum LiveRematchAction: String, Codable, Sendable { case offer, accept, cancel, decline }
struct LiveRematch: Decodable, Equatable, Sendable {
    let revision: Int64
    let isEligible: Bool
    let state: LiveRematchState
    let reason: LiveRematchReason?
    let generation: Int
    let nextGeneration: Int?
    let initiatorMemberID: UUID?
    let consentingMemberIDs: [UUID]
    var selectedElsewhere: Bool
    let deadline: Date
    let evaluatedAt: Date
    let successorMatchID: UUID?
    let successorAvailable: Bool
    enum CodingKeys: String, CodingKey {
        case revision, state, reason, generation, deadline
        case isEligible = "is_eligible", nextGeneration = "next_generation"
        case initiatorMemberID = "initiator_member_id", consentingMemberIDs = "consenting_member_ids"
        case selectedElsewhere = "selected_elsewhere", evaluatedAt = "evaluated_at"
        case successorMatchID = "successor_match_id", successorAvailable = "successor_available"
    }
}
struct LiveJoinCommand: Codable, Equatable, Sendable {
    let requestID: UUID
    let code: String
    let expectedMatchID: UUID?
    let clientBuild: Int
    enum CodingKeys: String, CodingKey { case requestID, code, expectedMatchID, clientBuild }
    init(requestID: UUID, code: String, expectedMatchID: UUID?, clientBuild: Int) {
        self.requestID = requestID; self.code = code; self.expectedMatchID = expectedMatchID; self.clientBuild = clientBuild
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.expectedMatchID) else { throw LiveMatchRecoveryError.invalidData }
        requestID = try c.decode(UUID.self, forKey: .requestID)
        code = try c.decode(String.self, forKey: .code)
        expectedMatchID = try c.decodeIfPresent(UUID.self, forKey: .expectedMatchID)
        clientBuild = try c.decode(Int.self, forKey: .clientBuild)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestID, forKey: .requestID); try c.encode(code, forKey: .code)
        try c.encode(expectedMatchID, forKey: .expectedMatchID); try c.encode(clientBuild, forKey: .clientBuild)
    }
}
struct LiveRematchCommand: Codable, Equatable, Sendable {
    let requestID: UUID
    let predecessorMatchID: UUID
    let generation: Int
    let action: LiveRematchAction
    let expectedParticipationEpoch: Int64
    let clientBuild: Int
}
struct LiveRematchReceipt: Decodable, Equatable, Sendable {
    let predecessorMatchID: UUID
    let generation: Int
    let state: LiveRematchState
    let successorMatchID: UUID?
    enum CodingKeys: String, CodingKey {
        case generation, state, predecessorMatchID = "predecessor_match_id", successorMatchID = "successor_match_id"
    }
}

extension LiveRematch {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.reason), c.contains(.nextGeneration), c.contains(.initiatorMemberID),
              c.contains(.successorMatchID) else { throw LiveMatchServiceError.invalidResponse }
        revision = try c.decode(Int64.self, forKey: .revision)
        isEligible = try c.decode(Bool.self, forKey: .isEligible)
        state = try c.decode(LiveRematchState.self, forKey: .state)
        reason = try c.decodeIfPresent(LiveRematchReason.self, forKey: .reason)
        generation = try c.decode(Int.self, forKey: .generation)
        nextGeneration = try c.decodeIfPresent(Int.self, forKey: .nextGeneration)
        initiatorMemberID = try c.decodeIfPresent(UUID.self, forKey: .initiatorMemberID)
        consentingMemberIDs = try c.decode([UUID].self, forKey: .consentingMemberIDs)
        selectedElsewhere = try c.decode(Bool.self, forKey: .selectedElsewhere)
        deadline = try c.decode(Date.self, forKey: .deadline)
        evaluatedAt = try c.decode(Date.self, forKey: .evaluatedAt)
        successorMatchID = try c.decodeIfPresent(UUID.self, forKey: .successorMatchID)
        successorAvailable = try c.decode(Bool.self, forKey: .successorAvailable)
    }
}
extension LiveRematchReceipt {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.successorMatchID) else { throw LiveMatchServiceError.invalidResponse }
        predecessorMatchID = try c.decode(UUID.self, forKey: .predecessorMatchID)
        generation = try c.decode(Int.self, forKey: .generation)
        state = try c.decode(LiveRematchState.self, forKey: .state)
        successorMatchID = try c.decodeIfPresent(UUID.self, forKey: .successorMatchID)
    }
}
