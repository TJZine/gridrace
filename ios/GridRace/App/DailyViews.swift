import SwiftUI
import UIKit

enum AppRoute: Hashable {
    case daily
    case statistics
    case account
    case settings
    case help
    case tutorial
}

struct DailyAppView: View {
    @Bindable var app: DailyAccountCoordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            DailyHomeView(
                model: app.daily,
                account: app.account,
                syncMessage: app.syncMessage,
                isDailyPlayable: app.isDailyPlayable,
                retryDailyStorage: { app.retrySync() }
            )
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .daily:
                        if app.isDailyPlayable {
                            DailyGameView(model: app.daily)
                        } else {
                            DailyStorageUnavailableView(retry: { app.retrySync() })
                        }
                    case .statistics: DailyStatisticsView(model: app.daily)
                    case .account: accountDestination
                    case .settings: DailySettingsView(model: app.daily)
                    case .help: DailyHelpView()
                    case .tutorial:
                        TutorialView(
                            model: app.tutorial,
                            hapticsEnabled: Binding(
                                get: { app.daily.settings.hapticsEnabled },
                                set: { app.daily.updateHaptics($0) }
                            )
                        )
                    }
                }
        }
        .tint(Color.raceIndigo)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.foregrounded() }
        }
        .task { await app.start() }
        .task(id: app.daily.puzzle.id) {
            let delay = max(1, app.daily.nextReset.timeIntervalSinceNow)
            try? await Task<Never, Never>.sleep(for: .seconds(delay))
            guard !Task.isCancelled, app.isDailyPlayable else { return }
            app.daily.refreshForCurrentDay()
        }
    }

    private var accountDestination: some View {
        AccountView(
            model: app.account,
            syncMessage: app.syncMessage,
            retrySync: app.showsRetry ? { app.retrySync() } : nil,
            canImportGuestHistory: app.canImportGuestHistory,
            importGuestHistory: { app.importGuestHistory() },
            skipGuestHistory: { app.skipGuestHistory() },
            useCloudAttempt: app.conflicts.isEmpty
                ? nil : { app.resolveFirstConflict(useCloud: true) },
            keepDeviceAttempt: app.conflicts.isEmpty
                ? nil : { app.resolveFirstConflict(useCloud: false) },
            conflictCount: app.conflicts.count
        )
    }
}

struct DailyHomeView: View {
    @Bindable var model: DailyClassicModel
    @Bindable var account: AccountModel
    let syncMessage: String?
    let isDailyPlayable: Bool
    let retryDailyStorage: () -> Void

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    brandHeader
                    dailyCard
                    statisticsStrip
                    accountCard
                    secondaryRoutes
                }
                .frame(maxWidth: 620)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.help) {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("How to play")
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(Color.raceIndigo)
                .accessibilityHidden(true)
            Text("GRIDRACE")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .tracking(1.5)
            Text("One grid. One day. Make every row count.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var dailyCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAILY CLASSIC")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(Color.raceIndigo)
                    Text("Puzzle #\(model.puzzle.number)")
                        .font(.title2.bold())
                    Label(model.homeStatus.title, systemImage: model.homeStatus.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MiniRaceGrid(rows: model.game.rows)
                    .frame(width: 82)
            }

            if isDailyPlayable {
                NavigationLink(value: AppRoute.daily) {
                    Text(model.homeStatus.action)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Account storage must be available before this puzzle can be played.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Retry account storage", action: retryDailyStorage)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            if model.game.isComplete {
                NextPuzzleLabel(reset: model.nextReset)
            } else if model.settings.hardModeEnabled {
                Label("Hard Mode", systemImage: "shield.checkered")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var statisticsStrip: some View {
        NavigationLink(value: AppRoute.statistics) {
            HStack(spacing: 0) {
                HomeMetric(value: "\(model.displayedCurrentStreak)", label: "Current streak")
                Divider().frame(height: 44)
                HomeMetric(value: "\(model.history.statistics.solvePercentage)%", label: "Solved")
                Divider().frame(height: 44)
                HomeMetric(value: "\(model.history.statistics.gamesPlayed)", label: "Played")
            }
            .padding(.vertical, 14)
            .background(Color.raceInset, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your Daily Classic statistics")
    }

    private var secondaryRoutes: some View {
        VStack(spacing: 10) {
            NavigationLink(value: AppRoute.help) {
                HomeRouteLabel(title: "How to play", subtitle: "Rules and tile evidence", symbol: "questionmark.circle")
            }
            NavigationLink(value: AppRoute.settings) {
                HomeRouteLabel(title: "Settings", subtitle: "Haptics, contrast, Hard Mode", symbol: "gearshape")
            }
            NavigationLink(value: AppRoute.tutorial) {
                HomeRouteLabel(title: "Practice race", subtitle: "Revisit the local tutorial", symbol: "figure.run")
            }
        }
        .buttonStyle(.plain)
    }

    private var accountCard: some View {
        NavigationLink(value: AppRoute.account) {
            HStack(spacing: 14) {
                if let profile = account.profile {
                    PlayerAvatarView(seed: profile.avatarSeed, size: 48)
                } else {
                    Image(systemName: account.isSignedIn ? "person.crop.circle" : "person.crop.circle.badge.plus")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(Color.raceInset, in: Circle())
                        .foregroundStyle(Color.raceIndigo)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.profile?.displayName ?? "GridRace account")
                        .font(.headline)
                    Text(account.isSignedIn
                        ? (syncMessage ?? "Save and sync your progress")
                        : "Save and sync your progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.raceLine, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(account.isSignedIn ? "Manage your profile and synchronization" : "Sign in to save your progress")
    }
}

private struct DailyStorageUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Daily storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Retry account storage, or sign out from Account to keep playing as a guest.")
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
            NavigationLink("Open Account", value: AppRoute.account)
        }
        .navigationTitle("Daily Classic")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MiniRaceGrid: View {
    let rows: [GuessRow]
    private let columns = Array(repeating: GridItem(.fixed(14), spacing: 3), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<30, id: \.self) { index in
                let row = index / 5
                let column = index % 5
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(row: row, column: column))
                    .frame(width: 14, height: 14)
                    .overlay {
                        if rows.indices.contains(row) {
                            Image(systemName: rows[row].feedback[column].symbolName)
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(row: Int, column: Int) -> Color {
        guard rows.indices.contains(row) else { return Color.raceLineSoft }
        switch rows[row].feedback[column] {
        case .absent: return Color.raceTeal
        case .present: return Color.raceCoral
        case .correct: return Color.raceIndigo
        }
    }
}

private struct HomeMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeRouteLabel: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(Color.raceInset, in: Circle())
                .foregroundStyle(Color.raceIndigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
    }
}

/// U-06 state-to-focus map (one speech owner per transition, never both):
/// terminal result -> focus result header (announcement off; focus speaks
/// exactly once). Draft-error focus uses a per-submit generation below.
enum DailyGameFocus: Hashable {
    case resultHeader
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
                ScrollView {
                    VStack(spacing: 12) {
                        puzzleHeader
                        BoardView(
                            rows: model.game.rows,
                            draft: model.game.draft,
                            isPlaying: !model.game.isComplete,
                            highContrast: model.settings.highContrastEnabled
                        )
                        .padding(.horizontal)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.game.rows.count)

                        statusMessage

                        if model.game.isComplete {
                            resultPanel
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }

                if !model.game.isComplete {
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
        .onAppear { acceptsHardwareInput = true }
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
            Text("\(model.game.rows.count) / 6")
                .monospacedDigit()
                .accessibilityLabel("\(model.game.rows.count) of 6 guesses used")
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
            Text(model.game.progress.hardModeEnabled
                ? "Hard Mode: revealed clues must be reused."
                : "Enter any accepted five-letter word.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resultHeaderLabel: String {
        guard let completion = model.game.completion else { return "Daily result." }
        if completion.outcome == .solved {
            return "Solved in \(completion.guessCount) guesses. The answer was \(model.puzzle.answer.uppercased())."
        }
        return "Daily puzzle failed. The answer was \(model.puzzle.answer.uppercased())."
    }

    private var resultPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: model.game.completion?.outcome == .solved
                ? "flag.checkered.2.crossed" : "lock.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.raceIndigo)
                .accessibilityHidden(true)
            Text(model.game.completion?.outcome == .solved ? "Solved" : "Not solved")
                .font(.title2.bold())
                .accessibilityFocused($axFocus, equals: .resultHeader)
                .accessibilityLabel(resultHeaderLabel)
            Text("The answer was \(model.puzzle.answer.uppercased()).")
                .font(.headline)
            Text("Locked result.")
                .font(.caption.weight(.semibold))
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

struct DailyStatisticsView: View {
    @Bindable var model: DailyClassicModel

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatisticCard(value: model.history.statistics.gamesPlayed, label: "Played")
                        StatisticCard(value: model.history.statistics.solvePercentage, label: "Solved", showsPercentSign: true)
                        StatisticCard(value: model.displayedCurrentStreak, label: "Streak")
                        StatisticCard(value: model.history.statistics.longestStreak, label: "Best")
                    }
                    GuessDistributionView(distribution: model.history.statistics.guessDistribution)
                    todayResult
                }
                .frame(maxWidth: 560)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var todayResult: some View {
        if let result = model.history.result(for: model.puzzle.id) {
            VStack(spacing: 12) {
                Text("TODAY").font(.caption.weight(.black)).tracking(1.2)
                Text(result.outcome == .solved ? "Solved in \(result.guessCount)" : "Not solved")
                    .font(.headline)
                ShareLink(item: DailyClassicShare.text(for: result)) {
                    Label("Share today's grid", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                NextPuzzleLabel(reset: model.nextReset)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Color.raceInset, in: RoundedRectangle(cornerRadius: 18))
        } else {
            ContentUnavailableView(
                "Today's result is waiting",
                systemImage: "flag.checkered",
                description: Text("Finish Daily Classic to add it to your statistics.")
            )
        }
    }
}

private struct StatisticCard: View {
    let value: Int
    let label: String
    var showsPercentSign = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)\(showsPercentSign ? "%" : "")")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        showsPercentSign ? "\(label), \(value) percent" : "\(value) \(label)"
    }
}

private struct GuessDistributionView: View {
    let distribution: [Int: Int]
    private var maximum: Int { max(1, distribution.values.max() ?? 0) }

    private func barWidth(count: Int, in total: CGFloat) -> CGFloat {
        // Zero-count rows render no fill (a 32pt minimum here would paint a
        // misleading indigo bar for zero). Positive counts keep the readable
        // 32pt minimum; the count label sits beside the bar in ink-on-card,
        // so AX5/Bold sizes cannot clip it.
        guard total > 0, count > 0 else { return 0 }
        return min(total, max(32, total * CGFloat(count) / CGFloat(maximum)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GUESS DISTRIBUTION")
                .font(.caption.weight(.black))
                .tracking(1.2)
            ForEach(1...6, id: \.self) { guess in
                HStack(spacing: 10) {
                    Text("\(guess)").font(.subheadline.bold()).frame(width: 12)
                    GeometryReader { proxy in
                        let count = distribution[guess, default: 0]
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.raceInset)
                            Capsule().fill(Color.raceIndigo)
                                .frame(width: barWidth(count: count, in: proxy.size.width))
                        }
                    }
                    .frame(height: 24)
                    // Count sits beside the bar in ink-on-card (never clipped
                    // white-on-fill), so AX5/Bold sizes cannot clip it or push
                    // it outside its contrasting fill.
                    Text("\(distribution[guess, default: 0])")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Color.raceInk)
                        .frame(minWidth: 28, alignment: .leading)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Solved in \(guess) guesses, \(distribution[guess, default: 0]) games")
            }
        }
        .padding(18)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
    }
}

struct DailySettingsView: View {
    @Bindable var model: DailyClassicModel

    var body: some View {
        Form {
            Section {
                Toggle("Haptics", isOn: Binding(
                    get: { model.settings.hapticsEnabled },
                    set: { model.updateHaptics($0) }
                ))
                Toggle("High-contrast feedback", isOn: Binding(
                    get: { model.settings.highContrastEnabled },
                    set: { model.updateHighContrast($0) }
                ))
                Toggle("Hard Mode", isOn: Binding(
                    get: { model.game.progress.hardModeEnabled },
                    set: { model.updateHardMode($0) }
                ))
                .disabled(!model.game.canChangeHardMode)
            } header: {
                Text("Play")
            } footer: {
                Text(model.game.canChangeHardMode
                    ? "Hard Mode requires every revealed clue to be reused."
                    : "Hard Mode is locked after the first accepted guess until tomorrow.")
            }
            Section("Learn") {
                NavigationLink(value: AppRoute.help) {
                    Label("How to Play", systemImage: "questionmark.circle")
                }
                NavigationLink(value: AppRoute.tutorial) {
                    Label("Practice race", systemImage: "figure.run")
                }
            }
            Section {
                Text("Daily Classic resets worldwide at 00:00 UTC. Reduce Motion follows your system accessibility setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.racePage)
        .navigationTitle("Settings")
    }
}

struct DailyHelpView: View {
    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Reach the finish in six")
                        .font(.largeTitle.bold())
                    Text("Guess the five-letter answer in six accepted words. Each row gives evidence for your next move.")
                        .font(.title3)
                    FeedbackExample(
                        letter: "R", feedback: .correct,
                        title: "Correct position", detail: "The checkmark means R is exactly where it belongs."
                    )
                    FeedbackExample(
                        letter: "A", feedback: .present,
                        title: "Present elsewhere", detail: "The turning arrow means A is in the answer in another position."
                    )
                    FeedbackExample(
                        letter: "C", feedback: .absent,
                        title: "Not in the answer", detail: "The minus means this C is not used. Repeated letters are counted exactly."
                    )
                    DuplicateLetterExample(
                        title: "Same letter twice",
                        detail: "In APPLE against GRAPE, exact matches use up answer copies first, so E is exact. Leftover copies are then claimed left to right: A and the first P are present while an unused copy remains, and the second P is absent because GRAPE has no P copy left."
                    )
                    Divider()
                    Label("One puzzle is shared worldwide each UTC day.", systemImage: "globe.americas.fill")
                    Label("A finished result cannot be replayed or changed.", systemImage: "lock.fill")
                    Label("Hard Mode reuses every revealed clue.", systemImage: "shield.checkered")
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeedbackExample: View {
    let letter: Character
    let feedback: Feedback
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            TileView(letter: letter, feedback: feedback, isDraft: false, emptyLabel: "")
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fourth Help example: fixed five-tile row for the canonical duplicate vector
/// `excess-guess-repeat` (answer `grape`, guess `apple`, feedback
/// `[present, present, absent, absent, correct]`). Fixed literals only —
/// evaluation and assertions belong in `GameRulesTests`.
private struct DuplicateLetterExample: View {
    let title: String
    let detail: String

    // One fixed source pairing each tile letter with its vector feedback
    // (`excess-guess-repeat`: APPLE vs GRAPE → [present, present, absent,
    // absent, correct]). Literals only; evaluation lives in GameRulesTests.
    private let tiles: [(letter: Character, feedback: Feedback)] = [
        (letter: "A", feedback: .present),
        (letter: "P", feedback: .present),
        (letter: "P", feedback: .absent),
        (letter: "L", feedback: .absent),
        (letter: "E", feedback: .correct),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack(spacing: 5) {
                ForEach(tiles.indices, id: \.self) { index in
                    TileView(
                        letter: tiles[index].letter,
                        feedback: tiles[index].feedback,
                        isDraft: false,
                        emptyLabel: ""
                    )
                    .frame(width: 52, height: 52)
                }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
