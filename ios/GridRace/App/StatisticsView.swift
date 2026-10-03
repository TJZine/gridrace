import SwiftUI

struct DailyStatisticsView: View {
    @Bindable var model: DailyClassicModel

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatisticCard(value: model.history.statistics.gamesPlayed, label: "Played")
                        StatisticCard(value: model.history.statistics.solvePercentage, label: "Solved", showsPercentSign: true)
                        StatisticCard(value: model.displayedCurrentStreak, label: "Streak")
                        StatisticCard(value: model.history.statistics.longestStreak, label: "Best")
                    }
                    GuessDistributionView(
                        distribution: model.history.statistics.guessDistribution,
                        todayGuessCount: model.history.result(for: model.puzzle.id).flatMap {
                            $0.outcome == .solved ? $0.guessCount : nil
                        }
                    )
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
                Text("TODAY").font(StampType.caption.weight(.black)).tracking(1.2)
                Text(result.outcome == .solved ? "Solved in \(result.guessCount)" : "Not solved")
                    .font(StampType.heading)
                ShareLink(item: DailyClassicShare.text(for: result)) {
                    Label("Share today's grid", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(InkButtonStyle())
                NextPuzzleLabel(reset: model.nextReset)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
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
                .font(.system(.largeTitle, design: .monospaced, weight: .bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(Color.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.line, lineWidth: 1.5)
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
    /// Today's solved guess count, when today's result exists and is solved.
    /// Failed results never highlight: six structural guesses are not part
    /// of the solved-guess distribution.
    var todayGuessCount: Int? = nil
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
                .font(StampType.caption.weight(.black))
                .tracking(1.2)
            ForEach(1...6, id: \.self) { guess in
                let isToday = todayGuessCount == guess
                HStack(spacing: 10) {
                    Text("\(guess)")
                        .font(isToday ? .subheadline.bold() : .subheadline)
                        .frame(width: 12)
                    GeometryReader { proxy in
                        let count = distribution[guess, default: 0]
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.card)
                            Capsule().fill(Color.ink)
                                .frame(width: barWidth(count: count, in: proxy.size.width))
                            if isToday {
                                Capsule()
                                    .stroke(Color.ink, lineWidth: 1.5)
                            }
                        }
                    }
                    .frame(height: 24)
                    // Count sits beside the bar in ink-on-card (never clipped
                    // white-on-fill), so AX5/Bold sizes cannot clip it or push
                    // it outside its contrasting fill.
                    Text("\(distribution[guess, default: 0])")
                        .font(StampType.caption.bold().monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .frame(minWidth: 28, alignment: .leading)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    // The literal marker reserves its own scaled width in
                    // every row; non-today rows keep the layout width while
                    // staying visually invisible, so all bars align at any
                    // text size. The row's custom label owns the semantics.
                    Text("Today")
                        .font(StampType.caption2.bold())
                        .foregroundStyle(Color.secondaryInk)
                        .opacity(isToday ? 1 : 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isToday
                    ? "Today, solved in \(guess) guesses, \(distribution[guess, default: 0]) games"
                    : "Solved in \(guess) guesses, \(distribution[guess, default: 0]) games")
            }
        }
        .padding(18)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.line, lineWidth: 1.5)
        }
    }
}
