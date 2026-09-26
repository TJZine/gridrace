import Foundation

struct LiveRecoveryState: Codable, Equatable, Sendable {
    var formatVersion = 1
    var matchID: UUID?
    var pendingIntent: LivePendingIntent?
}

enum LivePendingIntent: Codable, Equatable, Sendable {
    case create(requestID: UUID)
    case guess(matchID: UUID, requestID: UUID, word: String)

    private enum CodingKeys: String, CodingKey { case kind, matchID, requestID, word }
    private enum Kind: String, Codable { case create, guess }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .create:
            self = .create(requestID: try values.decode(UUID.self, forKey: .requestID))
        case .guess:
            self = .guess(
                matchID: try values.decode(UUID.self, forKey: .matchID),
                requestID: try values.decode(UUID.self, forKey: .requestID),
                word: try values.decode(String.self, forKey: .word)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .create(let requestID):
            try values.encode(Kind.create, forKey: .kind)
            try values.encode(requestID.uuidString.lowercased(), forKey: .requestID)
        case .guess(let matchID, let requestID, let word):
            try values.encode(Kind.guess, forKey: .kind)
            try values.encode(matchID.uuidString.lowercased(), forKey: .matchID)
            try values.encode(requestID.uuidString.lowercased(), forKey: .requestID)
            try values.encode(word, forKey: .word)
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
            guard state.formatVersion == 1,
                  Self.isConsistent(state)
            else { throw LiveMatchRecoveryError.invalidData }
            return state
        } catch is DecodingError {
            throw LiveMatchRecoveryError.invalidData
        }
    }

    func save(_ state: LiveRecoveryState) throws {
        guard state.formatVersion == 1, Self.isConsistent(state) else {
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
        case .create:
            state.matchID == nil
        case .guess(let matchID, _, let word):
            state.matchID == matchID && !word.isEmpty && word.utf8.count <= 64
        }
    }
}

enum LiveMatchRecoveryError: Error, Equatable, Sendable {
    case invalidData
    case unavailable
}
