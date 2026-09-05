import Foundation

enum DailyClassicError: Error, Equatable, Sendable {
    case invalidWordPack
    case missingWordPack
    case puzzleUnavailable
    case invalidSavedGame
    case invalidHistory
}

struct DailyWordPack: Decodable, Equatable, Sendable {
    let formatVersion: Int
    let id: String
    let scheduleVersion: Int
    let locale: String
    let wordLength: Int
    /// Whole UTC days since 1970-01-01. The first answer belongs to this day.
    let epochDay: Int
    let acceptedGuesses: [String]
    let answers: [String]

    static func load(from data: Data) throws -> DailyWordPack {
        let pack = try JSONDecoder().decode(DailyWordPack.self, from: data)
        guard pack.formatVersion == 1,
              !pack.id.isEmpty,
              pack.scheduleVersion > 0,
              pack.locale == "en-US",
              pack.wordLength == 5,
              pack.epochDay >= 0,
              !pack.acceptedGuesses.isEmpty,
              !pack.answers.isEmpty,
              Set(pack.acceptedGuesses).count == pack.acceptedGuesses.count,
              Set(pack.answers).count == pack.answers.count,
              pack.acceptedGuesses.allSatisfy(Self.isWord),
              pack.answers.allSatisfy(Self.isWord),
              Set(pack.answers).isSubset(of: Set(pack.acceptedGuesses))
        else { throw DailyClassicError.invalidWordPack }
        return pack
    }

    static func load(bundle: Bundle, resource: String = "daily-classic-en-US-v1") throws -> DailyWordPack {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw DailyClassicError.missingWordPack
        }
        let pack = try load(from: Data(contentsOf: url))
        try validateBundledIdentity(pack)
        return pack
    }

    static func validateBundledIdentity(_ pack: DailyWordPack) throws {
        guard pack.id == DailyPuzzleIdentity.wordPackID,
              pack.scheduleVersion == DailyPuzzleIdentity.scheduleVersion,
              pack.epochDay == DailyPuzzleIdentity.epochDay
        else { throw DailyClassicError.invalidWordPack }
    }

    private static func isWord(_ word: String) -> Bool {
        word.utf8.count == 5 && word.utf8.allSatisfy { (97...122).contains($0) }
    }
}

/// Canonical Daily Classic v1 puzzle identity.
///
/// Schedule source: shared/word-packs/daily-classic-en-US-v1 (schedule
/// version 1, epoch day 20696 = 2026-08-31, 725 published answers). Puzzle
/// days 20696...21420 carry puzzle numbers 1...725, and the puzzle id is the
/// UTC calendar date of the puzzle day. There is no v2 or generalized
/// identity framework; a future schedule needs an explicit contract change.
enum DailyPuzzleIdentity {
    static let wordPackID = "daily-classic-en-US-v1"
    static let scheduleVersion = 1
    static let epochDay = 20_696
    static let answerCount = 725
    static let lastDay = epochDay + answerCount - 1
    static let lastNumber = answerCount

    static func isValid(
        puzzleID: String,
        puzzleNumber: Int,
        puzzleDay: Int,
        wordPackID: String,
        scheduleVersion: Int
    ) -> Bool {
        guard wordPackID == self.wordPackID,
              scheduleVersion == self.scheduleVersion,
              (epochDay...lastDay).contains(puzzleDay),
              puzzleNumber == puzzleDay - epochDay + 1
        else { return false }
        return puzzleID == "daily-classic-\(DailyPuzzleSchedule.dateIdentifier(for: puzzleDay))"
    }
}

struct DailyPuzzle: Equatable, Sendable {
    let id: String
    let number: Int
    let day: Int
    let answer: String
    let wordPackID: String
    let scheduleVersion: Int
}

enum DailyPuzzleSchedule {
    static let secondsPerDay: TimeInterval = 86_400

    static func day(containing date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / secondsPerDay))
    }

    static func puzzle(at date: Date, in pack: DailyWordPack) throws -> DailyPuzzle {
        let day = day(containing: date)
        let index = day - pack.epochDay
        guard pack.answers.indices.contains(index) else {
            throw DailyClassicError.puzzleUnavailable
        }
        return DailyPuzzle(
            id: "daily-classic-\(dateIdentifier(for: day))",
            number: index + 1,
            day: day,
            answer: pack.answers[index],
            wordPackID: pack.id,
            scheduleVersion: pack.scheduleVersion
        )
    }

    static func nextReset(after date: Date) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day(containing: date) + 1) * secondsPerDay)
    }

    static func dateIdentifier(for day: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(day) * secondsPerDay)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

struct DailyGuess: Codable, Equatable, Sendable {
    let word: String
    let feedback: [Feedback]
    let acceptedAt: Date

    var row: GuessRow { GuessRow(word: word, feedback: feedback) }
}

enum DailyOutcome: String, Codable, Equatable, Sendable {
    case solved
    case failed
}

struct DailyCompletion: Codable, Equatable, Sendable {
    let outcome: DailyOutcome
    let guessCount: Int
    let completedAt: Date
}

struct DailyClassicProgress: Codable, Equatable, Sendable {
    let formatVersion: Int
    let puzzleID: String
    let puzzleNumber: Int
    let puzzleDay: Int
    let wordPackID: String
    let scheduleVersion: Int
    var hardModeEnabled: Bool
    var acceptedGuesses: [DailyGuess]
    var draft: String
    var completion: DailyCompletion?

    init(puzzle: DailyPuzzle, hardModeEnabled: Bool) {
        formatVersion = 1
        puzzleID = puzzle.id
        puzzleNumber = puzzle.number
        puzzleDay = puzzle.day
        wordPackID = puzzle.wordPackID
        scheduleVersion = puzzle.scheduleVersion
        self.hardModeEnabled = hardModeEnabled
        acceptedGuesses = []
        draft = ""
        completion = nil
    }

    init(result: DailyCompletedResult) {
        formatVersion = 1
        puzzleID = result.puzzleID
        puzzleNumber = result.puzzleNumber
        puzzleDay = result.puzzleDay
        wordPackID = result.wordPackID
        scheduleVersion = result.scheduleVersion
        hardModeEnabled = result.hardModeEnabled
        acceptedGuesses = result.guesses
        draft = ""
        completion = DailyCompletion(
            outcome: result.outcome,
            guessCount: result.guessCount,
            completedAt: result.completedAt
        )
    }
}

enum HardModeViolation: Equatable, Sendable {
    case requiredPosition(letter: Character, position: Int)
    case misplacedPosition(letter: Character, position: Int)
    case missingLetter(letter: Character, minimumCount: Int)

    var message: String {
        switch self {
        case .requiredPosition(let letter, let position):
            "Position \(position + 1) must be \(letter.uppercased())."
        case .misplacedPosition(let letter, let position):
            "\(letter.uppercased()) cannot stay in position \(position + 1)."
        case .missingLetter(let letter, let count):
            count == 1
                ? "Your guess must contain \(letter.uppercased())."
                : "Your guess must contain at least \(count) \(letter.uppercased())s."
        }
    }
}

enum DailySubmissionError: Equatable, Sendable {
    case validation(GuessValidationError)
    case hardMode(HardModeViolation)

    var message: String {
        switch self {
        case .validation(.invalidLength): "Enter five letters first."
        case .validation(.notAccepted): "That word is not in the accepted list."
        case .validation(let error): error.message
        case .hardMode(let violation): violation.message
        }
    }
}

struct DailySubmission: Equatable, Sendable {
    let guess: DailyGuess?
    let error: DailySubmissionError?
    let completion: DailyCompletion?
}

enum DailyHardMode {
    static func violation(for guess: String, previous: [DailyGuess]) -> HardModeViolation? {
        let letters = Array(guess)

        for row in previous {
            for (index, pair) in zip(row.word, row.feedback).enumerated()
            where pair.1 == .correct && letters[index] != pair.0 {
                return .requiredPosition(letter: pair.0, position: index)
            }
        }

        for row in previous {
            for (index, pair) in zip(row.word, row.feedback).enumerated()
            where pair.1 == .present && letters[index] == pair.0 {
                return .misplacedPosition(letter: pair.0, position: index)
            }
        }

        var minimumCounts: [Character: Int] = [:]
        for row in previous {
            var rowCounts: [Character: Int] = [:]
            for (letter, feedback) in zip(row.word, row.feedback) where feedback != .absent {
                rowCounts[letter, default: 0] += 1
            }
            for (letter, count) in rowCounts {
                minimumCounts[letter] = max(minimumCounts[letter, default: 0], count)
            }
        }
        let candidateCounts = Dictionary(grouping: letters, by: { $0 }).mapValues(\.count)
        for letter in minimumCounts.keys.sorted() {
            let required = minimumCounts[letter]!
            if candidateCounts[letter, default: 0] < required {
                return .missingLetter(letter: letter, minimumCount: required)
            }
        }
        return nil
    }
}

struct DailyClassicGame: Equatable, Sendable {
    let puzzle: DailyPuzzle
    private let acceptedWords: Set<String>
    private(set) var progress: DailyClassicProgress

    init(puzzle: DailyPuzzle, acceptedWords: Set<String>, hardModeEnabled: Bool = false) {
        self.puzzle = puzzle
        self.acceptedWords = acceptedWords
        progress = DailyClassicProgress(puzzle: puzzle, hardModeEnabled: hardModeEnabled)
    }

    init(puzzle: DailyPuzzle, acceptedWords: Set<String>, restoring saved: DailyClassicProgress) throws {
        guard Self.isValid(saved, for: puzzle, acceptedWords: acceptedWords) else {
            throw DailyClassicError.invalidSavedGame
        }
        self.puzzle = puzzle
        self.acceptedWords = acceptedWords
        progress = saved
    }

    var rows: [GuessRow] { progress.acceptedGuesses.map(\.row) }
    var draft: String { progress.draft }
    var completion: DailyCompletion? { progress.completion }
    var isComplete: Bool { completion != nil }
    var canChangeHardMode: Bool { !isComplete && progress.acceptedGuesses.isEmpty }

    var keyboard: KeyboardState {
        var keyboard = KeyboardState()
        for row in rows { keyboard.observe(row) }
        return keyboard
    }

    @discardableResult
    mutating func setHardMode(_ enabled: Bool) -> Bool {
        guard canChangeHardMode else { return false }
        progress.hardModeEnabled = enabled
        return true
    }

    mutating func type(_ letter: Character) {
        guard !isComplete, progress.draft.utf8.count < 5,
              let byte = String(letter).utf8.first,
              String(letter).utf8.count == 1,
              (65...90).contains(byte) || (97...122).contains(byte)
        else { return }
        progress.draft.append(Character(String(letter).uppercased()))
    }

    mutating func deleteBackward() {
        guard !isComplete, !progress.draft.isEmpty else { return }
        progress.draft.removeLast()
    }

    @discardableResult
    mutating func submit(at date: Date = Date()) -> DailySubmission {
        guard !isComplete else { return DailySubmission(guess: nil, error: nil, completion: completion) }

        switch GameRules.normalize(progress.draft, acceptedWords: acceptedWords) {
        case .failure(let error):
            return DailySubmission(guess: nil, error: .validation(error), completion: nil)
        case .success(let word):
            if progress.hardModeEnabled,
               let violation = DailyHardMode.violation(for: word, previous: progress.acceptedGuesses) {
                return DailySubmission(guess: nil, error: .hardMode(violation), completion: nil)
            }

            let acceptedAt = max(date, progress.acceptedGuesses.last?.acceptedAt ?? date)
            let guess = DailyGuess(
                word: word,
                feedback: GameRules.evaluate(answer: puzzle.answer, guess: word),
                acceptedAt: acceptedAt
            )
            progress.acceptedGuesses.append(guess)
            progress.draft = ""
            if guess.feedback.allSatisfy({ $0 == .correct }) {
                progress.completion = DailyCompletion(
                    outcome: .solved,
                    guessCount: progress.acceptedGuesses.count,
                    completedAt: acceptedAt
                )
            } else if progress.acceptedGuesses.count == 6 {
                progress.completion = DailyCompletion(
                    outcome: .failed,
                    guessCount: 6,
                    completedAt: acceptedAt
                )
            }
            return DailySubmission(guess: guess, error: nil, completion: progress.completion)
        }
    }

    var completedResult: DailyCompletedResult? {
        guard let completion else { return nil }
        return DailyCompletedResult(
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
    }

    private static func isValid(
        _ saved: DailyClassicProgress,
        for puzzle: DailyPuzzle,
        acceptedWords: Set<String>
    ) -> Bool {
        guard saved.formatVersion == 1,
              saved.puzzleID == puzzle.id,
              saved.puzzleNumber == puzzle.number,
              saved.puzzleDay == puzzle.day,
              saved.wordPackID == puzzle.wordPackID,
              saved.scheduleVersion == puzzle.scheduleVersion,
              saved.acceptedGuesses.count <= 6,
              saved.draft.utf8.count <= 5,
              saved.draft.utf8.allSatisfy({ (65...90).contains($0) }),
              saved.acceptedGuesses.enumerated().allSatisfy({ index, guess in
                  acceptedWords.contains(guess.word)
                      && guess.word.utf8.count == 5
                      && guess.feedback.count == 5
                      && guess.feedback == GameRules.evaluate(answer: puzzle.answer, guess: guess.word)
                      && (index < saved.acceptedGuesses.count - 1
                          ? !guess.feedback.allSatisfy({ $0 == .correct })
                          : true)
              })
        else { return false }

        if saved.hardModeEnabled {
            for index in saved.acceptedGuesses.indices {
                guard DailyHardMode.violation(
                    for: saved.acceptedGuesses[index].word,
                    previous: Array(saved.acceptedGuesses[..<index])
                ) == nil else { return false }
            }
        }

        let dates = saved.acceptedGuesses.map(\.acceptedAt)
        guard zip(dates, dates.dropFirst()).allSatisfy({ $0 <= $1 }) else { return false }

        let solved = saved.acceptedGuesses.last?.feedback.allSatisfy { $0 == .correct } == true
        switch saved.completion {
        case nil:
            return !solved && saved.acceptedGuesses.count < 6
        case .some(let completion):
            return saved.draft.isEmpty
                && completion.guessCount == saved.acceptedGuesses.count
                && (dates.last == nil || dates.last! <= completion.completedAt)
                && ((completion.outcome == .solved && solved)
                    || (completion.outcome == .failed && !solved && saved.acceptedGuesses.count == 6))
        }
    }
}

struct DailyCompletedResult: Codable, Equatable, Sendable {
    let puzzleID: String
    let puzzleNumber: Int
    let puzzleDay: Int
    let wordPackID: String
    let scheduleVersion: Int
    let hardModeEnabled: Bool
    let guesses: [DailyGuess]
    let outcome: DailyOutcome
    let guessCount: Int
    let completedAt: Date

    init(
        puzzleID: String,
        puzzleNumber: Int,
        puzzleDay: Int,
        wordPackID: String,
        scheduleVersion: Int,
        hardModeEnabled: Bool = false,
        guesses: [DailyGuess],
        outcome: DailyOutcome,
        guessCount: Int,
        completedAt: Date
    ) {
        self.puzzleID = puzzleID
        self.puzzleNumber = puzzleNumber
        self.puzzleDay = puzzleDay
        self.wordPackID = wordPackID
        self.scheduleVersion = scheduleVersion
        self.hardModeEnabled = hardModeEnabled
        self.guesses = guesses
        self.outcome = outcome
        self.guessCount = guessCount
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case puzzleID, puzzleNumber, puzzleDay, wordPackID, scheduleVersion
        case hardModeEnabled, guesses, outcome, guessCount, completedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        puzzleID = try values.decode(String.self, forKey: .puzzleID)
        puzzleNumber = try values.decode(Int.self, forKey: .puzzleNumber)
        puzzleDay = try values.decode(Int.self, forKey: .puzzleDay)
        wordPackID = try values.decode(String.self, forKey: .wordPackID)
        scheduleVersion = try values.decode(Int.self, forKey: .scheduleVersion)
        hardModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .hardModeEnabled) ?? false
        guesses = try values.decode([DailyGuess].self, forKey: .guesses)
        outcome = try values.decode(DailyOutcome.self, forKey: .outcome)
        guessCount = try values.decode(Int.self, forKey: .guessCount)
        completedAt = try values.decode(Date.self, forKey: .completedAt)
    }

    fileprivate var isStructurallyValid: Bool {
        let solved = guesses.last?.feedback.allSatisfy { $0 == .correct } == true
        return DailyPuzzleIdentity.isValid(
            puzzleID: puzzleID,
            puzzleNumber: puzzleNumber,
            puzzleDay: puzzleDay,
            wordPackID: wordPackID,
            scheduleVersion: scheduleVersion
        )
            && guessCount == guesses.count
            && (1...6).contains(guessCount)
            && guesses.allSatisfy {
                $0.word.utf8.count == 5
                    && $0.word.utf8.allSatisfy { (97...122).contains($0) }
                    && $0.feedback.count == 5
                    && $0.acceptedAt <= completedAt
            }
            && zip(guesses, guesses.dropFirst()).allSatisfy { $0.acceptedAt <= $1.acceptedAt }
            && !guesses.dropLast().contains { $0.feedback.allSatisfy { $0 == .correct } }
            && ((outcome == .solved && solved) || (outcome == .failed && !solved && guessCount == 6))
    }
}

struct DailyStatistics: Codable, Equatable, Sendable {
    var gamesPlayed = 0
    var gamesWon = 0
    var currentStreak = 0
    var longestStreak = 0
    var guessDistribution: [Int: Int] = [:]

    var solvePercentage: Int {
        gamesPlayed == 0 ? 0 : Int((Double(gamesWon) / Double(gamesPlayed) * 100).rounded())
    }

    func currentStreak(asOf puzzleDay: Int, latestResultDay: Int?) -> Int {
        guard let latestResultDay, latestResultDay >= puzzleDay - 1 else { return 0 }
        return currentStreak
    }

    static func calculate(from results: [DailyCompletedResult]) -> DailyStatistics {
        var statistics = DailyStatistics()
        var previous: DailyCompletedResult?
        for result in results.sorted(by: { $0.puzzleDay < $1.puzzleDay }) {
            statistics.gamesPlayed += 1
            if result.outcome == .solved {
                statistics.gamesWon += 1
                statistics.guessDistribution[result.guessCount, default: 0] += 1
                statistics.currentStreak = previous?.outcome == .solved
                    && previous?.puzzleDay == result.puzzleDay - 1
                    ? statistics.currentStreak + 1
                    : 1
                statistics.longestStreak = max(statistics.longestStreak, statistics.currentStreak)
            } else {
                statistics.currentStreak = 0
            }
            previous = result
        }
        return statistics
    }
}

struct DailyClassicHistory: Codable, Equatable, Sendable {
    private(set) var formatVersion = 1
    private(set) var completedResults: [DailyCompletedResult] = []
    private(set) var statistics = DailyStatistics()
    private(set) var statisticsAppliedPuzzleIDs: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case formatVersion, completedResults, statistics, statisticsAppliedPuzzleIDs
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        completedResults = try values.decode([DailyCompletedResult].self, forKey: .completedResults)
        statistics = try values.decode(DailyStatistics.self, forKey: .statistics)
        statisticsAppliedPuzzleIDs = try values.decode(
            Set<String>.self,
            forKey: .statisticsAppliedPuzzleIDs
        )
    }

    @discardableResult
    mutating func record(_ result: DailyCompletedResult) -> Bool {
        guard result.isStructurallyValid,
              !statisticsAppliedPuzzleIDs.contains(result.puzzleID),
              !completedResults.contains(where: { $0.puzzleDay == result.puzzleDay })
        else { return false }
        completedResults.append(result)
        completedResults.sort { $0.puzzleDay < $1.puzzleDay }
        statisticsAppliedPuzzleIDs.insert(result.puzzleID)
        statistics = DailyStatistics.calculate(from: completedResults)
        return true
    }

    @discardableResult
    mutating func replace(_ result: DailyCompletedResult) -> Bool {
        guard result.isStructurallyValid,
              let index = completedResults.firstIndex(where: { $0.puzzleID == result.puzzleID }),
              completedResults[index].puzzleDay == result.puzzleDay
        else { return false }
        completedResults[index] = result
        completedResults.sort { $0.puzzleDay < $1.puzzleDay }
        statisticsAppliedPuzzleIDs = Set(completedResults.map(\.puzzleID))
        statistics = DailyStatistics.calculate(from: completedResults)
        return true
    }

    @discardableResult
    mutating func removeResult(for puzzleID: String) -> Bool {
        guard let index = completedResults.firstIndex(where: { $0.puzzleID == puzzleID })
        else { return false }
        completedResults.remove(at: index)
        statisticsAppliedPuzzleIDs = Set(completedResults.map(\.puzzleID))
        statistics = DailyStatistics.calculate(from: completedResults)
        return true
    }

    func result(for puzzleID: String) -> DailyCompletedResult? {
        completedResults.first { $0.puzzleID == puzzleID }
    }

    var latestResultDay: Int? { completedResults.last?.puzzleDay }

    static func load(from data: Data) throws -> DailyClassicHistory {
        let history = try JSONDecoder().decode(DailyClassicHistory.self, from: data)
        let ids = history.completedResults.map(\.puzzleID)
        guard history.formatVersion == 1,
              Set(ids).count == ids.count,
              Set(history.completedResults.map(\.puzzleDay)).count == history.completedResults.count,
              history.completedResults.allSatisfy(\.isStructurallyValid),
              history.statisticsAppliedPuzzleIDs == Set(ids),
              history.statistics == DailyStatistics.calculate(from: history.completedResults)
        else { throw DailyClassicError.invalidHistory }
        return history
    }
}

enum DailyClassicPersistence {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decodeProgress(from data: Data) throws -> DailyClassicProgress {
        try JSONDecoder().decode(DailyClassicProgress.self, from: data)
    }
}

enum DailyClassicShare {
    static func text(for result: DailyCompletedResult) -> String {
        let score = result.outcome == .solved ? "\(result.guessCount)/6" : "X/6"
        let grid = result.guesses.map { guess in
            guess.feedback.map { feedback in
                switch feedback {
                case .correct: "✓"
                case .present: "↻"
                case .absent: "−"
                }
            }.joined()
        }.joined(separator: "\n")
        return "GridRace Daily Classic #\(result.puzzleNumber) \(score)\n\n\(grid)"
    }
}

struct DailyClassicSettings: Codable, Equatable, Sendable {
    var hapticsEnabled = true
    var highContrastEnabled = false
    var hardModeEnabled = false

    static let defaultsKey = "dailyClassic.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> DailyClassicSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(DailyClassicSettings.self, from: data)
        else { return DailyClassicSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try DailyClassicPersistence.encode(self), forKey: Self.defaultsKey)
    }
}
