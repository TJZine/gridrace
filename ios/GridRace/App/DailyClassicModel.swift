import Foundation
import Observation

protocol DailyClassicStoring: Sendable {
    func loadProgress() throws -> DailyClassicProgress?
    func save(_ progress: DailyClassicProgress) throws
    func discardProgress() throws
    func loadHistory() throws -> DailyClassicHistory
    func save(_ history: DailyClassicHistory) throws
}

struct DailyClassicStore: DailyClassicStoring, Sendable {
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
        let data = try Data(contentsOf: progressURL)
        do {
            return try DailyClassicPersistence.decodeProgress(from: data)
        } catch {
            throw DailyClassicError.invalidSavedGame
        }
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

    func discardProgress() throws {
        guard FileManager.default.fileExists(atPath: progressURL.path) else { return }
        try FileManager.default.removeItem(at: progressURL)
    }

    /// Removes only this store's guest Daily progress/history files.
    /// Never removes the containing directory, so sibling `Accounts/<uuid>`
    /// caches sharing the GridRace root are preserved.
    func resetGuestDailyData() throws {
        for url in [progressURL, historyURL] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.removeItem(at: url)
        }
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
        case .unplayed: "Ready to play"
        case .inProgress(let rows): "\(rows) of 6 rows used"
        case .solved(let rows): "Solved in \(rows)"
        case .failed: "Not solved"
        }
    }

    var action: String {
        switch self {
        case .unplayed: "Play"
        case .inProgress: "Continue"
        case .solved, .failed: "Result"
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
    private var validationMessage: String?
    private(set) var storageMessage: String?
    var errorMessage: String? { validationMessage ?? storageMessage }
    private(set) var hasUnsavedProgress = false
    private(set) var hapticEvent = 0
    private(set) var resultEvent = 0

    private let pack: DailyWordPack
    private let store: any DailyClassicStoring
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private var pendingTerminalResult: DailyCompletedResult?
    @ObservationIgnored var acceptedStateChanged: (@MainActor () -> Void)?

    init(
        pack: DailyWordPack,
        store: any DailyClassicStoring,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { Date() }
    ) throws {
        self.pack = pack
        self.store = store
        self.defaults = defaults
        self.now = now
        var puzzle = try DailyPuzzleSchedule.puzzle(at: now(), in: pack)
        var history = try store.loadHistory()
        var settings = DailyClassicSettings.load(from: defaults)
        // The single progress slot can contain yesterday's terminal fallback.
        // Validate against its canonical scheduled puzzle before recording history.
        if let saved = try? store.loadProgress(), saved.completion != nil,
           saved.puzzleDay < puzzle.day, history.result(for: saved.puzzleID) == nil {
            do {
                let prior = try DailyPuzzleSchedule.puzzle(
                    at: Date(timeIntervalSince1970: TimeInterval(saved.puzzleDay) * 86_400), in: pack)
                let terminal = try DailyClassicGame(
                    puzzle: prior, acceptedWords: Set(pack.acceptedGuesses), restoring: saved)
                guard let result = terminal.completedResult, history.record(result) else {
                    throw DailyClassicError.invalidSavedGame
                }
                pendingTerminalResult = result
                puzzle = prior
            } catch {
                try? store.discardProgress()
            }
        }
        self.puzzle = puzzle

        let restoredGame: DailyClassicGame
        if let result = history.result(for: puzzle.id) {
            restoredGame = try DailyClassicGame(
                puzzle: puzzle,
                acceptedWords: Set(pack.acceptedGuesses),
                restoring: DailyClassicProgress(result: result)
            )
        } else {
            let saved: DailyClassicProgress?
            do {
                saved = try store.loadProgress()
            } catch DailyClassicError.invalidSavedGame {
                try? store.discardProgress()
                saved = nil
            }
            if let saved, saved.puzzleID == puzzle.id {
                do {
                    restoredGame = try DailyClassicGame(
                        puzzle: puzzle,
                        acceptedWords: Set(pack.acceptedGuesses),
                        restoring: saved
                    )
                } catch DailyClassicError.invalidSavedGame {
                    try? store.discardProgress()
                    restoredGame = DailyClassicGame(
                        puzzle: puzzle,
                        acceptedWords: Set(pack.acceptedGuesses),
                        hardModeEnabled: settings.hardModeEnabled
                    )
                }
                if !restoredGame.canChangeHardMode {
                    settings.hardModeEnabled = restoredGame.progress.hardModeEnabled
                }
            } else {
                restoredGame = DailyClassicGame(
                    puzzle: puzzle,
                    acceptedWords: Set(pack.acceptedGuesses),
                    hardModeEnabled: settings.hardModeEnabled
                )
            }
        }
        if let completed = restoredGame.completedResult,
           history.result(for: completed.puzzleID) == nil {
            guard history.record(completed) else { throw DailyClassicError.invalidHistory }
            pendingTerminalResult = completed
        }
        game = restoredGame
        self.history = history
        self.settings = settings
        if pendingTerminalResult != nil {
            retryPendingCompletion()
            if pendingTerminalResult == nil { refreshForCurrentDay() }
        } else {
            persistProgress()
        }
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

    /// Displayed streak immediately before today's result, derived from
    /// completed results before the current puzzle day with the existing
    /// `DailyStatistics` rules. No new persistence; valid on reopen.
    var previousDisplayedStreak: Int {
        let prior = history.completedResults.filter { $0.puzzleDay < puzzle.day }
        let priorStatistics = DailyStatistics.calculate(from: prior)
        return priorStatistics.currentStreak(
            asOf: puzzle.day,
            latestResultDay: prior.last?.puzzleDay
        )
    }

    var nextReset: Date { DailyPuzzleSchedule.nextReset(after: now()) }

    func refreshForCurrentDay() {
        retryPendingCompletion()
        do {
            let current = try DailyPuzzleSchedule.puzzle(at: now(), in: pack)
            guard current.id != puzzle.id else { return }
            guard pendingTerminalResult == nil else {
                storageMessage = "Yesterday's result is still being saved. GridRace will retry."
                return
            }
            puzzle = current
            if let result = history.result(for: current.id) {
                game = try DailyClassicGame(
                    puzzle: current,
                    acceptedWords: Set(pack.acceptedGuesses),
                    restoring: DailyClassicProgress(result: result)
                )
            } else {
                game = DailyClassicGame(
                    puzzle: current,
                    acceptedWords: Set(pack.acceptedGuesses),
                    hardModeEnabled: settings.hardModeEnabled
                )
            }
            validationMessage = nil
            persistProgress()
        } catch {
            validationMessage = "Today's puzzle could not be refreshed."
        }
    }

    func typeLetter(_ letter: Character) {
        guard !game.isComplete else { return }
        validationMessage = nil
        game.type(letter)
        persistProgress()
    }

    func deleteLetter() {
        guard !game.isComplete else { return }
        validationMessage = nil
        game.deleteBackward()
        persistProgress()
    }

    func submitGuess() {
        let submissionDate = now()
        guard DailyPuzzleSchedule.day(containing: submissionDate) == puzzle.day else {
            refreshForCurrentDay()
            validationMessage = "A new daily puzzle is ready."
            hapticEvent += 1
            return
        }
        let submission = game.submit(at: submissionDate)
        if let error = submission.error {
            validationMessage = error.message
            hapticEvent += 1
            persistProgress()
            return
        }
        guard submission.guess != nil else { return }
        validationMessage = nil
        hapticEvent += 1
        if let result = game.completedResult {
            guard history.result(for: result.puzzleID) == nil else {
                validationMessage = "This daily result was already recorded."
                return
            }
            guard history.record(result) else {
                pendingTerminalResult = result
                validationMessage = "Your result could not be recorded. GridRace will retry."
                persistProgress()
                return
            }
            pendingTerminalResult = result
            resultEvent += 1
            retryPendingCompletion()
        } else {
            persistProgress()
        }
        acceptedStateChanged?()
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
        acceptedStateChanged?()
    }

    /// Flush the accepted owner state before any disk-based reconciliation.
    @discardableResult
    func retryPersistence() -> Bool {
        if pendingTerminalResult != nil { retryPendingCompletion() }
        if pendingTerminalResult == nil, hasUnsavedProgress { persistProgress() }
        return pendingTerminalResult == nil && !hasUnsavedProgress
    }

    /// Adopt durable reconciliation without replacing this accepted-state owner.
    func reloadReconciledState() throws {
        guard retryPersistence() else { return }
        let loadedHistory = try store.loadHistory()
        let progress = try loadedHistory.result(for: puzzle.id).map(DailyClassicProgress.init(result:))
            ?? store.loadProgress()
        if let progress, progress.puzzleID == puzzle.id {
            game = try DailyClassicGame(puzzle: puzzle, acceptedWords: Set(pack.acceptedGuesses), restoring: progress)
            settings.hardModeEnabled = game.progress.hardModeEnabled
        }
        history = loadedHistory
        refreshForCurrentDay()
    }

    /// An immutable remote completion can settle a dirty active attempt.
    func adoptAuthoritativeCompletion(_ result: DailyCompletedResult) throws {
        guard result.puzzleID == puzzle.id, history.result(for: puzzle.id) == nil else { return }
        let restored = try DailyClassicGame(puzzle: puzzle, acceptedWords: Set(pack.acceptedGuesses),
                                           restoring: DailyClassicProgress(result: result))
        guard history.record(result) else { throw DailyClassicError.invalidHistory }
        game = restored
        pendingTerminalResult = result
        retryPendingCompletion()
    }

    private func persistProgress() {
        hasUnsavedProgress = true
        do {
            try store.save(game.progress)
            hasUnsavedProgress = false
            if pendingTerminalResult == nil { storageMessage = nil }
        } catch {
            storageMessage = "Your puzzle could not be saved. Try again."
        }
    }

    private func retryPendingCompletion() {
        guard let result = pendingTerminalResult else { return }
        if let existing = history.result(for: result.puzzleID) {
            guard existing == result else {
                storageMessage = "The saved daily result conflicts with this game."
                return
            }
        } else {
            guard history.record(result) else {
                storageMessage = "Your result could not be recorded. GridRace will retry."
                return
            }
        }
        do {
            try store.save(history)
            pendingTerminalResult = nil
            // History is sufficient durability for a terminal game.
            hasUnsavedProgress = false
            storageMessage = nil
        } catch {
            persistProgress()
            storageMessage = "Your result is still being saved. GridRace will retry."
        }
    }

    private func persistSettings() {
        do {
            try settings.save(to: defaults)
        } catch {
            validationMessage = "Your settings could not be saved."
        }
    }

}
