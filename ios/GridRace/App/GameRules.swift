import Foundation

enum Feedback: Int, Codable, CaseIterable, Comparable, Sendable {
    case absent = 0
    case present = 1
    case correct = 2

    static func < (lhs: Feedback, rhs: Feedback) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var accessibilityMeaning: String {
        switch self {
        case .absent: "not in the word"
        case .present: "present in another position"
        case .correct: "correct position"
        }
    }

    var symbolName: String {
        switch self {
        case .absent: "minus"
        case .present: "arrow.trianglehead.2.clockwise.rotate.90"
        case .correct: "checkmark"
        }
    }
}

enum GuessValidationError: String, Codable, Error, Sendable {
    case nonAscii
    case invalidLength
    case invalidCharacter
    case notAccepted

    var message: String {
        switch self {
        case .nonAscii: "Use only the English letters A through Z."
        case .invalidLength: "Enter exactly five letters."
        case .invalidCharacter: "Use letters only."
        case .notAccepted: "That word is not in this small tutorial list."
        }
    }
}

enum RoundState: String, Codable, Sendable {
    case playing
    case solved
    case failed
}

struct GuessRow: Equatable, Sendable {
    let word: String
    let feedback: [Feedback]
}

struct Submission: Equatable, Sendable {
    let normalizedGuess: String?
    let validationError: GuessValidationError?
    let feedback: [Feedback]?
    let acceptedGuessCount: Int
    let roundState: RoundState
}

enum GameRules {
    static func submit(
        _ input: String,
        answer: String,
        acceptedWords: Set<String>,
        acceptedGuessesBefore: Int
    ) -> Submission {
        switch normalize(input, acceptedWords: acceptedWords) {
        case .failure(let error):
            let normalized = error == .nonAscii ? nil : asciiLowercased(input)
            return Submission(
                normalizedGuess: normalized,
                validationError: error,
                feedback: nil,
                acceptedGuessCount: acceptedGuessesBefore,
                roundState: .playing
            )
        case .success(let guess):
            let feedback = evaluate(answer: answer, guess: guess)
            let count = acceptedGuessesBefore + 1
            let state: RoundState = feedback.allSatisfy { $0 == .correct }
                ? .solved
                : count == 6 ? .failed : .playing
            return Submission(
                normalizedGuess: guess,
                validationError: nil,
                feedback: feedback,
                acceptedGuessCount: count,
                roundState: state
            )
        }
    }

    static func normalize(
        _ input: String,
        acceptedWords: Set<String>
    ) -> Result<String, GuessValidationError> {
        guard input.unicodeScalars.allSatisfy({ $0.value <= 127 }) else {
            return .failure(.nonAscii)
        }

        let normalized = asciiLowercased(input)
        guard normalized.utf8.count == 5 else {
            return .failure(.invalidLength)
        }
        guard normalized.utf8.allSatisfy({ (97...122).contains($0) }) else {
            return .failure(.invalidCharacter)
        }
        guard acceptedWords.contains(normalized) else {
            return .failure(.notAccepted)
        }
        return .success(normalized)
    }

    static func evaluate(answer: String, guess: String) -> [Feedback] {
        let answerBytes = Array(answer.utf8)
        let guessBytes = Array(guess.utf8)
        precondition(answerBytes.count == 5 && guessBytes.count == 5)

        var result = Array(repeating: Feedback.absent, count: 5)
        var remaining: [UInt8: Int] = [:]
        for byte in answerBytes {
            remaining[byte, default: 0] += 1
        }

        for index in 0..<5 where answerBytes[index] == guessBytes[index] {
            result[index] = .correct
            remaining[guessBytes[index], default: 0] -= 1
        }

        for index in 0..<5 where result[index] != .correct {
            let byte = guessBytes[index]
            if remaining[byte, default: 0] > 0 {
                result[index] = .present
                remaining[byte, default: 0] -= 1
            }
        }
        return result
    }

    private static func asciiLowercased(_ input: String) -> String {
        let bytes = input.utf8.map { byte in
            (65...90).contains(byte) ? byte + 32 : byte
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum BoardStatus: Equatable, Sendable {
    case playing
    case solved
    case failed
    case timedOut
}

struct KeyboardState: Equatable, Sendable {
    private(set) var evidence: [Character: Feedback] = [:]

    mutating func observe(_ row: GuessRow) {
        for (letter, feedback) in zip(row.word, row.feedback) {
            evidence[letter] = max(evidence[letter] ?? .absent, feedback)
        }
    }

    func feedback(for letter: Character) -> Feedback? {
        evidence[Character(letter.lowercased())]
    }
}

struct BoardState: Equatable, Sendable {
    let answer: String
    let acceptedWords: Set<String>
    private(set) var draft = ""
    private(set) var rows: [GuessRow] = []
    private(set) var status = BoardStatus.playing
    private(set) var keyboard = KeyboardState()

    mutating func type(_ letter: Character) {
        guard status == .playing, draft.utf8.count < 5,
              let byte = String(letter).utf8.first,
              String(letter).utf8.count == 1,
              (65...90).contains(byte) || (97...122).contains(byte)
        else { return }
        draft.append(Character(String(letter).uppercased()))
    }

    mutating func deleteBackward() {
        guard status == .playing, !draft.isEmpty else { return }
        draft.removeLast()
    }

    @discardableResult
    mutating func submitDraft() -> Submission? {
        guard status == .playing else { return nil }
        let submission = GameRules.submit(
            draft,
            answer: answer,
            acceptedWords: acceptedWords,
            acceptedGuessesBefore: rows.count
        )
        guard submission.validationError == nil,
              let word = submission.normalizedGuess,
              let feedback = submission.feedback
        else { return submission }

        let row = GuessRow(word: word, feedback: feedback)
        rows.append(row)
        keyboard.observe(row)
        draft = ""
        switch submission.roundState {
        case .playing: status = .playing
        case .solved: status = .solved
        case .failed: status = .failed
        }
        return submission
    }

    mutating func timeOut() {
        guard status == .playing else { return }
        status = .timedOut
        draft = ""
    }
}

struct WordPack: Decodable, Sendable {
    let formatVersion: Int
    let id: String
    let locale: String
    let wordLength: Int
    let words: [String]

    static func load(from data: Data) throws -> WordPack {
        let pack = try JSONDecoder().decode(WordPack.self, from: data)
        guard pack.formatVersion == 1,
              pack.id == "development-en-US-v1",
              pack.locale == "en-US",
              pack.wordLength == 5,
              pack.words.count == 100,
              Set(pack.words).count == pack.words.count,
              pack.words.allSatisfy(isLowercaseASCIIWord)
        else { throw ResourceError.invalidWordPack }
        return pack
    }

    static func load(bundle: Bundle) throws -> WordPack {
        guard let url = bundle.url(
            forResource: "development-en-US-v1",
            withExtension: "json"
        ) else { throw ResourceError.missingWordPack }
        return try load(from: Data(contentsOf: url))
    }
}

enum ResourceError: Error, Equatable {
    case missingWordPack
    case invalidWordPack
    case invalidRuleVectors
}

struct RuleVectorFile: Decodable, Sendable {
    struct Encoding: Decodable, Sendable {
        let absent: Int
        let present: Int
        let correct: Int
    }

    struct Expected: Decodable, Sendable {
        let normalizedGuess: String?
        let validationError: GuessValidationError?
        let feedback: [Feedback]?
        let acceptedGuessCount: Int
        let roundState: RoundState
    }

    struct Case: Decodable, Sendable {
        let id: String
        let covers: [String]
        let answer: String
        let input: String
        let acceptedGuessesBefore: Int
        let expected: Expected
    }

    let formatVersion: Int
    let acceptedWordPackID: String
    let feedbackEncoding: Encoding
    let cases: [Case]

    static func load(from data: Data, wordPack: WordPack) throws -> RuleVectorFile {
        let vectors = try JSONDecoder().decode(RuleVectorFile.self, from: data)
        try vectors.validate(wordPack: wordPack)
        return vectors
    }

    private func validate(wordPack: WordPack) throws {
        guard formatVersion == 1,
              acceptedWordPackID == wordPack.id,
              feedbackEncoding.absent == 0,
              feedbackEncoding.present == 1,
              feedbackEncoding.correct == 2,
              !cases.isEmpty,
              Set(cases.map(\.id)).count == cases.count
        else { throw ResourceError.invalidRuleVectors }

        let accepted = Set(wordPack.words)
        for item in cases {
            guard !item.id.isEmpty,
                  item.covers.allSatisfy({ !$0.isEmpty }),
                  isLowercaseASCIIWord(item.answer),
                  accepted.contains(item.answer),
                  (0...5).contains(item.acceptedGuessesBefore),
                  (0...6).contains(item.expected.acceptedGuessCount)
            else { throw ResourceError.invalidRuleVectors }

            if let error = item.expected.validationError {
                guard item.expected.feedback == nil,
                      item.expected.acceptedGuessCount == item.acceptedGuessesBefore,
                      item.expected.roundState == .playing,
                      error == .nonAscii
                        ? item.expected.normalizedGuess == nil
                        : item.expected.normalizedGuess != nil
                else { throw ResourceError.invalidRuleVectors }
            } else {
                guard item.expected.normalizedGuess != nil,
                      item.expected.feedback?.count == 5,
                      item.expected.acceptedGuessCount == item.acceptedGuessesBefore + 1
                else { throw ResourceError.invalidRuleVectors }
            }
        }
    }
}

private func isLowercaseASCIIWord(_ word: String) -> Bool {
    word.utf8.count == 5 && word.utf8.allSatisfy { (97...122).contains($0) }
}
