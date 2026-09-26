import Foundation

enum LiveMatchStatus: String, Sendable {
    case lobby
    case inProgress = "in_progress"
    case completed
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

struct LiveMatch: Equatable, Sendable {
    let id: UUID
    let joinCode: String
    let creatorMemberID: UUID
    let status: LiveMatchStatus
    let expiresAt: Date
    let minimumClientBuild: Int
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
}

struct LiveMatchSnapshot: Equatable, Sendable {
    let serverTime: Date
    let match: LiveMatch
    let members: [LiveMatchMember]
    let round: LiveRound
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
    case internalError = "internal_error"
}

enum LiveMatchServiceError: Error, Equatable, Sendable {
    case server(LiveMatchServerError)
    case invalidResponse
    case unavailable
}

protocol LiveMatchServicing: Sendable {
    func createMatch(requestID: UUID) async throws -> UUID
    func joinMatch(code: String) async throws -> UUID
    func startMatch(id: UUID) async throws -> UUID
    func submitGuess(matchID: UUID, requestID: UUID, guess: String) async throws -> LiveGuessReceipt
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot
}
