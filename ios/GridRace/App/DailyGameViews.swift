import SwiftUI
import UIKit

/// U-06 state-to-focus map (one speech owner per transition, never both):
/// terminal result -> focus result header (announcement off; focus speaks
/// exactly once). Draft-error focus uses a per-submit generation below.
enum DailyGameFocus: Hashable {
    case resultHeader
}

/// State-driven scroll targets: the fresh result panel, or the terminal
/// error banner when an error owns the completion transition.
private enum DailyGameScrollTarget: Hashable {
    case result
    case error
}

struct DailyGameView: View {
    @Bindable var model: DailyClassicModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var acceptsHardwareInput: Bool
    @AccessibilityFocusState private var axFocus: DailyGameFocus?
    // R-01/F1 + F3: every submit mints a fresh error-focus value so an
    // identical-error resubmit refires, and clearing resolves to nil so no
    // stale target survives (same-value assignment would never move focus).
    @AccessibilityFocusState private var errorFocus: Int?
    @State private var errorGeneration = 0
    // Message that already owns focus. Submit-path errors are focused in
    // noteSubmit; only errors arriving without a submit (save/record
    // failures) are focused in `onChange` — one owner per transition.
    @State private var lastFocusedError: String?

    private func noteSubmit() {
        errorGeneration += 1
        if let error = model.errorMessage {
            errorFocus = errorGeneration
            lastFocusedError = error
        } else {
            errorFocus = nil
            lastFocusedError = nil
        }
    }

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            puzzleHeader
                            if model.game.isComplete {
                                // Completed semantic order: a terminal error
                                // first when present, then the result, then
                                // the finished board below it.
                                terminalError
                                resultPanel
                                    .id(DailyGameScrollTarget.result)
                                BoardView(
                                    rows: model.game.rows,
                                    draft: model.game.draft,
                                    isPlaying: false,
                                    highContrast: model.settings.highContrastEnabled
                                )
                                .padding(.horizontal)
                            } else {
                                BoardView(
                                    rows: model.game.rows,
                                    draft: model.game.draft,
                                    isPlaying: true,
                                    highContrast: model.settings.highContrastEnabled
                                )
                                .padding(.horizontal)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.game.rows.count)

                                statusMessage
                            }
                        }
                        .frame(maxWidth: 620)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: model.resultEvent) { _, _ in
                        // Fresh completion: the error owns the transition
                        // when present, otherwise the result panel. No
                        // visual scroll animation under Reduce Motion, and
                        // never decorative motion for the error target.
                        guard model.game.isComplete else { return }
                        if model.errorMessage != nil {
                            proxy.scrollTo(DailyGameScrollTarget.error, anchor: .top)
                        } else if reduceMotion {
                            proxy.scrollTo(DailyGameScrollTarget.result, anchor: .top)
                        } else {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(DailyGameScrollTarget.result, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: model.errorMessage) { _, message in
                        // A completion-related error arriving after the
                        // result event still brings the error into view
                        // immediately; focus ownership stays with the
                        // existing error-focus path.
                        guard model.game.isComplete, message != nil else { return }
                        proxy.scrollTo(DailyGameScrollTarget.error, anchor: .top)
                    }
                }

                if !model.game.isComplete {
                    hardModeKeyboardHint
                    LetterKeyboardView(
                        keyboard: model.game.keyboard,
                        typeLetter: { model.typeLetter($0) },
                        submit: { model.submitGuess(); noteSubmit() },
                        delete: { model.deleteLetter() },
                        highContrast: model.settings.highContrastEnabled
                    )
                    .padding(.vertical, 8)
                    .background(Color.racePage)
                    .overlay(alignment: .top) {
                        Color.raceLine.frame(height: 1)
                    }
                }
            }
        }
        .navigationTitle("Daily Classic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .focusable(!model.game.isComplete)
        .focused($acceptsHardwareInput)
        .onAppear {
            acceptsHardwareInput = true
            // Reopened completed puzzle: the result already leads, so land
            // VoiceOver on it. An error still owns focus instead (handled by
            // the error-focus path), matching the fresh-completion rule.
            if model.game.isComplete, model.errorMessage == nil {
                axFocus = .resultHeader
            }
        }
        .onKeyPress(.return) {
            model.submitGuess()
            noteSubmit()
            return .handled
        }
        .onKeyPress(.delete) {
            model.deleteLetter()
            return .handled
        }
        .onKeyPress(characters: .letters) { press in
            guard let letter = press.characters.first else { return .ignored }
            model.typeLetter(letter)
            return .handled
        }
        .sensoryFeedback(trigger: model.hapticEvent) { _, _ in
            model.settings.hapticsEnabled ? .impact(weight: .light) : nil
        }
        .sensoryFeedback(trigger: model.resultEvent) { _, _ in
            model.settings.hapticsEnabled ? .success : nil
        }
        .onChange(of: model.errorMessage) { _, message in
            // Covers only non-submit error sources (save/record failures):
            // submit errors already own focus via noteSubmit, and an
            // identical message never re-triggers this handler.
            if message == nil {
                errorFocus = nil
                lastFocusedError = nil
            } else if message != lastFocusedError {
                errorGeneration += 1
                errorFocus = errorGeneration
                lastFocusedError = message
            }
        }
        .onChange(of: model.resultEvent) { _, _ in
            // A terminal submit can increment `resultEvent` and then set a
            // persistence error in the same transaction (record succeeds,
            // history save fails). The error owns the single speech via
            // noteSubmit/onChange(error); focusing the result as well would
            // interrupt it. Focus the result only for error-free completion.
            // Non-submit errors never touch `resultEvent`, and repeated
            // submits with an error keep `resultEvent` unchanged, so both
            // paths retain their existing single-owner behavior.
            if model.game.isComplete, model.errorMessage == nil { axFocus = .resultHeader }
        }
    }

    private var puzzleHeader: some View {
        HStack {
            Label("#\(model.puzzle.number)", systemImage: "calendar")
            Spacer()
            GuessesUsedIndicator(
                used: model.game.rows.count,
                outcome: model.game.completion?.outcome
            )
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = model.errorMessage {
            RaceErrorBanner(message: error)
                .padding(.horizontal)
                .accessibilityFocused($errorFocus, equals: errorGeneration)
        } else if !model.game.isComplete {
            // Once the above-keyboard Hard Mode hint appears (first accepted
            // guess), the generic line stays out so the two never duplicate.
            if model.game.progress.hardModeEnabled {
                if model.game.rows.isEmpty {
                    Text("Hard Mode: revealed clues must be reused.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Enter any accepted five-letter word.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Terminal completion error shown above the result panel. The error
    /// owns both scroll and VoiceOver focus when present; the result is
    /// the target only for error-free completion.
    @ViewBuilder
    private var terminalError: some View {
        if let error = model.errorMessage {
            RaceErrorBanner(message: error)
                .padding(.horizontal)
                .accessibilityFocused($errorFocus, equals: errorGeneration)
                .id(DailyGameScrollTarget.error)
        }
    }

    /// One-line Hard Mode lock reminder pinned immediately above the
    /// keyboard. Appears only after the first accepted guess; the generic
    /// status-area line owns the pre-first-guess state instead.
    @ViewBuilder
    private var hardModeKeyboardHint: some View {
        if !model.game.isComplete,
           model.game.progress.hardModeEnabled,
           !model.game.rows.isEmpty {
            Text("Hard Mode locked: keep ✓ letters in place and reuse ↻ letters elsewhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .accessibilityLabel("Hard Mode locked. Keep correct-position letters in place and reuse present letters in another position.")
        }
    }

    private var resultHeaderLabel: String {
        guard let completion = model.game.completion else { return "Daily result." }
        if completion.outcome == .solved {
            return "Solved in \(completion.guessCount) guesses. The answer was \(model.puzzle.answer.uppercased())."
        }
        return "Daily puzzle failed. The answer was \(model.puzzle.answer.uppercased())."
    }

    /// Streak line for the result panel, derived from model-owned streak
    /// state: solved shows the previous-to-current transition, a failed
    /// puzzle with a prior streak shows the streak ended, and a failed
    /// puzzle with no prior streak omits the row.
    @ViewBuilder
    private var streakContext: some View {
        if model.game.completion?.outcome == .solved {
            Text("Streak \(model.previousDisplayedStreak) → \(model.displayedCurrentStreak).")
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Streak \(model.previousDisplayedStreak) to \(model.displayedCurrentStreak).")
        } else if model.previousDisplayedStreak > 0 {
            Text("Streak ended.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var resultPanel: some View {
        VStack(spacing: 12) {
            Text("ANSWER")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.puzzle.answer.uppercased())
                .font(.title.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.raceInset, in: Capsule())
                .accessibilityFocused($axFocus, equals: .resultHeader)
                .accessibilityLabel(resultHeaderLabel)
            Text(model.game.completion?.outcome == .solved
                ? "Solved in \(model.game.completion?.guessCount ?? 0)"
                : "Not solved")
                .font(.headline)
                // Sighted copy only: the answer capsule above already
                // announces the full result (outcome, guess count, answer).
                .accessibilityHidden(true)
            streakContext
            Text("Locked result.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let result = model.game.completedResult {
                ShareLink(item: DailyClassicShare.text(for: result)) {
                    Label("Share result", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                NavigationLink(value: AppRoute.statistics) {
                    Label("View statistics", systemImage: "chart.bar.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            NextPuzzleLabel(reset: model.nextReset)
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}

/// Compact six-segment attempts-used indicator for the Daily header.
/// Filled segments use raceIndigo; remaining segments are indigo outlines,
/// so used vs remaining never depends on color alone. One AX element.
private struct GuessesUsedIndicator: View {
    let used: Int
    let outcome: DailyOutcome?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { index in
                if index < used {
                    Capsule()
                        .fill(Color.raceIndigo)
                        .frame(width: 18, height: 6)
                } else {
                    Capsule()
                        .stroke(Color.raceIndigo, lineWidth: 1.5)
                        .frame(width: 18, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch outcome {
        case .solved:
            "Solved using \(used) of 6 guesses."
        case .failed:
            "6 of 6 guesses used. Puzzle complete."
        case nil:
            "\(used) of 6 guesses used, \(6 - used) remaining."
        }
    }
}

struct NextPuzzleLabel: View {
    let reset: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label("Next puzzle in \(remaining(at: context.date))", systemImage: "clock")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Next puzzle available in \(spokenRemaining(at: context.date))")
        }
    }

    private func remaining(at date: Date) -> String {
        let seconds = max(0, Int(reset.timeIntervalSince(date)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func spokenRemaining(at date: Date) -> String {
        let seconds = max(0, Int(reset.timeIntervalSince(date)))
        return "\(seconds / 3600) hours, \(seconds / 60 % 60) minutes, \(seconds % 60) seconds"
    }
}
