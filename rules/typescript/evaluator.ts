export type Feedback = 0 | 1 | 2;
export type FeedbackResult = [Feedback, Feedback, Feedback, Feedback, Feedback];
export type ValidationError =
  | "nonAscii"
  | "invalidLength"
  | "invalidCharacter"
  | "notAccepted";
export type RoundState = "playing" | "solved" | "failed";

export interface SubmissionResult {
  normalizedGuess: string | null;
  validationError: ValidationError | null;
  feedback: FeedbackResult | null;
  acceptedGuessCount: number;
  roundState: RoundState;
}

export interface AcceptedWordPack {
  id: "development-en-US-v1";
  words: ReadonlySet<string>;
}

export interface RuleVectorCase {
  id: string;
  covers: string[];
  answer: string;
  input: string;
  acceptedGuessesBefore: number;
  expected: SubmissionResult;
}

export interface RuleVectorContract {
  formatVersion: 1;
  acceptedWordPackID: "development-en-US-v1";
  feedbackEncoding: { absent: 0; present: 1; correct: 2 };
  cases: RuleVectorCase[];
}

const WORD = /^[a-z]{5}$/;
const VALIDATION_ERRORS = [
  "nonAscii",
  "invalidLength",
  "invalidCharacter",
  "notAccepted",
] as const;
const ROUND_STATES = ["playing", "solved", "failed"] as const;

function require(condition: boolean, message: string): asserts condition {
  if (!condition) throw new TypeError(message);
}

function record(value: unknown, path: string): Record<string, unknown> {
  require(
    typeof value === "object" && value !== null && !Array.isArray(value),
    `${path} must be an object`,
  );
  return value as Record<string, unknown>;
}

function array(value: unknown, path: string): unknown[] {
  require(Array.isArray(value), `${path} must be an array`);
  return value;
}

function string(value: unknown, path: string): string {
  require(typeof value === "string", `${path} must be a string`);
  return value;
}

function integer(
  value: unknown,
  minimum: number,
  maximum: number,
  path: string,
): number {
  require(
    typeof value === "number" && Number.isInteger(value) &&
      value >= minimum && value <= maximum,
    `${path} must be an integer from ${minimum} through ${maximum}`,
  );
  return value;
}

function member<const Values extends readonly string[]>(
  value: unknown,
  values: Values,
  path: string,
): Values[number] {
  require(
    typeof value === "string" && values.includes(value),
    `${path} has an unsupported value`,
  );
  return value as Values[number];
}

function validWord(value: unknown, path: string): string {
  const word = string(value, path);
  require(WORD.test(word), `${path} must be five lowercase ASCII letters`);
  return word;
}

function decodeFeedback(value: unknown, path: string): FeedbackResult | null {
  if (value === null) return null;
  const values = array(value, path);
  require(values.length === 5, `${path} must contain five values`);
  return values.map((item, index) =>
    integer(item, 0, 2, `${path}[${index}]`)
  ) as FeedbackResult;
}

function decodeExpected(
  value: unknown,
  before: number,
  path: string,
): SubmissionResult {
  const expected = record(value, path);
  const normalizedGuess = expected.normalizedGuess === null
    ? null
    : string(expected.normalizedGuess, `${path}.normalizedGuess`);
  const validationError = expected.validationError === null ? null : member(
    expected.validationError,
    VALIDATION_ERRORS,
    `${path}.validationError`,
  );
  const feedback = decodeFeedback(expected.feedback, `${path}.feedback`);
  const acceptedGuessCount = integer(
    expected.acceptedGuessCount,
    0,
    6,
    `${path}.acceptedGuessCount`,
  );
  const roundState = member(
    expected.roundState,
    ROUND_STATES,
    `${path}.roundState`,
  );

  if (validationError === null) {
    require(
      normalizedGuess !== null,
      `${path}.normalizedGuess is required when accepted`,
    );
    require(feedback !== null, `${path}.feedback is required when accepted`);
    require(
      acceptedGuessCount === before + 1,
      `${path}.acceptedGuessCount must increment once`,
    );
  } else {
    require(feedback === null, `${path}.feedback must be null when rejected`);
    require(
      acceptedGuessCount === before,
      `${path}.acceptedGuessCount must not change`,
    );
    require(roundState === "playing", `${path}.roundState must remain playing`);
    require(
      (validationError === "nonAscii") === (normalizedGuess === null),
      `${path}.normalizedGuess does not match validation precedence`,
    );
  }

  return {
    normalizedGuess,
    validationError,
    feedback,
    acceptedGuessCount,
    roundState,
  };
}

export function decodeAcceptedWordPack(value: unknown): AcceptedWordPack {
  const pack = record(value, "wordPack");
  require(pack.formatVersion === 1, "wordPack.formatVersion must be 1");
  require(pack.id === "development-en-US-v1", "wordPack.id is unsupported");
  require(pack.locale === "en-US", "wordPack.locale must be en-US");
  require(pack.wordLength === 5, "wordPack.wordLength must be 5");

  const values = array(pack.words, "wordPack.words");
  require(values.length === 100, "wordPack.words must contain 100 words");
  const words = new Set<string>();
  for (const [index, value] of values.entries()) {
    const word = validWord(value, `wordPack.words[${index}]`);
    require(!words.has(word), `wordPack.words contains duplicate ${word}`);
    words.add(word);
  }
  return { id: "development-en-US-v1", words };
}

export function decodeRuleVectors(
  value: unknown,
  wordPack: AcceptedWordPack,
): RuleVectorContract {
  const root = record(value, "vectors");
  require(root.formatVersion === 1, "vectors.formatVersion must be 1");
  require(
    root.acceptedWordPackID === wordPack.id,
    "vectors.acceptedWordPackID is unsupported",
  );
  const encoding = record(root.feedbackEncoding, "vectors.feedbackEncoding");
  require(
    encoding.absent === 0 && encoding.present === 1 && encoding.correct === 2,
    "vectors.feedbackEncoding must be absent=0, present=1, correct=2",
  );

  const rawCases = array(root.cases, "vectors.cases");
  require(rawCases.length > 0, "vectors.cases must not be empty");
  const ids = new Set<string>();
  const cases = rawCases.map((value, index): RuleVectorCase => {
    const path = `vectors.cases[${index}]`;
    const item = record(value, path);
    const id = string(item.id, `${path}.id`);
    require(id.trim().length > 0, `${path}.id must not be empty`);
    require(!ids.has(id), `${path}.id duplicates ${id}`);
    ids.add(id);

    const covers = array(item.covers, `${path}.covers`).map(
      (value, coverIndex) => {
        const cover = string(value, `${path}.covers[${coverIndex}]`);
        require(
          cover.trim().length > 0,
          `${path}.covers[${coverIndex}] must not be empty`,
        );
        return cover;
      },
    );
    const answer = validWord(item.answer, `${path}.answer`);
    require(
      wordPack.words.has(answer),
      `${path}.answer is absent from the word pack`,
    );
    const input = string(item.input, `${path}.input`);
    const acceptedGuessesBefore = integer(
      item.acceptedGuessesBefore,
      0,
      5,
      `${path}.acceptedGuessesBefore`,
    );

    return {
      id,
      covers,
      answer,
      input,
      acceptedGuessesBefore,
      expected: decodeExpected(
        item.expected,
        acceptedGuessesBefore,
        `${path}.expected`,
      ),
    };
  });

  return {
    formatVersion: 1,
    acceptedWordPackID: "development-en-US-v1",
    feedbackEncoding: { absent: 0, present: 1, correct: 2 },
    cases,
  };
}

export function evaluateFeedback(
  answer: string,
  guess: string,
): FeedbackResult {
  require(WORD.test(answer), "answer must be five lowercase ASCII letters");
  require(WORD.test(guess), "guess must be five lowercase ASCII letters");

  const result: FeedbackResult = [0, 0, 0, 0, 0];
  const remaining = new Array<number>(26).fill(0);
  for (const letter of answer) remaining[letter.charCodeAt(0) - 97]++;

  for (let index = 0; index < 5; index++) {
    if (answer[index] === guess[index]) {
      result[index] = 2;
      remaining[guess.charCodeAt(index) - 97]--;
    }
  }
  for (let index = 0; index < 5; index++) {
    const letter = guess.charCodeAt(index) - 97;
    if (result[index] === 0 && remaining[letter] > 0) {
      result[index] = 1;
      remaining[letter]--;
    }
  }
  return result;
}

export function submitGuess(
  answer: string,
  input: string,
  acceptedWords: ReadonlySet<string>,
  acceptedGuessesBefore: number,
): SubmissionResult {
  require(WORD.test(answer), "answer must be five lowercase ASCII letters");
  integer(acceptedGuessesBefore, 0, 5, "acceptedGuessesBefore");

  for (const character of input) {
    if ((character.codePointAt(0) ?? 128) > 127) {
      return {
        normalizedGuess: null,
        validationError: "nonAscii",
        feedback: null,
        acceptedGuessCount: acceptedGuessesBefore,
        roundState: "playing",
      };
    }
  }

  const normalizedGuess = input.replace(
    /[A-Z]/g,
    (character) => String.fromCharCode(character.charCodeAt(0) + 32),
  );
  let validationError: ValidationError | null = null;
  if (normalizedGuess.length !== 5) validationError = "invalidLength";
  else if (!WORD.test(normalizedGuess)) validationError = "invalidCharacter";
  else if (!acceptedWords.has(normalizedGuess)) validationError = "notAccepted";

  if (validationError !== null) {
    return {
      normalizedGuess,
      validationError,
      feedback: null,
      acceptedGuessCount: acceptedGuessesBefore,
      roundState: "playing",
    };
  }

  const feedback = evaluateFeedback(answer, normalizedGuess);
  const acceptedGuessCount = acceptedGuessesBefore + 1;
  return {
    normalizedGuess,
    validationError: null,
    feedback,
    acceptedGuessCount,
    roundState: normalizedGuess === answer
      ? "solved"
      : acceptedGuessCount === 6
      ? "failed"
      : "playing",
  };
}
