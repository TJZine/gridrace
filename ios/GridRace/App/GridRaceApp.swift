import SwiftUI
import Observation

@main
struct GridRaceApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

@MainActor
@Observable
final class AppStartupModel {
    enum RecoveryAction: String, Identifiable {
        case retry
        case resetGuest

        var id: Self { self }
        var title: String {
            switch self {
            case .retry: "Try again"
            case .resetGuest: "Reset guest Daily data"
            }
        }
    }

    enum LoadFailure {
        case bundledData
        case storageUnavailable
        case savedData(DailyClassicStore)

        var message: String {
            switch self {
            case .bundledData:
                "The bundled puzzle data is unavailable. Reinstall or update GridRace."
            case .storageUnavailable:
                "Guest Daily Classic storage is unavailable. Try again to access your saved data."
            case .savedData:
                "Your guest Daily Classic data could not be read. You can retry or explicitly reset guest Daily progress and history. Signed-in account data is preserved."
            }
        }

        var actions: [RecoveryAction] {
            if case .savedData = self { return [.retry, .resetGuest] }
            return [.retry]
        }
    }

    let invitations: LiveInvitationCoordinator
    private(set) var appModel: DailyAccountCoordinator?
    private(set) var loadFailure: LoadFailure?
    private let loadPacks: () throws -> (tutorial: WordPack, daily: DailyWordPack)
    private let makeStore: () throws -> DailyClassicStore
    private let makeApp: (DailyWordPack, WordPack, DailyClassicStore) throws -> DailyAccountCoordinator

    init(
        loadPacks: @escaping () throws -> (tutorial: WordPack, daily: DailyWordPack) = {
            (try WordPack.load(bundle: .main), try DailyWordPack.load(bundle: .main))
        },
        makeStore: @escaping () throws -> DailyClassicStore = { try DailyClassicStore.applicationSupport() },
        makeApp: ((DailyWordPack, WordPack, DailyClassicStore) throws -> DailyAccountCoordinator)? = nil,
        invitations: LiveInvitationCoordinator? = nil
    ) {
        self.loadPacks = loadPacks
        self.makeStore = makeStore
        let invitations = invitations ?? LiveInvitationCoordinator.applicationSupport()
        self.invitations = invitations
        self.makeApp = makeApp ?? { try DailyAccountCoordinator(dailyPack: $0, tutorialPack: $1, guestStore: $2,
                                                               cleanupJournal: invitations.cleanupJournal) }
    }

    func loadApp() {
        loadFailure = nil
        let packs: (tutorial: WordPack, daily: DailyWordPack)
        do {
            packs = try loadPacks()
        } catch {
            loadFailure = .bundledData
            return
        }

        let store: DailyClassicStore
        do {
            store = try makeStore()
        } catch {
            loadFailure = .storageUnavailable
            return
        }

        do {
            appModel = try makeApp(packs.daily, packs.tutorial, store)
            appModel?.invitations = invitations
        } catch DailyClassicError.puzzleUnavailable {
            loadFailure = .bundledData
        } catch {
            loadFailure = .savedData(store)
        }
    }

    func perform(_ action: RecoveryAction) {
        guard let loadFailure, loadFailure.actions.contains(action) else { return }
        switch action {
        case .retry:
            loadApp()
        case .resetGuest:
            guard case .savedData(let store) = loadFailure else { return }
            do {
                try store.resetGuestDailyData()
                loadApp()
            } catch {
                self.loadFailure = .savedData(store)
            }
        }
    }
}

struct StartupRecoveryView: View {
    let loadFailure: AppStartupModel.LoadFailure
    let perform: (AppStartupModel.RecoveryAction) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    label: {
                        Label("GridRace unavailable", systemImage: "exclamationmark.triangle")
                    },
                    description: {
                        Text(loadFailure.message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                )
                .fixedSize(horizontal: false, vertical: true)

                ForEach(loadFailure.actions) { action in
                    if action == .retry {
                        Button(action.title) { perform(action) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("startup-recovery-\(action.rawValue)")
                    } else {
                        Button(action.title, role: .destructive) { perform(action) }
                            .accessibilityIdentifier("startup-recovery-\(action.rawValue)")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .accessibilityIdentifier("startup-recovery-scroll")
    }
}

private struct AppRootView: View {
    @State private var startup = AppStartupModel()

    var body: some View {
        Group {
            if let appModel = startup.appModel {
                DailyAppView(app: appModel, invitations: startup.invitations)
            } else if let loadFailure = startup.loadFailure {
                StartupRecoveryView(loadFailure: loadFailure, perform: startup.perform)
            } else {
                ProgressView("Loading GridRace")
                    .task { startup.loadApp() }
            }
        }
        .onOpenURL { startup.invitations.receive($0) }
        .safeAreaInset(edge: .top) {
            if startup.appModel == nil, startup.invitations.pending != nil || startup.invitations.needsAttention {
                Button { startup.invitations.isPresented = true } label: {
                    Text("Open invitation").padding().frame(minHeight: 44)
                }
            }
        }
        .sheet(isPresented: Binding(get: { startup.appModel == nil && startup.invitations.isPresented },
                                   set: { startup.invitations.isPresented = $0 })) {
            LiveInvitationView(invitations: startup.invitations, app: nil, resolveRace: {}, joined: {})
        }
    }
}
