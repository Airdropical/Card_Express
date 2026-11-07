import Foundation
import Combine

enum Language: String, CaseIterable, Identifiable, Codable {
    case de
    case en

    var id: String { rawValue }

    var name: String {
        switch self {
        case .de: return "Deutsch"
        case .en: return "English"
        }
    }

    var flag: String { self == .de ? "DE" : "EN" }
}

struct LemmaEntry: Codable, Identifiable, Hashable {
    let lemma: Lemma
    let senses: [Sense]
    let quality: Quality?

    var id: String { lemma.id }
}

struct Lemma: Codable, Hashable {
    let id: String
    let language: Language
    let text: String
    let wordClass: String
    let ipa: String?
    let frequencyRank: Int?
    let level: String
    let article: String?
    let plural: String?
}

struct Sense: Codable, Identifiable, Hashable {
    let id: String
    let shortMeaning: String
    let translation: Translation
    let explanations: [Explanation]
    let article: String?
    let plural: String?
}

struct Translation: Codable, Hashable {
    let language: Language
    let text: String
    let alternatives: [String]?
    let linkedSenseIDs: [String]?
}

struct Explanation: Codable, Hashable {
    let explanationLanguage: Language
    let level: String
    let definition: String
    let memoryAid: String?
    let confusion: String?
    let examples: [Example]
    let quality: Quality?
}

struct Example: Codable, Hashable {
    let sentence: String
    let translation: String?
    let source: String
    let sourceID: String?
}

struct Quality: Codable, Hashable {
    let status: String
    let score: Double?
    let notes: [String]?
    let modelVersion: String?
    let date: String?
}

extension Lemma {
    enum CodingKeys: String, CodingKey {
        case id, text, plural, ipa
        case level = "niveau"
        case article = "artikel"
        case language = "sprache"
        case wordClass = "wortart"
        case frequencyRank = "haeufigkeitsrang"
    }
}

extension LemmaEntry {
    enum CodingKeys: String, CodingKey {
        case lemma, senses
        case quality = "qualitaet"
    }
}

extension Sense {
    enum CodingKeys: String, CodingKey {
        case id, explanations
        case shortMeaning = "bedeutung_kurz"
        case translation = "uebersetzung"
        case article = "artikel"
        case plural
    }
}

extension Translation {
    enum CodingKeys: String, CodingKey {
        case text
        case language = "sprache"
        case alternatives = "alternativen"
        case linkedSenseIDs = "verknuepfte_sense_ids"
    }
}

extension Explanation {
    enum CodingKeys: String, CodingKey {
        case level = "stufe"
        case definition
        case examples = "beispiele"
        case explanationLanguage = "erklaersprache"
        case memoryAid = "merkhilfe"
        case confusion = "verwechslung"
        case quality = "qualitaet"
    }
}

extension Example {
    enum CodingKeys: String, CodingKey {
        case sentence = "satz"
        case translation = "uebersetzung"
        case source = "quelle"
        case sourceID = "quelle_id"
    }
}

extension Quality {
    enum CodingKeys: String, CodingKey {
        case status
        case score = "pruef_score"
        case notes = "hinweise"
        case modelVersion = "modellversion"
        case date = "datum"
    }
}

@MainActor
final class ContentStore: ObservableObject {
    @Published private(set) var entries: [LemmaEntry] = []
    @Published private(set) var loadError: String?

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "testlauf-03-ergebnisse", withExtension: "json") else {
            loadError = "Die Wortdaten konnten im App-Bundle nicht gefunden werden."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([LemmaEntry].self, from: data)
                .sorted { $0.lemma.text.localizedStandardCompare($1.lemma.text) == .orderedAscending }
        } catch {
            loadError = "Die Wortdaten konnten nicht geladen werden: \(error.localizedDescription)"
        }
        reloadFromConfiguredServer()
    }

    func reloadFromConfiguredServer() {
        let server = UserDefaults.standard.string(forKey: "wordExpressAPIURL") ?? "http://127.0.0.1:8080"
        guard let client = try? WordExpressAPIClient(serverURL: server),
              let url = URL(string: "/api/v1/content", relativeTo: client.baseURL) else { return }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { return }
                let remoteEntries = try JSONDecoder().decode([LemmaEntry].self, from: data)
                    .sorted { $0.lemma.text.localizedStandardCompare($1.lemma.text) == .orderedAscending }
                guard !remoteEntries.isEmpty else { return }
                entries = remoteEntries
                loadError = nil
            } catch {
                // Keep the bundled vocabulary available while offline.
            }
        }
    }

    var sensesByID: [String: (LemmaEntry, Sense)] {
        Dictionary(uniqueKeysWithValues: entries.flatMap { entry in
            entry.senses.map { ($0.id, (entry, $0)) }
        })
    }
}
