import Foundation

struct LiveRecoveryState: Codable, Equatable, Sendable {
    var formatVersion = 2
    var matchID: UUID?
    var pendingIntent: LivePendingIntent?

    private enum CodingKeys: String, CodingKey { case formatVersion, matchID, pendingIntent }

    init(formatVersion: Int = 2, matchID: UUID? = nil, pendingIntent: LivePendingIntent? = nil) {
        self.formatVersion = formatVersion
        self.matchID = matchID
        self.pendingIntent = pendingIntent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == 1 || formatVersion == 2 else {
            throw LiveMatchRecoveryError.invalidData
        }
        matchID = try values.decodeIfPresent(UUID.self, forKey: .matchID)
        if formatVersion == 1 {
            pendingIntent = try values.decodeIfPresent(LegacyIntent.self, forKey: .pendingIntent)?.migrated
        } else {
            pendingIntent = try values.decodeIfPresent(LivePendingIntent.self, forKey: .pendingIntent)
        }
    }

    // Kept separate so missing v2 payload fields can never silently become a legacy intent.
    private struct LegacyIntent: Decodable {
        let kind: String
        let matchID: UUID?
        let requestID: UUID
        let word: String?
        private enum CodingKeys: String, CodingKey {
            case kind, matchID, requestID, word, roundCount, roundNumber, clientBuild
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard !values.contains(.roundCount), !values.contains(.roundNumber),
                  !values.contains(.clientBuild) else { throw LiveMatchRecoveryError.invalidData }
            kind = try values.decode(String.self, forKey: .kind)
            matchID = try values.decodeIfPresent(UUID.self, forKey: .matchID)
            requestID = try values.decode(UUID.self, forKey: .requestID)
            word = try values.decodeIfPresent(String.self, forKey: .word)
        }

        var migrated: LivePendingIntent {
            get throws {
                switch kind {
                case "create" where matchID == nil && word == nil:
                    return .create(requestID: requestID, roundCount: 1, clientBuild: 1)
                case "guess":
                    guard let matchID, let word else { throw LiveMatchRecoveryError.invalidData }
                    return .guess(matchID: matchID, requestID: requestID, word: word,
                                  roundNumber: 1, clientBuild: 1)
                default: throw LiveMatchRecoveryError.invalidData
                }
            }
        }
    }
}

enum LivePendingIntent: Codable, Equatable, Sendable {
    case create(requestID: UUID, roundCount: Int = 3, clientBuild: Int = 2)
    case guess(matchID: UUID, requestID: UUID, word: String, roundNumber: Int = 1, clientBuild: Int = 2)

    private enum CodingKeys: String, CodingKey {
        case kind, matchID, requestID, word, roundCount, roundNumber, clientBuild
    }
    private enum Kind: String, Codable { case create, guess }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let build = try values.decode(Int.self, forKey: .clientBuild)
        let requestID = try values.decode(UUID.self, forKey: .requestID)
        switch try values.decode(Kind.self, forKey: .kind) {
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LiveRecoveryState()
        }
        do {
            let state = try JSONDecoder().decode(
                LiveRecoveryState.self,
                from: Data(contentsOf: fileURL)
            )
            guard (state.formatVersion == 1 || state.formatVersion == 2),
                  Self.isConsistent(state)
            else { throw LiveMatchRecoveryError.invalidData }
            return state
        } catch is DecodingError {
            throw LiveMatchRecoveryError.invalidData
        }
    }

    func save(_ state: LiveRecoveryState) throws {
        guard state.formatVersion == 2, Self.isConsistent(state) else {
            throw LiveMatchRecoveryError.invalidData
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func isConsistent(_ state: LiveRecoveryState) -> Bool {
        switch state.pendingIntent {
        case .none:
            true
        case .create(_, let count, let build):
            state.matchID == nil && [1, 3, 5].contains(count)
                && (build == 2 || (build == 1 && count == 1))
        case .guess(let matchID, _, let word, let round, let build):
            state.matchID == matchID && !word.isEmpty && word.utf8.count <= 64
                && (1...5).contains(round) && (build == 2 || (build == 1 && round == 1))
        }
    }
}

enum LiveMatchRecoveryError: Error, Equatable, Sendable {
    case invalidData
    case unavailable
}
