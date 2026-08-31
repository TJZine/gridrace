import Foundation
import Observation

enum CountdownState: Equatable, Sendable {
    case countdown(Int)
    case playing(TimeInterval)
    case expired
}

struct CountdownWindow: Equatable, Sendable {
    let startsAt: Date
    let endsAt: Date

    func state(at now: Date) -> CountdownState {
        if now < startsAt {
            return .countdown(max(1, Int(ceil(startsAt.timeIntervalSince(now)))))
        }
        if now < endsAt {
            return .playing(endsAt.timeIntervalSince(now))
        }
        return .expired
    }
}

enum TutorialPhase: Equatable, Sendable {
    case introduction
    case countdown
    case playing
    case reveal
}

enum OpponentState: String, Equatable, Sendable {
    case playing
    case solved
    case failed
    case timedOut
    case forfeited

    var spokenDescription: String {
        switch self {
        case .playing: "still playing"
        case .solved: "solved"
        case .failed: "failed"
        case .timedOut: "timed out"
        case .forfeited: "forfeited"
        }
    }
}

struct OpponentProgress: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let avatarSymbol: String
    var acceptedGuessCount: Int
    var isConnected: Bool
    var state: OpponentState

    var accessibilityLabel: String {
        let guesses = acceptedGuessCount == 1 ? "guess" : "guesses"
        let connection = isConnected ? "connected" : "disconnected"
        return "Opponent \(name), \(acceptedGuessCount) \(guesses) submitted, "
            + "\(state.spokenDescription), \(connection)."
    }
}

struct RevealBoard: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let rows: [GuessRow]
    let result: String
}

@Observable
@MainActor
final class TutorialModel {
    static let answer = "stone"

    private(set) var phase = TutorialPhase.introduction
    private(set) var board: BoardState
    private(set) var opponents: [OpponentProgress]
    private(set) var countdownSeconds = 3
    private(set) var roundSecondsRemaining = 180
    private(set) var errorMessage: String?
    private(set) var revealBoards: [RevealBoard] = []
    private(set) var visibleRevealRowCount = 0
    private(set) var revealSummaryVisible = false
    private(set) var countdownTaskIsActive = false
    private(set) var revealTaskIsActive = false
    private(set) var hapticEvent = 0

    var hapticsEnabled = true
    private(set) var prefersReducedMotion = false

    private let acceptedWords: Set<String>
    private let now: @MainActor () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var window: CountdownWindow?
    private var countdownTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?

    init(
        acceptedWords: Set<String>,
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task<Never, Never>.sleep(for: $0)
        }
    ) {
        self.acceptedWords = acceptedWords
        self.now = now
        self.sleep = sleep
        board = BoardState(answer: Self.answer, acceptedWords: acceptedWords)
        opponents = Self.initialOpponents
    }

    func startTutorial() {
        cancelSessionTasks()
        board = BoardState(answer: Self.answer, acceptedWords: acceptedWords)
        opponents = Self.initialOpponents
        revealBoards = []
        visibleRevealRowCount = 0
        revealSummaryVisible = false
        errorMessage = nil

        let requestedAt = now()
        let startsAt = requestedAt.addingTimeInterval(3)
        window = CountdownWindow(
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(180)
        )
        phase = .countdown
        update(at: requestedAt)
        startCountdownTask()
    }

    func setReduceMotion(_ enabled: Bool) {
        prefersReducedMotion = enabled
        guard enabled, phase == .reveal else { return }
        revealTask?.cancel()
        revealTask = nil
        revealTaskIsActive = false
        visibleRevealRowCount = totalRevealRowCount
        revealSummaryVisible = true
    }

    func refreshFromClock() {
        update(at: now())
    }

    func update(at date: Date) {
        guard phase == .countdown || phase == .playing, let window else { return }
        switch window.state(at: date) {
        case .countdown(let seconds):
            phase = .countdown
            countdownSeconds = seconds
        case .playing(let remaining):
            phase = .playing
            roundSecondsRemaining = max(0, Int(ceil(remaining)))
            updateOpponents(elapsed: date.timeIntervalSince(window.startsAt))
        case .expired:
            board.timeOut()
            beginReveal()
        }
    }

    func typeLetter(_ letter: Character) {
        guard phase == .playing else { return }
        errorMessage = nil
        board.type(letter)
    }

    func deleteLetter() {
        guard phase == .playing else { return }
        errorMessage = nil
        board.deleteBackward()
    }

    func submitGuess() {
        guard phase == .playing, let submission = board.submitDraft() else { return }
        if let error = submission.validationError {
            errorMessage = error.message
            return
        }

        errorMessage = nil
        hapticEvent += 1
        if board.status != .playing {
            beginReveal()
        }
    }

    func replay() {
        cancelSessionTasks()
        window = nil
        phase = .introduction
        board = BoardState(answer: Self.answer, acceptedWords: acceptedWords)
        opponents = Self.initialOpponents
        errorMessage = nil
        revealBoards = []
        visibleRevealRowCount = 0
        revealSummaryVisible = false
    }

    func cancelSessionTasks() {
        countdownTask?.cancel()
        revealTask?.cancel()
        countdownTask = nil
        revealTask = nil
        countdownTaskIsActive = false
        revealTaskIsActive = false
    }

    func visibleRows(in boardIndex: Int) -> Int {
        guard revealBoards.indices.contains(boardIndex) else { return 0 }
        let priorRows = revealBoards.prefix(boardIndex).reduce(0) { $0 + $1.rows.count }
        return min(
            revealBoards[boardIndex].rows.count,
            max(0, visibleRevealRowCount - priorRows)
        )
    }

    func advanceReveal() {
        guard visibleRevealRowCount < totalRevealRowCount else {
            revealSummaryVisible = true
            return
        }
        visibleRevealRowCount += 1
        if visibleRevealRowCount == totalRevealRowCount {
            revealSummaryVisible = true
        }
    }

    var comparisonSummary: String {
        guard revealBoards.count == 3 else { return "" }
        let localCount = revealBoards[0].rows.count
        let localGuesses = localCount == 1 ? "1 guess" : "\(localCount) guesses"
        return "You used \(localGuesses). "
            + "Alex solved in 3. Sam used 6 and failed."
    }

    private var totalRevealRowCount: Int {
        revealBoards.reduce(0) { $0 + $1.rows.count }
    }

    private func startCountdownTask() {
        countdownTask?.cancel()
        countdownTaskIsActive = true
        countdownTask = Task { [weak self, sleep] in
            defer { self?.countdownTaskIsActive = false }
            do {
                while !Task.isCancelled {
                    try await sleep(.milliseconds(100))
                    guard let self, !Task.isCancelled else { return }
                    self.update(at: self.now())
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.errorMessage = "The local timer stopped. Replay the tutorial to try again."
            }
        }
    }

    private func updateOpponents(elapsed: TimeInterval) {
        opponents = Self.ghosts.map { ghost in
            let count = ghost.acceptedAt.filter { $0 <= elapsed }.count
            let state: OpponentState = count == ghost.words.count ? ghost.finalState : .playing
            return OpponentProgress(
                id: ghost.id,
                name: ghost.name,
                avatarSymbol: ghost.avatarSymbol,
                acceptedGuessCount: count,
                isConnected: true,
                state: state
            )
        }
    }

    private func beginReveal() {
        guard phase != .reveal else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdownTaskIsActive = false
        phase = .reveal
        errorMessage = nil

        revealBoards = [
            RevealBoard(
                id: "local",
                name: "You",
                rows: board.rows,
                result: Self.resultText(for: board.status)
            )
        ] + Self.ghosts.map { ghost in
            RevealBoard(
                id: ghost.id,
                name: ghost.name,
                rows: ghost.words.map {
                    GuessRow(
                        word: $0,
                        feedback: GameRules.evaluate(answer: Self.answer, guess: $0)
                    )
                },
                result: ghost.finalState == .solved ? "Solved" : "Failed"
            )
        }

        if prefersReducedMotion {
            visibleRevealRowCount = totalRevealRowCount
            revealSummaryVisible = true
            return
        }

        visibleRevealRowCount = 0
        revealSummaryVisible = totalRevealRowCount == 0
        guard totalRevealRowCount > 0 else { return }
        revealTaskIsActive = true
        revealTask = Task { [weak self, sleep] in
            defer { self?.revealTaskIsActive = false }
            do {
                while let self, self.visibleRevealRowCount < self.totalRevealRowCount {
                    try await sleep(.milliseconds(350))
                    guard !Task.isCancelled else { return }
                    self.advanceReveal()
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.visibleRevealRowCount = self.totalRevealRowCount
                self.revealSummaryVisible = true
            }
        }
    }

    private static func resultText(for status: BoardStatus) -> String {
        switch status {
        case .playing: "Playing"
        case .solved: "Solved"
        case .failed: "Failed"
        case .timedOut: "Timed out"
        }
    }
}

private extension TutorialModel {
    struct Ghost {
        let id: String
        let name: String
        let avatarSymbol: String
        let words: [String]
        let acceptedAt: [TimeInterval]
        let finalState: OpponentState
    }

    static let ghosts = [
        Ghost(
            id: "alex",
            name: "Alex",
            avatarSymbol: "bolt.fill",
            words: ["crane", "grape", "stone"],
            acceptedAt: [6, 18, 32],
            finalState: .solved
        ),
        Ghost(
            id: "sam",
            name: "Sam",
            avatarSymbol: "moon.stars.fill",
            words: ["civic", "bloom", "mouse", "faith", "earth", "grace"],
            acceptedAt: [8, 16, 26, 40, 55, 72],
            finalState: .failed
        )
    ]

    static let initialOpponents = ghosts.map {
        OpponentProgress(
            id: $0.id,
            name: $0.name,
            avatarSymbol: $0.avatarSymbol,
            acceptedGuessCount: 0,
            isConnected: true,
            state: .playing
        )
    }
}
