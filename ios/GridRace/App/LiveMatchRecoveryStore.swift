import Foundation

struct LiveRecoveryState: Codable, Equatable, Sendable {
    var formatVersion = 3
    var matchID: UUID?
    var pendingIntent: LivePendingIntent?
    var completedInvitationGeneration: UUID?
    var successorFollowAllowed = true

    private enum CodingKeys: String, CodingKey { case formatVersion, matchID, pendingIntent, successorFollowAllowed, completedInvitationGeneration }

    init(formatVersion: Int = 3, matchID: UUID? = nil, pendingIntent: LivePendingIntent? = nil, successorFollowAllowed: Bool = true, completedInvitationGeneration: UUID? = nil) {
        self.formatVersion = formatVersion
        self.matchID = matchID
        self.pendingIntent = pendingIntent
        self.completedInvitationGeneration = completedInvitationGeneration
        self.successorFollowAllowed = successorFollowAllowed
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == 3 else {
            throw LiveMatchRecoveryError.invalidData
        }
        successorFollowAllowed = try values.decodeIfPresent(Bool.self, forKey: .successorFollowAllowed) ?? true
        completedInvitationGeneration = try values.decodeIfPresent(UUID.self, forKey: .completedInvitationGeneration)
        matchID = try values.decodeIfPresent(UUID.self, forKey: .matchID)
        pendingIntent = try values.decodeIfPresent(LivePendingIntent.self, forKey: .pendingIntent)
    }

}

enum LivePendingIntent: Codable, Equatable, Sendable {
    case create(requestID: UUID, roundCount: Int = 3, clientBuild: Int = 3)
    case join(command: LiveJoinCommand, sourceMatchID: UUID?, navigationGeneration: UUID, invitationGeneration: UUID?)
    case rematch(command: LiveRematchCommand, sourceMatchID: UUID, navigationGeneration: UUID)
    case guess(matchID: UUID, requestID: UUID, word: String, roundNumber: Int = 1, clientBuild: Int = 3)

    private enum CodingKeys: String, CodingKey {
        case kind, matchID, requestID, word, roundCount, roundNumber, clientBuild
        case command, sourceMatchID, navigationGeneration, invitationGeneration
    }
    private enum Kind: String, Codable { case create, guess, join, rematch }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(Kind.self, forKey: .kind)
        if kind == .join || kind == .rematch {
            guard !values.contains(.clientBuild), !values.contains(.requestID), !values.contains(.matchID),
                  !values.contains(.word), !values.contains(.roundNumber), !values.contains(.roundCount) else {
                throw LiveMatchRecoveryError.invalidData
            }
            let navigation = try values.decode(UUID.self, forKey: .navigationGeneration)
            if kind == .join {
                guard values.contains(.sourceMatchID), values.contains(.invitationGeneration) else {
                    throw LiveMatchRecoveryError.invalidData
                }
                self = .join(command: try values.decode(LiveJoinCommand.self, forKey: .command),
                             sourceMatchID: try values.decodeIfPresent(UUID.self, forKey: .sourceMatchID),
                             navigationGeneration: navigation,
                             invitationGeneration: try values.decodeIfPresent(UUID.self, forKey: .invitationGeneration))
            } else {
                guard !values.contains(.invitationGeneration) else { throw LiveMatchRecoveryError.invalidData }
                self = .rematch(command: try values.decode(LiveRematchCommand.self, forKey: .command),
                                sourceMatchID: try values.decode(UUID.self, forKey: .sourceMatchID),
                                navigationGeneration: navigation)
            }
            return
        }
        guard !values.contains(.command), !values.contains(.sourceMatchID),
              !values.contains(.navigationGeneration), !values.contains(.invitationGeneration) else {
            throw LiveMatchRecoveryError.invalidData
        }
        let build = try values.decode(Int.self, forKey: .clientBuild)
        let requestID = try values.decode(UUID.self, forKey: .requestID)
        switch kind {
        case .join, .rematch: throw LiveMatchRecoveryError.invalidData
        case .create:
            guard !values.contains(.matchID), !values.contains(.word), !values.contains(.roundNumber) else {
                throw LiveMatchRecoveryError.invalidData
            }
            self = .create(requestID: requestID,
                           roundCount: try values.decode(Int.self, forKey: .roundCount), clientBuild: build)
        case .guess:
            guard !values.contains(.roundCount) else { throw LiveMatchRecoveryError.invalidData }
            self = .guess(matchID: try values.decode(UUID.self, forKey: .matchID), requestID: requestID,
                          word: try values.decode(String.self, forKey: .word),
                          roundNumber: try values.decode(Int.self, forKey: .roundNumber), clientBuild: build)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .join(let command, let source, let navigation, let invitation):
            try values.encode(Kind.join, forKey: .kind)
            try values.encode(command, forKey: .command)
            try values.encode(source, forKey: .sourceMatchID)
            try values.encode(navigation, forKey: .navigationGeneration)
            try values.encode(invitation, forKey: .invitationGeneration)
        case .rematch(let command, let source, let navigation):
            try values.encode(Kind.rematch, forKey: .kind)
            try values.encode(command, forKey: .command)
            try values.encode(source, forKey: .sourceMatchID)
            try values.encode(navigation, forKey: .navigationGeneration)
        case .create(let requestID, let count, let build):
            try values.encode(Kind.create, forKey: .kind)
            try values.encode(requestID.uuidString.lowercased(), forKey: .requestID)
            try values.encode(count, forKey: .roundCount)
            try values.encode(build, forKey: .clientBuild)
        case .guess(let matchID, let requestID, let word, let round, let build):
            try values.encode(Kind.guess, forKey: .kind)
            try values.encode(matchID.uuidString.lowercased(), forKey: .matchID)
            try values.encode(requestID.uuidString.lowercased(), forKey: .requestID)
            try values.encode(word, forKey: .word)
            try values.encode(round, forKey: .roundNumber)
            try values.encode(build, forKey: .clientBuild)
        }
    }
}

protocol LiveMatchRecoveryStoring: Sendable {
    func load() throws -> LiveRecoveryState
    func save(_ state: LiveRecoveryState) throws
    func clear() throws
}

struct LiveMatchRecoveryStore: LiveMatchRecoveryStoring, Sendable {
    let directory: URL
    private var fileURL: URL { directory.appending(path: "live-recovery-v1.json") }

    init(rootDirectory: URL, userID: UUID) {
        directory = rootDirectory
            .appending(path: "Accounts", directoryHint: .isDirectory)
            .appending(path: userID.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    static func applicationSupport(userID: UUID) throws -> LiveMatchRecoveryStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return LiveMatchRecoveryStore(
            rootDirectory: base.appending(path: "GridRace", directoryHint: .isDirectory),
            userID: userID
        )
    }

    func load() throws -> LiveRecoveryState {
        guard let data = try PersistenceFile.readIfPresent(at: fileURL) else {
            return LiveRecoveryState()
        }
        do {
            let state = try JSONDecoder().decode(
                LiveRecoveryState.self,
                from: data
            )
            guard Self.isConsistent(state)
            else { throw LiveMatchRecoveryError.invalidData }
            return state
        } catch is DecodingError {
            throw LiveMatchRecoveryError.invalidData
        }
    }

    func save(_ state: LiveRecoveryState) throws {
        guard Self.isConsistent(state) else {
            throw LiveMatchRecoveryError.invalidData
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        try PersistenceFile.removeIfPresent(at: fileURL)
    }

    private static func isConsistent(_ state: LiveRecoveryState) -> Bool {
        guard state.formatVersion == 3 else { return false }
        return switch state.pendingIntent {
        case .none:
            true
        case .join(let command, let source, _, let invitation):
            (invitation == nil || state.completedInvitationGeneration == nil
                || invitation == state.completedInvitationGeneration)
                && state.matchID == source && command.clientBuild >= 3
                && validCode(command.code)
        case .rematch(let command, let source, _):
            state.matchID == source && source == command.predecessorMatchID
                && command.clientBuild >= 3 && (1...Int(Int32.max)).contains(command.generation)
                && (0...9_007_199_254_740_991).contains(command.expectedParticipationEpoch)
        case .create(_, let count, let build):
            state.matchID == nil && [1, 3, 5].contains(count)
                && build >= 3
        case .guess(let matchID, _, let word, let round, let build):
            state.matchID == matchID && build >= 3 && !word.isEmpty && word.utf8.count <= 64
                && (1...5).contains(round)
        }
    }
    private static func validCode(_ code: String) -> Bool {
        code.utf8.count == 6 && code.uppercased().utf8.allSatisfy {
            (65...72).contains($0) || (74...78).contains($0) || (80...90).contains($0) || (50...57).contains($0)
        }
    }
}

enum LiveMatchRecoveryError: Error, Equatable, Sendable {
    case invalidData
    case unavailable
}
