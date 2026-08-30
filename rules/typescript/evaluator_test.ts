import {
  decodeAcceptedWordPack,
  decodeRuleVectors,
  evaluateFeedback,
  submitGuess,
} from "./evaluator.ts";

const wordPackJSON: unknown = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../../shared/word-packs/development-en-US-v1.json",
      import.meta.url,
    ),
  ),
);
const vectorJSON: unknown = JSON.parse(
  await Deno.readTextFile(
    new URL("../../shared/test-vectors/game-rules-v1.json", import.meta.url),
  ),
);
const wordPack = decodeAcceptedWordPack(wordPackJSON);
const vectors = decodeRuleVectors(vectorJSON, wordPack);

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  const actualJSON = JSON.stringify(actual);
  const expectedJSON = JSON.stringify(expected);
  assert(
    actualJSON === expectedJSON,
    `${message}: ${actualJSON} != ${expectedJSON}`,
  );
}

function assertThrows(action: () => void, message: string): void {
  try {
    action();
  } catch {
    return;
  }
  throw new Error(`${message}: expected an error`);
}

function mutableRecord(value: unknown): Record<string, unknown> {
  assert(
    typeof value === "object" && value !== null && !Array.isArray(value),
    "object expected",
  );
  return value as Record<string, unknown>;
}

function mutableCases(
  root: Record<string, unknown>,
): Record<string, unknown>[] {
  assert(Array.isArray(root.cases), "cases expected");
  return root.cases.map(mutableRecord);
}

Deno.test("canonical vectors decode and execute every required rule", () => {
  const coverage = new Set<string>();
  for (const vector of vectors.cases) {
    vector.covers.forEach((item) => coverage.add(item));
    assertEquals(
      submitGuess(
        vector.answer,
        vector.input,
        wordPack.words,
        vector.acceptedGuessesBefore,
      ),
      vector.expected,
      vector.id,
    );
  }

  const requiredCoverage = [
    "allLettersCorrect",
    "noLettersPresent",
    "repeatedLetterInAnswer",
    "moreRepeatedLettersInGuessThanAnswer",
    "exactMatchesConsumeDuplicateCounts",
    "multipleDuplicateInteractions",
    "uppercaseNormalization",
    "invalidLength",
    "nonAsciiInput",
    "invalidAsciiCharacter",
    "unknownAcceptedWord",
    "sixthGuessFailure",
    "solveOnFinalGuess",
  ];
  for (const requirement of requiredCoverage) {
    assert(
      coverage.has(requirement),
      `missing vector coverage: ${requirement}`,
    );
  }
});

Deno.test("duplicate feedback never credits more copies than the answer", () => {
  const alphabet = "abc";
  const sample: string[] = [];
  for (let number = 0; number < alphabet.length ** 5; number++) {
    let remainder = number;
    let word = "";
    for (let position = 0; position < 5; position++) {
      word += alphabet[remainder % alphabet.length];
      remainder = Math.floor(remainder / alphabet.length);
    }
    sample.push(word);
  }

  for (const answer of sample) {
    for (const guess of sample) {
      const feedback = evaluateFeedback(answer, guess);
      for (const letter of alphabet) {
        let answerCount = 0;
        let creditedCount = 0;
        for (let index = 0; index < 5; index++) {
          if (answer[index] === letter) answerCount++;
          if (guess[index] === letter && feedback[index] > 0) creditedCount++;
          if (answer[index] === guess[index]) {
            assert(
              feedback[index] === 2,
              `${answer}/${guess} missed exact position ${index}`,
            );
          }
        }
        assert(
          creditedCount <= answerCount,
          `${answer}/${guess} over-credited ${letter}`,
        );
      }
    }
  }
});

Deno.test("vector decoder rejects malformed contracts and tolerates extra fields", () => {
  const corruptions: Array<[
    string,
    (root: Record<string, unknown>, cases: Record<string, unknown>[]) => void,
  ]> = [
    ["version", (root) => root.formatVersion = 2],
    ["pack", (root) => root.acceptedWordPackID = "other-pack"],
    ["encoding", (root) => mutableRecord(root.feedbackEncoding).correct = 1],
    ["empty id", (_root, cases) => cases[0].id = ""],
    ["duplicate id", (_root, cases) => cases[1].id = cases[0].id],
    ["field type", (_root, cases) => cases[0].input = 5],
    ["count", (_root, cases) => cases[0].acceptedGuessesBefore = 6],
    [
      "state",
      (_root, cases) =>
        mutableRecord(cases[0].expected).roundState = "timedOut",
    ],
    [
      "feedback",
      (_root, cases) =>
        mutableRecord(cases[0].expected).feedback = [2, 2, 2, 2],
    ],
    ["malformed answer", (_root, cases) => cases[0].answer = "Stone"],
    ["unknown answer", (_root, cases) => cases[0].answer = "zzzzz"],
  ];

  for (const [label, corrupt] of corruptions) {
    const copy = mutableRecord(structuredClone(vectorJSON));
    corrupt(copy, mutableCases(copy));
    assertThrows(() => decodeRuleVectors(copy, wordPack), label);
  }

  const compatible = mutableRecord(structuredClone(vectorJSON));
  compatible.futureField = true;
  mutableCases(compatible)[0].futureField = "ignored";
  decodeRuleVectors(compatible, wordPack);
});
