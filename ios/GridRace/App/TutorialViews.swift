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
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Practice starts in")
                .font(StampType.title2)
            CountdownNumeral(text: "\(seconds)")
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
    @FocusState private var acceptsHardwareInput: Bool
    @AccessibilityFocusState private var errorFocus: Int?
    @State private var errorGeneration = 0
    @State private var lastFocusedError: String?
    @State private var chromeHeight: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .title2) private var minimumTileSize: CGFloat = 44

    private var minimumBoardHeight: CGFloat {
        minimumTileSize * 6 + 6 * 5
    }

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 10) {
                        raceHeader
                        PracticeOpponentStrip(opponents: model.opponents)
                        boardView(boardHeight: nil)
                        statusMessage
                        keyboard
                    }
                    .padding(.vertical, 10)
                }
            } else {
                GeometryReader { proxy in
                    if proxy.size.width > proxy.size.height,
                       proxy.size.height < 500, proxy.size.width >= 636 {
                        HStack(spacing: 8) {
                            board(compact: true)
                                .frame(width: min(320, proxy.size.width - 388))
                                .frame(maxHeight: .infinity)
                            VStack(spacing: 6) {
                                raceHeader
                                PracticeOpponentStrip(opponents: model.opponents)
                                statusMessage
                                keyboard
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 4)
                    } else {
                        VStack(spacing: 0) {
                            VStack(spacing: 6) {
                                raceHeader
                                PracticeOpponentStrip(opponents: model.opponents)
                            }
                            .background(chromeMeasurement)
                            boardView(boardHeight: proposedBoardHeight(in: proxy.size.height))
                            statusMessage.background(chromeMeasurement)
                            keyboard
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onPreferenceChange(TutorialChromeHeightKey.self) { chromeHeight = $0 }
        .onPreferenceChange(TutorialKeyboardHeightKey.self) { keyboardHeight = $0 }
        .focusable(model.phase == .playing)
        .focused($acceptsHardwareInput)
        .onAppear { acceptsHardwareInput = model.phase == .playing }
        .onChange(of: model.phase) { _, phase in
            acceptsHardwareInput = phase == .playing
        }
        .onDisappear { acceptsHardwareInput = false }
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
        .onChange(of: model.errorMessage) { _, message in
            if message == nil {
                errorFocus = nil
                lastFocusedError = nil
            } else if message != lastFocusedError {
                errorGeneration += 1
                errorFocus = errorGeneration
                lastFocusedError = message
            }
        }
    }

    private var raceHeader: some View {
        HStack {
            Text("Practice").font(StampType.heading)
            Spacer()
            Label("\(model.roundSecondsRemaining)s", systemImage: "timer")
                .font(StampType.figure)
                .accessibilityLabel("\(model.roundSecondsRemaining) seconds remaining")
        }
        .padding(.horizontal)
    }

    private var chromeMeasurement: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: TutorialChromeHeightKey.self, value: proxy.size.height)
        }
    }

    private func proposedBoardHeight(in availableHeight: CGFloat) -> CGFloat {
        max(minimumBoardHeight, availableHeight - chromeHeight - keyboardHeight - 8)
    }

    private var boardBase: some View { board(compact: false).padding(.horizontal) }

    private func board(compact: Bool) -> some View {
        BoardView(
            rows: model.board.rows,
            draft: model.board.draft,
            isPlaying: model.board.status == .playing,
            compactLayout: compact
        )
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
            noteSubmit()
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            ForEach(opponents) { opponent in
                HStack(spacing: 4) {
                    Text(opponent.name).font(StampType.caption.bold())
                    Text("\(opponent.acceptedGuessCount)/6").font(StampType.caption.bold())
                    Text(shortVisualState(for: opponent.state))
                        .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(opponent.accessibilityLabel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .paperCard()
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

    private var usesStableReveal: Bool { model.prefersReducedMotion || voiceOverEnabled }

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
            if totalRevealRows == 0, model.revealSummaryVisible {
                focus = .summary
            } else {
                focus = .answer
            }
        }
        .onChange(of: model.visibleRevealRowCount) { _, count in
            guard !usesStableReveal, count > 0 else { return }
            focus = .row(count - 1)
        }
        .onChange(of: model.revealSummaryVisible) { _, visible in
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
            if enabled { focus = .answer }
        }
    }
}
