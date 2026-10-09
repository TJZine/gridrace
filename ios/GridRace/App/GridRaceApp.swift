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
        makeApp: @escaping (DailyWordPack, WordPack, DailyClassicStore) throws -> DailyAccountCoordinator = {
            try DailyAccountCoordinator(dailyPack: $0, tutorialPack: $1, guestStore: $2)
        }
    ) {
        self.loadPacks = loadPacks
        self.makeStore = makeStore
        self.makeApp = makeApp
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

private struct AppRootView: View {
    @State private var startup = AppStartupModel()

    var body: some View {
        Group {
            if let appModel = startup.appModel {
                DailyAppView(app: appModel)
            } else if let loadFailure = startup.loadFailure {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "GridRace unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadFailure.message)
                    )
                    ForEach(loadFailure.actions) { action in
                        if action == .retry {
                            Button(action.title) { startup.perform(action) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button(action.title, role: .destructive) { startup.perform(action) }
                        }
                    }
                }
                .padding()
            } else {
                ProgressView("Loading GridRace")
                    .task { startup.loadApp() }
            }
        }
    }
}
