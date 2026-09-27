import Foundation
import SwiftUI

enum LiveMatchPresentation {
    static func normalizedJoinCode(_ value: String) -> String {
        String(value.uppercased().prefix(6))
    }

    static func countdownSeconds(startsAt: Date, displayedServerTime: Date) -> Int {
        min(3, max(0, Int(ceil(startsAt.timeIntervalSince(displayedServerTime)))))
    }

    static func canStart(
        snapshot: LiveMatchSnapshot,
        displayedServerTime: Date,
        isCommandInFlight: Bool
    ) -> Bool {
        guard snapshot.match.status == .lobby,
              snapshot.round.state == .pending,
              snapshot.members.count == 2,
              snapshot.members.first(where: \LiveMatchMember.isSelf)?.id
                == snapshot.match.creatorMemberID,
              displayedServerTime < snapshot.match.expiresAt
        else { return false }
        return !isCommandInFlight
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
            case .invalidGuessFormat: "Enter exactly five English letters."
            case .wordNotAccepted: "That word is not accepted. Try another word."
            case .rateLimited: "Too many attempts. Retry this same guess in a moment."
            case .clientUpdateRequired: "Update GridRace to continue this live match."
            case .requestConflict: "This pending guess conflicts with the saved request. Retry or discard it."
            case .internalError: "The live match could not finish that request. Try again."
            }
        }
    }

    static func revealBoards(snapshot: LiveMatchSnapshot) -> [LiveRevealBoard] {
        let players = Dictionary(uniqueKeysWithValues: snapshot.round.players.map { ($0.memberID, $0) })
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
    @State private var retainedError: String?
    @State private var retainsDraftError = false

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            VStack(spacing: 0) {
                if showsTopError,
                   let message = retainedError ?? LiveMatchPresentation.errorMessage(session.lastError) {
                    RaceErrorBanner(message: message, retry: retryAction)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                content
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
                    pendingDecisionActions
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
                    retry: session.hasSavedMatch ? { session.retry() } : nil,
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
        case .playing:
            LiveRoundView(
                session: session,
                snapshot: snapshot,
                hapticsEnabled: hapticsEnabled,
                highContrast: highContrast,
                retainedError: $retainedError
            )
        case .revealed:
            LiveRevealView(
                snapshot: snapshot,
                highContrast: highContrast,
                goHome: goHome
            )
        }
    }

    private var retryAction: (() -> Void)? {
        switch session.phase {
        case .needsSignIn, .storageUnavailable, .inactive: nil
        default: {
            retainedError = nil
            session.retry()
        }
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

    @ViewBuilder
    private var pendingDecisionActions: some View {
        if session.pendingIntent != nil,
           session.lastError == .server(.requestConflict)
            || session.lastError == .server(.rateLimited) {
            HStack {
                Button("Retry saved request") { session.retry() }
                    .buttonStyle(.borderedProminent)
                if let discardAction {
                    Button("Discard saved request", role: .destructive, action: discardAction)
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
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.borderedProminent)
                        .disabled(!LiveMatchPresentation.canStart(
                            snapshot: snapshot,
                            displayedServerTime: displayedTime,
                            isCommandInFlight: session.isCommandInFlight
                        ))
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
            VStack(spacing: 18) {
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
                Text("The server clock controls the start. Backgrounding does not pause it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(seconds == 0 ? "Live race starting" : "Live race starts in \(seconds)")
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityFocused($focused)
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
                    ForEach(snapshot.members.filter { !$0.isSelf }, id: \.id) { member in
                        if let player = snapshot.round.players.first(where: { $0.memberID == member.id }) {
                            LiveOpponentRow(member: member, player: player)
                        }
                    }
                    BoardView(rows: rows, draft: draft, isPlaying: canInput, highContrast: highContrast)
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
                if case .guess(_, _, let word) = session.pendingIntent {
                    draft = word
                } else {
                    draft = session.guessDraft
                }
            }
            acceptsHardwareInput = canInput
        }
        .onChange(of: session.guessDraft) { _, value in
            if !value.isEmpty { draft = value }
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live round").font(.headline)
                Text(localConnectionText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Label(remainingTime, systemImage: "timer")
                    .font(.headline.monospacedDigit())
                    .accessibilityLabel("\(remainingSeconds) seconds remaining")
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var status: some View {
        if let player = selfPlayer, player.state.isTerminal {
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
                        Button("Retry") { session.retry() }.buttonStyle(.borderedProminent)
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
            RaceErrorBanner(message: retainedError)
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

private struct LiveOpponentRow: View {
    let member: LiveMatchMember
    let player: LiveRoundPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatarView(seed: member.avatarSeed, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName).font(.headline)
                Text("\(player.acceptedGuessCount)/6 guesses")
                    .font(.subheadline.monospacedDigit())
                    .contentTransition(.numericText())
            }
            Spacer()
            Label(
                LiveMatchPresentation.playerStateText(player.state).capitalized,
                systemImage: player.state == .playing ? "hourglass" : "flag.checkered"
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.raceInset, in: Capsule())
        }
        .padding(12)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.raceLine, lineWidth: 1.5) }
        .padding(.horizontal)
        .animation(reduceMotion ? nil : .snappy, value: player.acceptedGuessCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveMatchPresentation.opponentAccessibilityLabel(member: member, player: player))
    }
}

private enum LiveRevealFocus: Hashable {
    case answer
    case row(Int)
    case summary
}

private struct LiveRevealView: View {
    let snapshot: LiveMatchSnapshot
    let highContrast: Bool
    let goHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AccessibilityFocusState private var focus: LiveRevealFocus?
    @State private var visibleRows = 0

    private var boards: [LiveRevealBoard] { LiveMatchPresentation.revealBoards(snapshot: snapshot) }
    private var totalRows: Int { boards.reduce(0) { $0 + $1.rows.count } }
    private var stableReveal: Bool { reduceMotion || voiceOverEnabled }
    private var revealID: String {
        "\(snapshot.match.id.uuidString)-\(snapshot.round.completedAt?.timeIntervalSince1970 ?? 0)-\(stableReveal)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let answer = snapshot.round.answer, boards.count == snapshot.members.count {
                    Text("Answer: \(answer.uppercased())")
                        .font(.title.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.raceInset, in: Capsule())
                        .accessibilityFocused($focus, equals: .answer)

                    ForEach(Array(boards.enumerated()), id: \.element.member.id) { index, board in
                        let preceding = boards.prefix(index).reduce(0) { $0 + $1.rows.count }
                        let count = stableReveal
                            ? board.rows.count
                            : min(board.rows.count, max(0, visibleRows - preceding))
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                PlayerAvatarView(seed: board.member.avatarSeed, size: 42)
                                    .accessibilityHidden(true)
                                Text(board.member.isSelf ? "You" : board.member.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(LiveMatchPresentation.playerStateText(board.player.state).capitalized)
                                    .font(.caption.weight(.semibold))
                            }
                            ForEach(Array(board.rows.prefix(count).enumerated()), id: \.offset) { rowIndex, row in
                                LiveRevealRowView(row: row, highContrast: highContrast)
                                    .accessibilityFocused($focus, equals: .row(preceding + rowIndex))
                            }
                            if stableReveal || count == board.rows.count {
                                Text(boardSummary(board))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .padding()
                        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18).stroke(Color.raceLine, lineWidth: 1.5)
                        }
                    }

                    if stableReveal || visibleRows >= totalRows {
                        Text(comparisonSummary)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.raceInset, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityFocused($focus, equals: .summary)
                        Button("Home", action: goHome)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                    }
                } else {
                    ContentUnavailableView(
                        "Reveal unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The complete canonical reveal has not arrived yet.")
                    )
                }
            }
            .frame(maxWidth: 560)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .animation(stableReveal ? nil : .easeOut(duration: 0.25), value: visibleRows)
        .task(id: revealID) {
            visibleRows = stableReveal ? totalRows : 0
            focus = .answer
            guard !stableReveal, totalRows > 0 else {
                if totalRows == 0 { focus = .summary }
                return
            }
            for count in 1...totalRows {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                visibleRows = count
                focus = count == totalRows ? .summary : .row(count - 1)
            }
        }
        .onDisappear { visibleRows = stableReveal ? totalRows : 0 }
        .onChange(of: voiceOverEnabled) { _, enabled in if enabled { focus = .answer } }
        .onChange(of: reduceMotion) { _, enabled in if enabled { focus = .answer } }
    }

    private func boardSummary(_ board: LiveRevealBoard) -> String {
        let guesses = board.player.acceptedGuessCount == 1 ? "1 guess" : "\(board.player.acceptedGuessCount) guesses"
        let placement = board.player.placement.map { "place \($0)" } ?? "placement unavailable"
        return "\(guesses) used, \(placement)."
    }

    private var comparisonSummary: String {
        guard let own = boards.first(where: { $0.member.isSelf }) else { return "Round complete." }
        if own.player.placement == 1 {
            return boards.filter { $0.player.placement == 1 }.count > 1
                ? "Round complete. You tied for first place."
                : "Round complete. You placed first."
        }
        return "Round complete. You placed \(own.player.placement ?? 2) of \(boards.count)."
    }
}

private struct LiveRevealRowView: View {
    let row: LiveGuess
    let highContrast: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                TileView(
                    letter: Array(row.word.uppercased())[index],
                    feedback: row.feedback[index],
                    isDraft: false,
                    emptyLabel: "",
                    highContrast: highContrast
                )
            }
        }
        .frame(maxWidth: 320)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let tiles = zip(Array(row.word.uppercased()), row.feedback).map { letter, feedback in
            "\(letter) \(feedback.accessibilityMeaning)"
        }.joined(separator: ", ")
        return "Row \(row.sequence): \(tiles)."
    }
}
