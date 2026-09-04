import SwiftUI

struct TutorialView: View {
    @Bindable var model: TutorialModel
    @Binding var hapticsEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            switch model.phase {
            case .introduction:
                IntroductionView(model: model)
            case .countdown:
                CountdownView(seconds: model.countdownSeconds)
            case .playing:
                RaceView(model: model)
            case .reveal:
                RevealView(model: model)
            }
        }
        .tint(Color.raceIndigo)
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, value in model.setReduceMotion(value) }
        .onChange(of: scenePhase) { _, value in
            if value == .active { model.refreshFromClock() }
        }
        .onDisappear { model.replay() }
        .sensoryFeedback(trigger: model.hapticEvent) { _, _ in
            hapticsEnabled ? .impact(weight: .light) : nil
        }
    }
}

private struct IntroductionView: View {
    @Bindable var model: TutorialModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Color.raceIndigo)
                    .accessibilityHidden(true)
                Text("GridRace Tutorial")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Solve the same five-letter word while Alex and Sam race beside you.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Label(
                    "Opponent letters, feedback, and keyboard clues stay private during play.",
                    systemImage: "eye.slash.fill"
                )
                .font(.body.weight(.semibold))
                .padding()
                .background(Color.raceInset, in: RoundedRectangle(cornerRadius: 18))
                Text("This is an on-device practice race. Its answer and ghost moves are bundled with the app; production games will rely on the server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Start local race") {
                    model.startTutorial()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 44)
                NavigationLink(value: AppRoute.settings) {
                    Label("Haptics and contrast live in Settings", systemImage: "gearshape")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.raceIndigo)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CountdownView: View {
    let seconds: Int
    // U-06: countdown -> focus countdown label (announcement off).
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Local race starts in")
                .font(.title2)
            Text("\(seconds)")
                .font(.system(size: 92, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.raceCoral)
                .contentTransition(.numericText())
            // Determinate 3-second progress; presentation only, hidden from
            // VoiceOver so the combined label above stays the single speech.
            ProgressView(value: Double(3 - seconds), total: 3)
                .frame(maxWidth: 220)
                .accessibilityHidden(true)
            Text("The deadline uses absolute timestamps and does not pause in the background.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Local race starts in \(seconds)")
        .accessibilityFocused($focused)
        .onAppear { focused = true }
    }
}

/// Structured error banner (U-01 contract, defined once here). Props:
/// `message: String`, `retry: (() -> Void)?`. Single-speech behavior: this view
/// never posts an announcement; the owning screen moves focus to the banner per
/// the U-06 state-to-focus map (focus or announcement, never both).
struct RaceErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.raceDanger)
                .accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.raceDanger)
        .multilineTextAlignment(.leading)
        .padding(14)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.raceDanger, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RaceView: View {
    @Bindable var model: TutorialModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // U-06 + R-01/F1: invalid/incomplete draft -> focus error banner
    // (announcement off). A per-submit generation mints a fresh focus value
    // so an identical-error resubmit refires (same-value assignment would
    // coalesce and never move focus).
    @AccessibilityFocusState private var errorFocus: Int?
    @State private var errorGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local tutorial")
                                .font(.headline)
                            Text("Clue-free opponent progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("\(model.roundSecondsRemaining)s", systemImage: "timer")
                            .font(.headline.monospacedDigit())
                            .accessibilityLabel("\(model.roundSecondsRemaining) seconds remaining")
                    }
                    .padding(.horizontal)

                    OpponentStrip(opponents: model.opponents)
                    BoardView(
                        rows: model.board.rows,
                        draft: model.board.draft,
                        isPlaying: model.board.status == .playing
                    )
                        .padding(.horizontal)
                        // Subtle invalid-guess nudge; fully suppressed under
                        // Reduce Motion (banner + existing haptics only).
                        .offset(x: (model.errorMessage != nil && !reduceMotion) ? 6 : 0)
                        .animation(reduceMotion ? nil : .snappy, value: model.errorMessage)

                    if let error = model.errorMessage {
                        RaceErrorBanner(message: error)
                            .padding(.horizontal)
                            .accessibilityFocused($errorFocus, equals: errorGeneration)
                            .onAppear { errorFocus = errorGeneration }
                    } else {
                        Text("Type a five-letter word from the tutorial list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }

            KeyboardView(model: model) {
                errorGeneration += 1
                errorFocus = model.errorMessage != nil ? errorGeneration : nil
            }
            .padding(.vertical, 8)
            .background(Color.racePage)
            .overlay(alignment: .top) {
                Color.raceLine.frame(height: 1)
            }
        }
    }
}

/// Split-time opponent rows. Shows only already-visible live fields (avatar,
/// name, accepted count `n/6`, connection presentation, coarse state) in stable
/// roster order. Never position, placement, gap-as-rank, exact timing, words,
/// feedback, or keyboard state.
private struct OpponentStrip: View {
    let opponents: [OpponentProgress]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(opponents) { opponent in
                HStack(spacing: 12) {
                    Image(systemName: opponent.avatarSymbol)
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(Color.raceInset, in: Circle())
                        .foregroundStyle(Color.raceIndigo)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opponent.name).font(.headline)
                        HStack(spacing: 6) {
                            Text("\(opponent.acceptedGuessCount)/6")
                                .font(.subheadline.monospacedDigit())
                                .fixedSize(horizontal: true, vertical: false)
                                .contentTransition(.numericText())
                            Image(systemName: opponent.isConnected ? "wifi" : "wifi.slash")
                                .font(.caption2.bold())
                                .foregroundStyle(opponent.isConnected ? Color.raceTeal : Color.raceDanger)
                                .accessibilityHidden(true)
                            Text(opponent.isConnected ? "Connected" : "Disconnected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Label(
                        opponent.state.spokenDescription.capitalized,
                        systemImage: opponent.state == .playing
                            ? "hourglass" : "flag.checkered"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.raceInset, in: Capsule())
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.raceLine, lineWidth: 1.5)
                }
                .animation(reduceMotion ? nil : .snappy, value: opponent.acceptedGuessCount)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(opponent.accessibilityLabel)
            }
        }
        .padding(.horizontal)
    }
}

struct BoardView: View {
    let rows: [GuessRow]
    let draft: String
    let isPlaying: Bool
    var highContrast = false

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { columnIndex in
                        let tile = tile(row: rowIndex, column: columnIndex)
                        TileView(
                            letter: tile.letter,
                            feedback: tile.feedback,
                            isDraft: tile.isDraft,
                            emptyLabel: "Empty tile, row \(rowIndex + 1), column \(columnIndex + 1)",
                            highContrast: highContrast
                        )
                    }
                }
            }
        }
        .frame(maxWidth: 350)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your six-row game board")
    }

    private func tile(row: Int, column: Int) -> (letter: Character?, feedback: Feedback?, isDraft: Bool) {
        if rows.indices.contains(row) {
            let accepted = rows[row]
            return (Array(accepted.word.uppercased())[column], accepted.feedback[column], false)
        }
        if row == rows.count, isPlaying {
            let letters = Array(draft)
            return (letters.indices.contains(column) ? letters[column] : nil, nil, true)
        }
        return (nil, nil, false)
    }
}

struct TileView: View {
    let letter: Character?
    let feedback: Feedback?
    let isDraft: Bool
    let emptyLabel: String
    var highContrast = false

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: borderWidth)
            // Lane-edge signature: a bold leading edge carries feedback meaning
            // alongside the symbol and accessible label, never color alone.
            if feedback != nil {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 5)
                        .padding(.vertical, 7)
                        .padding(.leading, 5)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
            }
            if let letter {
                Text(String(letter).uppercased())
                    .font(.title2)
                    .fontWeight(isDraft || legibilityWeight == .bold ? .black : .bold)
                    .foregroundStyle(feedback == nil ? Color.raceInk : Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let feedback {
                Image(systemName: feedback.symbolName)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        guard let feedback else { return isDraft ? Color.raceCard : Color.raceInset }
        switch feedback {
        case .absent: return Color.raceTeal
        case .present: return Color.raceCoral
        case .correct: return Color.raceIndigo
        }
    }

    private var borderColor: Color {
        if isHighContrast { return .black }
        if feedback != nil { return .white }
        return isDraft ? Color.raceLineEmphasis : Color.raceLine
    }

    private var borderWidth: CGFloat {
        if isHighContrast { return 3 }
        if feedback != nil { return 1.5 }
        return isDraft ? 2.5 : 1.5
    }

    private var accessibilityLabel: String {
        guard let letter else { return emptyLabel }
        if let feedback {
            return "Letter \(letter), \(feedback.accessibilityMeaning)."
        }
        return "Letter \(letter), draft."
    }

    private var isHighContrast: Bool { highContrast || contrast == .increased }
}

private struct KeyboardView: View {
    @Bindable var model: TutorialModel
    var onSubmitAttempt: () -> Void = {}

    var body: some View {
        LetterKeyboardView(
            keyboard: model.board.keyboard,
            typeLetter: model.typeLetter,
            submit: {
                model.submitGuess()
                onSubmitAttempt()
            },
            delete: model.deleteLetter
        )
    }
}

struct LetterKeyboardView: View {
    let keyboard: KeyboardState
    let typeLetter: (Character) -> Void
    let submit: () -> Void
    let delete: () -> Void
    var highContrast = false

    private let rows = [Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]

    var body: some View {
        VStack(spacing: 5) {
            letterRow(rows[0])
            letterRow(rows[1]).padding(.horizontal, 14)
            HStack(spacing: 4) {
                Button(action: submit) {
                    Image(systemName: "return")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .keyboardActionStyle()
                .accessibilityLabel("Submit guess")

                ForEach(rows[2], id: \.self) { letter in
                    KeyboardKey(
                        letter: letter,
                        feedback: keyboard.feedback(for: letter),
                        highContrast: highContrast
                    ) { typeLetter(letter) }
                }

                Button(action: delete) {
                    Image(systemName: "delete.left")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .keyboardActionStyle()
                .accessibilityLabel("Delete letter")
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letter keyboard")
    }

    private func letterRow(_ letters: [Character]) -> some View {
        HStack(spacing: 4) {
            ForEach(letters, id: \.self) { letter in
                KeyboardKey(
                    letter: letter,
                    feedback: keyboard.feedback(for: letter),
                    highContrast: highContrast
                ) { typeLetter(letter) }
            }
        }
    }
}

struct KeyboardKey: View {
    let letter: Character
    let feedback: Feedback?
    var highContrast = false
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(String(letter))
                    .font(.callout.bold())
                if let feedback {
                    Image(systemName: feedback.symbolName)
                        .font(.system(size: 11, weight: .black))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(feedback == nil ? Color.raceInk : Color.white)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHighContrast ? Color.black : Color.raceLine,
                        lineWidth: isHighContrast ? 2.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        switch feedback {
        case .none: Color.raceCard
        case .absent: Color.raceTeal
        case .present: Color.raceCoral
        case .correct: Color.raceIndigo
        }
    }

    private var accessibilityLabel: String {
        guard let feedback else { return "Letter \(letter)" }
        return "Letter \(letter), \(feedback.accessibilityMeaning)."
    }

    private var isHighContrast: Bool { highContrast || contrast == .increased }
}

private extension View {
    func keyboardActionStyle() -> some View {
        buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.raceIndigo, in: RoundedRectangle(cornerRadius: 10))
            .frame(minWidth: 44)
            .contentShape(Rectangle())
    }
}

/// U-06 reveal focus (one speech owner per transition, never both):
/// reveal answer -> focus answer capsule on appear; animated rows -> focus each
/// completed row, then the summary; Reduce Motion -> full state immediately,
/// focus the answer first, manual traversal answer -> boards -> rows -> summary.
enum RevealFocus: Hashable {
    case answer
    case row(Int)
    case summary
}

private struct RevealView: View {
    @Bindable var model: TutorialModel
    @AccessibilityFocusState private var focus: RevealFocus?

    private var totalRevealRows: Int {
        model.revealBoards.reduce(0) { $0 + $1.rows.count }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Local reveal")
                    .font(.largeTitle.bold())
                Text("Answer: \(TutorialModel.answer.uppercased())")
                    .font(.title2.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.raceInset, in: Capsule())
                    .accessibilityFocused($focus, equals: .answer)

                ForEach(Array(model.revealBoards.enumerated()), id: \.element.id) { index, board in
                    let base = model.revealBoards.prefix(index).reduce(0) { $0 + $1.rows.count }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(board.name).font(.headline)
                            Spacer()
                            Text(board.result)
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                        ForEach(
                            Array(board.rows.prefix(model.visibleRows(in: index)).enumerated()),
                            id: \.offset
                        ) { rowOffset, row in
                            RevealRowView(row: row)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(board.name), row \(rowOffset + 1)")
                                .accessibilityFocused($focus, equals: .row(base + rowOffset))
                        }
                    }
                    .padding()
                    .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.raceLine, lineWidth: 1.5)
                    }
                }

                if model.revealSummaryVisible {
                    Text(model.comparisonSummary)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.raceInset, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityFocused($focus, equals: .summary)
                    Button("Replay tutorial") { model.replay() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: 560)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .animation(model.prefersReducedMotion ? nil : .easeOut(duration: 0.25), value: model.visibleRevealRowCount)
        .onAppear {
            if model.prefersReducedMotion {
                focus = .answer
            } else if totalRevealRows == 0, model.revealSummaryVisible {
                focus = .summary
            }
        }
        .onChange(of: model.visibleRevealRowCount) {
            guard !model.prefersReducedMotion else { return }
            if model.revealSummaryVisible, model.visibleRevealRowCount >= totalRevealRows {
                focus = .summary
            } else if model.visibleRevealRowCount > 0 {
                focus = .row(model.visibleRevealRowCount - 1)
            }
        }
        .onChange(of: model.prefersReducedMotion) {
            if model.prefersReducedMotion { focus = .answer }
        }
    }
}

private struct RevealRowView: View {
    let row: GuessRow

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                TileView(
                    letter: Array(row.word.uppercased())[index],
                    feedback: row.feedback[index],
                    isDraft: false,
                    emptyLabel: ""
                )
            }
        }
        .frame(maxWidth: 320)
    }
}

extension Color {
    // Race adaptive tokens (U-01 frozen shape). Light/dark hexes in comments.
    // Surfaces: racePage light #F7F2E9 / dark #141222; raceCard light #FFFFFF /
    // dark #232040; raceInset light #ECE5D8 / dark #171627. Borders-only depth
    // on app-owned surfaces; native Form/.alert/sheets stay system-owned.
    // Ink: raceInk light #1C1A24 / dark #F5F2EA; raceInkSecondary light #4E4B57 /
    // dark #C9C5D6; raceInkTertiary light #6F6C77 / dark #A8A4B8.
    // Lines: raceLine light #D8D2C4 / dark #3A3654; raceLineSoft light #E5DFD2 /
    // dark #2B2942; raceLineEmphasis light #3D3394 / dark #B7B0FF.
    // Hues (no green/yellow): raceIndigo light #3D3394 / dark #7B74E8;
    // raceCoral light #C74F33 / dark #E0704F; raceTeal light #0D6B78 / dark
    // #3A9AA8. Feedback fills keep white labels at >=3:1 in both appearances.
    // raceDanger light #B3261E / dark #FFB4A8.
    // Radius scale (frozen, enforced by literals in views): control 10, card 18,
    // sheet 26; Circle avatars and Capsule bars/answer pill excepted. Spacing
    // base 4pt (4/8/12/16/20/24). Type roles scale with Dynamic Type; no fixed
    // 92/56/44pt without .minimumScaleFactor or scaled-metric equivalents.
    private static func raceDynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let racePage: Color = raceDynamic(
        light: UIColor(red: 0.968, green: 0.949, blue: 0.914, alpha: 1),
        dark: UIColor(red: 0.078, green: 0.071, blue: 0.133, alpha: 1)
    )
    static let raceCard: Color = raceDynamic(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.137, green: 0.125, blue: 0.251, alpha: 1)
    )
    static let raceInset: Color = raceDynamic(
        light: UIColor(red: 0.925, green: 0.898, blue: 0.847, alpha: 1),
        dark: UIColor(red: 0.090, green: 0.086, blue: 0.153, alpha: 1)
    )
    static let raceInk: Color = raceDynamic(
        light: UIColor(red: 0.110, green: 0.102, blue: 0.141, alpha: 1),
        dark: UIColor(red: 0.961, green: 0.949, blue: 0.918, alpha: 1)
    )
    static let raceInkSecondary: Color = raceDynamic(
        light: UIColor(red: 0.306, green: 0.294, blue: 0.341, alpha: 1),
        dark: UIColor(red: 0.788, green: 0.773, blue: 0.839, alpha: 1)
    )
    static let raceInkTertiary: Color = raceDynamic(
        light: UIColor(red: 0.435, green: 0.424, blue: 0.467, alpha: 1),
        dark: UIColor(red: 0.659, green: 0.643, blue: 0.722, alpha: 1)
    )
    static let raceLine: Color = raceDynamic(
        light: UIColor(red: 0.847, green: 0.824, blue: 0.769, alpha: 1),
        dark: UIColor(red: 0.227, green: 0.212, blue: 0.329, alpha: 1)
    )
    static let raceLineSoft: Color = raceDynamic(
        light: UIColor(red: 0.898, green: 0.875, blue: 0.824, alpha: 1),
        dark: UIColor(red: 0.169, green: 0.161, blue: 0.259, alpha: 1)
    )
    static let raceLineEmphasis: Color = raceDynamic(
        light: UIColor(red: 0.239, green: 0.200, blue: 0.580, alpha: 1),
        dark: UIColor(red: 0.718, green: 0.690, blue: 1.0, alpha: 1)
    )
    static let raceBackground: Color = racePage
    static let raceIndigo: Color = raceDynamic(
        light: UIColor(red: 0.239, green: 0.200, blue: 0.580, alpha: 1),
        dark: UIColor(red: 0.482, green: 0.455, blue: 0.910, alpha: 1)
    )
    static let raceCoral: Color = raceDynamic(
        light: UIColor(red: 0.780, green: 0.310, blue: 0.200, alpha: 1),
        dark: UIColor(red: 0.878, green: 0.439, blue: 0.310, alpha: 1)
    )
    static let raceTeal: Color = raceDynamic(
        light: UIColor(red: 0.051, green: 0.420, blue: 0.470, alpha: 1),
        dark: UIColor(red: 0.227, green: 0.604, blue: 0.659, alpha: 1)
    )
    static let raceDanger: Color = raceDynamic(
        light: UIColor(red: 0.702, green: 0.149, blue: 0.118, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.706, blue: 0.659, alpha: 1)
    )
}
