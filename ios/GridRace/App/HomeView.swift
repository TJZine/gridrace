import SwiftUI

struct DailyHomeView: View {
    @Bindable var model: DailyClassicModel
    @Bindable var account: AccountModel
    @Bindable var live: LiveMatchSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let syncMessage: String?
    let isDailyPlayable: Bool
    let retryDailyStorage: () -> Void
    let openRoute: (AppRoute) -> Void
    @State private var joinCode = ""

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    brandHeader
                    dailyCard
                    statisticsStrip
                    liveCard
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
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.raceIndigo)
                    .accessibilityHidden(true)
                Text("GRIDRACE")
                    .font(.title3.bold())
                    .tracking(1.5)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("GridRace")
            // Only this decorative brand row is capped at accessibility
            // sizes, so the flag and word stay on one compact line while
            // Daily, account, Learn, and game content keep scaling.
            .dynamicTypeSize(dynamicTypeSize.isAccessibilitySize ? .large : dynamicTypeSize)
            if !dynamicTypeSize.isAccessibilitySize {
                Text("One grid. One day. Make every row count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    private var dailyCard: some View {
        HStack(spacing: 0) {
            // Brand signature lane edge: fixed indigo, never a status color.
            Color.raceIndigo
                .frame(width: 5)
                .accessibilityHidden(true)
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
        }
        .background(Color.raceCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var statisticsStrip: some View {
        NavigationLink(value: AppRoute.statistics) {
            HStack(spacing: 0) {
                HomeMetric(value: "\(model.displayedCurrentStreak)", label: "Current streak", emphasized: true)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("LEARN")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                NavigationLink(value: AppRoute.help) {
                    HomeRouteLabel(title: "How to play", subtitle: "Rules and tile evidence", symbol: "questionmark.circle")
                }
                Divider().padding(.leading, 70)
                NavigationLink(value: AppRoute.tutorial) {
                    HomeRouteLabel(title: "Practice race", subtitle: "Revisit the local tutorial", symbol: "figure.run")
                }
            }
            .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.raceLine, lineWidth: 1.5)
            }
        }
        .padding(.top, 12)
        .buttonStyle(.plain)
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LIVE RACE")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(Color.raceIndigo)
                    Text("Private two-player race")
                        .font(.headline)
                    Text("1, 3, or 5 private server rounds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundStyle(Color.raceIndigo)
                    .accessibilityHidden(true)
            }

            if live.phase == .storageUnavailable {
                Button {
                    openRoute(.live)
                } label: {
                    Label("Resolve saved live data", systemImage: "externaldrive.badge.exclamationmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Text("Live recovery data could not be removed. Retry or discard it before creating or joining another race.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if live.hasSavedMatch {
                Button {
                    live.resumeSavedMatch()
                    openRoute(.live)
                } label: {
                    Label("Resume live match", systemImage: "arrow.clockwise.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }

            if live.phase != .storageUnavailable {
                LiveCreateControls(live: live, isSignedIn: account.isSignedIn, openRoute: openRoute)
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 10) { liveControls }
                    } else {
                        HStack(spacing: 10) { liveControls }
                    }
                }

                if !account.isSignedIn {
                    Text("Create and Join open Account first. Daily Classic stays available without signing in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.raceLine, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var liveControls: some View {
        TextField("Room code", text: $joinCode)
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 44)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .textContentType(.oneTimeCode)
            .font(.body.monospaced())
            .accessibilityLabel("Six-character room code")
            .onChange(of: joinCode) { _, value in
                let normalized = LiveMatchPresentation.normalizedJoinCode(value)
                if normalized != value { joinCode = normalized }
            }

        Button("Join") {
            guard account.isSignedIn else {
                openRoute(.account)
                return
            }
            live.joinMatch(code: joinCode)
            openRoute(.live)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
        .disabled(joinCode.count != 6 || live.isCommandInFlight)
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
    var emphasized = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(emphasized ? .title2.weight(.semibold).monospacedDigit() : .title3.weight(.medium).monospacedDigit())
                .foregroundStyle(emphasized ? .primary : .secondary)
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
