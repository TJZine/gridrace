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

    private var presentation: LiveMatchPresentation.Presentation {
        LiveMatchPresentation.map(.init(session: session))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(LiveMatchPresentation.roundLabel(snapshot, number: displayedRound.number))
                .font(StampType.heading).accessibilityAddTraits(.isHeader)
            if let notice = presentation.priorRevealNotice {
                Text("\(notice.title) · \(notice.body)")
                    .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let answer = displayedRound.answer, boards.count == snapshot.members.count {
                ScorecardSeal(title: "Answer: \(answer.uppercased())")
                    .accessibilityFocused($focus, equals: .answer)

                // The shared rows retain a readable minimum width. Narrow devices
                // stack whole boards; wide devices show them beside each other.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) { revealBoards }
                    VStack(spacing: 12) { revealBoards }
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
                    if presentation.permits(.selectReveal) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(snapshot.revealedRounds, id: \.number) { round in
                                    Button("Round \(round.number)") {
                                        session.selectReveal(number: round.number == snapshot.round.number ? nil : round.number)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .buttonStyle(OutlinedInkButtonStyle())
                                    .accessibilityAddTraits(displayedRound.number == round.number ? .isSelected : [])
                                }
                            }
                        }.accessibilityLabel("Revealed rounds")
                    }
                    nextRoundAction
                    Button("Home", action: goHome)
                        .buttonStyle(InkButtonStyle())
                        .controlSize(.large)
                        .frame(minHeight: 44)
                }
            } else {
                if let notice = presentation.notice { LiveControlNotice(notice: notice, perform: { _ in }) }
            }
        }
        .frame(maxWidth: .infinity)
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
    private var revealBoards: some View {
        ForEach(Array(boards.enumerated()), id: \.element.member.id) { index, board in
            let preceding = boards.prefix(index).reduce(0) { $0 + $1.rows.count }
            let count = stableReveal ? board.rows.count : min(board.rows.count, max(0, visibleRows - preceding))
            VStack(alignment: .leading, spacing: 10) {
                Text(board.member.isSelf ? "You" : board.member.displayName)
                    .font(StampType.heading).accessibilityAddTraits(.isHeader)
                ForEach(Array(board.rows.prefix(count).enumerated()), id: \.offset) { rowIndex, row in
                    LiveRevealRowView(row: row, highContrast: highContrast)
                        .accessibilityFocused($focus, equals: .row(preceding + rowIndex))
                }
                if stableReveal || count == board.rows.count {
                    Text(boardSummary(board)).font(StampType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).paperCard()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(board.member.isSelf ? "Your" : board.member.displayName + "'s") revealed board")
        }
    }

    @ViewBuilder
    private var matchResults: some View {
        if let notice = presentation.notice {
            LiveControlNotice(notice: notice, perform: { _ in })
        }
        if let standings = snapshot.standings {
            VStack(alignment: .leading, spacing: 12) {
                Text(LiveMatchPresentation.standingsTitle(standings))
                    .font(StampType.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("Solved · points · time")
                    .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                if dynamicTypeSize.isAccessibilitySize {
                    ForEach(standings.players, id: \.memberID) { standing in
                        if let member = snapshot.members.first(where: { $0.id == standing.memberID }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.isSelf ? "You" : member.displayName).font(StampType.heading)
                                Text(LiveMatchPresentation.standingSummary(standing)).font(StampType.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 12) {
                        GridRow {
                            Text("Pos")
                            Text("Player")
                            Text("Solved")
                            Text("Pts")
                            Text("Time")
                        }.font(StampType.caption).foregroundStyle(Color.secondaryInk)
                        ForEach(standings.players, id: \.memberID) { standing in
                            if let member = snapshot.members.first(where: { $0.id == standing.memberID }) {
                                GridRow {
                                    Text("\(standing.placement)")
                                    Text(member.isSelf ? "You" : member.displayName)
                                    Text("\(standing.roundsSolved)")
                                    Text("\(standing.efficiencyPoints)")
                                    Text("\(standing.totalSolveDurationMilliseconds)ms")
                                }
                                .font(StampType.caption)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(member.isSelf ? "You" : member.displayName), \(LiveMatchPresentation.standingSummary(standing))")
                            }
                        }
                    }
                }
                Text("Most solved, then points, then fastest time.")
                    .font(StampType.caption).foregroundStyle(Color.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).paperCard()
        }
    }

    @ViewBuilder
    private var nextRoundAction: some View {
        if presentation.controls.contains(where: { $0.action == .start }) {
            Button("Start \(LiveMatchPresentation.roundLabel(snapshot, number: snapshot.match.currentRound + 1).lowercased())") {
                session.startMatch()
            }
            .font(StampType.heading).buttonStyle(InkButtonStyle()).frame(minHeight: 44)
            .disabled(!presentation.permits(.start))
        }
    }

    private func boardSummary(_ board: LiveRevealBoard) -> String {
        let guesses = board.player.acceptedGuessCount == 1 ? "1 guess" : "\(board.player.acceptedGuessCount) guesses"
        let placement = board.player.placement.map { "place \($0)" } ?? "placement unavailable"
        let time = board.player.solveDurationMilliseconds.map { " · \($0)ms" } ?? ""
        return "\(guesses) · \(placement)\(time)"
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
