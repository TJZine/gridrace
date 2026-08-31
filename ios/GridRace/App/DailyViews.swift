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
                syncMessage: app.syncMessage
            )
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .daily: DailyGameView(model: app.daily)
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
            guard !Task.isCancelled else { return }
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
                ? nil : { app.resolveFirstConflict(useCloud: false) }
        )
    }
}

struct DailyHomeView: View {
    @Bindable var model: DailyClassicModel
    @Bindable var account: AccountModel
    let syncMessage: String?

    var body: some View {
        ZStack {
            Color.raceBackground.ignoresSafeArea()
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
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
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
                    .frame(width: 86)
            }

            NavigationLink(value: AppRoute.daily) {
                Text(model.homeStatus.action)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if model.game.isComplete {
                NextPuzzleLabel(reset: model.nextReset)
            } else if model.settings.hardModeEnabled {
                Label("Hard Mode", systemImage: "shield.checkered")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.raceIndigo.opacity(0.18), lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var statisticsStrip: some View {
        HStack(spacing: 0) {
            HomeMetric(value: "\(model.displayedCurrentStreak)", label: "Current streak")
            Divider().frame(height: 44)
            HomeMetric(value: "\(model.history.statistics.solvePercentage)%", label: "Solved")
            Divider().frame(height: 44)
            HomeMetric(value: "\(model.history.statistics.gamesPlayed)", label: "Played")
        }
        .padding(.vertical, 14)
        .background(Color.raceIndigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var secondaryRoutes: some View {
        VStack(spacing: 10) {
            NavigationLink(value: AppRoute.statistics) {
                HomeRouteLabel(title: "Statistics", subtitle: "Streaks and guess distribution", symbol: "chart.bar.fill")
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
                        .background(Color.raceIndigo.opacity(0.1), in: Circle())
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
            .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(account.isSignedIn ? "Manage your profile and synchronization" : "Sign in to save your progress")
    }
}

private struct MiniRaceGrid: View {
    let rows: [GuessRow]
    private let columns = Array(repeating: GridItem(.fixed(12), spacing: 3), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<30, id: \.self) { index in
                let row = index / 5
                let column = index % 5
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(row: row, column: column))
                    .frame(width: 12, height: 12)
                    .overlay {
                        if rows.indices.contains(row) {
                            Image(systemName: rows[row].feedback[column].symbolName)
                                .font(.system(size: 5, weight: .black))
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(row: Int, column: Int) -> Color {
        guard rows.indices.contains(row) else { return Color.raceIndigo.opacity(0.12) }
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
                .background(Color.raceIndigo.opacity(0.1), in: Circle())
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
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}

struct DailyGameView: View {
    @Bindable var model: DailyClassicModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var acceptsHardwareInput: Bool

    var body: some View {
        ZStack {
            Color.raceBackground.ignoresSafeArea()
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
                    } else {
                        LetterKeyboardView(
                            keyboard: model.game.keyboard,
                            typeLetter: { model.typeLetter($0) },
                            submit: { model.submitGuess() },
                            delete: { model.deleteLetter() },
                            highContrast: model.settings.highContrastEnabled
                        )
                    }
                }
                .frame(maxWidth: 620)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
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
        .onChange(of: model.hapticEvent) { _, _ in
            if let error = model.errorMessage {
                UIAccessibility.post(notification: .announcement, argument: error)
            }
        }
        .onChange(of: model.resultEvent) { _, _ in
            guard let completion = model.game.completion else { return }
            let outcome = completion.outcome == .solved
                ? "Solved in \(completion.guessCount) guesses."
                : "Daily puzzle failed."
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(outcome) The answer was \(model.puzzle.answer.uppercased())."
            )
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
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
        } else if !model.game.isComplete {
            Text(model.game.progress.hardModeEnabled
                ? "Hard Mode: revealed clues must be reused."
                : "Enter any accepted five-letter word.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resultPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: model.game.completion?.outcome == .solved
                ? "flag.checkered.2.crossed" : "flag.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.raceIndigo)
                .accessibilityHidden(true)
            Text(model.game.completion?.outcome == .solved ? "Finish line!" : "Race complete")
                .font(.title2.bold())
            Text("The answer was \(model.puzzle.answer.uppercased()).")
                .font(.headline)
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
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.raceIndigo.opacity(0.18), lineWidth: 1.5)
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
        return "\(seconds / 3600) hours, \(seconds / 60 % 60) minutes"
    }
}

struct DailyStatisticsView: View {
    @Bindable var model: DailyClassicModel

    var body: some View {
        ZStack {
            Color.raceBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Text("Your Daily Race")
                        .font(.largeTitle.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatisticCard(value: model.history.statistics.gamesPlayed, label: "Played")
                        StatisticCard(value: model.history.statistics.solvePercentage, label: "Solve %")
                        StatisticCard(value: model.displayedCurrentStreak, label: "Current streak")
                        StatisticCard(value: model.history.statistics.longestStreak, label: "Best streak")
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
            .background(Color.raceIndigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
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

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct GuessDistributionView: View {
    let distribution: [Int: Int]
    private var maximum: Int { max(1, distribution.values.max() ?? 0) }

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
                            Capsule().fill(Color.raceIndigo.opacity(0.1))
                            Capsule().fill(Color.raceIndigo)
                                .frame(width: max(24, proxy.size.width * CGFloat(count) / CGFloat(maximum)))
                        }
                        .overlay(alignment: .leading) {
                            Text("\(count)")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.leading, 8)
                        }
                    }
                    .frame(height: 24)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Solved in \(guess) guesses, \(distribution[guess, default: 0]) games")
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
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
        .background(Color.raceBackground)
        .navigationTitle("Settings")
    }
}

struct DailyHelpView: View {
    var body: some View {
        ZStack {
            Color.raceBackground.ignoresSafeArea()
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
