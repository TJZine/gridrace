import SwiftUI

enum AppRoute: Hashable {
    case daily
    case live
    case statistics
    case account
    case settings
    case help
    case tutorial
    case attribution
}

struct DailyAppView: View {
    @Bindable var app: DailyAccountCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            DailyHomeView(
                model: app.daily,
                account: app.account,
                live: app.live,
                syncMessage: app.syncMessage,
                isDailyPlayable: app.isDailyPlayable,
                retryDailyStorage: { app.retrySync() },
                openRoute: { path.append($0) }
            )
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .daily:
                        if app.isDailyPlayable {
                            DailyGameView(model: app.daily)
                        } else {
                            DailyStorageUnavailableView(retry: { app.retrySync() })
                        }
                    case .live:
                        LiveMatchFlowView(
                            session: app.live,
                            hapticsEnabled: app.daily.settings.hapticsEnabled,
                            highContrast: app.daily.settings.highContrastEnabled,
                            isSignedIn: app.account.isSignedIn,
                            openAccount: { path.append(.account) }
                        )
                    case .statistics: DailyStatisticsView(model: app.daily)
                    case .account: accountDestination
                    case .settings: DailySettingsView(model: app.daily)
                    case .help: DailyHelpView()
                    case .attribution: DailyAttributionView()
                    case .tutorial:
                        TutorialView(
                            model: app.tutorial,
                            hapticsEnabled: Binding(
                                get: { app.daily.settings.hapticsEnabled },
                                set: { app.daily.updateHaptics($0) }
                            )
                        )
                    }
                }
        }
        .environment(\.highContrastFeedback, app.daily.settings.highContrastEnabled)
        .foregroundStyle(Color.ink)
        .tint(Color.ink)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.foregrounded()
            } else {
                app.backgrounded()
            }
        }
        .task { await app.start() }
        .task(id: app.daily.puzzle.id) {
            let delay = max(1, app.daily.nextReset.timeIntervalSinceNow)
            try? await Task<Never, Never>.sleep(for: .seconds(delay))
            guard !Task.isCancelled, app.isDailyPlayable else { return }
            app.daily.refreshForCurrentDay()
        }
    }

    private var accountDestination: some View {
        AccountView(
            model: app.account,
            syncMessage: app.syncMessage,
            retrySync: app.showsRetry ? { app.retrySync() } : nil,
            canImportGuestHistory: app.canImportGuestHistory,
            importGuestHistory: { app.importGuestHistory() },
            skipGuestHistory: { app.skipGuestHistory() },
            useCloudAttempt: app.conflicts.isEmpty
                ? nil : { app.resolveFirstConflict(useCloud: true) },
            keepDeviceAttempt: app.conflicts.isEmpty
                ? nil : { app.resolveFirstConflict(useCloud: false) },
            conflictCount: app.conflicts.count,
            conflict: app.conflicts.first
        )
    }
}

private struct DailyStorageUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Daily storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Retry account storage, or sign out from Account to keep playing as a guest.")
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(InkButtonStyle())
            NavigationLink("Open Account", value: AppRoute.account)
        }
        .navigationTitle("Daily Classic")
        .navigationBarTitleDisplayMode(.inline)
    }
}
