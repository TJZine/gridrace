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
        guard let data = try PersistenceFile.readIfPresent(at: fileURL) else {
            return LiveRecoveryState()
        }
        do {
            let state = try JSONDecoder().decode(
                LiveRecoveryState.self,
                from: data
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
#if DEBUG
        LiveRecoveryDiagnostics.record(.clearBefore, directory: directory)
#endif
        try PersistenceFile.removeIfPresent(at: fileURL)
#if DEBUG
        LiveRecoveryDiagnostics.record(.clearAfter, directory: directory)
#endif
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

#if DEBUG
// Temporary, opt-in observations for the independent-client recovery diagnosis.
// Never print identifiers, paths, credentials, guesses, or serialized recovery data.
enum LiveRecoveryDiagnostics {
    enum Stage: String {
        case postSignIn, postChangeAccount, postInjection
        case coordinatorTransition, accountTransitionClear, capturedCleanup
        case hostRestoreSettled, hostRestoreFailed
        case clearBefore, clearAfter
    }

    static func record(_ stage: Stage, userID: UUID?, hostOwner: Bool = false,
                       phase: LiveMatchSessionPhase? = nil, expectedMatchID: UUID? = nil) {
        guard let owned = ownedUser else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "GridRace/Accounts", directoryHint: .isDirectory)
            .appending(path: owned.uuidString.lowercased(), directoryHint: .isDirectory)
        emit(stage, directory: directory, subjectMatches: userID == owned,
             subjectPresent: userID != nil, hostOwner: hostOwner, phase: phase, expectedMatchID: expectedMatchID)
    }

    static func record(_ stage: Stage, directory: URL) {
        guard let owned = ownedUser else { return }
        guard UUID(uuidString: directory.lastPathComponent) == owned else { return }
        emit(stage, directory: directory,
             subjectMatches: true,
             subjectPresent: true, hostOwner: false, phase: nil)
    }

    private static var ownedUser: UUID? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GRIDRACE_LIVE_RECOVERY_DIAGNOSTICS"] == "1" else { return nil }
        return environment["GRIDRACE_LIVE_DIAGNOSTIC_USER_ID"].flatMap(UUID.init(uuidString:))
    }

    private static func emit(_ stage: Stage, directory: URL?, subjectMatches: Bool,
                             subjectPresent: Bool, hostOwner: Bool,
                             phase: LiveMatchSessionPhase?, expectedMatchID: UUID? = nil) {
        let file = directory?.appending(path: "live-recovery-v1.json")
        let exists = file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        var read = false
        var decoded = false
        var expectedMatch = false
        var pending = false
        if let file, let data = try? Data(contentsOf: file) {
            read = true
            if let state = try? JSONDecoder().decode(LiveRecoveryState.self, from: data) {
                decoded = true
                let expected = expectedMatchID ?? ProcessInfo.processInfo.environment["GRIDRACE_LIVE_MATCH_ID"]
                    .flatMap(UUID.init(uuidString:))
                expectedMatch = expected != nil && state.matchID == expected
                pending = state.pendingIntent != nil
            }
        }
        let phaseCode: String
        switch phase {
        case .inactive: phaseCode = "inactive"
        case .recovering: phaseCode = "recovering"
        case .ready: phaseCode = "ready"
        case .unavailable: phaseCode = "unavailable"
        case .needsSignIn: phaseCode = "needs_sign_in"
        case .storageUnavailable: phaseCode = "storage_unavailable"
        case nil: phaseCode = "unobserved"
        }
        print("RECOVERY_DIAGNOSTIC stage=\(stage.rawValue) subject_present=\(subjectPresent) subject_owned=\(subjectMatches) host_owner_observed=\(hostOwner) file_exists=\(exists) read_ok=\(read) decode_ok=\(decoded) expected_match=\(expectedMatch) pending=\(pending) phase=\(phaseCode)")
    }
}
#endif
