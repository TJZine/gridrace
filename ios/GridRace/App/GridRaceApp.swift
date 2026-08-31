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
    @State private var loadError: String?

    var body: some View {
        Group {
            if let dailyModel, let tutorialModel {
                DailyAppView(daily: dailyModel, tutorial: tutorialModel)
            } else if let loadError {
                ContentUnavailableView(
                    "GridRace unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Loading GridRace")
                    .task { loadApp() }
            }
        }
    }

    @MainActor
    private func loadApp() {
        do {
            let tutorialPack = try WordPack.load(bundle: .main)
            let dailyPack = try DailyWordPack.load(bundle: .main)
            tutorialModel = TutorialModel(acceptedWords: Set(tutorialPack.words))
            dailyModel = try DailyClassicModel(
                pack: dailyPack,
                store: DailyClassicStore.applicationSupport()
            )
        } catch {
            loadError = "The bundled puzzle data or saved progress could not be read."
        }
    }
}
