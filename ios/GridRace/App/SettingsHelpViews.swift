import SwiftUI

struct DailySettingsView: View {
    @Bindable var model: DailyClassicModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("Play") {
                Toggle("Haptics", isOn: Binding(
                    get: { model.settings.hapticsEnabled },
                    set: { model.updateHaptics($0) }
                ))
                .listRowBackground(Color.card)
                Toggle("High-contrast feedback", isOn: Binding(
                    get: { model.settings.highContrastEnabled },
                    set: { model.updateHighContrast($0) }
                ))
                .listRowBackground(Color.card)
                Toggle("Hard Mode", isOn: Binding(
                    get: { model.game.progress.hardModeEnabled },
                    set: { model.updateHardMode($0) }
                ))
                .disabled(!model.game.canChangeHardMode)
                .listRowBackground(Color.card)
                Text("Reuse every revealed clue")
                    .font(StampType.caption)
                    .foregroundStyle(Color.secondaryInk)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.card)
                if !model.game.canChangeHardMode {
                    Text("Locked until tomorrow's puzzle")
                        .font(StampType.caption)
                        .foregroundStyle(Color.secondaryInk)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.card)
                }
            }
            if let message = model.storageMessage {
                Section {
                    Text(message)
                        .font(StampType.caption)
                        .foregroundStyle(Color.secondaryInk)
                    Button("Retry saving") { model.retryPersistence() }
                        .accessibilityIdentifier("daily-settings-retry-saving")
                }
                .listRowBackground(Color.card)
            }
            Section("Learn") {
                NavigationLink(value: AppRoute.help) {
                    Label("How to play", systemImage: "questionmark.circle")
                }
                .listRowBackground(Color.card)
            }
            Section("About") {
                NavigationLink(value: AppRoute.attribution) {
                    Label("Word list credits", systemImage: "book.closed")
                }
                .listRowBackground(Color.card)
                LabeledContent("Version", value: version)
                    .font(StampType.caption)
                    .listRowBackground(Color.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .listStyle(.insetGrouped)
        .tint(Color.ink)
        .environment(\.defaultMinListRowHeight, 44)
        .navigationTitle("Settings")
    }
}

struct DailyHelpView: View {
    var body: some View {
        ZStack {
            Color.page.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Six guesses to find the word")
                        .font(StampType.display.bold())
                    Text("Guess the five-letter answer in six accepted words. Each row gives evidence for your next move.")
                        .font(StampType.title3)
                    FeedbackExample(
                        letter: "R", feedback: .correct,
                        title: "Right letter, right spot", detail: "A checkmark means the letter is exactly where it belongs."
                    )
                    FeedbackExample(
                        letter: "A", feedback: .present,
                        title: "In the word, wrong spot", detail: "Turning arrows mean the letter is in the answer in another position."
                    )
                    FeedbackExample(
                        letter: "C", feedback: .absent,
                        title: "Not in the word", detail: "A minus means this letter is not in the answer."
                    )
                    DuplicateLetterExample(
                        title: "Same letter twice",
                        detail: "Answer GRAPE has one P, so only the first P is marked.",
                        accessibilityDetail: "In APPLE against GRAPE, exact matches use up answer copies first, so E is exact. Leftover copies are then claimed left to right: A and the first P are present while an unused copy remains, and the second P is absent because GRAPE has no P copy left."
                    )
                    Text("One puzzle a day, worldwide · new at 00:00 UTC")
                        .font(StampType.caption)
                        .foregroundStyle(Color.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var tileSize: CGFloat = 58

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            TileView(letter: letter, feedback: feedback, isDraft: false, emptyLabel: "")
                .frame(width: tileSize, height: tileSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(StampType.heading)
                Text(detail).font(.callout).foregroundStyle(Color.secondaryInk)
            }
        }
        .padding(14)
        .paperCard()
        .accessibilityElement(children: .combine)
    }
}

/// Fourth Help example: shared five-tile row for the canonical duplicate vector
/// `excess-guess-repeat` (answer `grape`, guess `apple`, feedback
/// `[present, present, absent, absent, correct]`). Fixed literals only —
/// evaluation and assertions belong in `GameRulesTests`.
private struct DuplicateLetterExample: View {
    let title: String
    let detail: String
    let accessibilityDetail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(StampType.heading)
            TileRowView(
                word: "APPLE",
                feedback: [.present, .present, .absent, .absent, .correct]
            )
            Text(detail).font(.callout).foregroundStyle(Color.secondaryInk)
        }
        .padding(14)
        .paperCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(accessibilityDetail)")
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
            Color.page.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Word list credits")
                        .font(StampType.display.bold())
                    Text("Daily Classic accepts a frozen baseline plus eligible English Wiktionary spellings. Answers are original GridRace curation.")
                        .font(StampType.title3)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Wiktionary snapshot enwiktionary-20260901", systemImage: "archivebox")
                            .font(StampType.heading)
                        Text("Dump SHA-256 0b7f554b…14c5e719. The full hash is recorded in the shipped corpus notice.")
                            .font(.callout)
                            .foregroundStyle(Color.secondaryInk)
                            .accessibilityLabel("Dump SHA-256 recorded in full in the shipped corpus notice.")
                        Link("Wiktionary dump archive for this release", destination: dumpsURL)
                            .font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Baseline union, expansions excluded", systemImage: "square.on.square")
                            .font(StampType.heading)
                        Text("Every one of the 8,508 frozen baseline spellings is kept verbatim. Wiktionary adds only explicitly evidenced forms; template-computed expansion-only forms stay excluded.")
                            .font(.callout)
                            .foregroundStyle(Color.secondaryInk)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Wiktionary data terms apply to that portion", systemImage: "text.book.closed")
                            .font(StampType.heading)
                        Text("The Wiktionary-derived spellings are used under the Creative Commons Attribution-ShareAlike 4.0 International License and the GNU Free Documentation License, which require attribution and same-or-compatible licensing of adapted material.")
                            .font(.callout)
                            .foregroundStyle(Color.secondaryInk)
                        Link("Creative Commons Attribution-ShareAlike 4.0 deed", destination: licenseDeedURL)
                            .font(.callout)
                        Link("Wiktionary copyright terms", destination: copyrightsURL)
                            .font(.callout)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Extraction software is separately licensed", systemImage: "wrench.and.screwdriver")
                            .font(StampType.heading)
                        Text("The Wiktextract extraction tool is MIT-licensed software. That license covers the tool, not the dictionary data above.")
                            .font(.callout)
                            .foregroundStyle(Color.secondaryInk)
                    }
                    Divider().overlay(Color.line)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Release review still pending", systemImage: "lock.fill")
                            .font(StampType.heading)
                        Text("Not cleared for distribution. Attribution review, baseline provenance beyond the historical web2 supplier note, and App Store and distribution review are still open release gates.")
                            .font(.callout)
                            .foregroundStyle(Color.secondaryInk)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Word list credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}
