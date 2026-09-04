import XCTest
@testable import GridRace

final class GameRulesTests: XCTestCase {
    func testCanonicalVectorsDecodeAndExecute() throws {
        let pack = try loadWordPack()
        let vectors = try loadVectors(wordPack: pack)
        let accepted = Set(pack.words)

        for item in vectors.cases {
            let actual = GameRules.submit(
                item.input,
                answer: item.answer,
                acceptedWords: accepted,
                acceptedGuessesBefore: item.acceptedGuessesBefore
            )
            XCTAssertEqual(actual.normalizedGuess, item.expected.normalizedGuess, item.id)
            XCTAssertEqual(actual.validationError, item.expected.validationError, item.id)
            XCTAssertEqual(actual.feedback, item.expected.feedback, item.id)
            XCTAssertEqual(actual.acceptedGuessCount, item.expected.acceptedGuessCount, item.id)
            XCTAssertEqual(actual.roundState, item.expected.roundState, item.id)
        }
    }

    func testVectorDecoderRejectsContractDrift() throws {
        let pack = try loadWordPack()
        let source = try vectorData()
        let json = try XCTUnwrap(String(data: source, encoding: .utf8))

        let wrongVersion = json.replacingOccurrences(
            of: "\"formatVersion\": 1",
            with: "\"formatVersion\": 2"
        )
        XCTAssertThrowsError(
            try RuleVectorFile.load(from: Data(wrongVersion.utf8), wordPack: pack)
        )

        let wrongEncoding = json.replacingOccurrences(
            of: "\"correct\": 2",
            with: "\"correct\": 9"
        )
        XCTAssertThrowsError(
            try RuleVectorFile.load(from: Data(wrongEncoding.utf8), wordPack: pack)
        )

        let duplicateID = json.replacingOccurrences(
            of: "\"id\": \"none-present\"",
            with: "\"id\": \"all-correct\""
        )
        XCTAssertThrowsError(
            try RuleVectorFile.load(from: Data(duplicateID.utf8), wordPack: pack)
        )
    }

    func testDuplicateFeedbackNeverExceedsAnswerFrequency() throws {
        let words = try loadWordPack().words
        for answer in words {
            for guess in words {
                let feedback = GameRules.evaluate(answer: answer, guess: guess)
                for letter in Set(guess) {
                    let credited = zip(guess, feedback).filter {
                        $0.0 == letter && $0.1 != .absent
                    }.count
                    XCTAssertLessThanOrEqual(
                        credited,
                        answer.filter { $0 == letter }.count,
                        "\(answer) / \(guess) / \(letter)"
                    )
                }
            }
        }
    }

    func testValidationPrecedenceAndNormalization() throws {
        let accepted = Set(try loadWordPack().words)
        XCTAssertEqual(
            GameRules.submit("stöne", answer: "stone", acceptedWords: accepted, acceptedGuessesBefore: 0)
                .validationError,
            .nonAscii
        )
        XCTAssertEqual(
            GameRules.submit("FOUR", answer: "stone", acceptedWords: accepted, acceptedGuessesBefore: 0)
                .validationError,
            .invalidLength
        )
        XCTAssertEqual(
            GameRules.submit("ST0NE", answer: "stone", acceptedWords: accepted, acceptedGuessesBefore: 0)
                .validationError,
            .invalidCharacter
        )
        XCTAssertEqual(
            GameRules.submit("ZZZZZ", answer: "stone", acceptedWords: accepted, acceptedGuessesBefore: 0)
                .validationError,
            .notAccepted
        )
        XCTAssertEqual(
            GameRules.submit("STONE", answer: "stone", acceptedWords: accepted, acceptedGuessesBefore: 0)
                .normalizedGuess,
            "stone"
        )
    }

    func testInvalidGuessDoesNotConsumeBoardRow() throws {
        var board = BoardState(answer: "stone", acceptedWords: Set(try loadWordPack().words))
        board.type("Z")
        board.type("Z")
        board.type("Z")
        board.type("Z")
        board.type("Z")

        let result = try XCTUnwrap(board.submitDraft())
        XCTAssertEqual(result.validationError, .notAccepted)
        XCTAssertEqual(board.rows.count, 0)
        XCTAssertEqual(board.draft, "ZZZZZ")
        XCTAssertEqual(board.status, .playing)
    }

    func testBoardSolveWinsOnSixthGuessAndIncorrectSixthFails() throws {
        let accepted = Set(try loadWordPack().words)
        var solved = BoardState(answer: "stone", acceptedWords: accepted)
        for _ in 0..<5 {
            type("civic", into: &solved)
            solved.submitDraft()
        }
        type("stone", into: &solved)
        solved.submitDraft()
        XCTAssertEqual(solved.rows.count, 6)
        XCTAssertEqual(solved.status, .solved)

        var failed = BoardState(answer: "stone", acceptedWords: accepted)
        for _ in 0..<6 {
            type("civic", into: &failed)
            failed.submitDraft()
        }
        XCTAssertEqual(failed.rows.count, 6)
        XCTAssertEqual(failed.status, .failed)
    }

    func testExcessGuessRepeatVectorMatchesCanonicalFeedback() {
        // Canonical vector `excess-guess-repeat`: answer `grape`, guess `apple`.
        XCTAssertEqual(
            GameRules.evaluate(answer: "grape", guess: "apple"),
            [.present, .present, .absent, .absent, .correct]
        )
    }

    func testKeyboardEvidenceNeverDowngrades() {
        var keyboard = KeyboardState()
        keyboard.observe(GuessRow(word: "civic", feedback: [.absent, .absent, .absent, .absent, .absent]))
        keyboard.observe(GuessRow(word: "civic", feedback: [.correct, .present, .absent, .absent, .absent]))
        keyboard.observe(GuessRow(word: "civic", feedback: [.present, .absent, .absent, .absent, .absent]))
        XCTAssertEqual(keyboard.feedback(for: "C"), .correct)
        XCTAssertEqual(keyboard.feedback(for: "I"), .present)
    }

    func testBoardCanBeExternallyTimedOut() throws {
        var board = BoardState(answer: "stone", acceptedWords: Set(try loadWordPack().words))
        board.type("S")
        board.timeOut()
        XCTAssertEqual(board.status, .timedOut)
        XCTAssertEqual(board.draft, "")
        board.type("T")
        XCTAssertEqual(board.draft, "")
    }

    private func type(_ word: String, into board: inout BoardState) {
        for letter in word { board.type(letter) }
    }

    private func loadWordPack() throws -> WordPack {
        guard let url = testBundle.url(
            forResource: "development-en-US-v1",
            withExtension: "json"
        ) else { throw ResourceError.missingWordPack }
        return try WordPack.load(from: Data(contentsOf: url))
    }

    private func loadVectors(wordPack: WordPack) throws -> RuleVectorFile {
        try RuleVectorFile.load(from: vectorData(), wordPack: wordPack)
    }

    private func vectorData() throws -> Data {
        guard let url = testBundle.url(forResource: "game-rules-v1", withExtension: "json") else {
            throw ResourceError.invalidRuleVectors
        }
        return try Data(contentsOf: url)
    }

    private var testBundle: Bundle {
        Bundle(for: Self.self)
    }
}
