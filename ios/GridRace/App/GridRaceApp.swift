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
    @State private var model: TutorialModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                TutorialView(model: model)
            } else if let loadError {
                ContentUnavailableView(
                    "Tutorial unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Loading tutorial")
                    .task { loadTutorial() }
            }
        }
    }

    @MainActor
    private func loadTutorial() {
        do {
            let pack = try WordPack.load(bundle: .main)
            model = TutorialModel(acceptedWords: Set(pack.words))
        } catch {
            loadError = "The bundled development words could not be read."
        }
    }
}
