import SwiftUI
import UIKit

/// System text styles preserve Dynamic Type while giving the scorecard its
/// printed headings and precise figures. Tile and key letters always stay bold.
enum StampType {
    static let display = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let title = Font.system(.title, design: .serif)
    static let title2 = Font.system(.title2, design: .serif)
    static let title3 = Font.system(.title3, design: .serif)
    static let heading = Font.system(.headline, design: .serif)
    static let figure = Font.system(.headline, design: .monospaced)
    static let caption = Font.system(.caption, design: .monospaced)
    static let caption2 = Font.system(.caption2, design: .monospaced)
    static let tile = Font.system(.title2, design: .serif, weight: .bold)
    static let key = Font.system(.callout, design: .serif, weight: .bold)
}

extension Color {
    private static func paperColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }

    private static func paperDynamic(
        light: UInt32, dark: UInt32,
        increasedLight: UInt32? = nil, increasedDark: UInt32? = nil
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let increased = traits.accessibilityContrast == .high
            let value = isDark
                ? (increased ? increasedDark ?? dark : dark)
                : (increased ? increasedLight ?? light : light)
            return paperColor(value)
        })
    }

    static let page = paperDynamic(light: 0xF2ECDF, dark: 0x171513)
    static let card = paperDynamic(light: 0xFAF6EC, dark: 0x211E1A)
    static let ink = paperDynamic(light: 0x1B1A17, dark: 0xEDE5D3)
    static let secondaryInk = paperDynamic(
        light: 0x6B6352, dark: 0x9C937F, increasedDark: 0xA39A86
    )
    // Quiet lines are decorative. Controls and action notices use ink borders.
    static let line = paperDynamic(
        light: 0xD8CFBC, dark: 0x3A352D,
        increasedLight: 0x6B6352, increasedDark: 0xA39A86
    )
    static let correct = paperDynamic(light: 0x7A1F2B, dark: 0xB8495A)
    static let present = paperDynamic(light: 0x7A1F2B, dark: 0xE08592)
    static let absent = paperDynamic(
        light: 0x8F8670, dark: 0x7A7262,
        increasedLight: 0x6B6352, increasedDark: 0xA39A86
    )
    static let strengthenedSecondaryInk = paperDynamic(light: 0x6B6352, dark: 0xA39A86)
    static let strengthenedAbsent = strengthenedSecondaryInk
    static let feedbackLetter = paperDynamic(light: 0xF7F0E2, dark: 0xFFFFFF)
}

private struct HighContrastFeedbackKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var highContrastFeedback: Bool {
        get { self[HighContrastFeedbackKey.self] }
        set { self[HighContrastFeedbackKey.self] = newValue }
    }
}

struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StampType.heading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(Color.card)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.ink, lineWidth: configuration.isPressed ? 3 : 1.5)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct OutlinedInkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StampType.heading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(Color.ink)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.ink, lineWidth: configuration.isPressed ? 3 : 1.5)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct PaperCardSurface: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.ink)
            .background(Color.card, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.line, lineWidth: 1)
            }
    }
}

extension View {
    func paperCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(PaperCardSurface(cornerRadius: cornerRadius))
    }
}

/// A ceremonial mark, never a control. Its text remains the accessible meaning.
struct ScorecardSeal: View {
    let title: String
    var symbol: String? = nil
    var usesClaret = true

    var body: some View {
        Label {
            Text(title).font(StampType.heading)
        } icon: {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
        }
        .foregroundStyle(usesClaret ? Color.present : Color.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.card, in: Capsule())
        .overlay { Capsule().stroke(usesClaret ? Color.present : Color.ink, lineWidth: 2) }
        .overlay { Capsule().inset(by: 4).stroke(usesClaret ? Color.present : Color.ink, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

enum NoticeKind {
    case action
    case information
}

/// Focus and timing belong to the screen. This leaf does not announce or
/// manufacture actions; the caller supplies exactly its permitted controls.
struct NoticeCard<Actions: View>: View {
    var subject: String? = nil
    var title: String? = nil
    let message: String
    var kind: NoticeKind = .action
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let subject { Text(subject).font(StampType.caption).foregroundStyle(Color.secondaryInk) }
            if let title { Text(title).font(StampType.title3.bold()).accessibilityAddTraits(.isHeader) }
            Text(message)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.ink, style: StrokeStyle(
                    lineWidth: kind == .action ? 1.5 : 1,
                    dash: kind == .information ? [5, 4] : []
                ))
        }
    }
}

/// At standard sizes the slot reserves keyboard space. At accessibility sizes
/// content grows naturally; feature containers own scrolling and focus.
struct KeyboardSlot<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 175)
            .background(Color.page)
    }
}

/// Single-speech behavior: the owning screen moves focus here; no announcement.
struct RaceErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        NoticeCard(message: message) {
            if let retry { Button("Retry", action: retry).buttonStyle(OutlinedInkButtonStyle()) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RaceKeyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.ink, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
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
