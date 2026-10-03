import Foundation
import SwiftUI

private enum LiveRevealFocus: Hashable {
    case answer
    case row(Int)
    case summary
}

struct LiveRevealView: View {
    @Bindable var session: LiveMatchSession
    let snapshot: LiveMatchSnapshot
    let highContrast: Bool
    let goHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focus: LiveRevealFocus?
    @State private var visibleRows = 0

    private var displayedRound: LiveRound { session.displayedReveal ?? snapshot.round }
    private var boards: [LiveRevealBoard] { LiveMatchPresentation.revealBoards(snapshot: snapshot, round: displayedRound) }
    private var totalRows: Int { boards.reduce(0) { $0 + $1.rows.count } }
    private var stableReveal: Bool { reduceMotion || voiceOverEnabled }
    private var revealID: String {
        "\(LiveMatchPresentation.roundIdentity(snapshot, number: displayedRound.number))-\(stableReveal)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(LiveMatchPresentation.roundLabel(snapshot, number: displayedRound.number))
                    .font(StampType.heading).accessibilityAddTraits(.isHeader)
                if displayedRound.number != snapshot.round.number {
                    Text("Viewing a prior reveal. Current match: \(LiveMatchPresentation.roundLabel(snapshot)).")
                        .font(.callout).foregroundStyle(Color.secondaryInk).multilineTextAlignment(.center)
                }
                if let answer = displayedRound.answer, boards.count == snapshot.members.count {
                    Text("Answer: \(answer.uppercased())")
                        .font(StampType.title.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.card, in: Capsule())
                        .accessibilityFocused($focus, equals: .answer)

                    ForEach(Array(boards.enumerated()), id: \.element.member.id) { index, board in
                        let preceding = boards.prefix(index).reduce(0) { $0 + $1.rows.count }
                        let count = stableReveal
                            ? board.rows.count
                            : min(board.rows.count, max(0, visibleRows - preceding))
                        VStack(alignment: .leading, spacing: 10) {
                            let layout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout())
                            layout {
                                PlayerAvatarView(seed: board.member.avatarSeed, size: 42)
                                    .accessibilityHidden(true)
                                Text(board.member.isSelf ? "You" : board.member.displayName)
                                    .font(StampType.heading)
                                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                Text(LiveMatchPresentation.playerStateText(board.player.state).capitalized)
                                    .font(StampType.caption.weight(.semibold))
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
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18).stroke(Color.line, lineWidth: 1.5)
                        }
                    }

                    if stableReveal || visibleRows >= totalRows {
                        Text("Round standings").font(StampType.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(comparisonSummary)
                            .font(StampType.heading)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityFocused($focus, equals: .summary)
                        matchResults
                        if snapshot.revealedRounds.count > 1 {
                            Picker("Revealed round", selection: Binding(
                                get: { session.selectedRevealNumber ?? snapshot.round.number },
                                set: { session.selectReveal(number: $0 == snapshot.round.number ? nil : $0) }
                            )) {
                                ForEach(snapshot.revealedRounds, id: \.number) { round in
                                    Text("Round \(round.number)").tag(round.number)
                                }
                            }
                            .pickerStyle(.menu)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                        }
                        nextRoundAction
                        Button("Home", action: goHome)
                            .buttonStyle(InkButtonStyle())
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

    @ViewBuilder
    private var matchResults: some View {
        if snapshot.match.status == .incomplete {
            Text("Match incomplete")
                .font(StampType.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("A player account was deleted. Unstarted rounds cannot continue. Revealed rounds are preserved.")
                .font(.callout).multilineTextAlignment(.center)
        }
        if let standings = snapshot.standings {
            VStack(alignment: .leading, spacing: 12) {
                Text(LiveMatchPresentation.standingsTitle(standings))
                    .font(StampType.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Through \(standings.throughRound) of \(snapshot.match.roundCount) revealed rounds")
                    .font(.callout).foregroundStyle(Color.secondaryInk)
                ForEach(snapshot.members.sorted { $0.isSelf && !$1.isSelf }, id: \.id) { member in
                    if let standing = standings.players.first(where: { $0.memberID == member.id }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.isSelf ? "You" : member.displayName).font(StampType.heading)
                            Text(LiveMatchPresentation.standingSummary(standing))
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private var nextRoundAction: some View {
        if snapshot.match.status == .inProgress, snapshot.match.terminalReason == nil,
           snapshot.match.currentRound < snapshot.match.roundCount {
            if snapshot.members.first(where: \.isSelf)?.id == snapshot.match.creatorMemberID {
                Button("Start next round (\(snapshot.match.currentRound + 1) of \(snapshot.match.roundCount))") {
                    session.startMatch()
                }
                .font(StampType.heading).buttonStyle(InkButtonStyle()).controlSize(.large).frame(minHeight: 48)
                .disabled(session.phase != .ready || !LiveMatchPresentation.canStart(
                    snapshot: snapshot,
                    displayedServerTime: session.displayedServerTime ?? snapshot.serverTime,
                    isCommandInFlight: session.isCommandInFlight,
                    hasPendingIntent: session.pendingIntent != nil,
                    hasPendingStart: session.hasPendingStart
                ))
            } else {
                Text("Waiting for the room creator to start the next round.")
                    .font(StampType.heading).multilineTextAlignment(.center)
            }
        }
    }

    private func boardSummary(_ board: LiveRevealBoard) -> String {
        let guesses = board.player.acceptedGuessCount == 1 ? "1 guess" : "\(board.player.acceptedGuessCount) guesses"
        let placement = board.player.placement.map { "place \($0)" } ?? "placement unavailable"
        return "\(guesses) used, round \(placement)."
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
