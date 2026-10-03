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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AccessibilityFocusState private var focus: RevealFocus?

    private var totalRevealRows: Int {
        model.revealBoards.reduce(0) { $0 + $1.rows.count }
    }

    /// VoiceOver uses the same stable full-state + manual traversal as Reduce
    /// Motion: the animated row timer would otherwise steal focus every 350ms,
    /// interrupting row speech, and any fixed summary delay stays
    /// speech-rate dependent. Visual animation is preserved only when
    /// VoiceOver is off and Reduce Motion is off.
    private var usesStableReveal: Bool { model.prefersReducedMotion || voiceOverEnabled }

    /// Full row speech: player and row position plus every tile's letter and
    /// feedback meaning, so the combined row label never drops tile content.
    private func revealRowLabel(boardName: String, rowIndex: Int, row: GuessRow) -> String {
        let tiles = zip(Array(row.word.uppercased()), row.feedback).map { letter, feedback in
            "\(letter) \(feedback.accessibilityMeaning)"
        }.joined(separator: ", ")
        return "\(boardName), row \(rowIndex + 1): \(tiles)"
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
                    // Stable VoiceOver tree: expose every row immediately so
                    // the accessibility order (answer → global row order →
                    // summary) never mutates mid-traversal. Visual animation
                    // still uses `visibleRows` when VoiceOver is off.
                    let visibleCount = usesStableReveal ? board.rows.count : model.visibleRows(in: index)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(board.name).font(.headline)
                            Spacer()
                            Text(board.result)
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                        ForEach(
                            Array(board.rows.prefix(visibleCount).enumerated()),
                            id: \.offset
                        ) { rowOffset, row in
                            RevealRowView(row: row)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    revealRowLabel(
                                        boardName: board.name,
                                        rowIndex: rowOffset,
                                        row: row
                                    )
                                )
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

                // Stable VoiceOver tree: the summary is part of the initial
                // manual-traversal order when VoiceOver is on, instead of
                // appearing mid-traversal after the timed rows complete.
                if model.revealSummaryVisible || (voiceOverEnabled && totalRevealRows > 0) {
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
        .animation(usesStableReveal ? nil : .easeOut(duration: 0.25), value: model.visibleRevealRowCount)
        .onAppear {
            // Initial focus is never nil: the answer first in every mode
            // (the zero-row edge falls through to its visible summary).
            // VoiceOver then traverses manually in global order with no
            // timed focus changes to interrupt row speech.
            if totalRevealRows == 0, model.revealSummaryVisible {
                focus = .summary
            } else {
                focus = .answer
            }
        }
        .onChange(of: model.visibleRevealRowCount) { _, count in
            // Timed focus only when VoiceOver is off: with VoiceOver on the
            // full state is already exposed and manual traversal owns the
            // sequence, so any per-row move would interrupt speech.
            guard !usesStableReveal, count > 0 else { return }
            focus = .row(count - 1)
        }
        .onChange(of: model.revealSummaryVisible) { _, visible in
            // State-driven, never a fixed sleep: with VoiceOver off the final
            // row and summary arrive together and the summary owns the single
            // post-animation focus (no speech to interrupt). With VoiceOver
            // on, manual traversal owns answer → rows → summary, so this
            // never steals focus (the zero-row edge is set on appear).
            guard visible, !usesStableReveal else { return }
            if model.visibleRevealRowCount >= totalRevealRows {
                focus = .summary
            } else if model.visibleRevealRowCount > 0 {
                focus = .row(model.visibleRevealRowCount - 1)
            }
        }
        .onChange(of: model.prefersReducedMotion) {
            if model.prefersReducedMotion { focus = .answer }
        }
        .onChange(of: voiceOverEnabled) { _, enabled in
            // Toggling VoiceOver mid-reveal restarts the manual sequence at
            // its head; no view-owned Task exists, so leaving/replaying is
            // safe (model cancellation owns the timed tasks).
            if enabled { focus = .answer }
        }
    }
}
