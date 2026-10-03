import SwiftUI
import UIKit

/// Structured error banner (U-01 contract, defined once here). Props:
/// `message: String`, `retry: (() -> Void)?`. Single-speech behavior: this view
/// never posts an announcement; the owning screen moves focus to the banner per
/// the U-06 state-to-focus map (focus or announcement, never both).
struct RaceErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.raceDanger)
                .accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button(action: retry) {
                    Text("Retry")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.raceDanger)
        .multilineTextAlignment(.leading)
        .padding(14)
        .background(Color.raceCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.raceDanger, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Subtle key-press feedback shared by letter and action keys: a short
/// ~0.97 scale plus a small opacity dip. Under Reduce Motion the scale
/// stays exactly 1.0 and only the non-motion opacity feedback remains.
struct RaceKeyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Color {
    // Race adaptive tokens (U-01 frozen shape). Light/dark hexes in comments.
    // Surfaces: racePage light #F7F2E9 / dark #141222; raceCard light #FFFFFF /
    // dark #232040; raceInset light #ECE5D8 / dark #171627. Borders-only depth
    // on app-owned surfaces; native Form/.alert/sheets stay system-owned.
    // Ink: raceInk light #1C1A24 / dark #F5F2EA; raceInkSecondary light #4E4B57 /
    // dark #C9C5D6; raceInkTertiary light #6F6C77 / dark #A8A4B8.
    // Lines: raceLine light #D8D2C4 / dark #3A3654; raceLineSoft light #E5DFD2 /
    // dark #2B2942; raceLineEmphasis light #3D3394 / dark #B7B0FF.
    // Hues (no green/yellow): raceIndigo light #3D3394 / dark #7B74E8;
    // raceCoral light #C74F33 / dark #E0704F; raceTeal light #0D6B78 / dark
    // #3A9AA8. Feedback fills keep white labels at >=3:1 in both appearances.
    // raceDanger light #B3261E / dark #FFB4A8.
    // Radius scale (frozen, enforced by literals in views): control 10, card 18,
    // sheet 26; Circle avatars and Capsule bars/answer pill excepted. Spacing
    // base 4pt (4/8/12/16/20/24). Type roles scale with Dynamic Type; no fixed
    // 92/56/44pt without .minimumScaleFactor or scaled-metric equivalents.
    private static func raceDynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let racePage: Color = raceDynamic(
        light: UIColor(red: 0.968, green: 0.949, blue: 0.914, alpha: 1),
        dark: UIColor(red: 0.078, green: 0.071, blue: 0.133, alpha: 1)
    )
    static let raceCard: Color = raceDynamic(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
        dark: UIColor(red: 0.137, green: 0.125, blue: 0.251, alpha: 1)
    )
    static let raceInset: Color = raceDynamic(
        light: UIColor(red: 0.925, green: 0.898, blue: 0.847, alpha: 1),
        dark: UIColor(red: 0.090, green: 0.086, blue: 0.153, alpha: 1)
    )
    static let raceInk: Color = raceDynamic(
        light: UIColor(red: 0.110, green: 0.102, blue: 0.141, alpha: 1),
        dark: UIColor(red: 0.961, green: 0.949, blue: 0.918, alpha: 1)
    )
    static let raceInkSecondary: Color = raceDynamic(
        light: UIColor(red: 0.306, green: 0.294, blue: 0.341, alpha: 1),
        dark: UIColor(red: 0.788, green: 0.773, blue: 0.839, alpha: 1)
    )
    static let raceInkTertiary: Color = raceDynamic(
        light: UIColor(red: 0.435, green: 0.424, blue: 0.467, alpha: 1),
        dark: UIColor(red: 0.659, green: 0.643, blue: 0.722, alpha: 1)
    )
    static let raceLine: Color = raceDynamic(
        light: UIColor(red: 0.847, green: 0.824, blue: 0.769, alpha: 1),
        dark: UIColor(red: 0.227, green: 0.212, blue: 0.329, alpha: 1)
    )
    static let raceLineSoft: Color = raceDynamic(
        light: UIColor(red: 0.898, green: 0.875, blue: 0.824, alpha: 1),
        dark: UIColor(red: 0.169, green: 0.161, blue: 0.259, alpha: 1)
    )
    static let raceLineEmphasis: Color = raceDynamic(
        light: UIColor(red: 0.239, green: 0.200, blue: 0.580, alpha: 1),
        dark: UIColor(red: 0.718, green: 0.690, blue: 1.0, alpha: 1)
    )
    static let raceBackground: Color = racePage
    static let raceIndigo: Color = raceDynamic(
        light: UIColor(red: 0.239, green: 0.200, blue: 0.580, alpha: 1),
        dark: UIColor(red: 0.482, green: 0.455, blue: 0.910, alpha: 1)
    )
    static let raceCoral: Color = raceDynamic(
        light: UIColor(red: 0.780, green: 0.310, blue: 0.200, alpha: 1),
        dark: UIColor(red: 0.878, green: 0.439, blue: 0.310, alpha: 1)
    )
    static let raceTeal: Color = raceDynamic(
        light: UIColor(red: 0.051, green: 0.420, blue: 0.470, alpha: 1),
        dark: UIColor(red: 0.227, green: 0.604, blue: 0.659, alpha: 1)
    )
    static let raceDanger: Color = raceDynamic(
        light: UIColor(red: 0.702, green: 0.149, blue: 0.118, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.706, blue: 0.659, alpha: 1)
    )
}

/// Explicit per-index avatar background swatch. Fixed sRGB values keep white
/// symbols at >=3:1 in both appearances.
struct AvatarSwatch: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

struct PlayerAvatarView: View {
    let seed: String
    var size: CGFloat = 56

    /// Frozen seed-to-symbol mapping. Do not reorder or remove entries:
    /// persisted seeds must resolve to the same symbol.
    static let avatarSymbols = [
        "hare.fill", "tortoise.fill", "bird.fill", "fish.fill",
        "ladybug.fill", "pawprint.fill", "leaf.fill", "bolt.fill"
    ]

    /// Explicit per-index backgrounds, each >=3:1 against white.
    static let avatarSwatches = [
        AvatarSwatch(red: 0.239, green: 0.200, blue: 0.580),
        AvatarSwatch(red: 0.051, green: 0.420, blue: 0.470),
        AvatarSwatch(red: 0.698, green: 0.227, blue: 0.122),
        AvatarSwatch(red: 0.478, green: 0.310, blue: 0.639),
        AvatarSwatch(red: 0.651, green: 0.141, blue: 0.310),
        AvatarSwatch(red: 0.357, green: 0.357, blue: 0.839),
        AvatarSwatch(red: 0.541, green: 0.353, blue: 0.000),
        AvatarSwatch(red: 0.200, green: 0.255, blue: 0.333),
    ]

    static func paletteIndex(for seed: String) -> Int {
        seed.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % avatarSymbols.count }
    }

    var body: some View {
        let index = Self.paletteIndex(for: seed)
        Image(systemName: Self.avatarSymbols[index])
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.avatarSwatches[index].color, in: Circle())
            .accessibilityLabel("Generated player avatar")
    }
}
