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

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("GRIDRACE")
                        .font(StampType.display)
                        .tracking(1)
                        .accessibilityLabel("GridRace")
                    Text("Today's program · \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                        .font(StampType.caption)
                        .foregroundStyle(Color.secondaryInk)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                    Rectangle().fill(Color.ink).frame(height: 2).accessibilityHidden(true)
                    programRow(number: "01", title: "Daily classic", status: dailyStatus, action: model.homeStatus.action) {
                        openRoute(.daily)
                    }
                    if !isDailyPlayable {
                        NoticeCard(subject: "Daily", title: "Couldn't open your puzzle", message: "Retry, or open Account to sign out and play as a guest.") {
                            Button("Retry", action: retryDailyStorage).buttonStyle(InkButtonStyle())
                            Button("Open Account") { openRoute(.account) }.buttonStyle(OutlinedInkButtonStyle())
                        }
                        .padding(.bottom, 16)
                    }
                    programRow(number: "02", title: "Live race", status: liveStatus, action: liveAction) {
                        if live.phase != .storageUnavailable, live.hasSavedMatch { live.resumeSavedMatch() }
                        openRoute(.live)
                    }
                    programRow(number: "03", title: "Practice", status: "Race two bots", action: "Play") {
                        openRoute(.tutorial)
                    }
                    Text("\(model.history.statistics.gamesPlayed) played · \(model.history.statistics.solvePercentage)% solved · \(model.displayedCurrentStreak) streak")
                        .font(StampType.caption)
                        .foregroundStyle(Color.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                }
                .frame(maxWidth: 620)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                headerButton("Statistics", symbol: "chart.bar", route: .statistics)
                headerButton("Account", symbol: "person.crop.circle", route: .account)
                headerButton("Settings", symbol: "gearshape", route: .settings)
            }
        }
    }

    private func headerButton(_ title: String, symbol: String, route: AppRoute) -> some View {
        Button { openRoute(route) } label: {
            Image(systemName: symbol).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(title)
    }

    private var dailyStatus: String {
        guard isDailyPlayable else { return "Puzzle needs attention" }
        return "#\(model.puzzle.number) · \(model.homeStatus.title)"
    }

    private var liveStatus: String {
        if live.phase == .storageUnavailable { return "Saved race needs attention" }
        return live.hasSavedMatch ? "Saved race" : "Create or join a room"
    }

    private var liveAction: String {
        if live.phase == .storageUnavailable { return "Resolve" }
        return live.hasSavedMatch ? "Resume" : "Open"
    }

    private func programRow(number: String, title: String, status: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                Text(number).font(StampType.figure).foregroundStyle(Color.secondaryInk).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(StampType.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(status).font(StampType.caption).foregroundStyle(Color.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if number == "01", model.game.isComplete, isDailyPlayable {
                        NextPuzzleLabel(reset: model.nextReset)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button(action, action: perform)
                    .buttonStyle(InkButtonStyle())
                    .accessibilityLabel("\(action) \(title)")
                    .disabled(number == "01" && !isDailyPlayable)
            }
            Rectangle().fill(Color.line).frame(height: 1).accessibilityHidden(true)
        }
        .padding(.top, 22)
        .accessibilityElement(children: .contain)
    }
}
