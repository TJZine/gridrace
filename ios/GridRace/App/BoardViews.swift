import SwiftUI

/// Split-time opponent rows. Shows only already-visible live fields (avatar,
/// name, accepted count `n/6`, connection presentation, coarse state) in stable
/// roster order. Never position, placement, gap-as-rank, exact timing, words,
/// feedback, or keyboard state.
struct OpponentStrip: View {
    let opponents: [OpponentProgress]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(opponents) { opponent in
                HStack(spacing: 12) {
                    Image(systemName: opponent.avatarSymbol)
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(Color.raceInset, in: Circle())
                        .foregroundStyle(Color.raceIndigo)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opponent.name).font(.headline)
                        HStack(spacing: 6) {
                            Text("\(opponent.acceptedGuessCount)/6")
                                .font(.subheadline.monospacedDigit())
                                .fixedSize(horizontal: true, vertical: false)
                                .contentTransition(.numericText())
                            Image(systemName: opponent.isConnected ? "wifi" : "wifi.slash")
                                .font(.caption2.bold())
                                .foregroundStyle(opponent.isConnected ? Color.raceTeal : Color.raceDanger)
                                .accessibilityHidden(true)
                            Text(opponent.isConnected ? "Connected" : "Disconnected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Label(
                        opponent.state.spokenDescription.capitalized,
                        systemImage: opponent.state == .playing
                            ? "hourglass" : "flag.checkered"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.raceInset, in: Capsule())
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.raceLine, lineWidth: 1.5)
                }
                .animation(reduceMotion ? nil : .snappy, value: opponent.acceptedGuessCount)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(opponent.accessibilityLabel)
            }
        }
        .padding(.horizontal)
    }
}

struct BoardView: View {
    let rows: [GuessRow]
    let draft: String
    let isPlaying: Bool
    var highContrast = false

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { columnIndex in
                        let tile = tile(row: rowIndex, column: columnIndex)
                        TileView(
                            letter: tile.letter,
                            feedback: tile.feedback,
                            isDraft: tile.isDraft,
                            emptyLabel: "Empty tile, row \(rowIndex + 1), column \(columnIndex + 1)",
                            highContrast: highContrast
                        )
                    }
                }
            }
        }
        .frame(maxWidth: 350)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your six-row game board")
    }

    private func tile(row: Int, column: Int) -> (letter: Character?, feedback: Feedback?, isDraft: Bool) {
        if rows.indices.contains(row) {
            let accepted = rows[row]
            return (Array(accepted.word.uppercased())[column], accepted.feedback[column], false)
        }
        if row == rows.count, isPlaying {
            let letters = Array(draft)
            return (letters.indices.contains(column) ? letters[column] : nil, nil, true)
        }
        return (nil, nil, false)
    }
}

struct TileView: View {
    let letter: Character?
    let feedback: Feedback?
    let isDraft: Bool
    let emptyLabel: String
    var highContrast = false

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: borderWidth)
            // Lane-edge signature: a bold leading edge carries feedback meaning
            // alongside the symbol and accessible label, never color alone.
            if feedback != nil {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 5)
                        .padding(.vertical, 7)
                        .padding(.leading, 5)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
            }
            if let letter {
                Text(String(letter).uppercased())
                    .font(.title2)
                    .fontWeight(isDraft || legibilityWeight == .bold ? .black : .bold)
                    .foregroundStyle(feedback == nil ? Color.raceInk : Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let feedback {
                Image(systemName: feedback.symbolName)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        guard let feedback else { return isDraft ? Color.raceCard : Color.raceInset }
        switch feedback {
        case .absent: return Color.raceTeal
        case .present: return Color.raceCoral
        case .correct: return Color.raceIndigo
        }
    }

    private var borderColor: Color {
        // Adaptive system primary: dark edge in light, light edge in dark,
        // so the stroke contrasts both fills and surfaces in each appearance.
        if isHighContrast { return .primary }
        if feedback != nil { return .white }
        return isDraft ? Color.raceLineEmphasis : Color.raceLine
    }

    private var borderWidth: CGFloat {
        if isHighContrast { return 3 }
        if feedback != nil { return 1.5 }
        return isDraft ? 2.5 : 1.5
    }

    private var accessibilityLabel: String {
        guard let letter else { return emptyLabel }
        if let feedback {
            return "Letter \(letter), \(feedback.accessibilityMeaning)."
        }
        return "Letter \(letter), draft."
    }

    private var isHighContrast: Bool { highContrast || contrast == .increased }
}

struct LetterKeyboardView: View {
    let keyboard: KeyboardState
    let typeLetter: (Character) -> Void
    let submit: () -> Void
    let delete: () -> Void
    var highContrast = false

    private let rows = [Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]

    var body: some View {
        VStack(spacing: 5) {
            letterRow(rows[0])
            letterRow(rows[1]).padding(.horizontal, 14)
            HStack(spacing: 4) {
                // The visible indigo surface lives inside the label so the
                // press style transforms the whole key, not just the icon.
                Button(action: submit) {
                    Image(systemName: "return")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.raceIndigo, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(RaceKeyPressStyle())
                .frame(minWidth: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Submit guess")

                ForEach(rows[2], id: \.self) { letter in
                    KeyboardKey(
                        letter: letter,
                        feedback: keyboard.feedback(for: letter),
                        highContrast: highContrast
                    ) { typeLetter(letter) }
                }

                Button(action: delete) {
                    Image(systemName: "delete.left")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.raceIndigo, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(RaceKeyPressStyle())
                .frame(minWidth: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Delete letter")
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letter keyboard")
    }

    private func letterRow(_ letters: [Character]) -> some View {
        HStack(spacing: 4) {
            ForEach(letters, id: \.self) { letter in
                KeyboardKey(
                    letter: letter,
                    feedback: keyboard.feedback(for: letter),
                    highContrast: highContrast
                ) { typeLetter(letter) }
            }
        }
    }
}

struct KeyboardKey: View {
    let letter: Character
    let feedback: Feedback?
    var highContrast = false
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(String(letter))
                    .font(.callout.bold())
                if let feedback {
                    Image(systemName: feedback.symbolName)
                        .font(.system(size: 11, weight: .black))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(feedback == nil ? Color.raceInk : Color.white)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHighContrast ? Color.primary : Color.raceLine,
                        lineWidth: isHighContrast ? 2.5 : 1
                    )
            }
        }
        .buttonStyle(RaceKeyPressStyle())
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var fillColor: Color {
        switch feedback {
        case .none: Color.raceCard
        case .absent: Color.raceTeal
        case .present: Color.raceCoral
        case .correct: Color.raceIndigo
        }
    }

    private var accessibilityLabel: String {
        guard let feedback else { return "Letter \(letter)" }
        return "Letter \(letter), \(feedback.accessibilityMeaning)."
    }

    private var isHighContrast: Bool { highContrast || contrast == .increased }
}

struct RevealRowView: View {
    let row: GuessRow

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                TileView(
                    letter: Array(row.word.uppercased())[index],
                    feedback: row.feedback[index],
                    isDraft: false,
                    emptyLabel: ""
                )
            }
        }
        .frame(maxWidth: 320)
    }
}

struct LiveOpponentRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let member: LiveMatchMember
    let player: LiveRoundPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            PlayerAvatarView(seed: member.avatarSeed, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName).font(.headline)
                Text("\(player.acceptedGuessCount)/6 guesses")
                    .font(.subheadline.monospacedDigit())
                    .contentTransition(.numericText())
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.raceLine, lineWidth: 1.5) }
        .padding(.horizontal)
        .animation(reduceMotion ? nil : .snappy, value: player.acceptedGuessCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveMatchPresentation.opponentAccessibilityLabel(member: member, player: player))
    }
}

struct LiveRevealRowView: View {
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
