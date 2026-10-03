import SwiftUI

struct DailySettingsView: View {
    @Bindable var model: DailyClassicModel

    var body: some View {
        Form {
            Section {
                Toggle("Haptics", isOn: Binding(
                    get: { model.settings.hapticsEnabled },
                    set: { model.updateHaptics($0) }
                ))
                Toggle("High-contrast feedback", isOn: Binding(
                    get: { model.settings.highContrastEnabled },
                    set: { model.updateHighContrast($0) }
                ))
                Toggle("Hard Mode", isOn: Binding(
                    get: { model.game.progress.hardModeEnabled },
                    set: { model.updateHardMode($0) }
                ))
                .disabled(!model.game.canChangeHardMode)
            } header: {
                Text("Play")
            } footer: {
                Text(model.game.canChangeHardMode
                    ? "Hard Mode requires every revealed clue to be reused."
                    : "Hard Mode is locked after the first accepted guess until tomorrow.")
            }
            Section("Learn") {
                NavigationLink(value: AppRoute.help) {
                    Label("How to Play", systemImage: "questionmark.circle")
                }
                NavigationLink(value: AppRoute.tutorial) {
                    Label("Practice race", systemImage: "figure.run")
                }
            }
            Section("Word list") {
                NavigationLink(value: AppRoute.attribution) {
                    Label("Word list attribution", systemImage: "book.closed")
                }
            }
            Section {
                Text("Daily Classic resets worldwide at 00:00 UTC. Reduce Motion follows your system accessibility setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.racePage)
        .navigationTitle("Settings")
    }
}

struct DailyHelpView: View {
    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Reach the finish in six")
                        .font(.largeTitle.bold())
                    Text("Guess the five-letter answer in six accepted words. Each row gives evidence for your next move.")
                        .font(.title3)
                    FeedbackExample(
                        letter: "R", feedback: .correct,
                        title: "Correct position", detail: "The checkmark means R is exactly where it belongs."
                    )
                    FeedbackExample(
                        letter: "A", feedback: .present,
                        title: "Present elsewhere", detail: "The turning arrow means A is in the answer in another position."
                    )
                    FeedbackExample(
                        letter: "C", feedback: .absent,
                        title: "Not in the answer", detail: "The minus means this C is not used. Repeated letters are counted exactly."
                    )
                    DuplicateLetterExample(
                        title: "Same letter twice",
                        detail: "In APPLE against GRAPE, exact matches use up answer copies first, so E is exact. Leftover copies are then claimed left to right: A and the first P are present while an unused copy remains, and the second P is absent because GRAPE has no P copy left."
                    )
                    Divider()
                    Label("One puzzle is shared worldwide each UTC day.", systemImage: "globe.americas.fill")
                    Label("A finished result cannot be replayed or changed.", systemImage: "lock.fill")
                    Label("Hard Mode reuses every revealed clue.", systemImage: "shield.checkered")
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeedbackExample: View {
    let letter: Character
    let feedback: Feedback
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            TileView(letter: letter, feedback: feedback, isDraft: false, emptyLabel: "")
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fourth Help example: fixed five-tile row for the canonical duplicate vector
/// `excess-guess-repeat` (answer `grape`, guess `apple`, feedback
/// `[present, present, absent, absent, correct]`). Fixed literals only —
/// evaluation and assertions belong in `GameRulesTests`.
private struct DuplicateLetterExample: View {
    let title: String
    let detail: String

    // One fixed source pairing each tile letter with its vector feedback
    // (`excess-guess-repeat`: APPLE vs GRAPE → [present, present, absent,
    // absent, correct]). Literals only; evaluation lives in GameRulesTests.
    private let tiles: [(letter: Character, feedback: Feedback)] = [
        (letter: "A", feedback: .present),
        (letter: "P", feedback: .present),
        (letter: "P", feedback: .absent),
        (letter: "L", feedback: .absent),
        (letter: "E", feedback: .correct),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack(spacing: 5) {
                ForEach(tiles.indices, id: \.self) { index in
                    TileView(
                        letter: tiles[index].letter,
                        feedback: tiles[index].feedback,
                        isDraft: false,
                        emptyLabel: ""
                    )
                    .frame(width: 52, height: 52)
                }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact summary of `shared/word-packs/ATTRIBUTION.md`. Static notice
/// text only: snapshot, transform, data terms, software-license
/// distinction, and the pending release gates. Stock components match
/// `DailyHelpView` so Dynamic Type and VoiceOver behavior stay native.
struct DailyAttributionView: View {
    private let copyrightsURL = URL(string: "https://en.wiktionary.org/wiki/Wiktionary:Copyrights")!
    private let licenseDeedURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
    private let dumpsURL = URL(string: "https://dumps.wikimedia.org/enwiktionary/20260901/")!

    var body: some View {
        ZStack {
            Color.racePage.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Where the words come from")
                        .font(.largeTitle.bold())
                    Text("Daily Classic accepts a frozen baseline plus eligible English Wiktionary spellings. Answers are original GridRace curation.")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Wiktionary snapshot enwiktionary-20260901", systemImage: "archivebox")
                            .font(.headline)
                        Text("Dump SHA-256 0b7f554b…14c5e719. The full hash is recorded in the shipped corpus notice.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Dump SHA-256 recorded in full in the shipped corpus notice.")
                        Link("Wiktionary dump archive for this release", destination: dumpsURL)
                            .font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Baseline union, expansions excluded", systemImage: "square.on.square")
                            .font(.headline)
                        Text("Every one of the 8,508 frozen baseline spellings is kept verbatim. Wiktionary adds only explicitly evidenced forms; template-computed expansion-only forms stay excluded.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Wiktionary data terms apply to that portion", systemImage: "text.book.closed")
                            .font(.headline)
                        Text("The Wiktionary-derived spellings are used under the Creative Commons Attribution-ShareAlike 4.0 International License and the GNU Free Documentation License, which require attribution and same-or-compatible licensing of adapted material.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Link("Creative Commons Attribution-ShareAlike 4.0 deed", destination: licenseDeedURL)
                            .font(.callout)
                        Link("Wiktionary copyright terms", destination: copyrightsURL)
                            .font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Extraction software is separately licensed", systemImage: "wrench.and.screwdriver")
                            .font(.headline)
                        Text("The Wiktextract extraction tool is MIT-licensed software. That license covers the tool, not the dictionary data above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Release review still pending", systemImage: "lock.fill")
                            .font(.headline)
                        Text("Not cleared for distribution. Attribution review, baseline provenance beyond the historical web2 supplier note, and App Store and distribution review are still open release gates.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Word List")
        .navigationBarTitleDisplayMode(.inline)
    }
}
