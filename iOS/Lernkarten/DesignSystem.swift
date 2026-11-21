import SwiftUI
import UIKit

enum Palette {
    static let purple = Color(red: 0.37, green: 0.27, blue: 0.83)
    static let lilac = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.20, green: 0.17, blue: 0.30, alpha: 1) : UIColor(red: 0.94, green: 0.92, blue: 1.0, alpha: 1) })
    static let ink = Color.primary
    static let muted = Color.secondary
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let green = Color(red: 0.15, green: 0.55, blue: 0.31)
    static let red = Color(red: 0.72, green: 0.20, blue: 0.32)
    /// Dunkler als die Systemfarben, damit weiße Schrift darauf lesbar bleibt.
    static let orange = Color(red: 0.72, green: 0.36, blue: 0.02)
    static let blue = Color(red: 0.05, green: 0.40, blue: 0.80)
    static let deckAccentOptions: [(name: String, color: Color)] = [
        ("purple", purple), ("blue", .blue), ("teal", .teal), ("green", green),
        ("orange", .orange), ("pink", .pink), ("red", red)
    ]
    static func deckAccent(_ name: String) -> Color {
        deckAccentOptions.first(where: { $0.name == name })?.color ?? purple
    }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.045), lineWidth: 1))
            .shadow(color: Palette.ink.opacity(0.035), radius: 12, y: 4)
    }
}

struct ErrorMessageCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(Palette.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.red.opacity(0.14), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

/// Gemeinsame Maße aller großen Knöpfe, damit Paare wie „Ablehnen / Übernehmen“ exakt gleich hoch sind.
private struct LargeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let foreground: Color
    let background: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 22)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(background.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Gesperrte Knöpfe sahen bisher aus wie aktive.
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LargeButtonBody(configuration: configuration, foreground: .white, background: Palette.purple)
    }
}

/// Zweitrangige Aktion neben einem `PrimaryButtonStyle`-Knopf (Ablehnen, Lösung zeigen, Beenden).
struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        LargeButtonBody(configuration: configuration, foreground: destructive ? Palette.red : Palette.purple,
                        background: destructive ? Palette.red.opacity(0.1) : Palette.purple.opacity(0.1))
    }
}

/// Kleiner Kapselknopf für Aktionen in Zeilen und Karten („Öffnen“, „Begründung“).
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(prominent ? Color.white : Palette.purple)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(prominent ? Palette.purple : Palette.purple.opacity(0.1), in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        }
    }
}
