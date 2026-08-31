import SwiftUI

struct TutorialView: View {
    @Bindable var model: TutorialModel
    @Binding var hapticsEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.raceBackground.ignoresSafeArea()
            switch model.phase {
            case .introduction:
                IntroductionView(model: model, hapticsEnabled: $hapticsEnabled)
            case .countdown:
                CountdownView(seconds: model.countdownSeconds)
            case .playing:
                RaceView(model: model, hapticsEnabled: $hapticsEnabled)
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
    @Binding var hapticsEnabled: Bool

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
                .background(Color.raceIndigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                Text("This is an on-device practice race. Its answer and ghost moves are bundled with the app; production games will rely on the server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Toggle("Haptics", isOn: $hapticsEnabled)
                    .frame(maxWidth: 280)
                Button("Start local race") {
                    model.startTutorial()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(minHeight: 44)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CountdownView: View {
    let seconds: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("Local race starts in")
                .font(.title2)
            Text("\(seconds)")
                .font(.system(size: 92, weight: .black, design: .rounded))
                .foregroundStyle(Color.raceCoral)
                .contentTransition(.numericText())
            Text("The deadline uses absolute timestamps and does not pause in the background.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Local race starts in \(seconds)")
    }
}

private struct RaceView: View {
    @Bindable var model: TutorialModel
    @Binding var hapticsEnabled: Bool

    var body: some View {
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

                if let error = model.errorMessage {
                    Text(error)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Type a five-letter word from the tutorial list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                KeyboardView(model: model)
                Toggle("Haptics", isOn: $hapticsEnabled)
                    .font(.callout)
                    .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct OpponentStrip: View {
    let opponents: [OpponentProgress]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(opponents) { opponent in
                    HStack(spacing: 10) {
                        Image(systemName: opponent.avatarSymbol)
                            .frame(width: 42, height: 42)
                            .background(Color.raceCoral.opacity(0.16), in: Circle())
                            .foregroundStyle(Color.raceIndigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opponent.name).font(.headline)
                            Text("\(opponent.acceptedGuessCount) / 6 guesses")
                                .font(.subheadline.monospacedDigit())
                                .contentTransition(.numericText())
                            Label(
                                opponent.state.spokenDescription.capitalized,
                                systemImage: opponent.state == .playing
                                    ? "hourglass" : "flag.checkered"
                            )
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 180, alignment: .leading)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.raceIndigo.opacity(0.35), lineWidth: 1.5)
                    }
                    .animation(reduceMotion ? nil : .snappy, value: opponent.acceptedGuessCount)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(opponent.accessibilityLabel)
                }
            }
            .padding(.horizontal)
        }
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
            RoundedRectangle(cornerRadius: 12)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: isHighContrast ? 3 : 1.5)
            if let letter {
                Text(String(letter).uppercased())
                    .font(.title2)
                    .fontWeight(legibilityWeight == .bold ? .black : .bold)
                    .foregroundStyle(feedback == nil ? Color.primary : Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let feedback {
                Image(systemName: feedback.symbolName)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        guard let feedback else { return isDraft ? .white.opacity(0.85) : .white.opacity(0.45) }
        switch feedback {
        case .absent: return Color.raceTeal
        case .present: return Color.raceCoral
        case .correct: return Color.raceIndigo
        }
    }

    private var borderColor: Color {
        if isHighContrast { return .black }
        return feedback == nil
            ? Color.raceIndigo.opacity(isDraft ? 0.65 : 0.22)
            : Color.white.opacity(0.9)
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

    var body: some View {
        LetterKeyboardView(
            keyboard: model.board.keyboard,
            typeLetter: model.typeLetter,
            submit: model.submitGuess,
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
                        .font(.system(size: 8, weight: .black))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(feedback == nil ? Color.primary : Color.white)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHighContrast ? Color.black : Color.raceIndigo.opacity(0.4),
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
        case .none: .white.opacity(0.85)
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
            .background(Color.raceIndigo, in: RoundedRectangle(cornerRadius: 8))
            .frame(minWidth: 44)
            .contentShape(Rectangle())
    }
}

private struct RevealView: View {
    @Bindable var model: TutorialModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Local reveal")
                    .font(.largeTitle.bold())
                Text("Answer: \(TutorialModel.answer.uppercased())")
                    .font(.title2.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.raceCoral.opacity(0.18), in: Capsule())

                ForEach(Array(model.revealBoards.enumerated()), id: \.element.id) { index, board in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(board.name).font(.headline)
                            Spacer()
                            Text(board.result)
                                .font(.subheadline.weight(.semibold))
                        }
                        ForEach(
                            Array(board.rows.prefix(model.visibleRows(in: index)).enumerated()),
                            id: \.offset
                        ) { _, row in
                            RevealRowView(row: row)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding()
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(board.name), \(board.result)")
                }

                if model.revealSummaryVisible {
                    Text(model.comparisonSummary)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.raceIndigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    Button("Replay tutorial") { model.replay() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: 560)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .animation(model.prefersReducedMotion ? nil : .easeOut(duration: 0.25), value: model.visibleRevealRowCount)
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
    static let raceBackground = Color(red: 0.96, green: 0.94, blue: 0.99)
    static let raceIndigo = Color(red: 0.24, green: 0.20, blue: 0.58)
    static let raceCoral = Color(red: 0.78, green: 0.31, blue: 0.20)
    static let raceTeal = Color(red: 0.05, green: 0.42, blue: 0.47)
}
