import Foundation
import SwiftUI

/// The native Create selection belongs to this action, independent of Join and
/// of the session's immutable saved request.
struct LiveCreateControls: View {
    @Bindable var live: LiveMatchSession
    let isSignedIn: Bool
    let openRoute: (AppRoute) -> Void
    @State var roundCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Rounds", selection: $roundCount) {
                Text("1 round").tag(1)
                Text("3 rounds").tag(3)
                Text("5 rounds").tag(5)
            }
            .pickerStyle(.menu)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
            Button(action: create) {
                Text("Create").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .disabled(live.isCommandInFlight || live.pendingIntent != nil)
    }

    func create() {
        guard isSignedIn else { openRoute(.account); return }
        live.createMatch(roundCount: roundCount)
        openRoute(.live)
    }
}

enum LiveMatchPresentation {
    static func normalizedJoinCode(_ value: String) -> String {
        String(value.uppercased().prefix(6))
    }

    static func countdownSeconds(startsAt: Date, displayedServerTime: Date) -> Int {
        min(3, max(0, Int(ceil(startsAt.timeIntervalSince(displayedServerTime)))))
    }

    static func roundLabel(_ snapshot: LiveMatchSnapshot, number: Int? = nil) -> String {
        "Round \(number ?? snapshot.round.number) of \(snapshot.match.roundCount)"
    }

    static func roundIdentity(_ snapshot: LiveMatchSnapshot, number: Int? = nil) -> String {
        "\(snapshot.match.id)-\(number ?? snapshot.round.number)"
    }

    static func countdownLabel(_ snapshot: LiveMatchSnapshot, seconds: Int) -> String {
        let start = seconds == 0 ? "Live race starting" : "Live race starts in \(seconds)"
        let deletion = snapshot.match.terminalReason == nil ? ""
            : ", A player account was deleted. This round will finish; remaining rounds cannot start."
        return "\(roundLabel(snapshot)), \(start)\(deletion)"
    }

    static func canStart(
        snapshot: LiveMatchSnapshot,
        displayedServerTime: Date,
        isCommandInFlight: Bool,
        hasPendingIntent: Bool = false,
        hasPendingStart: Bool = false
    ) -> Bool {
        guard !isCommandInFlight, !hasPendingIntent, !hasPendingStart,
              snapshot.match.terminalReason == nil,
              snapshot.members.count == 2,
              snapshot.members.allSatisfy({ !$0.isDeleted }),
              snapshot.members.first(where: \.isSelf)?.id == snapshot.match.creatorMemberID
        else { return false }
        if snapshot.match.status == .lobby {
            return snapshot.round.state == .pending && displayedServerTime < snapshot.match.expiresAt
        }
        return snapshot.match.status == .inProgress && snapshot.round.state == .revealed
            && snapshot.match.currentRound < snapshot.match.roundCount
    }

    static func initialDraft(snapshot: LiveMatchSnapshot, pending: LivePendingIntent?, draft: String) -> String {
        if case .guess(let matchID, _, let word, let roundNumber, _) = pending {
            return matchID == snapshot.match.id && roundNumber == snapshot.round.number ? word : ""
        }
        return draft
    }

    static func resolvedGuessClearsDraft(
        snapshot: LiveMatchSnapshot, previous: LivePendingIntent?, current: LivePendingIntent?, draft: String
    ) -> Bool {
        guard current == nil, draft.isEmpty,
              case .guess(let matchID, _, _, let roundNumber, _) = previous else { return false }
        return matchID == snapshot.match.id && roundNumber == snapshot.round.number
    }

    static func standingsTitle(_ standings: LiveMatchStandings) -> String {
        standings.isFinal ? "Final match standings" : "Match standings so far"
    }

    static func standingSummary(_ standing: LiveMatchStanding) -> String {
        "Place \(standing.placement) · \(standing.roundsSolved) rounds solved · \(standing.efficiencyPoints) efficiency points · \(standing.totalSolveDurationMilliseconds) ms total solve time"
    }

    static func rows(for player: LiveRoundPlayer?) -> [GuessRow] {
        player?.board?.map { GuessRow(word: $0.word, feedback: $0.feedback) } ?? []
    }

    static func keyboard(for player: LiveRoundPlayer?) -> KeyboardState {
        rows(for: player).reduce(into: KeyboardState()) { $0.observe($1) }
    }

    static func playerStateText(_ state: LivePlayerState) -> String {
        switch state {
        case .playing: "still playing"
        case .solved: "solved"
        case .failed: "finished without solving"
        case .timedOut: "timed out"
        case .forfeited: "forfeited"
        }
    }

    static func opponentAccessibilityLabel(
        member: LiveMatchMember,
        player: LiveRoundPlayer
    ) -> String {
        let guesses = player.acceptedGuessCount == 1 ? "one guess" : "\(player.acceptedGuessCount) guesses"
        return "Opponent \(member.displayName), \(guesses) submitted, \(playerStateText(player.state))."
    }

    static func errorMessage(_ error: LiveMatchServiceError?) -> String? {
        guard let error else { return nil }
        return switch error {
        case .invalidResponse:
            "This live match needs a newer compatible response. Try again."
        case .unavailable:
            "The live match is unavailable. Check your connection and try again."
        case .server(let error):
            switch error {
            case .notAuthenticated: "Sign in again to continue this live match."
            case .notAMatchMember: "This room is no longer available to this account."
            case .matchNotJoinable: "This room can no longer be joined."
            case .roomFull: "This room already has two players."
            case .roomExpired: "This room has expired."
            case .notHost: "Only the room creator can start the race."
            case .notEnoughPlayers: "Two players are required to start."
            case .roundNotActive: "The round is not accepting guesses yet."
            case .roundAlreadyFinished: "The round has finished. Refreshing the result."
            case .invalidMatchConfiguration: "Choose 1, 3, or 5 rounds."
            case .matchIncomplete: "This match cannot continue because a player account was deleted."
            case .invalidGuessFormat: "Enter exactly five English letters."
            case .wordNotAccepted: "That word is not accepted. Try another word."
            case .rateLimited: "Too many attempts. Retry this same guess in a moment."
            case .clientUpdateRequired: "Update GridRace to continue this live match."
            case .requestConflict: "This pending guess conflicts with the saved request. Retry or discard it."
            case .internalError: "The live match could not finish that request. Try again."
            }
        }
    }

    static func revealBoards(snapshot: LiveMatchSnapshot, round: LiveRound? = nil) -> [LiveRevealBoard] {
        let players = Dictionary(uniqueKeysWithValues: (round ?? snapshot.round).players.map { ($0.memberID, $0) })
        return snapshot.members
            .sorted { lhs, rhs in
                if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
                return lhs.seat < rhs.seat
            }
            .compactMap { member in
                guard let player = players[member.id], let board = player.board else { return nil }
                return LiveRevealBoard(member: member, player: player, rows: board)
            }
    }
}

struct LiveRevealBoard: Equatable, Sendable {
    let member: LiveMatchMember
    let player: LiveRoundPlayer
    let rows: [LiveGuess]
}

struct LiveMatchFlowView: View {
    @Bindable var session: LiveMatchSession
    let hapticsEnabled: Bool
    let highContrast: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var retainedError: String?
    @State private var retainsDraftError = false

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            VStack(spacing: 0) {
                if showsTopError, !showsSavedRecovery,
                   let message = retainedError ?? LiveMatchPresentation.errorMessage(session.lastError) {
                    ScrollView {
                        LiveErrorBanner(message: message, retry: retryAction).padding()
                    }
                    .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 220 : 130)
                }
                content
                if session.snapshot?.round.state != .playing, showsSavedRecovery {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let message = retainedError ?? LiveMatchPresentation.errorMessage(session.lastError) {
                                Text(message).font(.callout.weight(.semibold))
                                    .foregroundStyle(Color.raceDanger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            pendingDecisionActions
                        }.padding()
                    }
                    .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 300 : 180)
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .navigationTitle("Live Race")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Home", systemImage: "house") { goHome() }
            }
        }
        .onChange(of: session.snapshot.map { LiveMatchPresentation.roundIdentity($0) }) { _, _ in
            retainedError = nil
            retainsDraftError = false
        }
        .onChange(of: session.lastError) { _, error in
            if let message = LiveMatchPresentation.errorMessage(error) {
                retainedError = message
                retainsDraftError = error == .server(.invalidGuessFormat)
                    || error == .server(.wordNotAccepted)
            } else if !retainsDraftError {
                retainedError = nil
            }
        }
        .onChange(of: session.guessDraft) { _, draft in
            if draft.isEmpty, session.lastError == nil { retainedError = nil }
        }
        .onChange(of: retainedError) { _, value in
            if value == nil { retainsDraftError = false }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .needsSignIn:
            LiveUnavailableView(
                title: "Sign in required",
                message: "Open Account to sign in, then resume this match from Home.",
                symbol: "person.crop.circle.badge.exclamationmark",
                retry: nil,
                discardTitle: "Discard saved request",
                discard: nil
            )
        case .storageUnavailable:
            LiveUnavailableView(
                title: "Live recovery unavailable",
                message: "GridRace could not read or remove saved live recovery data. A previous command may still be unresolved.",
                symbol: "externaldrive.badge.exclamationmark",
                retry: session.canRetryRecoveryStorage ? { session.retry() } : nil,
                discardTitle: "Discard saved recovery data",
                discard: session.canDiscardRecovery ? { session.discardRecovery() } : nil
            )
        default:
            if let snapshot = session.snapshot {
                snapshotView(snapshot)
            } else if session.phase == .recovering {
                VStack(spacing: 18) {
                    ProgressView("Recovering live match")
                    Text("Waiting for a canonical server snapshot.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .accessibilityElement(children: .contain)
            } else {
                LiveUnavailableView(
                    title: "Live match unavailable",
                    message: retainedError ?? LiveMatchPresentation.errorMessage(session.lastError)
                        ?? "Return Home or try recovering the saved match.",
                    symbol: "wifi.exclamationmark",
                    retry: session.canRetry ? { session.retry() } : nil,
                    discardTitle: "Discard saved request",
                    discard: discardAction
                )
            }
        }
    }

    @ViewBuilder
    private func snapshotView(_ snapshot: LiveMatchSnapshot) -> some View {
        switch snapshot.round.state {
        case .pending:
            LiveLobbyView(session: session, snapshot: snapshot)
        case .countdown:
            LiveCountdownView(session: session, snapshot: snapshot)
                .id(LiveMatchPresentation.roundIdentity(snapshot))
        case .playing:
            LiveRoundView(
                session: session,
                snapshot: snapshot,
                hapticsEnabled: hapticsEnabled,
                highContrast: highContrast,
                retainedError: $retainedError
            )
            .id(LiveMatchPresentation.roundIdentity(snapshot))
        case .revealed:
            LiveRevealView(
                session: session,
                snapshot: snapshot,
                highContrast: highContrast,
                goHome: goHome
            )
        }
    }

    private var retryAction: (() -> Void)? {
        guard session.canRetry else { return nil }
        return {
            guard session.canRetry else { return }
            retainedError = nil
            session.retry()
        }
    }

    private var showsTopError: Bool {
        session.snapshot?.round.state != .playing
    }

    private var discardAction: (() -> Void)? {
        switch session.pendingIntent {
        case .create?: { session.discardPendingCreate() }
        case .guess?: { session.discardPendingGuess() }
        case nil: nil
        }
    }

    private var showsSavedRecovery: Bool {
        session.hasPendingStart || (session.pendingIntent != nil
            && (session.lastError == .server(.requestConflict) || session.lastError == .server(.rateLimited)))
    }

    @ViewBuilder
    private var pendingDecisionActions: some View {
        if session.hasPendingStart {
            VStack(spacing: 8) {
                Text("Saved Start is unresolved. Retry the original round.")
                    .font(.callout).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { session.retry() } label: {
                    Text("Retry saved Start").fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .disabled(!session.canRetry)
            }
        } else if session.pendingIntent != nil,
           session.lastError == .server(.requestConflict)
            || session.lastError == .server(.rateLimited) {
            VStack(spacing: 10) {
                Button { session.retry() } label: {
                    Text("Retry saved request").fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).disabled(!session.canRetry)
                if let discardAction {
                    Button(role: .destructive, action: discardAction) {
                        Text("Discard saved request").fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func goHome() {
        session.leaveToHome()
        dismiss()
    }
}

private struct LiveErrorBanner: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.raceDanger)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Retry", action: retry).buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.raceDanger, lineWidth: 1.5) }
        .accessibilityElement(children: .contain)
    }
}

private struct LiveUnavailableView: View {
    let title: String
    let message: String
    let symbol: String
    let retry: (() -> Void)?
    let discardTitle: String
    let discard: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let retry { Button("Retry", action: retry).buttonStyle(.borderedProminent) }
            if let discard {
                Button(discardTitle, role: .destructive, action: discard)
                    .buttonStyle(.bordered)
            }
            NavigationLink("Open Account", value: AppRoute.account)
        }
    }
}

private struct LiveLobbyView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot

    private var displayedTime: Date { session.displayedServerTime ?? snapshot.serverTime }
    private var expired: Bool { displayedTime >= snapshot.match.expiresAt }
    private var isCreator: Bool {
        snapshot.members.first(where: \LiveMatchMember.isSelf)?.id == snapshot.match.creatorMemberID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("PRIVATE ROOM")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.match.roundCount == 1 ? "1 round" : "\(snapshot.match.roundCount) rounds")
                        .font(.headline)
                    Text(snapshot.match.joinCode)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .tracking(4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel("Room code \(snapshot.match.joinCode.map(String.init).joined(separator: " "))")
                    Label(localStatus, systemImage: localStatusSymbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.raceInset, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("PLAYERS")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                    ForEach(snapshot.members, id: \.id) { member in
                        HStack(spacing: 12) {
                            PlayerAvatarView(seed: member.avatarSeed, size: 48)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName).font(.headline)
                                Text(member.id == snapshot.match.creatorMemberID ? "Room creator" : "Player two")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if member.isSelf {
                                Text("You")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.raceInset, in: Capsule())
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if snapshot.members.count == 1 {
                        Label("Waiting for player two", systemImage: "person.badge.clock")
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.raceLine, lineWidth: 1.5)
                }

                if expired {
                    Label("This lobby expired before the race started.", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(Color.raceDanger)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                } else if isCreator {
                    Button("Start race") { session.startMatch() }
                        .controlSize(.large)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.borderedProminent)
                        .disabled(!LiveMatchPresentation.canStart(
                            snapshot: snapshot,
                            displayedServerTime: displayedTime,
                            isCommandInFlight: session.isCommandInFlight,
                            hasPendingIntent: session.pendingIntent != nil,
                            hasPendingStart: session.hasPendingStart
                        ) || session.phase != .ready)
                    if snapshot.members.count < 2 {
                        Text("Start becomes available when the second player joins.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Waiting for the room creator to start.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 560)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var localStatus: String {
        switch session.phase {
        case .ready: "Your connection is ready"
        case .recovering: "Recovering your connection"
        case .unavailable: "Your connection is unavailable"
        default: "Checking your connection"
        }
    }

    private var localStatusSymbol: String {
        session.phase == .ready ? "checkmark.circle" : "arrow.trianglehead.2.clockwise"
    }
}

private struct LiveCountdownView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let seconds = remaining
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        Text(LiveMatchPresentation.roundLabel(snapshot)).font(.headline)
                        Text("Live race starts in")
                            .font(.title2)
                        Text(seconds == 0 ? "GO" : "\(seconds)")
                            .font(.system(size: 92, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(Color.raceCoral)
                            .contentTransition(.numericText())
                        ProgressView(value: Double(3 - seconds), total: 3)
                            .frame(maxWidth: 220)
                            .accessibilityHidden(true)
                        if snapshot.match.terminalReason != nil {
                            Text("A player account was deleted. This round will finish; remaining rounds cannot start.")
                                .font(.callout).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("The server clock controls the start. Backgrounding does not pause it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - 40))
                    .padding(.horizontal)
                    .padding(.vertical, 20)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(LiveMatchPresentation.countdownLabel(snapshot, seconds: seconds))
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityFocused($focused)
                }
            }
        }
        .onAppear { focused = true }
    }

    private var remaining: Int {
        guard let startsAt = snapshot.round.startsAt else { return 0 }
        return LiveMatchPresentation.countdownSeconds(
            startsAt: startsAt,
            displayedServerTime: session.displayedServerTime ?? snapshot.serverTime
        )
    }
}

private struct LiveRoundView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot
    let hapticsEnabled: Bool
    let highContrast: Bool
    @Binding var retainedError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var acceptsHardwareInput: Bool
    @AccessibilityFocusState private var errorFocus: Int?
    @State private var draft = ""
    @State private var errorGeneration = 0
    @State private var previousAcceptedCount = 0

    private var selfMember: LiveMatchMember? { snapshot.members.first(where: \LiveMatchMember.isSelf) }
    private var selfPlayer: LiveRoundPlayer? {
        guard let selfMember else { return nil }
        return snapshot.round.players.first { $0.memberID == selfMember.id }
    }
    private var rows: [GuessRow] { LiveMatchPresentation.rows(for: selfPlayer) }
    private var keyboard: KeyboardState { LiveMatchPresentation.keyboard(for: selfPlayer) }
    private var canInput: Bool {
        selfPlayer?.state == .playing
            && !session.isInputLocked
            && !session.isCommandInFlight
            && session.pendingIntent == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    roundHeader
                    if snapshot.match.terminalReason != nil {
                        Text("A player account was deleted. Finish this round; the match cannot continue afterward.")
                            .font(.callout).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    ForEach(snapshot.members.filter { !$0.isSelf }, id: \.id) { member in
                        if let player = snapshot.round.players.first(where: { $0.memberID == member.id }) {
                            LiveOpponentRow(member: member, player: player)
                        }
                    }
                    BoardView(rows: rows, draft: draft, isPlaying: canInput, highContrast: highContrast)
                        .dynamicTypeSize(.large)
                        .padding(.horizontal)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: rows.count)
                    status
                }
                .frame(maxWidth: 620)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }

            if canInput {
                LetterKeyboardView(
                    keyboard: keyboard,
                    typeLetter: typeLetter,
                    submit: submit,
                    delete: deleteLetter,
                    highContrast: highContrast
                )
                // Fixed five-letter board and keyboard glyphs retain their shape;
                // surrounding instructions and semantic labels keep full Dynamic Type.
                .dynamicTypeSize(.large)
                .padding(.vertical, 8)
                .background(Color.racePage)
                .overlay(alignment: .top) { Color.raceLine.frame(height: 1) }
            }
        }
        .focusable(canInput)
        .focused($acceptsHardwareInput)
        .onAppear {
            previousAcceptedCount = selfPlayer?.acceptedGuessCount ?? 0
            if draft.isEmpty {
                draft = LiveMatchPresentation.initialDraft(
                    snapshot: snapshot, pending: session.pendingIntent, draft: session.guessDraft
                )
            }
            acceptsHardwareInput = canInput
        }
        .onChange(of: session.guessDraft) { _, value in draft = value }
        .onChange(of: session.pendingIntent) { previous, current in
            if LiveMatchPresentation.resolvedGuessClearsDraft(
                snapshot: snapshot, previous: previous, current: current, draft: session.guessDraft
            ) {
                draft = ""
                retainedError = nil
            }
        }
        .onChange(of: selfPlayer?.acceptedGuessCount ?? 0) { oldValue, newValue in
            if newValue > oldValue || newValue > previousAcceptedCount {
                draft = ""
                retainedError = nil
            }
            previousAcceptedCount = newValue
        }
        .onChange(of: canInput) { _, value in acceptsHardwareInput = value }
        .onChange(of: retainedError) { _, message in
            guard message != nil else {
                errorFocus = nil
                return
            }
            errorGeneration += 1
            errorFocus = errorGeneration
        }
        .onKeyPress(.return) { submit(); return .handled }
        .onKeyPress(.delete) { deleteLetter(); return .handled }
        .onKeyPress(characters: .letters) { press in
            guard let letter = press.characters.first else { return .ignored }
            typeLetter(letter)
            return .handled
        }
        .sensoryFeedback(trigger: rows.count) { oldValue, newValue in
            hapticsEnabled && newValue > oldValue ? .impact(weight: .light) : nil
        }
    }

    private var roundHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(LiveMatchPresentation.roundLabel(snapshot)).font(.headline)
                Text(localConnectionText).font(.caption).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Label(remainingTime, systemImage: "timer")
                    .font(.headline.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(remainingSeconds) seconds remaining")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var status: some View {
        if session.pendingIntent != nil,
           session.lastError == .server(.requestConflict) || session.lastError == .server(.rateLimited) {
            VStack(spacing: 8) {
                Text("Resolve the original saved guess before continuing.").font(.callout)
                if let retainedError { Text(retainedError).foregroundStyle(Color.raceDanger) }
                Button { session.retry() } label: {
                    Text("Retry saved request").fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).disabled(!session.canRetry)
                Button(role: .destructive) { session.discardPendingGuess() } label: {
                    Text("Discard saved request").fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }.padding()
        } else if let player = selfPlayer, player.state.isTerminal {
            VStack(spacing: 8) {
                Text(terminalTitle(player.state)).font(.title3.bold())
                Text("Your accepted board is locked. Waiting for the canonical shared reveal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if session.phase == .recovering {
                    ProgressView("Recovering your connection")
                } else if session.phase == .unavailable {
                    if let retainedError { Text(retainedError).foregroundStyle(Color.raceDanger) }
                    Button("Retry") { session.retry() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.canRetry)
                }
            }
            .padding()
            .accessibilityElement(children: .contain)
        } else if session.pendingIntent != nil || session.isCommandInFlight {
            VStack(spacing: 10) {
                ProgressView("Recovering your submitted guess")
                Text("New submission is locked until the saved request is resolved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let retainedError {
                    Text(retainedError)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.raceDanger)
                        .multilineTextAlignment(.center)
                }
                if session.lastError == .server(.requestConflict)
                    || session.lastError == .server(.rateLimited) {
                    HStack {
                        Button("Retry") { session.retry() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!session.canRetry)
                        Button("Discard", role: .destructive) { session.discardPendingGuess() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal)
        } else if session.phase == .recovering || session.phase == .unavailable {
            VStack(spacing: 8) {
                if session.phase == .recovering {
                    ProgressView("Recovering your connection")
                } else {
                    Text(retainedError ?? "Your live connection is unavailable.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.raceDanger)
                        .multilineTextAlignment(.center)
                    Button("Retry") { session.retry() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.canRetry)
                }
                Text("Your accepted board is preserved. New input stays locked until recovery finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .accessibilityFocused($errorFocus, equals: errorGeneration)
        } else if session.isInputLocked {
            VStack(spacing: 8) {
                ProgressView("Checking the final server state")
                Text("The local timer ended. Only the server can finalize and reveal this round.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
        } else if let retainedError {
            LiveErrorBanner(message: retainedError, retry: nil)
                .padding(.horizontal)
                .accessibilityFocused($errorFocus, equals: errorGeneration)
        } else {
            Text("Enter a five-letter word. The server validates every live guess.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var remainingSeconds: Int {
        guard let endsAt = snapshot.round.endsAt else { return 0 }
        return max(0, Int(ceil(endsAt.timeIntervalSince(session.displayedServerTime ?? snapshot.serverTime))))
    }

    private var remainingTime: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var localConnectionText: String {
        switch session.phase {
        case .ready: "Your connection is ready"
        case .recovering: "Recovering your connection"
        case .unavailable: "Your connection is unavailable"
        default: "Checking your connection"
        }
    }

    private func terminalTitle(_ state: LivePlayerState) -> String {
        switch state {
        case .solved: "Solved — waiting for reveal"
        case .failed: "Six guesses used — waiting for reveal"
        case .timedOut: "Time ended — waiting for reveal"
        case .forfeited: "Round forfeited — waiting for reveal"
        case .playing: "Round in progress"
        }
    }

    private func typeLetter(_ letter: Character) {
        guard canInput, draft.utf8.count < 5,
              String(letter).utf8.count == 1,
              let byte = String(letter).utf8.first,
              (65...90).contains(byte) || (97...122).contains(byte)
        else { return }
        draft.append(Character(String(letter).uppercased()))
        retainedError = nil
        errorFocus = nil
    }

    private func deleteLetter() {
        guard canInput, !draft.isEmpty else { return }
        draft.removeLast()
        retainedError = nil
        errorFocus = nil
    }

    private func submit() {
        guard canInput else { return }
        guard draft.utf8.count == 5 else {
            let message = "Enter exactly five letters."
            if retainedError == message {
                errorGeneration += 1
                errorFocus = errorGeneration
            } else {
                retainedError = message
            }
            return
        }
        retainedError = nil
        session.submitGuess(draft)
    }
}
