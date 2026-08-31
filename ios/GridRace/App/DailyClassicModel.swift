import Foundation
import Observation

struct DailyClassicStore: Sendable {
    let directory: URL

    private var progressURL: URL { directory.appending(path: "daily-progress-v1.json") }
    private var historyURL: URL { directory.appending(path: "daily-history-v1.json") }

    static func applicationSupport() throws -> DailyClassicStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return DailyClassicStore(directory: base.appending(path: "GridRace", directoryHint: .isDirectory))
    }

    func loadProgress() throws -> DailyClassicProgress? {
        guard FileManager.default.fileExists(atPath: progressURL.path) else { return nil }
        return try DailyClassicPersistence.decodeProgress(from: Data(contentsOf: progressURL))
    }

    func save(_ progress: DailyClassicProgress) throws {
        try prepareDirectory()
        try DailyClassicPersistence.encode(progress).write(to: progressURL, options: .atomic)
    }

    func loadHistory() throws -> DailyClassicHistory {
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return DailyClassicHistory()
        }
        return try DailyClassicHistory.load(from: Data(contentsOf: historyURL))
    }

    func save(_ history: DailyClassicHistory) throws {
        try prepareDirectory()
        try DailyClassicPersistence.encode(history).write(to: historyURL, options: .atomic)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

enum DailyHomeStatus: Equatable, Sendable {
    case unplayed
    case inProgress(Int)
    case solved(Int)
    case failed

    var title: String {
        switch self {
        case .unplayed: "Ready to race"
        case .inProgress: "Race in progress"
        case .solved: "Solved today"
        case .failed: "Finished today"
        }
    }

    var action: String {
        switch self {
        case .unplayed: "Play today's puzzle"
        case .inProgress: "Continue today's puzzle"
        case .solved, .failed: "View today's result"
        }
    }

    var symbol: String {
        switch self {
        case .unplayed: "flag.checkered"
        case .inProgress: "figure.run"
        case .solved: "checkmark.seal.fill"
        case .failed: "flag.fill"
        }
    }
}

@Observable
@MainActor
final class DailyClassicModel {
    private(set) var puzzle: DailyPuzzle
    private(set) var game: DailyClassicGame
    private(set) var history: DailyClassicHistory
    var settings: DailyClassicSettings
    private(set) var errorMessage: String?
    private(set) var hapticEvent = 0
    private(set) var resultEvent = 0

    private let pack: DailyWordPack
    private let store: DailyClassicStore
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date

    init(
        pack: DailyWordPack,
        store: DailyClassicStore,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { Date() }
    ) throws {
        self.pack = pack
        self.store = store
        self.defaults = defaults
        self.now = now
        let puzzle = try DailyPuzzleSchedule.puzzle(at: now(), in: pack)
        var history = try store.loadHistory()
        var settings = DailyClassicSettings.load(from: defaults)
        self.puzzle = puzzle

        let restoredGame: DailyClassicGame
        if let saved = try store.loadProgress(), saved.puzzleID == puzzle.id {
            restoredGame = try DailyClassicGame(
                puzzle: puzzle,
                acceptedWords: Set(pack.acceptedGuesses),
                restoring: saved
            )
            if !restoredGame.canChangeHardMode {
                settings.hardModeEnabled = restoredGame.progress.hardModeEnabled
            }
        } else if let result = history.result(for: puzzle.id) {
            restoredGame = try DailyClassicGame(
                puzzle: puzzle,
                acceptedWords: Set(pack.acceptedGuesses),
                restoring: DailyClassicProgress(result: result, hardModeEnabled: settings.hardModeEnabled)
            )
        } else {
            restoredGame = DailyClassicGame(
                puzzle: puzzle,
                acceptedWords: Set(pack.acceptedGuesses),
                hardModeEnabled: settings.hardModeEnabled
            )
        }
        if let completed = restoredGame.completedResult, history.record(completed) {
            try store.save(history)
        }
        game = restoredGame
        self.history = history
        self.settings = settings
        try store.save(restoredGame.progress)
    }

    var homeStatus: DailyHomeStatus {
        switch game.completion?.outcome {
        case .solved?: .solved(game.rows.count)
        case .failed?: .failed
        case nil where game.rows.isEmpty && game.draft.isEmpty: .unplayed
        case nil: .inProgress(game.rows.count)
        }
    }

    var displayedCurrentStreak: Int {
        history.statistics.currentStreak(
            asOf: puzzle.day,
            latestResultDay: history.latestResultDay
        )
    }

    var nextReset: Date { DailyPuzzleSchedule.nextReset(after: now()) }

    func refreshForCurrentDay() {
        do {
            let current = try DailyPuzzleSchedule.puzzle(at: now(), in: pack)
            guard current.id != puzzle.id else { return }
            puzzle = current
            if let result = history.result(for: current.id) {
                game = try DailyClassicGame(
                    puzzle: current,
                    acceptedWords: Set(pack.acceptedGuesses),
                    restoring: DailyClassicProgress(result: result, hardModeEnabled: settings.hardModeEnabled)
                )
            } else {
                game = DailyClassicGame(
                    puzzle: current,
                    acceptedWords: Set(pack.acceptedGuesses),
                    hardModeEnabled: settings.hardModeEnabled
                )
            }
            errorMessage = nil
            try store.save(game.progress)
        } catch {
            errorMessage = "Today's puzzle could not be refreshed."
        }
    }

    func typeLetter(_ letter: Character) {
        guard !game.isComplete else { return }
        errorMessage = nil
        game.type(letter)
        persistProgress()
    }

    func deleteLetter() {
        guard !game.isComplete else { return }
        errorMessage = nil
        game.deleteBackward()
        persistProgress()
    }

    func submitGuess() {
        let submission = game.submit(at: now())
        if let error = submission.error {
            errorMessage = error.message
            hapticEvent += 1
            persistProgress()
            return
        }
        guard submission.guess != nil else { return }
        errorMessage = nil
        hapticEvent += 1
        if let result = game.completedResult {
            _ = history.record(result)
            do {
                try store.save(history)
                resultEvent += 1
            } catch {
                errorMessage = "Your result could not be saved. Try again."
            }
        }
        persistProgress()
    }

    func updateHaptics(_ enabled: Bool) {
        settings.hapticsEnabled = enabled
        persistSettings()
    }

    func updateHighContrast(_ enabled: Bool) {
        settings.highContrastEnabled = enabled
        persistSettings()
    }

    func updateHardMode(_ enabled: Bool) {
        guard game.setHardMode(enabled) else { return }
        settings.hardModeEnabled = enabled
        persistSettings()
        persistProgress()
    }

    private func persistProgress() {
        do {
            try store.save(game.progress)
        } catch {
            errorMessage = "Your puzzle could not be saved. Try again."
        }
    }

    private func persistSettings() {
        do {
            try settings.save(to: defaults)
        } catch {
            errorMessage = "Your settings could not be saved."
        }
    }

}
