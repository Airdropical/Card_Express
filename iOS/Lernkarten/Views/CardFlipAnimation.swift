import SwiftUI

// MARK: - Style

private enum CardFlipStyle {
    static let axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 1, 0)

    /// Etwas straffer als zuvor, mit kaum sichtbarem Nachschwingen am Ende der Drehung.
    static let animation = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// Alternative für „Bewegung reduzieren“: nur eine kurze Überblendung.
    static let reducedMotionAnimation = Animation.easeInOut(duration: 0.2)

    /// Weniger dramatisch als der Standardwert 1: die Karte bleibt flach und lesbar.
    static let perspective: CGFloat = 0.45
    /// Wie stark die Karte beim Drehen „abhebt“ (Maximum bei 90°).
    static let liftScale: Double = 0.035
    /// Wie stark die Karte beim Wegdrehen abdunkelt (Maximum bei 90°).
    static let shadeOpacity: Double = 0.14
}

/// 0 bei 0° und 180° (Karte liegt flach), 1 bei 90° (Karte steht auf der Kante).
private func flipEdgeFactor(_ angle: Double) -> Double {
    abs(sin(angle * .pi / 180))
}

private extension View {
    /// Gemeinsame Transformation: leichtes Abheben + 3D-Drehung mit abgestimmter Perspektive.
    func flipTransform(angle: Double) -> some View {
        scaleEffect(1 + CardFlipStyle.liftScale * flipEdgeFactor(angle))
            .rotation3DEffect(
                .degrees(angle),
                axis: CardFlipStyle.axis,
                perspective: CardFlipStyle.perspective
            )
    }
}

// MARK: - FlipCard (empfohlen)

/// Karte mit Vorder- und Rückseite.
///
/// Die Seiten wechseln exakt bei 90°, wenn die Karte auf der Kante steht. Dadurch gibt es
/// kein Aufblitzen der Rückseite und keine gespiegelte Schrift, egal wie schnell oder
/// wie oft getippt wird. Die Animation ist unterbrechbar und übernimmt die Geschwindigkeit
/// der laufenden Drehung.
///
///     FlipCard(isFlipped: isFlipped) {
///         FrontView()
///     } back: {
///         BackView()
///     }
///     .onTapGesture { isFlipped.toggle() }
///
/// Die Animation steckt in `FlipCard`, ein `withAnimation` ist nicht nötig.
/// Beim Wechsel zur nächsten Karte `.id(card.id)` setzen, damit die neue Antwort
/// nicht kurz sichtbar wird.
struct FlipCard<Front: View, Back: View>: View {
    let isFlipped: Bool
    let cornerRadius: CGFloat
    let haptics: Bool
    private let front: Front
    private let back: Back

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isFlipped: Bool,
        cornerRadius: CGFloat = 24,
        haptics: Bool = true,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.isFlipped = isFlipped
        self.cornerRadius = cornerRadius
        self.haptics = haptics
        self.front = front()
        self.back = back()
    }

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    front
                        .opacity(isFlipped ? 0 : 1)
                        .allowsHitTesting(!isFlipped)
                        .accessibilityHidden(isFlipped)
                    back
                        .opacity(isFlipped ? 1 : 0)
                        .allowsHitTesting(isFlipped)
                        .accessibilityHidden(!isFlipped)
                }
            } else {
                FlipLayout(
                    angle: isFlipped ? 180 : 0,
                    cornerRadius: cornerRadius,
                    front: front,
                    back: back
                )
            }
        }
        .animation(
            reduceMotion ? CardFlipStyle.reducedMotionAnimation : CardFlipStyle.animation,
            value: isFlipped
        )
        .sensoryFeedback(trigger: isFlipped) { _, _ in
            haptics ? SensoryFeedback.impact(weight: .light, intensity: 0.8) : nil
        }
    }
}

/// Kennt den aktuellen (interpolierten) Winkel in jedem Animations-Frame
/// und kann deshalb die sichtbare Seite exakt bei 90° umschalten.
private struct FlipLayout<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let cornerRadius: CGFloat
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showsBack = cos(angle * .pi / 180) < 0
        let edge = flipEdgeFactor(angle)

        ZStack {
            front
                .opacity(showsBack ? 0 : 1)
                .allowsHitTesting(!showsBack)
                .accessibilityHidden(showsBack)

            // Die Rückseite ist von Anfang an um 180° gedreht und steht nach der Drehung aufrecht.
            back
                .rotation3DEffect(.degrees(180), axis: CardFlipStyle.axis)
                .opacity(showsBack ? 1 : 0)
                .allowsHitTesting(showsBack)
                .accessibilityHidden(!showsBack)
        }
        .overlay {
            // Dezente Abdunklung beim Wegdrehen gibt der Karte Tiefe.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(CardFlipStyle.shadeOpacity * edge))
                .allowsHitTesting(false)
        }
        .flipTransform(angle: angle)
    }
}

// MARK: - Bisherige API (bleibt kompatibel)

private struct CardFlipRotation: ViewModifier, Animatable {
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.flipTransform(angle: angle)
    }
}

extension View {
    /// Dreht den Inhalt einer Seite um 180°, damit die Schrift nach dem Flip aufrecht steht.
    /// Hinweis: Dieser Modifier kennt den Drehwinkel nicht und kann die Seite deshalb nicht
    /// bei 90° umschalten. Für neuen Code `FlipCard` verwenden.
    func cardFlipFace(isFlipped: Bool) -> some View {
        rotation3DEffect(
            .degrees(isFlipped ? 180 : 0),
            axis: CardFlipStyle.axis,
            perspective: CardFlipStyle.perspective
        )
    }

    /// Dreht die Karte mit der gemeinsamen Flip-Animation (jetzt mit Perspektive und leichtem Abheben).
    func cardFlipContainer(isFlipped: Bool) -> some View {
        modifier(CardFlipRotation(angle: isFlipped ? 180 : 0))
            .animation(CardFlipStyle.animation, value: isFlipped)
    }
}

// MARK: - Preview

private struct FlipCardPreview: View {
    @State private var isFlipped = false

    var body: some View {
        FlipCard(isFlipped: isFlipped) {
            face(title: "Frage", text: "Wofür steht die Abkürzung DNA?", color: .indigo)
        } back: {
            face(title: "Antwort", text: "Desoxyribonukleinsäure", color: .teal)
        }
        .frame(height: 280)
        .padding(24)
        .onTapGesture { isFlipped.toggle() }
    }

    private func face(title: String, text: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(text).font(.title2.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview {
    FlipCardPreview()
}
