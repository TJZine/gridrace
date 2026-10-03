import Foundation

extension DailyClassicProgress {
    init(
        puzzleID: String,
        puzzleNumber: Int,
        puzzleDay: Int,
        wordPackID: String,
        scheduleVersion: Int,
        hardModeEnabled: Bool,
        acceptedGuesses: [DailyGuess],
        draft: String,
        completion: DailyCompletion?
    ) {
        formatVersion = 1
        self.puzzleID = puzzleID
        self.puzzleNumber = puzzleNumber
        self.puzzleDay = puzzleDay
        self.wordPackID = wordPackID
        self.scheduleVersion = scheduleVersion
        self.hardModeEnabled = hardModeEnabled
        self.acceptedGuesses = acceptedGuesses
        self.draft = draft
        self.completion = completion
    }
}

struct DailyGuessDTO: Codable, Equatable, Sendable {
    let word: String
    let feedback: [Feedback]
    let acceptedAt: Date

    private enum CodingKeys: String, CodingKey {
        case word, feedback
        case acceptedAt = "accepted_at"
    }

    init(_ guess: DailyGuess) {
        word = guess.word
        feedback = guess.feedback
        acceptedAt = guess.acceptedAt.dailyWireDate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        word = try values.decode(String.self, forKey: .word)
        feedback = try values.decode([Feedback].self, forKey: .feedback)
        acceptedAt = try values.decode(Date.self, forKey: .acceptedAt)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(word, forKey: .word)
        try values.encode(feedback, forKey: .feedback)
        try values.encode(acceptedAt.dailyWireTimestamp, forKey: .acceptedAt)
    }

    var domain: DailyGuess {
        DailyGuess(word: word, feedback: feedback, acceptedAt: acceptedAt)
    }
}

struct DailyProgressDTO: Codable, Equatable, Sendable {
    let userID: UUID
    let puzzleID: String
    let puzzleNumber: Int
    let puzzleDay: Int
    let wordPackID: String
    let scheduleVersion: Int
    let hardModeEnabled: Bool
    let guesses: [DailyGuessDTO]
    let revision: Int
    let serverUpdatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case guesses, revision
        case userID = "user_id"
        case puzzleID = "puzzle_id"
        case puzzleNumber = "puzzle_number"
        case puzzleDay = "puzzle_day"
        case wordPackID = "word_pack_id"
        case scheduleVersion = "schedule_version"
        case hardModeEnabled = "hard_mode_enabled"
        case serverUpdatedAt = "server_updated_at"
    }

    var domain: DailyClassicProgress {
        DailyClassicProgress(
            puzzleID: puzzleID,
            puzzleNumber: puzzleNumber,
            puzzleDay: puzzleDay,
            wordPackID: wordPackID,
            scheduleVersion: scheduleVersion,
            hardModeEnabled: hardModeEnabled,
            acceptedGuesses: guesses.map(\.domain),
            draft: "",
            completion: nil
        )
    }
}

struct DailyProgressUploadDTO: Codable, Equatable, Sendable {
    let puzzleID: String
    let puzzleNumber: Int
    let puzzleDay: Int
    let wordPackID: String
    let scheduleVersion: Int
    let hardModeEnabled: Bool
    let guesses: [DailyGuessDTO]
    let expectedRevision: Int?

    private enum CodingKeys: String, CodingKey {
        case guesses
        case puzzleID = "puzzle_id"
        case puzzleNumber = "puzzle_number"
        case puzzleDay = "puzzle_day"
        case wordPackID = "word_pack_id"
        case scheduleVersion = "schedule_version"
        case hardModeEnabled = "hard_mode_enabled"
        case expectedRevision = "expected_revision"
    }

    init(progress: DailyClassicProgress, expectedRevision: Int?) {
        puzzleID = progress.puzzleID
        puzzleNumber = progress.puzzleNumber
        puzzleDay = progress.puzzleDay
        wordPackID = progress.wordPackID
        scheduleVersion = progress.scheduleVersion
        hardModeEnabled = progress.hardModeEnabled
        guesses = progress.acceptedGuesses.map(DailyGuessDTO.init)
        self.expectedRevision = expectedRevision
    }
}

struct DailyImportedResultDTO: Codable, Equatable, Sendable {
    let userID: UUID
    let puzzleID: String
    let puzzleNumber: Int
    let puzzleDay: Int
    let wordPackID: String
    let scheduleVersion: Int
    let hardModeEnabled: Bool
    let guesses: [DailyGuessDTO]
    let outcome: DailyOutcome
    let guessCount: Int
    let clientCompletedAt: Date
    let serverImportedAt: Date

    private enum CodingKeys: String, CodingKey {
        case guesses, outcome
        case userID = "user_id"
        case puzzleID = "puzzle_id"
        case puzzleNumber = "puzzle_number"
        case puzzleDay = "puzzle_day"
        case wordPackID = "word_pack_id"
        case scheduleVersion = "schedule_version"
        case hardModeEnabled = "hard_mode_enabled"
        case guessCount = "guess_count"
        case clientCompletedAt = "client_completed_at"
        case serverImportedAt = "server_imported_at"
    }

    var domain: DailyCompletedResult {
        DailyCompletedResult(
            puzzleID: puzzleID,
            puzzleNumber: puzzleNumber,
            puzzleDay: puzzleDay,
            wordPackID: wordPackID,
            scheduleVersion: scheduleVersion,
            hardModeEnabled: hardModeEnabled,
            guesses: guesses.map(\.domain),
            outcome: outcome,
            guessCount: guessCount,
            completedAt: clientCompletedAt
        )
    }
}

struct DailyImportedResultUploadDTO: Codable, Equatable, Sendable {
    let puzzleID: String
    let puzzleNumber: Int
    let puzzleDay: Int
    let wordPackID: String
    let scheduleVersion: Int
    let hardModeEnabled: Bool
    let guesses: [DailyGuessDTO]
    let outcome: DailyOutcome
    let guessCount: Int
    let clientCompletedAt: Date

    private enum CodingKeys: String, CodingKey {
        case guesses, outcome
        case puzzleID = "puzzle_id"
        case puzzleNumber = "puzzle_number"
        case puzzleDay = "puzzle_day"
        case wordPackID = "word_pack_id"
        case scheduleVersion = "schedule_version"
        case hardModeEnabled = "hard_mode_enabled"
        case guessCount = "guess_count"
        case clientCompletedAt = "client_completed_at"
    }

    init(_ result: DailyCompletedResult) {
        puzzleID = result.puzzleID
        puzzleNumber = result.puzzleNumber
        puzzleDay = result.puzzleDay
        wordPackID = result.wordPackID
        scheduleVersion = result.scheduleVersion
        hardModeEnabled = result.hardModeEnabled
        guesses = result.guesses.map(DailyGuessDTO.init)
        outcome = result.outcome
        guessCount = result.guessCount
        clientCompletedAt = result.completedAt.dailyWireDate
    }
}

struct DailyCloudSnapshot: Equatable, Sendable {
    let progress: DailyProgressDTO?
    let importedResults: [DailyImportedResultDTO]
}

enum DailySyncConflict: Error, Equatable, Sendable {
    case progress(puzzleID: String, local: DailyClassicProgress, cloud: DailyClassicProgress)
    case completedResult(
        puzzleID: String,
        local: DailyCompletedResult,
        cloud: DailyCompletedResult
    )
}

enum DailyProgressConflictResolution: Equatable, Sendable {
    case useCloud
    case keepDevice
}

enum DailySyncFailure: Equatable, Sendable {
    case unavailable
    case rejected
    case invalidData
}

enum DailySyncStatus: Equatable, Sendable {
    case idle
    case pending
    case synced(Date)
    case conflict([DailySyncConflict])
    case failed(DailySyncFailure)
}

enum DailySyncError: Error, Equatable, Sendable {
    case invalidLocalData
    case invalidCloudData
}

enum DailySyncRemoteError: Error, Equatable, Sendable {
    case unavailable
    case rejected
    case invalidData
}

struct DailyReconciliation: Equatable, Sendable {
    let progress: DailyClassicProgress?
    let history: DailyClassicHistory
    let conflicts: [DailySyncConflict]
}

enum DailySyncReconciler {
    static func reconcile(
        localProgress: DailyClassicProgress?,
        localHistory: DailyClassicHistory,
        cloud: DailyCloudSnapshot
    ) throws -> DailyReconciliation {
        try reconcile(
            localProgress: localProgress,
            localHistory: localHistory,
            incomingProgress: cloud.progress?.domain,
            incomingResults: cloud.importedResults.map(\.domain)
        )
    }

    static func reconcile(
        localProgress: DailyClassicProgress?,
        localHistory: DailyClassicHistory,
        incomingProgress: DailyClassicProgress?,
        incomingResults: [DailyCompletedResult],
        allowIncomingDraft: Bool = false
    ) throws -> DailyReconciliation {
        var history = localHistory
        var conflicts: [DailySyncConflict] = []

        for incomingResult in incomingResults.sorted(by: resultOrder) {
            guard isValid(incomingResult) else { throw DailySyncError.invalidCloudData }
            if let localResult = history.result(for: incomingResult.puzzleID) {
                if !sameImportedPayload(localResult, incomingResult) {
                    conflicts.append(.completedResult(
                        puzzleID: incomingResult.puzzleID,
                        local: localResult,
                        cloud: incomingResult
                    ))
                }
            } else if !history.record(incomingResult) {
                throw DailySyncError.invalidCloudData
            }
        }

        if let incomingProgress,
           !(allowIncomingDraft
                ? isValidLocalProgress(incomingProgress)
                : isValidActiveProgress(incomingProgress)) {
            throw DailySyncError.invalidCloudData
        }

        var progress = mergeProgress(
            local: localProgress,
            cloud: incomingProgress,
            conflicts: &conflicts
        )

        if let active = progress,
           let completed = history.result(for: active.puzzleID) {
            if sameIdentity(active, completed) {
                progress = DailyClassicProgress(result: completed)
            } else if !activeRepresents(active, result: completed) {
                conflicts.append(.progress(
                    puzzleID: active.puzzleID,
                    local: active,
                    cloud: DailyClassicProgress(result: completed)
                ))
            }
        }

        return DailyReconciliation(progress: progress, history: history, conflicts: conflicts)
    }

    private static func mergeProgress(
        local: DailyClassicProgress?,
        cloud: DailyClassicProgress?,
        conflicts: inout [DailySyncConflict]
    ) -> DailyClassicProgress? {
        guard let local else { return cloud }
        guard let cloud else { return local }
        guard sameIdentity(local, cloud) else {
            // There is one active-progress slot. UTC puzzle day deterministically wins.
            return local.puzzleDay >= cloud.puzzleDay ? local : cloud
        }
        if local.completion != nil, cloud.completion == nil { return local }
        if cloud.completion != nil, local.completion == nil { return cloud }
        if local.hardModeEnabled != cloud.hardModeEnabled {
            if local.acceptedGuesses.isEmpty != cloud.acceptedGuesses.isEmpty {
                var selected = local.acceptedGuesses.isEmpty ? cloud : local
                selected.draft = local.draft
                return selected
            }
            if !local.acceptedGuesses.isEmpty {
                conflicts.append(.progress(puzzleID: local.puzzleID, local: local, cloud: cloud))
            }
            return local
        }

        if isPrefix(local.acceptedGuesses, of: cloud.acceptedGuesses) {
            var selected = cloud
            selected.draft = local.draft
            return selected
        }
        if isPrefix(cloud.acceptedGuesses, of: local.acceptedGuesses) {
            return local
        }

        conflicts.append(.progress(puzzleID: local.puzzleID, local: local, cloud: cloud))
        return local
    }

    private static func resultOrder(_ lhs: DailyCompletedResult, _ rhs: DailyCompletedResult) -> Bool {
        if lhs.puzzleDay != rhs.puzzleDay { return lhs.puzzleDay < rhs.puzzleDay }
        return lhs.puzzleID < rhs.puzzleID
    }

    /// Immutable puzzle identity. Hard Mode is attempt configuration and is excluded.
    static func sameIdentity(_ lhs: DailyClassicProgress, _ rhs: DailyClassicProgress) -> Bool {
        lhs.puzzleID == rhs.puzzleID
            && lhs.puzzleNumber == rhs.puzzleNumber
            && lhs.puzzleDay == rhs.puzzleDay
            && lhs.wordPackID == rhs.wordPackID
            && lhs.scheduleVersion == rhs.scheduleVersion
    }

    /// Immutable puzzle identity. Hard Mode is attempt configuration and is excluded.
    static func sameIdentity(
        _ progress: DailyClassicProgress,
        _ result: DailyCompletedResult
    ) -> Bool {
        progress.puzzleID == result.puzzleID
            && progress.puzzleNumber == result.puzzleNumber
            && progress.puzzleDay == result.puzzleDay
            && progress.wordPackID == result.wordPackID
            && progress.scheduleVersion == result.scheduleVersion
    }

    static func samePuzzle(_ lhs: DailyClassicProgress, _ rhs: DailyClassicProgress) -> Bool {
        sameIdentity(lhs, rhs) && lhs.hardModeEnabled == rhs.hardModeEnabled
    }

    static func samePuzzle(_ progress: DailyClassicProgress, _ result: DailyCompletedResult) -> Bool {
        sameIdentity(progress, result) && progress.hardModeEnabled == result.hardModeEnabled
    }

    static func isPrefix(_ shorter: [DailyGuess], of longer: [DailyGuess]) -> Bool {
        shorter.count <= longer.count
            && shorter.map(DailyGuessDTO.init)
                == Array(longer.prefix(shorter.count)).map(DailyGuessDTO.init)
    }

    static func activeRepresents(
        _ progress: DailyClassicProgress,
        result: DailyCompletedResult
    ) -> Bool {
        guard let completion = progress.completion else { return false }
        return samePuzzle(progress, result)
            && progress.draft.isEmpty
            && progress.acceptedGuesses.map(DailyGuessDTO.init) == result.guesses.map(DailyGuessDTO.init)
            && completion.outcome == result.outcome
            && completion.guessCount == result.guessCount
            && completion.completedAt.dailyWireDate == result.completedAt.dailyWireDate
    }

    static func sameImportedPayload(
        _ lhs: DailyCompletedResult,
        _ rhs: DailyCompletedResult
    ) -> Bool {
        DailyImportedResultUploadDTO(lhs) == DailyImportedResultUploadDTO(rhs)
    }

    static func isValidActiveProgress(_ progress: DailyClassicProgress) -> Bool {
        isValidLocalProgress(progress) && progress.draft.isEmpty
    }

    static func isValidLocalProgress(_ progress: DailyClassicProgress) -> Bool {
        progress.formatVersion == 1
            && DailyPuzzleIdentity.isValid(
                puzzleID: progress.puzzleID,
                puzzleNumber: progress.puzzleNumber,
                puzzleDay: progress.puzzleDay,
                wordPackID: progress.wordPackID,
                scheduleVersion: progress.scheduleVersion
            )
            && progress.acceptedGuesses.count < 6
            && progress.draft.utf8.count <= 5
            && progress.draft.utf8.allSatisfy { (65...90).contains($0) }
            && progress.completion == nil
            && progress.acceptedGuesses.allSatisfy {
                $0.word.utf8.count == 5
                    && $0.word.utf8.allSatisfy { (97...122).contains($0) }
                    && $0.feedback.count == 5
                    && !$0.feedback.allSatisfy { $0 == .correct }
            }
            && zip(progress.acceptedGuesses, progress.acceptedGuesses.dropFirst())
                .allSatisfy { $0.acceptedAt <= $1.acceptedAt }
    }

    static func completedResult(from progress: DailyClassicProgress) -> DailyCompletedResult? {
        guard let completion = progress.completion else { return nil }
        let result = DailyCompletedResult(
            puzzleID: progress.puzzleID,
            puzzleNumber: progress.puzzleNumber,
            puzzleDay: progress.puzzleDay,
            wordPackID: progress.wordPackID,
            scheduleVersion: progress.scheduleVersion,
            hardModeEnabled: progress.hardModeEnabled,
            guesses: progress.acceptedGuesses,
            outcome: completion.outcome,
            guessCount: completion.guessCount,
            completedAt: completion.completedAt
        )
        return isValid(result) ? result : nil
    }

    static func isValid(_ result: DailyCompletedResult) -> Bool {
        var history = DailyClassicHistory()
        return history.record(result)
    }
}

enum DailyProgressPushOutcome: Equatable, Sendable {
    case stored(DailyProgressDTO)
    case serverAhead(DailyProgressDTO)
    case completed(DailyImportedResultDTO)
    case conflict(DailyProgressConflictState)
}

enum DailyProgressConflictState: Equatable, Sendable {
    case progress(DailyProgressDTO)
    case completed(DailyImportedResultDTO)
}

enum DailyResultImportOutcome: Equatable, Sendable {
    case stored(DailyImportedResultDTO)
    case conflict(DailyResultConflictState)
}

enum DailyResultConflictState: Equatable, Sendable {
    case result(DailyImportedResultDTO)
    case progress(DailyProgressDTO)
}

protocol DailySyncRemote: Sendable {
    func pull() async throws -> DailyCloudSnapshot
    func pushProgress(_ progress: DailyProgressUploadDTO) async throws -> DailyProgressPushOutcome
    func importResult(_ result: DailyImportedResultUploadDTO) async throws -> DailyResultImportOutcome
}

/// Synchronous invalidation token for an account sync lifecycle. The coordinator
/// invalidates the token before deleting the UUID-scoped cache so late
/// engine writes suspended in transport observe invalidity without any hang.
final class DailySyncLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var invalidatedFlag = false

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        invalidatedFlag = true
    }

    var isInvalidated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return invalidatedFlag
    }

    /// Runs a synchronous filesystem mutation while holding the lifecycle
    /// lock, making the validity check atomic with the write: `invalidate()`
    /// either completes fully before the mutation runs or the mutation throws
    /// `CancellationError` instead of running. The lock is never held across
    /// an await; callers check `Task` cancellation separately.
    func performThrowingIfValid(_ work: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !invalidatedFlag else { throw CancellationError() }
        try work()
    }
}

@MainActor
final class DailySyncEngine {
    private let userID: UUID
    private let store: AccountDailyClassicStore
    private let remote: any DailySyncRemote
    private let now: @Sendable () -> Date
    private let lifecycle: DailySyncLifecycle

    nonisolated init(
        userID: UUID,
        store: AccountDailyClassicStore,
        remote: any DailySyncRemote,
        now: @escaping @Sendable () -> Date = Date.init,
        lifecycle: DailySyncLifecycle = DailySyncLifecycle()
    ) {
        precondition(store.userID == userID)
        self.userID = userID
        self.store = store
        self.remote = remote
        self.now = now
        self.lifecycle = lifecycle
    }

    func markProgressPending() throws {
        try Task.checkCancellation()
        var metadata = try store.loadSyncMetadata()
        metadata.pendingProgress = true
        if let puzzleID = try store.loadProgress()?.puzzleID {
            metadata.ignoredProgress.remove(puzzleID)
        }
        try lifecycle.performThrowingIfValid { try store.save(metadata) }
    }

    func markResultPending(_ puzzleID: String) throws {
        try Task.checkCancellation()
        var metadata = try store.loadSyncMetadata()
        metadata.pendingResultPuzzleIDs.insert(puzzleID)
        try lifecycle.performThrowingIfValid { try store.save(metadata) }
    }

    func markAllLocalDataPending() throws {
        try Task.checkCancellation()
        var metadata = try store.loadSyncMetadata()
        if let progress = try store.loadProgress() {
            metadata.pendingProgress = progress.completion == nil
        } else {
            metadata.pendingProgress = false
        }
        metadata.pendingResultPuzzleIDs.formUnion(
            try store.loadHistory().completedResults.map(\.puzzleID)
        )
        metadata.ignoredProgress = []
        metadata.ignoredResults = []
        try lifecycle.performThrowingIfValid { try store.save(metadata) }
    }

    /// Copies guest data into the account cache without modifying the guest store.
    /// Call `synchronize()` after the player confirms the import.
    func stageGuestImport(from guestStore: any DailyClassicStoring) throws -> DailySyncStatus {
        try Task.checkCancellation()
        var guestHistory = try guestStore.loadHistory()
        var guestProgress = try guestStore.loadProgress()
        if let progress = guestProgress, progress.completion != nil {
            guard let terminal = DailySyncReconciler.completedResult(from: progress) else {
                throw DailySyncError.invalidLocalData
            }
            if let existing = guestHistory.result(for: terminal.puzzleID) {
                guard DailySyncReconciler.sameImportedPayload(existing, terminal) else {
                    throw DailySyncError.invalidLocalData
                }
            } else if !guestHistory.record(terminal) {
                throw DailySyncError.invalidLocalData
            }
            guestProgress = nil
        }
        let reconciliation = try DailySyncReconciler.reconcile(
            localProgress: store.loadProgress(),
            localHistory: store.loadHistory(),
            incomingProgress: guestProgress,
            incomingResults: guestHistory.completedResults,
            allowIncomingDraft: true
        )
        try save(reconciliation)

        var metadata = try store.loadSyncMetadata()
        if let progress = reconciliation.progress {
            metadata.pendingProgress = progress.completion == nil
        } else {
            metadata.pendingProgress = false
        }
        metadata.pendingResultPuzzleIDs.formUnion(
            reconciliation.history.completedResults.map(\.puzzleID)
        )
        try lifecycle.performThrowingIfValid { try store.save(metadata) }

        let importConflicts: [DailySyncConflict] = reconciliation.conflicts.map { conflict in
            switch conflict {
            case .progress(let puzzleID, let account, let guest):
                .progress(puzzleID: puzzleID, local: guest, cloud: account)
            case .completedResult(let puzzleID, let account, let guest):
                .completedResult(puzzleID: puzzleID, local: guest, cloud: account)
            }
        }
        return importConflicts.isEmpty
            ? .pending
            : .conflict(importConflicts)
    }

    func resolve(
        _ conflict: DailySyncConflict,
        with resolution: DailyProgressConflictResolution
    ) throws {
        try Task.checkCancellation()
        var metadata = try store.loadSyncMetadata()
        switch conflict {
        case .progress(let puzzleID, let local, let cloud):
            if let completed = DailySyncReconciler.completedResult(from: local),
               cloud.completion == nil {
                guard let current = try store.loadHistory().result(for: puzzleID),
                      DailySyncReconciler.sameImportedPayload(current, completed) else {
                    throw DailySyncError.invalidLocalData
                }
                try lifecycle.performThrowingIfValid { try store.save(local) }
                metadata.pendingProgress = false
                metadata.ignoredProgress.insert(puzzleID)
                metadata.ignoredResults.remove(puzzleID)
                metadata.pendingResultPuzzleIDs.insert(puzzleID)
            } else if let completed = DailySyncReconciler.completedResult(from: cloud),
                      local.completion == nil {
                var history = try store.loadHistory()
                if let current = history.result(for: puzzleID) {
                    guard DailySyncReconciler.sameImportedPayload(current, completed) else {
                        throw DailySyncError.invalidLocalData
                    }
                } else if !history.record(completed) {
                    throw DailySyncError.invalidCloudData
                }
                try lifecycle.performThrowingIfValid { try store.save(history) }
                try lifecycle.performThrowingIfValid { try store.save(cloud) }
                metadata.pendingProgress = false
                metadata.pendingResultPuzzleIDs.remove(puzzleID)
                metadata.ignoredProgress.remove(puzzleID)
                metadata.ignoredResults.remove(puzzleID)
            } else {
                switch resolution {
                case .useCloud:
                    try lifecycle.performThrowingIfValid { try store.save(cloud) }
                    metadata.pendingProgress = false
                    metadata.ignoredProgress.remove(puzzleID)
                    metadata.ignoredResults.remove(puzzleID)
                case .keepDevice:
                    try lifecycle.performThrowingIfValid { try store.save(local) }
                    metadata.pendingProgress = false
                    metadata.ignoredProgress.insert(puzzleID)
                }
            }
        case .completedResult(let puzzleID, let local, let cloud):
            let selected: DailyCompletedResult
            switch resolution {
            case .useCloud:
                var history = try store.loadHistory()
                guard history.replace(cloud) else { throw DailySyncError.invalidLocalData }
                try lifecycle.performThrowingIfValid { try store.save(history) }
                metadata.ignoredResults.remove(puzzleID)
                selected = cloud
            case .keepDevice:
                var history = try store.loadHistory()
                guard history.replace(local) else { throw DailySyncError.invalidLocalData }
                try lifecycle.performThrowingIfValid { try store.save(history) }
                metadata.ignoredResults.insert(puzzleID)
                selected = local
            }
            if try store.loadProgress()?.puzzleID == puzzleID {
                try lifecycle.performThrowingIfValid { try store.save(DailyClassicProgress(result: selected)) }
            }
            metadata.pendingResultPuzzleIDs.remove(puzzleID)
        }
        try lifecycle.performThrowingIfValid { try store.save(metadata) }
    }

    func status() throws -> DailySyncStatus {
        let metadata = try store.loadSyncMetadata()
        if metadata.hasPendingChanges { return .pending }
        if let date = metadata.lastSuccessfulSyncAt { return .synced(date) }
        return .idle
    }

    func synchronize() async throws -> DailySyncStatus {
        do {
            try Task.checkCancellation()
            let pulled = try await remote.pull()
            try Task.checkCancellation()
            let existingMetadata = try store.loadSyncMetadata()
            let cloud = DailyCloudSnapshot(
                progress: pulled.progress.flatMap {
                    existingMetadata.ignoredProgress.contains($0.puzzleID) ? nil : $0
                },
                importedResults: pulled.importedResults.filter {
                    !existingMetadata.ignoredResults.contains($0.puzzleID)
                }
            )
            guard owns(cloud), isValid(cloud) else { throw DailySyncError.invalidCloudData }

            let localProgressBefore = try store.loadProgress()
            let localHistoryBefore = try store.loadHistory()
            let reconciliation = try DailySyncReconciler.reconcile(
                localProgress: localProgressBefore,
                localHistory: localHistoryBefore,
                cloud: cloud
            )
            try Task.checkCancellation()
            try saveIfChanged(
                reconciliation,
                oldProgress: localProgressBefore,
                oldHistory: localHistoryBefore
            )
            guard reconciliation.conflicts.isEmpty else {
                return .conflict(reconciliation.conflicts)
            }

            // Derive upload work from durable reconciled state so valid local
            // progress/results converge even when pending metadata was never written.
            // Explicitly ignored puzzle IDs are never reuploaded. Exact cloud matches
            // skip uploads and local writes unless an explicit pending marker requires
            // an idempotent confirmation write.
            let cloudResultsByID = Dictionary(
                uniqueKeysWithValues: cloud.importedResults.map { ($0.puzzleID, $0) }
            )
            let localResultsByID = Dictionary(
                uniqueKeysWithValues: reconciliation.history.completedResults.map {
                    ($0.puzzleID, $0)
                }
            )
            var resultsToUpload: [DailyCompletedResult] = []
            for puzzleID in Set(localResultsByID.keys)
                .union(existingMetadata.pendingResultPuzzleIDs).sorted() {
                if existingMetadata.ignoredResults.contains(puzzleID) { continue }
                guard let localResult = localResultsByID[puzzleID] else { continue }
                if let cloudResult = cloudResultsByID[puzzleID],
                   DailySyncReconciler.sameImportedPayload(cloudResult.domain, localResult),
                   !existingMetadata.pendingResultPuzzleIDs.contains(puzzleID) {
                    continue
                }
                resultsToUpload.append(localResult)
            }
            resultsToUpload.sort {
                if $0.puzzleDay != $1.puzzleDay { return $0.puzzleDay < $1.puzzleDay }
                return $0.puzzleID < $1.puzzleID
            }

            var needsProgressPass = false
            if let active = reconciliation.progress, active.completion == nil,
               !existingMetadata.ignoredProgress.contains(active.puzzleID) {
                if let cloudProgress = cloud.progress,
                   cloudProgress.puzzleID == active.puzzleID {
                    let exact = isExactProgressMatch(local: active, cloud: cloudProgress)
                    needsProgressPass = !exact || existingMetadata.pendingProgress
                } else {
                    needsProgressPass = true
                }
            }

            var conflicts: [DailySyncConflict] = []
            for uploaded in resultsToUpload {
                try Task.checkCancellation()
                let outcome = try await remote.importResult(DailyImportedResultUploadDTO(uploaded))
                try Task.checkCancellation()
                try handleResultOutcomeFresh(outcome, uploaded: uploaded, conflicts: &conflicts)
            }

            // The derivation snapshot is uploaded; the handler re-reads current
            // state and drops the response when newer local work arrived first.
            if needsProgressPass,
               let upload = reconciliation.progress,
               upload.completion == nil {
                try Task.checkCancellation()
                let revision = cloud.progress?.puzzleID == upload.puzzleID
                    ? cloud.progress?.revision : nil
                let outcome = try await remote.pushProgress(
                    DailyProgressUploadDTO(progress: upload, expectedRevision: revision)
                )
                try Task.checkCancellation()
                try handleProgressOutcomeFresh(
                    outcome,
                    uploaded: upload,
                    conflicts: &conflicts
                )
            }

            guard conflicts.isEmpty else {
                return .conflict(conflicts)
            }

            // Converge metadata in one fresh write: drop stale markers, clear
            // exact matches, stamp success. The snapshot is re-read here with
            // no await before the save, so newer pending work cannot be clobbered.
            // The save itself runs inside the lifecycle lock (see
            // performThrowingIfValid), so invalidation cannot land mid-write.
            try Task.checkCancellation()
            var finalMetadata = try store.loadSyncMetadata()
            let currentHistory = try store.loadHistory()
            for pendingID in finalMetadata.pendingResultPuzzleIDs.sorted() {
                if finalMetadata.ignoredResults.contains(pendingID) { continue }
                guard let local = currentHistory.result(for: pendingID) else {
                    finalMetadata.pendingResultPuzzleIDs.remove(pendingID)
                    continue
                }
                if let cloudResult = cloudResultsByID[pendingID],
                   DailySyncReconciler.sameImportedPayload(cloudResult.domain, local) {
                    finalMetadata.pendingResultPuzzleIDs.remove(pendingID)
                }
            }
            if finalMetadata.pendingProgress {
                let current = try store.loadProgress()
                if current == nil || current?.completion != nil {
                    finalMetadata.pendingProgress = false
                } else if let current,
                          !finalMetadata.ignoredProgress.contains(current.puzzleID),
                          let cloudProgress = cloud.progress,
                          cloudProgress.puzzleID == current.puzzleID,
                          isExactProgressMatch(local: current, cloud: cloudProgress) {
                    finalMetadata.pendingProgress = false
                }
            }
            let date = now()
            finalMetadata.lastSuccessfulSyncAt = date
            try lifecycle.performThrowingIfValid { try store.save(finalMetadata) }
            return .synced(date)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DailySyncRemoteError {
            return .failed(error.failure)
        } catch is DailyClassicError {
            return .failed(.invalidData)
        } catch is DailySyncError {
            return .failed(.invalidData)
        } catch {
            return .failed(.unavailable)
        }
    }

    private func handleResultOutcomeFresh(
        _ outcome: DailyResultImportOutcome,
        uploaded: DailyCompletedResult,
        conflicts: inout [DailySyncConflict]
    ) throws {
        switch outcome {
        case .stored(let remoteResult), .conflict(.result(let remoteResult)):
            guard remoteResult.userID == userID,
                  DailySyncReconciler.isValid(remoteResult.domain) else {
                throw DailySyncError.invalidCloudData
            }
            let current = try store.loadHistory().result(for: uploaded.puzzleID)
            guard let current else {
                try removeResultPendingFresh(uploaded.puzzleID)
                return
            }
            guard DailySyncReconciler.sameImportedPayload(current, uploaded) else { return }
            if DailySyncReconciler.sameImportedPayload(remoteResult.domain, uploaded) {
                try removeResultPendingFresh(uploaded.puzzleID)
            } else {
                conflicts.append(.completedResult(
                    puzzleID: uploaded.puzzleID,
                    local: current,
                    cloud: remoteResult.domain
                ))
            }
        case .conflict(.progress(let remoteProgress)):
            guard valid(remoteProgress) else { throw DailySyncError.invalidCloudData }
            let current = try store.loadHistory().result(for: uploaded.puzzleID)
            guard let current,
                  DailySyncReconciler.sameImportedPayload(current, uploaded) else { return }
            conflicts.append(.progress(
                puzzleID: uploaded.puzzleID,
                local: DailyClassicProgress(result: current),
                cloud: remoteProgress.domain
            ))
        }
    }

    private func handleProgressOutcomeFresh(
        _ outcome: DailyProgressPushOutcome,
        uploaded: DailyClassicProgress,
        conflicts: inout [DailySyncConflict]
    ) throws {
        switch outcome {
        case .stored(let saved):
            guard valid(saved), sameCloudProgress(saved.domain, uploaded) else {
                throw DailySyncError.invalidCloudData
            }
            guard let current = try store.loadProgress(),
                  progressPayloadMatches(current, uploaded) else { return }
            try clearProgressPendingFresh()
        case .serverAhead(let saved):
            guard valid(saved) else { throw DailySyncError.invalidCloudData }
            let cloudProgress = saved.domain
            if uploaded.hardModeEnabled != cloudProgress.hardModeEnabled {
                guard uploaded.acceptedGuesses.isEmpty,
                      !cloudProgress.acceptedGuesses.isEmpty else {
                    conflicts.append(.progress(
                        puzzleID: uploaded.puzzleID,
                        local: uploaded,
                        cloud: cloudProgress
                    ))
                    return
                }
                guard let current = try store.loadProgress(),
                      progressPayloadMatches(current, uploaded) else { return }
                var restored = cloudProgress
                restored.draft = current.draft
                try Task.checkCancellation()
                try lifecycle.performThrowingIfValid { try store.save(restored) }
                try clearProgressPendingFresh()
                return
            }
            guard DailySyncReconciler.sameIdentity(uploaded, cloudProgress),
                  DailySyncReconciler.isPrefix(
                    uploaded.acceptedGuesses,
                    of: cloudProgress.acceptedGuesses
                  ) else {
                conflicts.append(.progress(
                    puzzleID: uploaded.puzzleID,
                    local: uploaded,
                    cloud: cloudProgress
                ))
                return
            }
            guard let current = try store.loadProgress(),
                  progressPayloadMatches(current, uploaded) else { return }
            var restored = cloudProgress
            restored.draft = current.draft
            try Task.checkCancellation()
            try lifecycle.performThrowingIfValid { try store.save(restored) }
            try clearProgressPendingFresh()
        case .completed(let saved):
            guard saved.userID == userID,
                  DailySyncReconciler.isValid(saved.domain) else {
                throw DailySyncError.invalidCloudData
            }
            let result = saved.domain
            guard DailySyncReconciler.sameIdentity(uploaded, result) else {
                throw DailySyncError.invalidCloudData
            }
            guard let current = try store.loadProgress(),
                  progressPayloadMatches(current, uploaded) else { return }
            var history = try store.loadHistory()
            if let existing = history.result(for: result.puzzleID),
               !DailySyncReconciler.sameImportedPayload(existing, result) {
                conflicts.append(.completedResult(
                    puzzleID: result.puzzleID,
                    local: existing,
                    cloud: result
                ))
                return
            }
            if history.result(for: result.puzzleID) == nil, !history.record(result) {
                throw DailySyncError.invalidCloudData
            }
            try Task.checkCancellation()
            try lifecycle.performThrowingIfValid { try store.save(history) }
            try Task.checkCancellation()
            try lifecycle.performThrowingIfValid { try store.save(DailyClassicProgress(result: result)) }
            try clearProgressPendingFresh()
        case .conflict(.progress(let saved)):
            guard valid(saved) else { throw DailySyncError.invalidCloudData }
            guard let current = try store.loadProgress(),
                  progressPayloadMatches(current, uploaded) else { return }
            conflicts.append(.progress(
                puzzleID: uploaded.puzzleID,
                local: uploaded,
                cloud: saved.domain
            ))
        case .conflict(.completed(let saved)):
            guard saved.userID == userID,
                  DailySyncReconciler.isValid(saved.domain) else {
                throw DailySyncError.invalidCloudData
            }
            guard let current = try store.loadProgress(),
                  progressPayloadMatches(current, uploaded) else { return }
            conflicts.append(.progress(
                puzzleID: uploaded.puzzleID,
                local: uploaded,
                cloud: DailyClassicProgress(result: saved.domain)
            ))
        }
    }

    private func save(_ reconciliation: DailyReconciliation) throws {
        try lifecycle.performThrowingIfValid { try store.save(reconciliation.history) }
        if let progress = reconciliation.progress {
            try lifecycle.performThrowingIfValid { try store.save(progress) }
        } else {
            try lifecycle.performThrowingIfValid { try store.discardProgress() }
        }
    }

    private func saveIfChanged(
        _ reconciliation: DailyReconciliation,
        oldProgress: DailyClassicProgress?,
        oldHistory: DailyClassicHistory
    ) throws {
        if reconciliation.history != oldHistory {
            try Task.checkCancellation()
            try lifecycle.performThrowingIfValid { try store.save(reconciliation.history) }
        }
        if reconciliation.progress != oldProgress {
            try Task.checkCancellation()
            if let progress = reconciliation.progress {
                try lifecycle.performThrowingIfValid { try store.save(progress) }
            } else if oldProgress != nil {
                try lifecycle.performThrowingIfValid { try store.discardProgress() }
            }
        }
    }

    private func isExactProgressMatch(
        local: DailyClassicProgress,
        cloud: DailyProgressDTO
    ) -> Bool {
        local.puzzleID == cloud.puzzleID
            && local.puzzleNumber == cloud.puzzleNumber
            && local.puzzleDay == cloud.puzzleDay
            && local.wordPackID == cloud.wordPackID
            && local.scheduleVersion == cloud.scheduleVersion
            && local.hardModeEnabled == cloud.hardModeEnabled
            && local.acceptedGuesses.map(DailyGuessDTO.init) == cloud.guesses
    }

    private func progressPayloadMatches(
        _ current: DailyClassicProgress,
        _ uploaded: DailyClassicProgress
    ) -> Bool {
        DailySyncReconciler.sameIdentity(current, uploaded)
            && current.hardModeEnabled == uploaded.hardModeEnabled
            && current.completion == nil
            && uploaded.completion == nil
            && current.acceptedGuesses.map(DailyGuessDTO.init)
                == uploaded.acceptedGuesses.map(DailyGuessDTO.init)
    }

    private func removeResultPendingFresh(_ puzzleID: String) throws {
        var fresh = try store.loadSyncMetadata()
        guard fresh.pendingResultPuzzleIDs.remove(puzzleID) != nil else { return }
        try Task.checkCancellation()
        try lifecycle.performThrowingIfValid { try store.save(fresh) }
    }

    private func clearProgressPendingFresh() throws {
        var fresh = try store.loadSyncMetadata()
        guard fresh.pendingProgress else { return }
        fresh.pendingProgress = false
        try Task.checkCancellation()
        try lifecycle.performThrowingIfValid { try store.save(fresh) }
    }

    private func owns(_ cloud: DailyCloudSnapshot) -> Bool {
        (cloud.progress == nil || cloud.progress?.userID == userID)
            && cloud.importedResults.allSatisfy { $0.userID == userID }
    }

    private func isValid(_ cloud: DailyCloudSnapshot) -> Bool {
        (cloud.progress.map(valid) ?? true)
            && cloud.importedResults.allSatisfy {
                DailySyncReconciler.isValid($0.domain)
            }
    }

    private func valid(_ progress: DailyProgressDTO) -> Bool {
        progress.userID == userID
            && progress.revision > 0
            && DailySyncReconciler.isValidActiveProgress(progress.domain)
    }

    private func sameCloudProgress(
        _ cloud: DailyClassicProgress,
        _ local: DailyClassicProgress
    ) -> Bool {
        DailySyncReconciler.samePuzzle(cloud, local)
            && cloud.draft.isEmpty
            && cloud.completion == nil
            && cloud.acceptedGuesses.map(DailyGuessDTO.init)
                == local.acceptedGuesses.map(DailyGuessDTO.init)
    }
}

extension Date {
    var dailyWireDate: Date {
        Date(timeIntervalSince1970: floor(timeIntervalSince1970 * 1_000) / 1_000)
    }

    var dailyWireTimestamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: dailyWireDate)
    }
}

private extension DailySyncRemoteError {
    var failure: DailySyncFailure {
        switch self {
        case .unavailable: .unavailable
        case .rejected: .rejected
        case .invalidData: .invalidData
        }
    }
}
