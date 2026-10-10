import Foundation
import SwiftUI

/// The native Create selection belongs to this action, independent of Join and
/// of the session's immutable saved request.
struct LiveCreateControls: View {
    @Bindable var live: LiveMatchSession
    let isSignedIn: Bool
    let openRoute: (AppRoute) -> Void
    @State var roundCount = 3
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                rounds.pickerStyle(.menu)
            } else {
                rounds.pickerStyle(.segmented)
            }
            Button(action: create) {
                Text("Create room").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(OutlinedInkButtonStyle())
        }
        .disabled(live.isCommandInFlight || live.pendingIntent != nil)
    }

    private var rounds: some View {
        Picker("Rounds", selection: $roundCount) {
            Text("1 round").tag(1)
            Text("3 rounds").tag(3)
            Text("5 rounds").tag(5)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
    }

    func create() {
        guard isSignedIn else { openRoute(.account); return }
        live.createMatch(roundCount: roundCount)
        openRoute(.live)
    }
}

enum LiveMatchPresentation {
    enum Surface: Equatable { case entry, notice, lobby, countdown, round, reveal }
    enum Action: Equatable {
        case account, backToRace, retry, retryStorage, retryStart, retryRequest
        case discardCreate, discardGuess, discardRecovery
        case resume, create, join, copyCode, shareCode, start, selectReveal, home
    }
    struct Control: Equatable {
        let action: Action
        var enabled = true
    }
    struct Notice: Equatable {
        let subject: String
        let title: String
        let body: String
        var requiresAction = false
        var controls: [Control] = []
        var showsProgress = false
        var seal = false
        var usesClaret = false
    }
    /// A value projection keeps presentation independent of session mutation and tasks.
    struct State {
        var phase: LiveMatchSessionPhase = .inactive
        var snapshot: LiveMatchSnapshot?
        var displayedReveal: LiveRound?
        var isSignedIn = true
        var hasSavedMatch = false
        var pendingIntent: LivePendingIntent?
        var hasPendingStart = false
        var isCommandInFlight = false
        var canRetry = false
        var canRetryRecoveryStorage = false
        var canDiscardRecovery = false
        var canStart = false
        var isInputLocked = true
        var error: LiveMatchServiceError?
        var retainedError: String?
        var displayedTime: Date?
        var joinCode = ""

        @MainActor
        init(session: LiveMatchSession, isSignedIn: Bool = true, retainedError: String? = nil, joinCode: String = "") {
            phase = session.phase
            snapshot = session.snapshot
            displayedReveal = session.displayedReveal
            self.isSignedIn = isSignedIn
            hasSavedMatch = session.hasSavedMatch
            pendingIntent = session.pendingIntent
            hasPendingStart = session.hasPendingStart
            isCommandInFlight = session.isCommandInFlight
            canRetry = session.canRetry
            canRetryRecoveryStorage = session.canRetryRecoveryStorage
            canDiscardRecovery = session.canDiscardRecovery
            canStart = session.canStart
            isInputLocked = session.isInputLocked
            error = session.lastError
            self.retainedError = retainedError
            displayedTime = session.displayedServerTime
            self.joinCode = joinCode
        }

        init() {}
    }
    struct Presentation: Equatable {
        var surface: Surface = .notice
        var notice: Notice?
        var topNotice: Notice?
        var savedNotice: Notice?
        var deletionNotice: Notice?
        var priorRevealNotice: Notice?
        var inlineError: String?
        var controls: [Control] = []

        func permits(_ action: Action) -> Bool {
            controls.contains { $0.action == action && $0.enabled }
        }
    }

    /// The single state-to-copy/action mapping. It never calculates gameplay results.
    static func map(_ state: State) -> Presentation {
        let message = state.retainedError ?? errorMessage(state.error)
        let retry = Control(action: .retry, enabled: state.canRetry)
        let discard: Action? = switch state.pendingIntent {
        case .create?: .discardCreate
        case .guess?: .discardGuess
        case nil: nil
        }
        let decision = state.pendingIntent != nil
            && (state.error == .server(.requestConflict) || state.error == .server(.rateLimited))
        var result = Presentation(controls: [Control(action: .home)])
        if state.phase == .needsSignIn {
            result.notice = Notice(subject: "Account", title: "Your sign-in expired",
                body: "Your race is saved on this device. Go back to the race to try again; signing out removes it.",
                requiresAction: true, controls: [.init(action: .backToRace), .init(action: .account)])
            return result
        }
        if state.phase == .storageUnavailable {
            var actions: [Control] = []
            if state.canRetryRecoveryStorage { actions.append(.init(action: .retryStorage)) }
            if state.canDiscardRecovery { actions.append(.init(action: .discardRecovery)) }
            actions.append(.init(action: .account))
            result.notice = Notice(subject: "Room", title: "Couldn't open your saved race",
                body: "Saved race data on this device couldn't be read or cleared.", requiresAction: true, controls: actions)
            return result
        }
        if state.snapshot?.round.state != .playing {
            if state.hasPendingStart {
                result.savedNotice = Notice(subject: "Room", title: "Round didn't start yet",
                    body: "Retry starts the same round.", requiresAction: true,
                    controls: [.init(action: .retryStart, enabled: state.canRetry)])
            } else if decision {
                result.savedNotice = Notice(subject: "Room", title: "Your saved request needs a decision",
                    body: message ?? "Retry or discard it.", requiresAction: true,
                    controls: [.init(action: .retryRequest, enabled: state.canRetry)]
                        + (discard.map { [.init(action: $0)] } ?? []))
            }
        }
        guard let snapshot = state.snapshot else {
            if state.phase == .inactive {
                if state.isSignedIn {
                    result.surface = .entry
                    if state.hasSavedMatch { result.controls.append(.init(action: .resume)) }
                    result.controls += [.init(action: .create, enabled: !state.isCommandInFlight && state.pendingIntent == nil),
                                        .init(action: .join, enabled: state.joinCode.count == 6 && !state.isCommandInFlight)]
                } else {
                    result.notice = Notice(subject: "Account", title: "Sign in to race",
                        body: "Live races need a player name. Daily stays open without an account.",
                        requiresAction: true, controls: [.init(action: .account)])
                }
            } else if state.phase == .recovering {
                result.notice = Notice(subject: "Room", title: "Connecting to your race",
                    body: "Hang tight. This only takes a moment.", showsProgress: true)
            } else {
                var actions: [Control] = []
                if result.savedNotice == nil {
                    if state.canRetry { actions.append(retry) }
                    if let discard { actions.append(.init(action: discard)) }
                }
                actions += [.init(action: .backToRace), .init(action: .account)]
                result.notice = Notice(subject: "Room", title: "Race unavailable",
                    body: message ?? "Go back and try reopening your race.", requiresAction: true, controls: actions)
            }
            return result
        }
        let isHost = snapshot.members.first(where: \.isSelf)?.id == snapshot.match.creatorMemberID
        let host = snapshot.members.first { $0.id == snapshot.match.creatorMemberID }?.displayName ?? "the host"
        let opponent = snapshot.members.first { !$0.isSelf }?.displayName ?? "player two"
        let time = state.displayedTime ?? snapshot.serverTime
        let canStart = state.canStart
        if snapshot.round.state != .playing, result.savedNotice == nil, let message {
            result.topNotice = Notice(subject: "Room", title: message, body: "", requiresAction: true,
                controls: state.canRetry ? [retry] : [])
        }
        if snapshot.match.terminalReason != nil && (snapshot.round.state == .countdown || snapshot.round.state == .playing) {
            result.deletionNotice = Notice(subject: "Room", title: "Your opponent left GridRace",
                body: "Finish this round. It's the last one in this match.")
        }
        switch snapshot.round.state {
        case .pending:
            result.surface = .lobby
            if time < snapshot.match.expiresAt {
                result.controls += [.init(action: .copyCode), .init(action: .shareCode)]
            }
            if time >= snapshot.match.expiresAt {
                result.notice = Notice(subject: "Room", title: "This room closed", body: "It expired before the race started.")
            } else if isHost && snapshot.members.count < 2 {
                result.notice = Notice(subject: "Room", title: "Waiting for player two", body: "Share the code to invite them.")
            } else if isHost {
                result.controls.append(.init(action: .start, enabled: canStart))
            } else {
                result.notice = Notice(subject: "Room", title: "Waiting for \(host)", body: "The host starts each round.")
            }
        case .countdown:
            result.surface = .countdown
            result.notice = Notice(subject: "Time", title: roundLabel(snapshot),
                body: "Starts on the server clock. Leaving the app won't pause it.")
        case .playing:
            result.surface = .round
            let ownID = snapshot.members.first(where: \.isSelf)?.id
            let player = snapshot.round.players.first { $0.memberID == ownID }
            if decision {
                result.notice = Notice(subject: "Guess", title: "Your guess needs a decision",
                    body: message ?? "Retry or discard it.", requiresAction: true,
                    controls: [.init(action: .retryRequest, enabled: state.canRetry), .init(action: .discardGuess)])
            } else if let player, player.state.isTerminal {
                let title: String = switch player.state {
                case .solved: "Solved in \(player.acceptedGuessCount)"
                case .failed: "Out of guesses"
                case .timedOut: "Time's up"
                case .forfeited: "Round forfeited"
                case .playing: "Round in progress"
                }
                result.notice = Notice(subject: "Round", title: title, body: "Waiting for \(opponent)",
                    controls: state.phase == .unavailable ? [retry] : [],
                    showsProgress: state.phase == .recovering, seal: true, usesClaret: player.state == .solved)
            } else if state.pendingIntent != nil || state.isCommandInFlight {
                result.notice = Notice(subject: "Guess", title: "Sending your guess",
                    body: "Typing is locked until it's confirmed.", showsProgress: true)
            } else if state.phase == .recovering || state.phase == .unavailable {
                result.notice = Notice(subject: "Room", title: state.phase == .recovering ? "Reconnecting" : "Connection lost",
                    body: "Your board is saved. Typing resumes when you're back.", requiresAction: state.phase == .unavailable,
                    controls: state.phase == .unavailable ? [retry] : [], showsProgress: state.phase == .recovering)
            } else if state.isInputLocked {
                result.notice = Notice(subject: "Time", title: "Time's up", body: "Getting the final result for this round.", showsProgress: true)
            } else {
                result.inlineError = message
            }
        case .revealed:
            result.surface = .reveal
            let round = state.displayedReveal ?? snapshot.round
            if round.number != snapshot.round.number {
                result.priorRevealNotice = Notice(subject: "Round", title: "Round \(round.number) reveal",
                    body: "Current match: \(roundLabel(snapshot)).")
            }
            if round.answer == nil || revealBoards(snapshot: snapshot, round: round).count != snapshot.members.count {
                result.notice = Notice(subject: "Round", title: "Reveal on its way", body: "The full reveal hasn't arrived yet.")
                return result
            }
            if snapshot.revealedRounds.count > 1 { result.controls.append(.init(action: .selectReveal)) }
            if snapshot.match.status == .incomplete {
                let unplayed = snapshot.match.currentRound < snapshot.match.roundCount
                    ? "; round \(snapshot.match.currentRound + 1) won't be played." : "."
                result.notice = Notice(subject: "Match", title: "Match incomplete",
                    body: "Your opponent left GridRace after round \(snapshot.match.currentRound). The rounds you played are saved\(unplayed)", seal: true)
            } else if snapshot.standings?.isFinal == true {
                let winners = snapshot.standings?.players.filter { $0.placement == 1 } ?? []
                let winner = snapshot.members.first { $0.id == winners.first?.memberID }
                let title = winners.count > 1 ? "Tied"
                    : winner?.isSelf == true ? "You won" : "\(winner?.displayName ?? "Winner") won"
                result.notice = Notice(subject: "Match", title: title,
                    body: "Final match standings", seal: true, usesClaret: true)
            } else if snapshot.match.status == .inProgress && snapshot.match.terminalReason == nil
                        && snapshot.match.currentRound < snapshot.match.roundCount {
                if isHost { result.controls.append(.init(action: .start, enabled: canStart)) }
                else {
                    result.notice = Notice(subject: "Room", title: "Waiting for \(host)",
                        body: "They'll start \(roundLabel(snapshot, number: snapshot.match.currentRound + 1).lowercased()).")
                }
            }
        }
        return result
    }

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
            case .rateLimited: "Try again in a moment."
            case .clientUpdateRequired: "Update GridRace to continue this live match."
            case .requestConflict: "Retry or discard it."
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
    var isSignedIn = true
    var openAccount: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var codeLetterWidth: CGFloat = 10.2
    @State private var retainedError: String?
    @State private var retainsDraftError = false
    @State private var joinCode = ""
    @State private var discardConfirmation: LiveMatchPresentation.Action?

    private var presentation: LiveMatchPresentation.Presentation {
        LiveMatchPresentation.map(.init(session: session, isSignedIn: isSignedIn,
            retainedError: retainedError, joinCode: joinCode))
    }

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
            if presentation.surface == .round, let snapshot = session.snapshot {
                LiveRoundView(session: session, snapshot: snapshot, hapticsEnabled: hapticsEnabled,
                    highContrast: highContrast, retainedError: $retainedError, perform: perform)
                    .id(LiveMatchPresentation.roundIdentity(snapshot))
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 16) {
                            if let notice = presentation.topNotice { LiveControlNotice(notice: notice, perform: perform) }
                            content
                            if let notice = presentation.savedNotice { LiveControlNotice(notice: notice, perform: perform) }
                        }
                        .frame(maxWidth: 620)
                        .frame(minHeight: max(0, geometry.size.height - 32))
                        .padding(16)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .confirmationDialog("Discard this saved race data?", isPresented: Binding(
            get: { discardConfirmation != nil },
            set: { if !$0 { discardConfirmation = nil } }
        ), titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                guard let action = discardConfirmation else { return }
                discardConfirmation = nil
                switch action {
                case .discardCreate: session.discardPendingCreate()
                case .discardGuess: session.discardPendingGuess()
                case .discardRecovery: session.discardRecovery()
                default: break
                }
            }
            Button("Cancel", role: .cancel) { discardConfirmation = nil }
        } message: {
            Text("This removes the saved data from this device. It can't undo a guess or race already accepted.")
        }
        .navigationTitle("Live race")
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
        switch presentation.surface {
        case .entry:
            VStack(alignment: .leading, spacing: 24) {
                Text("Live race").font(StampType.display)
                if presentation.permits(.resume) {
                    Button { session.resumeSavedMatch() } label: {
                        Label("Resume saved race", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(InkButtonStyle())
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Host a race").font(StampType.title2.bold())
                    LiveCreateControls(live: session, isSignedIn: isSignedIn, openRoute: { route in
                        if route == .account { openAccount() }
                    })
                }.padding(16).paperCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Join a race").font(StampType.title2.bold())
                    joinField
                    Button("Join", action: join)
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(InkButtonStyle())
                        .disabled(!presentation.permits(.join))
                }.padding(16).paperCard()
            }
        case .notice:
            if let notice = presentation.notice { LiveControlNotice(notice: notice, perform: perform) }
        case .lobby:
            if let snapshot = session.snapshot { LiveLobbyView(session: session, snapshot: snapshot, perform: perform) }
        case .countdown:
            if let snapshot = session.snapshot {
                LiveCountdownView(session: session, snapshot: snapshot)
                    .id(LiveMatchPresentation.roundIdentity(snapshot))
            }
        case .reveal:
            if let snapshot = session.snapshot {
                LiveRevealView(session: session, snapshot: snapshot, highContrast: highContrast, goHome: goHome)
            }
        case .round: EmptyView()
        }
    }

    @ViewBuilder
    private var joinField: some View {
        if dynamicTypeSize.isAccessibilitySize {
            codeInput.padding(12).frame(minHeight: 44)
                .background(Color.page, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.ink, lineWidth: 1) }
        } else {
            GeometryReader { geometry in
                let cellWidth = (geometry.size.width - 20) / 6
                codeInput
                    .tracking(max(0, cellWidth + 4 - codeLetterWidth))
                    .padding(.leading, max(0, (cellWidth - codeLetterWidth) / 2))
                    .frame(maxHeight: .infinity)
                    .background {
                        HStack(spacing: 4) {
                            ForEach(0..<6) { _ in
                                RoundedRectangle(cornerRadius: 6).fill(Color.page)
                                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.ink, lineWidth: 1) }
                            }
                        }.accessibilityHidden(true)
                    }
            }.frame(height: 48)
        }
    }

    private var codeInput: some View {
        TextField("ABC234", text: $joinCode)
            .font(StampType.figure).textInputAutocapitalization(.characters)
            .autocorrectionDisabled().submitLabel(.join)
            .accessibilityLabel("Six-character room code")
            .onChange(of: joinCode) { _, value in joinCode = LiveMatchPresentation.normalizedJoinCode(value) }
            .onSubmit { join() }
    }

    private func join() {
        guard presentation.permits(.join) else { return }
        session.joinMatch(code: joinCode)
    }

    private func perform(_ action: LiveMatchPresentation.Action) {
        switch action {
        case .account: openAccount()
        case .backToRace: session.leaveToHome()
        case .retry, .retryRequest, .retryStart, .retryStorage:
            retainedError = nil
            session.retry()
        case .discardCreate, .discardGuess, .discardRecovery: discardConfirmation = action
        case .home: goHome()
        default: break
        }
    }

    private func goHome() {
        session.leaveToHome()
        dismiss()
    }
}

/// The controls are projected by the mapper; destructive intents return to the flow's native dialog.
struct LiveControlNotice: View {
    let notice: LiveMatchPresentation.Notice
    let perform: (LiveMatchPresentation.Action) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if notice.seal {
                VStack(spacing: 10) {
                    ScorecardSeal(title: notice.title, symbol: notice.usesClaret ? "checkmark" : "flag.checkered",
                        usesClaret: notice.usesClaret)
                    Text(notice.body).font(StampType.caption).fixedSize(horizontal: false, vertical: true)
                    actions
                    if notice.showsProgress { ProgressView("Reconnecting") }
                }.frame(maxWidth: .infinity).padding(14).paperCard()
            } else {
                NoticeCard(subject: notice.subject, title: notice.title, message: notice.body,
                    kind: notice.requiresAction ? .action : .information) {
                    actions
                    if notice.showsProgress { ProgressView().accessibilityLabel(notice.title) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize || notice.controls.count > 2
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(Array(notice.controls.enumerated()), id: \.offset) { index, control in
                let destructive = control.action == .discardCreate || control.action == .discardGuess || control.action == .discardRecovery
                let button = Button(role: destructive ? .destructive : nil) { perform(control.action) } label: {
                    Text(title(control.action)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }.disabled(!control.enabled)
                if index == 0 && !destructive {
                    button.buttonStyle(InkButtonStyle())
                } else {
                    button.buttonStyle(OutlinedInkButtonStyle())
                }
            }
        }
    }

    private func title(_ action: LiveMatchPresentation.Action) -> String {
        switch action {
        case .account: notice.title == "Sign in to race" ? "Sign in" : "Open account"
        case .backToRace: "Back to race"
        case .retry, .retryStorage: "Retry"
        case .retryStart: "Retry saved start"
        case .retryRequest: "Retry saved request"
        case .discardRecovery: "Discard saved race"
        case .discardCreate, .discardGuess: "Discard saved request"
        default: "Home"
        }
    }
}

private struct LiveLobbyView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot
    let perform: (LiveMatchPresentation.Action) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copied = false

    private var presentation: LiveMatchPresentation.Presentation {
        LiveMatchPresentation.map(.init(session: session))
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text(snapshot.match.roundCount == 1 ? "1 round" : "\(snapshot.match.roundCount) rounds")
                    .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                ScorecardSeal(title: snapshot.match.joinCode)
                    .accessibilityLabel("Room code \(snapshot.match.joinCode.map(String.init).joined(separator: " "))")
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                if presentation.permits(.copyCode) {
                    layout {
                        Button {
                            UIPasteboard.general.string = snapshot.match.joinCode
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc")
                                .frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(OutlinedInkButtonStyle())
                        ShareLink(item: snapshot.match.joinCode) {
                            Label("Share", systemImage: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(OutlinedInkButtonStyle())
                    }
                }
                Label(session.phase == .ready ? "Your connection is ready" : "Checking your connection",
                    systemImage: session.phase == .ready ? "checkmark.circle" : "arrow.clockwise")
                    .font(StampType.caption).foregroundStyle(Color.secondaryInk)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(snapshot.members, id: \.id) { member in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", member.seat)).font(StampType.figure)
                        PlayerAvatarView(seed: member.avatarSeed, size: 36).accessibilityHidden(true)
                        Text(member.displayName).font(StampType.heading)
                        if member.isSelf { Text("You").font(StampType.caption) }
                    }.accessibilityElement(children: .combine)
                }
                if snapshot.members.count == 1 {
                    Label("02 · Open seat", systemImage: "person.badge.clock")
                        .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).paperCard()
            if let notice = presentation.notice { LiveControlNotice(notice: notice, perform: perform) }
            if presentation.controls.contains(where: { $0.action == .start }) {
                Button("Start race") { session.startMatch() }
                    .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(InkButtonStyle())
                    .disabled(!presentation.permits(.start))
            }
        }
    }
}

private struct LiveCountdownView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot
    @AccessibilityFocusState private var focused: Bool

    private var presentation: LiveMatchPresentation.Presentation {
        LiveMatchPresentation.map(.init(session: session))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let seconds = remaining
            VStack(spacing: 18) {
                Text(presentation.notice?.title ?? LiveMatchPresentation.roundLabel(snapshot))
                    .font(StampType.heading)
                Text("Live race starts in").font(StampType.title2)
                CountdownNumeral(text: seconds == 0 ? "GO" : "\(seconds)")
                HStack(spacing: 12) {
                    ForEach(0..<3) { mark in
                        Circle().fill(mark < 3 - seconds ? Color.present : Color.line)
                            .frame(width: 8, height: 8)
                    }
                }.accessibilityHidden(true)
                if let notice = presentation.deletionNotice {
                    Text("\(notice.title). \(notice.body)")
                        .font(StampType.caption).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(presentation.notice?.body ?? "")
                    .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(LiveMatchPresentation.countdownLabel(snapshot, seconds: seconds))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityFocused($focused)
        }
        .onAppear { focused = true }
    }

    private var remaining: Int {
        guard let startsAt = snapshot.round.startsAt else { return 0 }
        return LiveMatchPresentation.countdownSeconds(startsAt: startsAt,
            displayedServerTime: session.displayedServerTime ?? snapshot.serverTime)
    }
}

private struct LiveRoundView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot
    let hapticsEnabled: Bool
    let highContrast: Bool
    @Binding var retainedError: String?
    let perform: (LiveMatchPresentation.Action) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var acceptsHardwareInput: Bool
    @AccessibilityFocusState private var errorFocus: Int?
    @AccessibilityFocusState private var slotFocus: Bool
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
    private var canInput: Bool { session.canInput }

    private var presentation: LiveMatchPresentation.Presentation {
        LiveMatchPresentation.map(.init(session: session, retainedError: retainedError))
    }

    var body: some View {
        GeometryReader { geometry in
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { roundContent.padding(.vertical, 8) }
            } else if geometry.size.width > geometry.size.height,
                      geometry.size.height < 500, geometry.size.width >= 636 {
                HStack(spacing: 8) {
                    roundBoard(compact: true)
                        .frame(width: min(320, geometry.size.width - 388))
                        .frame(maxHeight: .infinity)
                    VStack(spacing: 6) {
                        roundChrome
                        controlSlot
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 4)
            } else {
                roundContent.frame(height: geometry.size.height)
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
            slotFocus = presentation.notice != nil
        }
        .onChange(of: presentation.notice?.title) { _, title in slotFocus = title != nil }
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

    private var roundContent: some View {
        VStack(spacing: 8) {
            roundChrome
            roundBoard(compact: false)
                .padding(.horizontal, 12)
                .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : .infinity)
                .layoutPriority(-1)
            controlSlot
        }
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var roundChrome: some View {
        VStack(spacing: 6) {
            roundHeader
            if let notice = presentation.deletionNotice {
                Text("\(notice.title). \(notice.body)")
                    .font(StampType.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12)
            }
            ForEach(snapshot.members.filter { !$0.isSelf }, id: \.id) { member in
                if let player = snapshot.round.players.first(where: { $0.memberID == member.id }) {
                    OpponentLine(name: member.displayName, count: "\(player.acceptedGuessCount)/6",
                        state: opponentState(player.state),
                        stateSymbol: player.state == .playing ? "hourglass" : "flag.checkered",
                        accessibilitySummary: LiveMatchPresentation.opponentAccessibilityLabel(member: member, player: player)) {
                        PlayerAvatarView(seed: member.avatarSeed, size: 24)
                    }.padding(.horizontal, 12)
                }
            }
        }
    }

    private func roundBoard(compact: Bool) -> some View {
        BoardView(rows: rows, draft: draft, isPlaying: canInput, highContrast: highContrast,
                  compactLayout: compact)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: rows.count)
    }

    private var controlSlot: some View {
        KeyboardSlot {
            if let notice = presentation.notice {
                LiveControlNotice(notice: notice, perform: perform)
                    .padding(.horizontal, 12)
                    .accessibilityFocused($slotFocus)
            } else {
                VStack(spacing: 4) {
                    if let message = presentation.inlineError {
                        Text(message).font(StampType.caption.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .accessibilityFocused($errorFocus, equals: errorGeneration)
                    }
                    LetterKeyboardView(keyboard: keyboard, typeLetter: typeLetter, submit: submit,
                        delete: deleteLetter, highContrast: highContrast)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func opponentState(_ state: LivePlayerState) -> String {
        switch state {
        case .playing: "Playing"
        case .solved: "Solved"
        case .failed: "Finished"
        case .timedOut: "Time ended"
        case .forfeited: "Forfeited"
        }
    }

    private var roundHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(LiveMatchPresentation.roundLabel(snapshot)).font(StampType.heading)
                    .fixedSize(horizontal: false, vertical: true)
                Label(localConnectionText, systemImage: session.phase == .ready ? "checkmark.circle" : "arrow.clockwise")
                    .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }.layoutPriority(1)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Label(remainingTime, systemImage: "timer")
                    .font(StampType.figure)
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityLabel("\(remainingSeconds) seconds remaining")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .fixedSize(horizontal: false, vertical: true)
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
        case .ready: "Connected"
        case .recovering: "Reconnecting"
        case .unavailable: "Connection lost"
        default: "Checking connection"
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
