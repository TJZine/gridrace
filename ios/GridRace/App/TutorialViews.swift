import SwiftUI

private struct TutorialChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private struct TutorialKeyboardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TutorialView: View {
    @Bindable var model: TutorialModel
    @Binding var hapticsEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
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
        .tint(Color.ink)
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
                    .foregroundStyle(Color.ink)
                    .accessibilityHidden(true)
                Text("Practice")
                    .font(StampType.display.bold())
                    .multilineTextAlignment(.center)
                Text("Race two bots")
                    .font(StampType.title.bold())
                    .multilineTextAlignment(.center)
                Text("Alex and Sam are practice bots chasing the same word. You'll only see their progress until the reveal.")
                    .font(StampType.title3)
                    .multilineTextAlignment(.center)
                Text("Practice runs on this device. Live races use the server.")
                    .font(.callout)
                    .foregroundStyle(Color.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .paperCard()
                Button("Start practice") {
                    model.startTutorial()
                }
                .buttonStyle(InkButtonStyle())
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 44)
                NavigationLink(value: AppRoute.settings) {
                    Label("Haptics and contrast live in Settings", systemImage: "gearshape")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink)
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
            Text("Practice starts in")
                .font(StampType.title2)
            CountdownNumeral(text: "\(seconds)")
            // Determinate 3-second progress; presentation only, hidden from
            // VoiceOver so the combined label above stays the single speech.
            ProgressView(value: Double(3 - seconds), total: 3)
                .frame(maxWidth: 220)
                .accessibilityHidden(true)
            Text("The deadline uses absolute timestamps and does not pause in the background.")
                .font(.callout)
                .foregroundStyle(Color.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Practice starts in \(seconds)")
        .accessibilityFocused($focused)
        .onAppear { focused = true }
    }
}

private struct RaceView: View {
    @Bindable var model: TutorialModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // U-06 + R-01/F1: invalid/incomplete draft -> focus error banner
    // (announcement off). A per-submit generation mints a fresh focus value
    // so an identical-error resubmit refires (same-value assignment would
    // coalesce and never move focus).
    @AccessibilityFocusState private var errorFocus: Int?
    @State private var errorGeneration = 0
    @State private var chromeHeight: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .title2) private var minimumTileSize: CGFloat = 44

    private var minimumBoardHeight: CGFloat {
        minimumTileSize * 6 + 6 * 5
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 0) {
                        raceContent(boardHeight: nil)
                        keyboard
                    }
                }
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        ScrollView {
                            raceContent(boardHeight: proposedBoardHeight(in: proxy.size.height))
                        }
                        keyboard
                    }
                }
            }
        }
        .onPreferenceChange(TutorialChromeHeightKey.self) { chromeHeight = $0 }
        .onPreferenceChange(TutorialKeyboardHeightKey.self) { keyboardHeight = $0 }
    }

    private func proposedBoardHeight(in availableHeight: CGFloat) -> CGFloat {
        let measuredChrome = chromeHeight + 40
        return max(minimumBoardHeight, availableHeight - measuredChrome - keyboardHeight)
    }

    @ViewBuilder
    private func raceContent(boardHeight: CGFloat? = nil) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    Text("Practice")
                        .font(StampType.heading)
                    Spacer()
                    Label("\(model.roundSecondsRemaining)s", systemImage: "timer")
                        .font(StampType.figure)
                        .accessibilityLabel("\(model.roundSecondsRemaining) seconds remaining")
                }
                .padding(.horizontal)

                PracticeOpponentStrip(opponents: model.opponents)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TutorialChromeHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }

            boardView(boardHeight: boardHeight)

            statusMessage
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TutorialChromeHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private var boardBase: some View {
        BoardView(
            rows: model.board.rows,
            draft: model.board.draft,
            isPlaying: model.board.status == .playing
        )
        .padding(.horizontal)
        // Subtle invalid-guess nudge; fully suppressed under Reduce Motion
        // (banner + existing haptics only).
        .offset(x: (model.errorMessage != nil && !reduceMotion) ? 6 : 0)
        .animation(reduceMotion ? nil : .snappy, value: model.errorMessage)
    }

    @ViewBuilder
    private func boardView(boardHeight: CGFloat?) -> some View {
        if let boardHeight {
            boardBase.frame(height: boardHeight)
        } else {
            boardBase
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = model.errorMessage {
            RaceErrorBanner(message: error)
                .padding(.horizontal)
                .accessibilityFocused($errorFocus, equals: errorGeneration)
                .onAppear { errorFocus = errorGeneration }
        } else {
            Text("Enter five letters from the practice list.")
                .font(StampType.caption)
                .foregroundStyle(Color.secondaryInk)
        }
    }

    private var keyboard: some View {
        KeyboardView(model: model) {
            errorGeneration += 1
            errorFocus = model.errorMessage != nil ? errorGeneration : nil
        }
        .padding(.vertical, 8)
        .background(Color.page)
        .overlay(alignment: .top) {
            Color.line.frame(height: 1)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialKeyboardHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}

private struct PracticeOpponentStrip: View {
    let opponents: [OpponentProgress]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(opponents) { opponent in
                OpponentLine(
                    name: opponent.name,
                    count: "\(opponent.acceptedGuessCount)/6",
                    state: shortVisualState(for: opponent.state),
                    stateSymbol: opponent.state == .playing ? "hourglass" : "flag.checkered",
                    connection: nil,
                    accessibilitySummary: opponent.accessibilityLabel
                ) {
                    Image(systemName: opponent.avatarSymbol)
                        .font(StampType.caption.bold())
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .padding(.horizontal)
    }

    private func shortVisualState(for state: OpponentState) -> String {
        switch state {
        case .playing: "Playing"
        case .solved: "Solved"
        case .failed: "Failed"
        case .timedOut: "Timed out"
        case .forfeited: "Forfeited"
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
                Text("Practice reveal")
                    .font(StampType.display.bold())
                Text("Answer: \(TutorialModel.answer.uppercased())")
                    .font(StampType.title2.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.card, in: Capsule())
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
                            Text(board.name).font(StampType.heading)
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
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.line, lineWidth: 1.5)
                    }
                }

                // Stable VoiceOver tree: the summary is part of the initial
                // manual-traversal order when VoiceOver is on, instead of
                // appearing mid-traversal after the timed rows complete.
                if model.revealSummaryVisible || (voiceOverEnabled && totalRevealRows > 0) {
                    Text(model.comparisonSummary)
                        .font(StampType.heading)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityFocused($focus, equals: .summary)
                    Button("Replay practice") { model.replay() }
                        .buttonStyle(InkButtonStyle())
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
