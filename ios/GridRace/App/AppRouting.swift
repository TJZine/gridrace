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
    @State private var showsAccount = false
    @State private var accountSheetState = AccountSheetState(isSignedIn: false)

    var body: some View {
        NavigationStack(path: $path) {
            DailyHomeView(
                model: app.daily,
                account: app.account,
                live: app.live,
                syncMessage: app.syncMessage,
                isDailyPlayable: app.isDailyPlayable,
                retryDailyStorage: { app.retrySync() },
                openRoute: openRoute
            )
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .daily:
                        if app.isDailyPlayable {
                            DailyGameView(model: app.daily)
                        } else {
                            DailyStorageUnavailableView(retry: { app.retrySync() }, openAccount: presentAccount)
                        }
                    case .live:
                        LiveMatchFlowView(
                            session: app.live,
                            hapticsEnabled: app.daily.settings.hapticsEnabled,
                            highContrast: app.daily.settings.highContrastEnabled,
                            isSignedIn: app.account.isSignedIn,
                            openAccount: presentAccount
                        )
                    case .statistics: DailyStatisticsView(model: app.daily)
                    case .account: Color.page
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
        .sheet(isPresented: $showsAccount) {
            NavigationStack {
                accountDestination
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showsAccount = false }
                        }
                    }
            }
            .foregroundStyle(Color.ink)
            .tint(Color.ink)
            .environment(\.highContrastFeedback, app.daily.settings.highContrastEnabled)
        }
        .onChange(of: path) { _, routes in
            // Older value-based Account links use the same sheet route.
            if routes.last == .account {
                path.removeLast()
                presentAccount()
            }
        }
        .onChange(of: app.account.isSignedIn) { _, _ in updateAccountSheet() }
        .onChange(of: app.account.needsProfileSetup) { _, _ in updateAccountSheet() }
        .onChange(of: app.account.isWorking) { _, _ in updateAccountSheet() }
        .onChange(of: app.account.profile) { _, _ in updateAccountSheet() }
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

    private func openRoute(_ route: AppRoute) {
        if route == .account { presentAccount() }
        else { path.append(route) }
    }

    private func presentAccount() {
        accountSheetState = AccountSheetState(isSignedIn: app.account.isSignedIn)
        showsAccount = true
    }

    private func updateAccountSheet() {
        guard showsAccount else { return }
        if accountSheetState.observe(
            isSignedIn: app.account.isSignedIn,
            profileReady: app.account.profile != nil && !app.account.isWorking && !app.account.needsProfileSetup
        ) { showsAccount = false }
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

/// Dismiss only a sign-in begun while this sheet was open. Profile setup can
/// finish after authentication; an already signed-in expired session stays open.
struct AccountSheetState {
    private var wasSignedIn: Bool
    private var awaitsProfile = false

    init(isSignedIn: Bool) { wasSignedIn = isSignedIn }

    mutating func observe(isSignedIn: Bool, profileReady: Bool) -> Bool {
        if !wasSignedIn && isSignedIn { awaitsProfile = true }
        wasSignedIn = isSignedIn
        if !isSignedIn { awaitsProfile = false }
        return awaitsProfile && isSignedIn && profileReady
    }
}

private struct DailyStorageUnavailableView: View {
    let retry: () -> Void
    let openAccount: () -> Void

    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
            ScrollView {
                NoticeCard(subject: "Daily", title: "Couldn't open your puzzle", message: "Retry, or open Account to sign out and play as a guest.") {
                    Button("Retry", action: retry).buttonStyle(InkButtonStyle())
                    Button("Open Account", action: openAccount).buttonStyle(OutlinedInkButtonStyle())
                }
                .padding(20)
            }
        }
        .navigationTitle("Daily classic")
        .navigationBarTitleDisplayMode(.inline)
    }
}
