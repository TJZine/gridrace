import Foundation

struct DailySyncMetadata: Codable, Equatable, Sendable {
    var formatVersion = 1
    var pendingProgress = false
    var pendingResultPuzzleIDs: Set<String> = []
    var lastSuccessfulSyncAt: Date?
    var guestImportDecision: GuestImportDecision?
    var ignoredCloudProgressPuzzleIDs: Set<String>?
    var ignoredCloudResultPuzzleIDs: Set<String>?

    var hasPendingChanges: Bool {
        pendingProgress || !pendingResultPuzzleIDs.isEmpty
    }

    var ignoredProgress: Set<String> {
        get { ignoredCloudProgressPuzzleIDs ?? [] }
        set { ignoredCloudProgressPuzzleIDs = newValue.isEmpty ? nil : newValue }
    }

    var ignoredResults: Set<String> {
        get { ignoredCloudResultPuzzleIDs ?? [] }
        set { ignoredCloudResultPuzzleIDs = newValue.isEmpty ? nil : newValue }
    }
}

enum GuestImportDecision: String, Codable, Equatable, Sendable {
    case imported
    case skipped
}

struct AccountDailyClassicStore: DailyClassicStoring, Sendable {
    let userID: UUID
    let directory: URL

    private var dailyStore: DailyClassicStore { DailyClassicStore(directory: directory) }
    private var metadataURL: URL { directory.appending(path: "daily-sync-metadata-v1.json") }

    init(rootDirectory: URL, userID: UUID) {
        self.userID = userID
        directory = rootDirectory
            .appending(path: "Accounts", directoryHint: .isDirectory)
            .appending(path: userID.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    static func applicationSupport(userID: UUID) throws -> AccountDailyClassicStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return AccountDailyClassicStore(
            rootDirectory: base.appending(path: "GridRace", directoryHint: .isDirectory),
            userID: userID
        )
    }

    func loadProgress() throws -> DailyClassicProgress? { try dailyStore.loadProgress() }
    func save(_ progress: DailyClassicProgress) throws { try dailyStore.save(progress) }
    func discardProgress() throws { try dailyStore.discardProgress() }
    func loadHistory() throws -> DailyClassicHistory { try dailyStore.loadHistory() }
    func save(_ history: DailyClassicHistory) throws { try dailyStore.save(history) }

    func loadSyncMetadata() throws -> DailySyncMetadata {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return DailySyncMetadata()
        }
        do {
            let metadata = try JSONDecoder().decode(
                DailySyncMetadata.self,
                from: Data(contentsOf: metadataURL)
            )
            guard metadata.formatVersion == 1 else { throw DailySyncError.invalidLocalData }
            return metadata
        } catch is DecodingError {
            throw DailySyncError.invalidLocalData
        }
    }

    func save(_ metadata: DailySyncMetadata) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try DailyClassicPersistence.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    func deleteAccountCache() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
