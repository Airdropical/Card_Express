import SwiftUI

enum AppDesign {
    static let accent = Color(red: 0.20, green: 0.39, blue: 0.33)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let cardCorner: CGFloat = 24
    static let cardInset: CGFloat = 22

    static func card<S: ShapeStyle>(_ style: S = .regularMaterial) -> some View {
        RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
            .fill(style)
            .overlay {
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                    .strokeBorder(.white.opacity(0.42), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 8)
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = AppDesign.cardInset
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                AppDesign.card(.ultraThinMaterial)
                    .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.68))
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.cardCorner, style: .continuous))
            }
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}

struct LevelBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppDesign.accent.opacity(0.10), in: Capsule())
            .foregroundStyle(AppDesign.accent)
    }
}
