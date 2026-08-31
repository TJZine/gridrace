import SwiftUI

@main
struct GridRaceApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private struct AppRootView: View {
    @State private var dailyModel: DailyClassicModel?
    @State private var tutorialModel: TutorialModel?
    @State private var loadFailure: LoadFailure?

    private enum LoadFailure {
        case bundledData
        case savedData(DailyClassicStore)

        var message: String {
            switch self {
            case .bundledData:
                "The bundled puzzle data is unavailable. Reinstall or update GridRace."
            case .savedData:
                "Your local Daily Classic history could not be read. You can retry or explicitly reset local game data."
            }
        }
    }

    var body: some View {
        Group {
            if let dailyModel, let tutorialModel {
                DailyAppView(daily: dailyModel, tutorial: tutorialModel)
            } else if let loadFailure {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "GridRace unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadFailure.message)
                    )
                    Button("Try again") { loadApp() }
                        .buttonStyle(.borderedProminent)
                    if case .savedData(let store) = loadFailure {
                        Button("Reset local game data", role: .destructive) {
                            do {
                                try store.resetLocalData()
                                loadApp()
                            } catch {
                                self.loadFailure = .savedData(store)
                            }
                        }
                    }
                }
                .padding()
            } else {
                ProgressView("Loading GridRace")
                    .task { loadApp() }
            }
        }
    }

    @MainActor
    private func loadApp() {
        loadFailure = nil
        let tutorialPack: WordPack
        let dailyPack: DailyWordPack
        do {
            tutorialPack = try WordPack.load(bundle: .main)
            dailyPack = try DailyWordPack.load(bundle: .main)
        } catch {
            loadFailure = .bundledData
            return
        }

        do {
            let store = try DailyClassicStore.applicationSupport()
            dailyModel = try DailyClassicModel(
                pack: dailyPack,
                store: store
            )
            tutorialModel = TutorialModel(acceptedWords: Set(tutorialPack.words))
        } catch DailyClassicError.puzzleUnavailable {
            loadFailure = .bundledData
        } catch {
            if let store = try? DailyClassicStore.applicationSupport() {
                loadFailure = .savedData(store)
            } else {
                loadFailure = .bundledData
            }
        }
    }
}
