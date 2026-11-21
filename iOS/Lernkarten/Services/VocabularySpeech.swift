import AVFoundation
import SwiftUI

@MainActor
final class VocabularySpeechPlayer {
    static let shared = VocabularySpeechPlayer()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, languageCode: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        if let voice = AVSpeechSynthesisVoice(language: Self.localeIdentifier(for: languageCode)) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    private static func localeIdentifier(for code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        if normalized.contains("-") { return normalized }

        switch normalized.uppercased() {
        case "DE", "GER", "DEU", "GERMAN", "DEUTSCH": return "de-DE"
        case "EN", "ENG", "ENGLISH", "ENGLISCH": return "en-US"
        case "FR", "FRA", "FRE", "FRENCH", "FRANZÖSISCH": return "fr-FR"
        case "ES", "SPA", "SPANISH", "SPANISCH": return "es-ES"
        case "IT", "ITA", "ITALIAN", "ITALIENISCH": return "it-IT"
        case "PT", "POR", "PORTUGUESE", "PORTUGIESISCH": return "pt-PT"
        case "NL", "DUTCH", "NIEDERLÄNDISCH": return "nl-NL"
        case "JA", "JPN", "JAPANESE", "JAPANISCH": return "ja-JP"
        case "KO", "KOR", "KOREAN", "KOREANISCH": return "ko-KR"
        case "ZH", "CHI", "CHINESE", "CHINESISCH": return "zh-CN"
        case "RU", "RUS", "RUSSIAN", "RUSSISCH": return "ru-RU"
        case "TR", "TUR", "TURKISH", "TÜRKISCH": return "tr-TR"
        case "AR", "ARA", "ARABIC", "ARABISCH": return "ar-SA"
        case "PL", "POL", "POLISH", "POLNISCH": return "pl-PL"
        case "SV", "SWE", "SWEDISH", "SCHWEDISCH": return "sv-SE"
        case "DA", "DAN", "DANISH", "DÄNISCH": return "da-DK"
        case "NO", "NOR", "NORWEGIAN", "NORWEGISCH": return "nb-NO"
        default: return normalized.lowercased()
        }
    }
}

struct VocabularySpeechButton: View {
    let text: String
    let languageCode: String
    let label: String
    var size: Font = .body

    var body: some View {
        Button {
            VocabularySpeechPlayer.shared.speak(text, languageCode: languageCode)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(size.weight(.semibold))
                .foregroundStyle(Palette.purple)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
