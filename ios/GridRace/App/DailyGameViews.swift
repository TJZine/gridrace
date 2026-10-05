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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var acceptsHardwareInput: Bool
    @AccessibilityFocusState private var axFocus: DailyGameFocus?
    // R-01/F1 + F3: every submit mints a fresh error-focus value so an
    // identical-error resubmit refires, and clearing resolves to nil so no
    // stale target survives (same-value assignment would never move focus).
    @AccessibilityFocusState private var errorFocus: Int?
    @State private var errorGeneration = 0
    @State private var chromeHeight: CGFloat = 219
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
            Color.page.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    Group {
                        if usesColumns(in: geometry.size) {
                            HStack(spacing: 8) {
                                gameBoard(compact: true)
                                    .frame(width: min(320, geometry.size.width - 388))
                                    .frame(maxHeight: .infinity)
                                VStack(spacing: 2) {
                                    puzzleHeader
                                    inputSlot
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 4)
                        } else {
                            ScrollView {
                                VStack(spacing: 6) {
                                    puzzleHeader.background(chromeMeasurement)
                                    gameBoard(compact: false)
                                        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : max(294, geometry.size.height - chromeHeight - 20))
                                    inputSlot.background(chromeMeasurement)
                                }
                                .frame(maxWidth: 620)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                            }
                        }
                    }
                    .onChange(of: model.resultEvent) { _, _ in
                        guard model.game.isComplete else { return }
                        if model.errorMessage != nil {
                            proxy.scrollTo(DailyGameScrollTarget.error, anchor: .top)
                        } else if dynamicTypeSize.isAccessibilitySize {
                            proxy.scrollTo(DailyGameScrollTarget.result, anchor: .top)
                        }
                    }
                    .onChange(of: model.errorMessage) { _, message in
                        guard model.game.isComplete, message != nil else { return }
                        proxy.scrollTo(DailyGameScrollTarget.error, anchor: .top)
                    }
                }
            }
        }
        .onPreferenceChange(DailyChromeHeightKey.self) { chromeHeight = $0 }
        .navigationTitle("Daily classic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
        .focusable(!model.game.isComplete)
        .focused($acceptsHardwareInput)
        .onAppear {
            acceptsHardwareInput = true
            // Reopened completed puzzle: the result seal owns focus, so land
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

    private func usesColumns(in size: CGSize) -> Bool {
        !dynamicTypeSize.isAccessibilitySize && size.width > size.height
            && size.height < 500 && size.width >= 636
    }

    private func gameBoard(compact: Bool) -> some View {
        BoardView(
            rows: model.game.rows,
            draft: model.game.draft,
            isPlaying: !model.game.isComplete,
            highContrast: model.settings.highContrastEnabled,
            compactLayout: compact
        )
        .accessibilitySortPriority(model.game.isComplete ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.game.rows.count)
    }

    private var chromeMeasurement: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: DailyChromeHeightKey.self, value: geometry.size.height)
        }
    }

    @ViewBuilder
    private var inputSlot: some View {
        VStack(spacing: 6) {
            if model.game.isComplete {
                terminalError
                KeyboardSlot { resultPanel }.id(DailyGameScrollTarget.result)
            } else {
                statusMessage
                KeyboardSlot {
                    VStack(spacing: 0) {
                        hardModeKeyboardHint
                        LetterKeyboardView(
                            keyboard: model.game.keyboard,
                            typeLetter: { model.typeLetter($0) },
                            submit: { model.submitGuess(); noteSubmit() },
                            delete: { model.deleteLetter() },
                            highContrast: model.settings.highContrastEnabled
                        )
                    }
                }
            }
        }
    }

    private var puzzleHeader: some View {
        HStack {
            Text("Puzzle #\(model.puzzle.number)").font(StampType.caption)
            Spacer(minLength: 4)
            GuessesUsedIndicator(used: model.game.rows.count, outcome: model.game.completion?.outcome)
            NavigationLink(value: AppRoute.help) {
                Image(systemName: "questionmark.circle").frame(width: 44, height: 44)
            }
            .accessibilityLabel("How to play")
        }
        .foregroundStyle(Color.secondaryInk)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = model.errorMessage {
            RaceErrorBanner(message: error)
                .padding(.horizontal)
                .accessibilityFocused($errorFocus, equals: errorGeneration)
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
                .accessibilitySortPriority(4)
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
                .font(StampType.caption)
                .foregroundStyle(Color.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .accessibilityLabel("Hard Mode locked. Keep correct-position letters in place and reuse present letters in another position.")
        }
    }

    private var resultTitle: String {
        model.game.completion?.outcome == .solved
            ? "Solved in \(model.game.completion?.guessCount ?? 0)" : "Not solved"
    }

    private var streakText: String {
        if model.game.completion?.outcome == .solved {
            return "Streak \(model.previousDisplayedStreak) → \(model.displayedCurrentStreak)"
        }
        return model.previousDisplayedStreak > 0 ? "Streak ended" : "Result locked"
    }

    private var resultPanel: some View {
        VStack(spacing: 4) {
            ScorecardSeal(title: resultTitle, usesClaret: model.game.completion?.outcome == .solved)
                .accessibilityFocused($axFocus, equals: .resultHeader)
                .accessibilitySortPriority(3)
            Text("The answer was \(model.puzzle.answer.uppercased())")
                .font(StampType.caption.bold())
                .accessibilitySortPriority(2)
            Label(streakText, systemImage: "lock.fill")
                .font(StampType.caption2)
                .foregroundStyle(Color.secondaryInk)
                .accessibilityLabel("Locked result. \(streakText)")
            NextPuzzleLabel(reset: model.nextReset)
            if let result = model.game.completedResult {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    ShareLink(item: DailyClassicShare.text(for: result)) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(InkButtonStyle())
                    .accessibilityLabel("Share result")
                    NavigationLink(value: AppRoute.statistics) {
                        Text("Stats").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlinedInkButtonStyle())
                    .accessibilityLabel("View statistics")
                }
                .padding(.top, 2)
            }
        }
        .padding(6)
        .frame(maxWidth: 440)
        .paperCard(cornerRadius: 12)
        .padding(.horizontal, 16)
    }
}

/// Compact six-dot attempts-used indicator for the Daily header.
/// Filled segments use ink; remaining segments are ink outlines,
/// so used vs remaining never depends on color alone. One AX element.
private struct GuessesUsedIndicator: View {
    let used: Int
    let outcome: DailyOutcome?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { index in
                if index < used {
                    Circle()
                        .fill(Color.ink)
                        .frame(width: 7, height: 7)
                } else {
                    Circle()
                        .stroke(Color.ink, lineWidth: 1.5)
                        .frame(width: 7, height: 7)
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
                .font(StampType.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.secondaryInk)
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

/// Sum the screen's natural header and footer heights before proposing the
/// remaining board space. Error and Hard Mode copy grow without truncation.
private struct DailyChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}
