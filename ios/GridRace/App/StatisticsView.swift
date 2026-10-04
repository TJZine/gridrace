import SwiftUI

struct DailyStatisticsView: View {
    @Bindable var model: DailyClassicModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Rectangle().fill(Color.ink).frame(height: 2).accessibilityHidden(true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 12) {
                        StatisticCard(value: model.history.statistics.gamesPlayed, label: "Played")
                        StatisticCard(value: model.history.statistics.solvePercentage, label: "Solved", showsPercentSign: true)
                        StatisticCard(value: model.displayedCurrentStreak, label: "Streak")
                        StatisticCard(value: model.history.statistics.longestStreak, label: "Best")
                    }
                    GuessDistributionView(
                        distribution: model.history.statistics.guessDistribution,
                        failedCount: model.history.statistics.gamesPlayed - model.history.statistics.gamesWon,
                        todayFailed: model.history.result(for: model.puzzle.id)?.outcome == .failed,
                        todayGuessCount: model.history.result(for: model.puzzle.id).flatMap {
                            $0.outcome == .solved ? $0.guessCount : nil
                        }
                    )
                }
                .frame(maxWidth: 560)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StatisticCard: View {
    let value: Int
    let label: String
    var showsPercentSign = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)\(showsPercentSign ? "%" : "")")
                .font(.system(.title2, design: .monospaced, weight: .bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(Color.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        showsPercentSign ? "\(label), \(value) percent" : "\(value) \(label)"
    }
}

private struct GuessDistributionView: View {
    let distribution: [Int: Int]
    let failedCount: Int
    let todayFailed: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Failed games have their own outlined row, separate from solved-six.
    var todayGuessCount: Int? = nil
    @ScaledMetric(relativeTo: .subheadline) private var rowLabelWidth: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 24
    private var maximum: Int { max(1, failedCount, distribution.values.max() ?? 0) }

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
            Text("Rows used")
                .font(StampType.caption.weight(.black))
                .tracking(1.2)
            ForEach(1...7, id: \.self) { guess in
                let isFailed = guess == 7
                let isToday = isFailed ? todayFailed : todayGuessCount == guess
                let count = isFailed ? failedCount : distribution[guess, default: 0]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(isFailed ? "—" : "\(guess)")
                            .font(isToday ? .subheadline.bold() : .subheadline)
                            .frame(width: rowLabelWidth)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.card)
                                Capsule().fill(isToday ? Color.correct : (isFailed ? Color.clear : Color.ink))
                                    .frame(width: barWidth(count: count, in: proxy.size.width))
                                    .overlay(alignment: .leading) {
                                        if isFailed, count > 0 {
                                            Capsule().stroke(Color.ink, lineWidth: 1.5)
                                                .frame(width: barWidth(count: count, in: proxy.size.width))
                                        }
                                    }
                            }
                        }
                        .frame(height: barHeight)
                        // Count sits beside the bar in ink-on-card (never clipped
                        // white-on-fill), so AX5/Bold sizes cannot clip it or push
                        // it outside its contrasting fill.
                        Text("\(count)")
                            .font(StampType.caption.bold().monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .frame(minWidth: 28, alignment: .leading)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Today")
                                .font(StampType.caption2.bold())
                                .foregroundStyle(Color.secondaryInk)
                                .opacity(isToday ? 1 : 0)
                        }
                    }
                    if dynamicTypeSize.isAccessibilitySize, isToday {
                        Text("Today").font(StampType.caption2.bold()).foregroundStyle(Color.secondaryInk)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isToday ? "Today, " : "")\(isFailed ? "Not solved" : "Solved in \(guess) guesses"), \(count) games")
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
