import SwiftUI

/// Both flows supply already-public progress and their existing spoken summary.
/// The leaf owns neither roster ordering nor connectivity or gameplay policy.
struct OpponentLine<Avatar: View>: View {
    let name: String
    let count: String
    let state: String
    let stateSymbol: String
    var connection: String? = nil
    let accessibilitySummary: String
    @ViewBuilder var avatar: () -> Avatar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            avatar().accessibilityHidden(true)
            Text(name).font(StampType.heading)
            Text(count).font(StampType.caption.bold())
                .contentTransition(.numericText())
            if let connection {
                Text(connection).font(StampType.caption).foregroundStyle(Color.secondaryInk)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Label(state, systemImage: stateSymbol)
                .font(StampType.caption)
                .foregroundStyle(Color.secondaryInk)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}

struct OpponentStrip: View {
    let opponents: [OpponentProgress]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            ForEach(opponents) { opponent in
                OpponentLine(
                    name: opponent.name,
                    count: "\(opponent.acceptedGuessCount)/6",
                    state: opponent.state.spokenDescription.capitalized,
                    stateSymbol: opponent.state == .playing ? "hourglass" : "flag.checkered",
                    connection: opponent.isConnected ? "Connected" : "Disconnected",
                    accessibilitySummary: opponent.accessibilityLabel
                ) {
                    Image(systemName: opponent.avatarSymbol)
                        .font(StampType.caption.bold())
                        .foregroundStyle(Color.ink)
                }
                .animation(reduceMotion ? nil : .snappy, value: opponent.acceptedGuessCount)
            }
        }
        .padding(.horizontal)
    }
}

/// The proposed height participates in sizing as well as width. Scroll views
/// propose no height; there the natural six-row size is used. A caller can
/// reserve a keyboard slot and propose the remaining height without a second
/// board implementation. If too little room remains, the minimum readable
/// size overflows for the owning scroll container instead of clipping text.
private struct BoardRowsLayout: Layout {
    let minimumTileSize: CGFloat
    let preferredTileSize: CGFloat
    private let spacing: CGFloat = 6

    private func tileSize(_ proposal: ProposedViewSize) -> CGFloat {
        let widthLimit = proposal.width.map { ($0 - spacing * 4) / 5 } ?? preferredTileSize
        let heightLimit = proposal.height.map { ($0 - spacing * 5) / 6 } ?? preferredTileSize
        return max(minimumTileSize, min(preferredTileSize, widthLimit, heightLimit))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let tile = tileSize(proposal)
        return CGSize(width: tile * 5 + spacing * 4, height: tile * 6 + spacing * 5)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let tile = tileSize(ProposedViewSize(bounds.size))
        for (index, row) in subviews.enumerated() {
            row.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(index) * (tile + spacing)),
                proposal: ProposedViewSize(width: tile * 5 + spacing * 4, height: tile)
            )
        }
    }
}

struct BoardView: View {
    let rows: [GuessRow]
    let draft: String
    let isPlaying: Bool
    var highContrast = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var minimumTileSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var preferredTileSize: CGFloat = 54

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) { board }
            } else {
                board
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your six-row game board")
    }

    private var board: some View {
        BoardRowsLayout(minimumTileSize: minimumTileSize, preferredTileSize: preferredTileSize) {
            ForEach(0..<6, id: \.self) { rowIndex in
                let acceptedRow = rows.indices.contains(rowIndex) ? rows[rowIndex] : nil
                let isDraftRow = rowIndex == rows.count && isPlaying
                TileRowView(
                    word: acceptedRow?.word ?? (isDraftRow ? draft : ""),
                    feedback: acceptedRow?.feedback ?? [],
                    isDraft: isDraftRow,
                    rowNumber: rowIndex + 1,
                    highContrast: highContrast,
                    scrollsAtAccessibilitySize: false
                )
            }
        }
    }
}

/// Shared shape grammar for full tiles and the small history board.
/// Empty rings are decorative at default; strengthened rings use secondary ink.
struct FeedbackSeal: View {
    let feedback: Feedback?
    var isDraft = false
    var highContrast = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.highContrastFeedback) private var highContrastFeedback

    private var strengthened: Bool { highContrast || highContrastFeedback || contrast == .increased }

    var body: some View {
        switch feedback {
        case .correct:
            Circle().fill(Color.correct)
        case .present:
            Circle().strokeBorder(Color.present, lineWidth: strengthened ? 3.5 : 2)
                .overlay {
                    Circle().inset(by: strengthened ? 6 : 5)
                        .strokeBorder(Color.present, lineWidth: 1)
                }
        case .absent:
            Color.clear
        case .none:
            Circle().fill(isDraft ? Color.card : Color.clear)
                .overlay {
                    Circle().strokeBorder(
                        isDraft ? Color.ink : (strengthened ? Color.strengthenedSecondaryInk : Color.line),
                        style: StrokeStyle(lineWidth: isDraft ? 2 : 1, dash: isDraft ? [] : [3, 3])
                    )
                }
        }
    }
}

struct TileView: View {
    let letter: Character?
    let feedback: Feedback?
    let isDraft: Bool
    let emptyLabel: String
    var highContrast = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.highContrastFeedback) private var highContrastFeedback
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        ZStack {
            FeedbackSeal(feedback: feedback, isDraft: isDraft, highContrast: highContrast)
            VStack(spacing: 0) {
                if let letter {
                    Text(String(letter).uppercased())
                        .font(StampType.tile)
                        .fontWeight(legibilityWeight == .bold || isDraft ? .black : .bold)
                }
                if let feedback {
                    Image(systemName: feedback.symbolName)
                        .font(.system(.caption2, weight: .black))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(letterColor)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var letterColor: Color {
        switch feedback {
        case .correct: Color.feedbackLetter
        case .present: Color.present
        case .absent: highContrast || highContrastFeedback || contrast == .increased ? Color.strengthenedAbsent : Color.absent
        case .none: Color.ink
        }
    }

    private var accessibilityLabel: String {
        guard let letter else { return emptyLabel }
        if let feedback { return "Letter \(letter), \(feedback.accessibilityMeaning)." }
        return "Letter \(letter), draft."
    }
}

struct TileRowView: View {
    let word: String
    let feedback: [Feedback]
    var isDraft = false
    var rowNumber = 1
    var highContrast = false
    var scrollsAtAccessibilitySize = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var minimumTileSize: CGFloat = 44

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize && scrollsAtAccessibilitySize {
                ScrollView(.horizontal) { tiles }
            } else {
                tiles
            }
        }
    }

    private var tiles: some View {
        let letters = Array(word.uppercased())
        return HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                TileView(
                    letter: letters.indices.contains(index) ? letters[index] : nil,
                    feedback: feedback.indices.contains(index) ? feedback[index] : nil,
                    isDraft: isDraft,
                    emptyLabel: "Empty tile, row \(rowNumber), column \(index + 1)",
                    highContrast: highContrast
                )
                .frame(minWidth: minimumTileSize, minHeight: minimumTileSize)
            }
        }
    }
}

struct CountdownNumeral: View {
    let text: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 92

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .serif))
            .foregroundStyle(Color.present)
            .contentTransition(.numericText())
    }
}

struct LetterKeyboardView: View {
    let keyboard: KeyboardState
    let typeLetter: (Character) -> Void
    let submit: () -> Void
    let delete: () -> Void
    var highContrast = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let rows = [Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) { keys }
            } else {
                keys
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letter keyboard")
    }

    private var keys: some View {
        VStack(spacing: 5) {
            letterRow(rows[0])
            letterRow(rows[1]).padding(.horizontal, 14)
            HStack(spacing: 4) {
                actionKey(symbol: "return", label: "Submit guess", action: submit)
                ForEach(rows[2], id: \.self) { letter in
                    letterKey(letter)
                }
                actionKey(symbol: "delete.left", label: "Delete letter", action: delete)
            }
        }
    }

    private func actionKey(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.callout, weight: .bold))
                .foregroundStyle(Color.card)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 48)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(RaceKeyPressStyle())
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }

    private func letterRow(_ letters: [Character]) -> some View {
        HStack(spacing: 4) {
            ForEach(letters, id: \.self) { letter in
                letterKey(letter)
            }
        }
    }

    private func letterKey(_ letter: Character) -> some View {
        KeyboardKey(letter: letter, feedback: keyboard.feedback(for: letter), highContrast: highContrast) {
            typeLetter(letter)
        }
    }
}

struct KeyboardKey: View {
    let letter: Character
    let feedback: Feedback?
    var highContrast = false
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.highContrastFeedback) private var highContrastFeedback
    @ScaledMetric(relativeTo: .callout) private var keyHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .callout) private var keyWidth: CGFloat = 26

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(String(letter)).font(StampType.key)
                if let feedback {
                    Image(systemName: feedback.symbolName)
                        .font(.system(.caption2, weight: .black))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(letterColor)
            .frame(minWidth: keyWidth, maxWidth: .infinity, minHeight: keyHeight)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10)
                switch feedback {
                case .correct:
                    shape.fill(Color.correct)
                case .present:
                    shape.strokeBorder(Color.present, lineWidth: strengthened ? 3.5 : 2)
                        .overlay {
                            shape.inset(by: strengthened ? 6 : 5).strokeBorder(Color.present, lineWidth: 1)
                        }
                case .absent:
                    Color.clear
                case .none:
                    shape.fill(Color.card)
                        .overlay { shape.strokeBorder(Color.ink, lineWidth: 1) }
                }
            }
        }
        .buttonStyle(RaceKeyPressStyle())
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var strengthened: Bool { highContrast || highContrastFeedback || contrast == .increased }

    private var letterColor: Color {
        switch feedback {
        case .correct: Color.feedbackLetter
        case .present: Color.present
        case .absent: highContrast || highContrastFeedback || contrast == .increased ? Color.strengthenedAbsent : Color.absent
        case .none: Color.ink
        }
    }

    private var accessibilityLabel: String {
        guard let feedback else { return "Letter \(letter)" }
        return "Letter \(letter), \(feedback.accessibilityMeaning)."
    }
}

struct RevealRowView: View {
    let row: GuessRow

    var body: some View {
        TileRowView(word: row.word, feedback: row.feedback).frame(maxWidth: 320)
    }
}

struct LiveOpponentRow: View {
    let member: LiveMatchMember
    let player: LiveRoundPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OpponentLine(
            name: member.displayName,
            count: "\(player.acceptedGuessCount)/6 guesses",
            state: LiveMatchPresentation.playerStateText(player.state).capitalized,
            stateSymbol: player.state == .playing ? "hourglass" : "flag.checkered",
            accessibilitySummary: LiveMatchPresentation.opponentAccessibilityLabel(member: member, player: player)
        ) {
            PlayerAvatarView(seed: member.avatarSeed, size: 24)
        }
        .padding(.horizontal)
        .animation(reduceMotion ? nil : .snappy, value: player.acceptedGuessCount)
    }
}

struct LiveRevealRowView: View {
    let row: LiveGuess
    let highContrast: Bool

    var body: some View {
        TileRowView(word: row.word, feedback: row.feedback, rowNumber: row.sequence, highContrast: highContrast)
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
