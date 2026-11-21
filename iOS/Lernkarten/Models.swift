import Foundation
import NaturalLanguage

struct Flashcard: Identifiable, Codable, Equatable {
    var id = UUID()
    var question: String
    var answer: String
    var dueToday = true
    var timesSeen = 0
    /// Wiedervorlage: Abstand in Tagen und der Tag, ab dem die Karte wieder fällig ist.
    /// Optional, damit ältere gespeicherte Karten ohne diese Felder weiter lesbar bleiben.
    var intervalDays: Int? = nil
    var nextDue: Date? = nil
    /// Wie die Karte bisher lief: Anzahl falscher und mühsamer Antworten und die letzte Bewertung.
    /// Daraus entsteht der tägliche Test mit schweren Karten.
    var lapses: Int? = nil
    var hardCount: Int? = nil
    var lastRating: CardRating? = nil

    /// Dieselbe Regel wie im Backend (`daily_tests.is_hard`).
    var isHard: Bool {
        lastRating == .wrong || lastRating == .hard || 2 * (lapses ?? 0) + (hardCount ?? 0) >= 3
    }
}

/// Ein Test, den der Tutor erstellen kann: zu einem Termin mit Deck in den nächsten Tagen oder aus schweren Karten.
struct DailyTestOffer: Identifiable, Equatable {
    enum Kind: String { case exam, weak }
    var kind: Kind
    /// Kennung des Kalendereintrags bzw. Decks; leer beim Test aus schweren Karten.
    var reference: String
    var title: String
    var examDate: Date?
    var cards: [Flashcard]
    var id: String { "\(kind.rawValue):\(reference)" }

    static let examWindowDays = 3
    static let minExamCards = 4
    static let minWeakCards = 5
}

enum ReviewSchedule {
    static let maxIntervalDays = 180

    /// Neuer Abstand in Tagen; 0 bedeutet: bleibt heute fällig.
    static func nextInterval(current: Int?, rating: CardRating) -> Int {
        let previous = max(current ?? 0, 0)
        switch rating {
        case .wrong: return 0
        case .hard: return 0
        case .good: return min(previous == 0 ? 1 : previous * 2, maxIntervalDays)
        case .easy: return min(previous == 0 ? 3 : previous * 3, maxIntervalDays)
        }
    }

    static func dueDate(afterDays days: Int, from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
    }
}

struct VocabularyEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var term: String
    var translation: String
    var pronunciation: String = ""
    var example: String = ""
    var synonyms: [String] = []
    var difficulty = 1
    var isPinned = false
    var deckID: UUID? = nil
    var languagePairID: UUID? = nil
    var dueToday = true
    var timesSeen = 0
    var intervalDays: Int? = nil
    var nextDue: Date? = nil

    enum CodingKeys: String, CodingKey { case id, term, translation, pronunciation, example, synonyms, difficulty, isPinned, deckID, languagePairID, dueToday, timesSeen, intervalDays, nextDue }

    init(id: UUID = UUID(), term: String, translation: String, pronunciation: String = "", example: String = "", synonyms: [String] = [], difficulty: Int = 1, isPinned: Bool = false, deckID: UUID? = nil, languagePairID: UUID? = nil, dueToday: Bool = true, timesSeen: Int = 0) {
        self.id = id; self.term = term; self.translation = translation; self.pronunciation = pronunciation; self.example = example; self.synonyms = synonyms
        self.difficulty = difficulty; self.isPinned = isPinned; self.deckID = deckID; self.languagePairID = languagePairID; self.dueToday = dueToday; self.timesSeen = timesSeen
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        term = try values.decode(String.self, forKey: .term)
        translation = try values.decode(String.self, forKey: .translation)
        pronunciation = try values.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        example = try values.decodeIfPresent(String.self, forKey: .example) ?? ""
        synonyms = try values.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        difficulty = try values.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        deckID = try values.decodeIfPresent(UUID.self, forKey: .deckID)
        languagePairID = try values.decodeIfPresent(UUID.self, forKey: .languagePairID)
        dueToday = try values.decodeIfPresent(Bool.self, forKey: .dueToday) ?? true
        timesSeen = try values.decodeIfPresent(Int.self, forKey: .timesSeen) ?? 0
        intervalDays = try values.decodeIfPresent(Int.self, forKey: .intervalDays)
        nextDue = try values.decodeIfPresent(Date.self, forKey: .nextDue)
    }
}

struct VocabularyDeck: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var emoji = ""
    var languagePairID: UUID? = nil
    /// Übergeordneter Ordner; nil für Hauptordner. Es gibt nur eine Ebene Unterordner.
    var parentID: UUID? = nil
}

struct VocabularyLanguage: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var code: String
}

struct VocabularyLanguagePair: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourceLanguageID: UUID
    var targetLanguageID: UUID
}

struct FeedCard: Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case flashcard, vocabulary }
    var id: String
    var kind: Kind
    var front: String
    var back: String
    var detail: String
    var sourceLanguageCode: String? = nil
    var targetLanguageCode: String? = nil
}

struct Deck: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var emoji: String = "📚"
    var accentColor: String = "purple"
    var cards: [Flashcard] = []
    var summary: String = ""
    var parentID: UUID? = nil
    var examDate: Date? = nil
    var newCardsStopDaysBeforeExam = 4
    var targetGrade: Double? = nil

    enum CodingKeys: String, CodingKey { case id, name, emoji, accentColor, cards, summary, parentID, examDate, newCardsStopDaysBeforeExam, targetGrade }

    init(id: UUID = UUID(), name: String, emoji: String = "📚", accentColor: String = "purple", cards: [Flashcard] = [], summary: String = "", parentID: UUID? = nil, examDate: Date? = nil, newCardsStopDaysBeforeExam: Int = 4, targetGrade: Double? = nil) {
        self.id = id; self.name = name; self.emoji = emoji; self.accentColor = accentColor; self.cards = cards; self.summary = summary
        self.parentID = parentID; self.examDate = examDate; self.newCardsStopDaysBeforeExam = newCardsStopDaysBeforeExam; self.targetGrade = targetGrade
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        emoji = try values.decodeIfPresent(String.self, forKey: .emoji) ?? "📚"
        accentColor = try values.decodeIfPresent(String.self, forKey: .accentColor) ?? "purple"
        cards = try values.decodeIfPresent([Flashcard].self, forKey: .cards) ?? []
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        parentID = try values.decodeIfPresent(UUID.self, forKey: .parentID)
        examDate = try values.decodeIfPresent(Date.self, forKey: .examDate)
        newCardsStopDaysBeforeExam = try values.decodeIfPresent(Int.self, forKey: .newCardsStopDaysBeforeExam) ?? 4
        targetGrade = try values.decodeIfPresent(Double.self, forKey: .targetGrade)
    }
}

enum CardRating: String, Codable {
    case easy, good, hard, wrong
}

struct Evaluation: Decodable {
    var rating: CardRating
    var feedback: String
}

struct GeneratedCards: Decodable { var cards: [CardDraft] }
struct CardDraft: Codable, Identifiable {
    var id = UUID()
    var question: String
    var answer: String
    enum CodingKeys: String, CodingKey { case question, answer }
    init(question: String, answer: String) { self.question = question; self.answer = answer }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decode(String.self, forKey: .question)
        answer = try container.decode(String.self, forKey: .answer)
    }
}
struct TutorMessage: Codable, Identifiable { var id = UUID(); var role: String; var text: String }

struct TutorAgentPlan: Decodable {
    var reply: String
    var actions: [TutorAgentAction]
}

struct TutorAgentAction: Decodable {
    var type: String
    var parentDeck: String?
    var createParentDeck: Bool?
    var deckName: String?
    var subdeckName: String?
    var folderName: String?
    var title: String?
    var dateISO: String?
    var kind: String?
    var note: String?
    var cards: [CardDraft]?
    var vocabularyEntries: [TutorVocabularyDraft]?
    var subjectName: String?
    var termEntries: [TutorTermDraft]?
    var newTitle: String?
    var newDateISO: String?
    var newName: String?
}

struct TutorVocabularyDraft: Decodable, Identifiable {
    var id = UUID()
    var term: String
    var translation: String
    var pronunciation: String = ""
    var example: String = ""
    var synonyms: [String] = []
    var difficulty: Int = 1

    enum CodingKeys: String, CodingKey { case term, translation, pronunciation, example, synonyms, difficulty }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        term = try values.decode(String.self, forKey: .term)
        translation = try values.decode(String.self, forKey: .translation)
        pronunciation = try values.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        example = try values.decodeIfPresent(String.self, forKey: .example) ?? ""
        synonyms = try values.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        difficulty = min(max(try values.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1, 1), 3)
    }
}

struct SessionResult {
    var easy = 0
    var good = 0
    var hard = 0
    var wrong = 0
    var total: Int { easy + good + hard + wrong }
}

struct StudyActivity: Identifiable, Codable {
    var id = UUID()
    var answeredAt: Date
    var durationSeconds: TimeInterval
}

enum CalendarEntryKind: String, Codable, CaseIterable, Identifiable {
    case exam, test, assignment, other
    var id: String { rawValue }
}

struct CalendarEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var kind: CalendarEntryKind = .test
    var deckID: UUID? = nil
    var note: String = ""
}

/// Der vollständige Lernstand eines Kontos, wie er zwischen Geräten synchronisiert wird.
/// Einstellungen wie Sprache oder Erscheinungsbild bleiben pro Gerät.
struct CloudSnapshot: Codable {
    var schemaVersion = 1
    var savedAt = Date()
    var decks: [Deck]
    var vocabulary: [VocabularyEntry]
    var vocabularyDecks: [VocabularyDeck] = []
    var vocabularyLanguages: [VocabularyLanguage] = []
    var vocabularyLanguagePairs: [VocabularyLanguagePair] = []
    var calendarEntries: [CalendarEntry] = []
    var activities: [StudyActivity] = []
    var studyDays: [Date] = []
    var termSubjects: [TermSubject] = []
    var terms: [TermCard] = []

    enum CodingKeys: String, CodingKey { case schemaVersion, savedAt, decks, vocabulary, vocabularyDecks, vocabularyLanguages, vocabularyLanguagePairs, calendarEntries, activities, studyDays, termSubjects, terms }

    init(decks: [Deck], vocabulary: [VocabularyEntry], vocabularyDecks: [VocabularyDeck], vocabularyLanguages: [VocabularyLanguage], vocabularyLanguagePairs: [VocabularyLanguagePair], calendarEntries: [CalendarEntry], activities: [StudyActivity], studyDays: [Date], termSubjects: [TermSubject] = [], terms: [TermCard] = []) {
        self.termSubjects = termSubjects; self.terms = terms
        self.decks = decks; self.vocabulary = vocabulary; self.vocabularyDecks = vocabularyDecks; self.vocabularyLanguages = vocabularyLanguages
        self.vocabularyLanguagePairs = vocabularyLanguagePairs; self.calendarEntries = calendarEntries; self.activities = activities; self.studyDays = studyDays
    }

    /// Fehlende Felder bekommen Standardwerte, damit ältere und neuere App-Versionen denselben Stand lesen können.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        savedAt = try values.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        decks = try values.decode([Deck].self, forKey: .decks)
        vocabulary = try values.decode([VocabularyEntry].self, forKey: .vocabulary)
        vocabularyDecks = try values.decodeIfPresent([VocabularyDeck].self, forKey: .vocabularyDecks) ?? []
        vocabularyLanguages = try values.decodeIfPresent([VocabularyLanguage].self, forKey: .vocabularyLanguages) ?? []
        vocabularyLanguagePairs = try values.decodeIfPresent([VocabularyLanguagePair].self, forKey: .vocabularyLanguagePairs) ?? []
        calendarEntries = try values.decodeIfPresent([CalendarEntry].self, forKey: .calendarEntries) ?? []
        activities = try values.decodeIfPresent([StudyActivity].self, forKey: .activities) ?? []
        studyDays = try values.decodeIfPresent([Date].self, forKey: .studyDays) ?? []
        termSubjects = try values.decodeIfPresent([TermSubject].self, forKey: .termSubjects) ?? []
        terms = try values.decodeIfPresent([TermCard].self, forKey: .terms) ?? []
    }
}

/// Erkennt Vokabeln, bei denen Begriff und Übersetzung vertauscht sind (z. B. Englisch → Deutsch statt Deutsch → Englisch).
/// Die Spracherkennung läuft auf dem Gerät und unterscheidet zwei bekannte Sprachen auch bei einzelnen Wörtern zuverlässig.
enum VocabularyDirection {
    /// Ab diesem Wert gilt ein Eintrag als vertauscht. Eindeutige Fälle liegen nahe 2, unklare (z. B. „single“) nahe 0.
    static let swapThreshold = 0.8

    /// Positiv, wenn der Begriff nach der Zielsprache und die Übersetzung nach der Ausgangssprache aussieht (−2 … 2).
    static func swapScore(term: String, translation: String, sourceCode: String, targetCode: String) -> Double {
        let source = NLLanguage(rawValue: sourceCode.lowercased())
        let target = NLLanguage(rawValue: targetCode.lowercased())
        guard source != target else { return 0 }
        func likelihood(_ text: String) -> (source: Double, target: Double) {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [source, target]
            recognizer.processString(text)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
            return (hypotheses[source] ?? 0, hypotheses[target] ?? 0)
        }
        let termLanguage = likelihood(term)
        let translationLanguage = likelihood(translation)
        return (termLanguage.target - termLanguage.source) + (translationLanguage.source - translationLanguage.target)
    }

    static func looksSwapped(term: String, translation: String, sourceCode: String, targetCode: String) -> Bool {
        swapScore(term: term, translation: translation, sourceCode: sourceCode, targetCode: targetCode) > swapThreshold
    }

    /// Dreht vertauschte Vorschläge des Tutors um, bevor sie im Vorschlag erscheinen.
    static func oriented(_ entries: [TutorVocabularyDraft], sourceCode: String, targetCode: String) -> [TutorVocabularyDraft] {
        entries.map { entry in
            guard looksSwapped(term: entry.term, translation: entry.translation, sourceCode: sourceCode, targetCode: targetCode) else { return entry }
            var fixed = entry
            fixed.term = entry.translation
            fixed.translation = entry.term
            return fixed
        }
    }
}

// MARK: - Begriffe

/// Ein Fach im Bereich „Begriffe“, z. B. Biologie oder Jura. Vom Nutzer selbst angelegt.
struct TermSubject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var emoji: String = ""
}

/// Ein Fachbegriff mit Erklärung. Eigener Kartentyp, damit der Tutor Begriffe und Vokabeln unterscheidet.
struct TermCard: Identifiable, Codable, Equatable {
    var id = UUID()
    var subjectID: UUID?
    var term: String
    var definition: String
    var example: String = ""
    var isPinned = false
    var dueToday = true
    var timesSeen = 0
    var intervalDays: Int? = nil
    var nextDue: Date? = nil
    var lapses: Int? = nil

    enum CodingKeys: String, CodingKey { case id, subjectID, term, definition, example, isPinned, dueToday, timesSeen, intervalDays, nextDue, lapses }

    init(id: UUID = UUID(), subjectID: UUID?, term: String, definition: String, example: String = "") {
        self.id = id; self.subjectID = subjectID; self.term = term; self.definition = definition; self.example = example
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        subjectID = try values.decodeIfPresent(UUID.self, forKey: .subjectID)
        term = try values.decode(String.self, forKey: .term)
        definition = try values.decodeIfPresent(String.self, forKey: .definition) ?? ""
        example = try values.decodeIfPresent(String.self, forKey: .example) ?? ""
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        dueToday = try values.decodeIfPresent(Bool.self, forKey: .dueToday) ?? true
        timesSeen = try values.decodeIfPresent(Int.self, forKey: .timesSeen) ?? 0
        intervalDays = try values.decodeIfPresent(Int.self, forKey: .intervalDays)
        nextDue = try values.decodeIfPresent(Date.self, forKey: .nextDue)
        lapses = try values.decodeIfPresent(Int.self, forKey: .lapses)
    }
}

/// Vom Tutor vorgeschlagener Begriff.
struct TutorTermDraft: Decodable, Identifiable {
    var id = UUID()
    var term: String
    var definition: String
    var example: String = ""
    enum CodingKeys: String, CodingKey { case term, definition, example }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        term = try values.decode(String.self, forKey: .term)
        definition = try values.decodeIfPresent(String.self, forKey: .definition) ?? ""
        example = try values.decodeIfPresent(String.self, forKey: .example) ?? ""
    }
}
