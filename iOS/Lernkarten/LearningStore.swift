import Foundation
import Observation
import UIKit
import UserNotifications

@Observable @MainActor
final class LearningStore {
    private let storageKey = "learncards.decks.v1"
    private let activityStorageKey = "learncards.activity.v1"
    private let studyDaysStorageKey = "learncards.studyDays.v1"
    private let vocabularyStorageKey = "learncards.vocabulary.v1"
    private let vocabularyDeckStorageKey = "learncards.vocabularyDecks.v1"
    private let vocabularyLanguagesStorageKey = "learncards.vocabularyLanguages.v1"
    private let vocabularyLanguagePairsStorageKey = "learncards.vocabularyLanguagePairs.v1"
    private let selectedVocabularyLanguagePairKey = "learncards.selectedVocabularyLanguagePair.v1"
    private let calendarStorageKey = "learncards.calendarEntries.v1"
    static let defaultGermanLanguageID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
    static let defaultEnglishLanguageID = UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!
    static let defaultVocabularyLanguagePairID = UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!
    var decks: [Deck] { didSet { save() } }
    var activities: [StudyActivity] { didSet { saveActivities() } }
    var studyDays: [Date] { didSet { saveStudyDays() } }
    var calendarEntries: [CalendarEntry] { didSet { saveCalendarEntries() } }
    var vocabulary: [VocabularyEntry] { didSet { saveVocabulary() } }
    var vocabularyDecks: [VocabularyDeck] { didSet { saveVocabularyDecks() } }
    var vocabularyLanguages: [VocabularyLanguage] { didSet { saveVocabularyLanguages() } }
    var vocabularyLanguagePairs: [VocabularyLanguagePair] { didSet { saveVocabularyLanguagePairs() } }
    var termSubjects: [TermSubject] { didSet { persist(termSubjects, key: termSubjectsStorageKey) } }
    var terms: [TermCard] { didSet { persist(terms, key: termsStorageKey) } }
    private let termSubjectsStorageKey = "learncards.termSubjects.v1"
    private let termsStorageKey = "learncards.terms.v1"
    var selectedVocabularyLanguagePairID: UUID { didSet { UserDefaults.standard.set(selectedVocabularyLanguagePairID.uuidString, forKey: selectedVocabularyLanguagePairKey) } }
    var sessionSize = UserDefaults.standard.object(forKey: "learncards.sessionSize") as? Int ?? 20 { didSet { UserDefaults.standard.set(sessionSize, forKey: "learncards.sessionSize") } }
    var language = {
        let saved = UserDefaults.standard.string(forKey: "learncards.language") ?? "Deutsch"
        return saved == "Englisch" ? "Englisch" : "Deutsch"
    }() {
        didSet {
            if language != "Deutsch" && language != "Englisch" { language = "Deutsch" }
            UserDefaults.standard.set(language, forKey: "learncards.language")
        }
    }
    var appearance = UserDefaults.standard.string(forKey: "learncards.appearance") ?? "System" { didSet { UserDefaults.standard.set(appearance, forKey: "learncards.appearance") } }
    var randomOrder = UserDefaults.standard.object(forKey: "learncards.randomOrder") as? Bool ?? true { didSet { UserDefaults.standard.set(randomOrder, forKey: "learncards.randomOrder") } }
    var aiEvaluation = UserDefaults.standard.object(forKey: "learncards.aiEvaluation") as? Bool ?? true { didSet { UserDefaults.standard.set(aiEvaluation, forKey: "learncards.aiEvaluation") } }

    /// Speicherschlüssel, deren Inhalt beim Start nicht lesbar war. Die Rohdaten liegen dann
    /// unverändert unter `<Schlüssel>.unreadable`, damit nichts stillschweigend verloren geht.
    private(set) var unreadableStorageKeys: [String] = []
    var showsUnreadableDataWarning = false

    // MARK: Synchronisierung (Zustand)

    enum SyncState: Equatable { case idle, syncing, failed(String) }
    /// Cloud und Gerät haben sich unabhängig voneinander geändert; der Nutzer entscheidet, welcher Stand gilt.
    struct SyncConflict { let remote: CloudSnapshot; let remoteRevision: Int }

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncedAt: Date? = UserDefaults.standard.object(forKey: "learncards.sync.lastSyncedAt") as? Date {
        didSet { UserDefaults.standard.set(lastSyncedAt, forKey: "learncards.sync.lastSyncedAt") }
    }
    var syncConflict: SyncConflict?
    /// Heute bereits abgeschlossene Tests (pro Gerät), damit sie nicht erneut angeboten werden.
    private(set) var completedTestKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "learncards.completedTests") ?? []) {
        didSet { UserDefaults.standard.set(Array(completedTestKeys), forKey: "learncards.completedTests") }
    }
    @ObservationIgnored private var isLoading = true
    @ObservationIgnored private var tracksChanges = true
    @ObservationIgnored private var changeCounter = 0
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    /// Die Cloud-Revision, auf der der lokale Stand beruht; nil, solange dieses Gerät noch nie synchronisiert hat.
    @ObservationIgnored private var syncedRevision: Int? {
        get { UserDefaults.standard.object(forKey: "learncards.sync.revision") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "learncards.sync.revision") }
    }
    @ObservationIgnored private var hasUnsyncedChanges: Bool {
        get { UserDefaults.standard.bool(forKey: "learncards.sync.dirty") }
        set { UserDefaults.standard.set(newValue, forKey: "learncards.sync.dirty") }
    }

    /// Liest einen gespeicherten Wert. Sind Daten vorhanden, aber nicht dekodierbar, werden sie
    /// gesichert, bevor der Standardwert (und später ein neuer Speicherstand) sie ersetzt.
    private static func load<T: Decodable>(_ type: T.Type, key: String, unreadable: inout [String]) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        UserDefaults.standard.set(data, forKey: key + ".unreadable")
        unreadable.append(key)
        return nil
    }

    init() {
        var unreadable: [String] = []
        defer {
            unreadableStorageKeys = unreadable
            showsUnreadableDataWarning = !unreadable.isEmpty
        }
        studyDays = Self.load([Date].self, key: studyDaysStorageKey, unreadable: &unreadable) ?? []
        let defaultLanguages = [
            VocabularyLanguage(id: Self.defaultGermanLanguageID, name: "Deutsch", code: "DE"),
            VocabularyLanguage(id: Self.defaultEnglishLanguageID, name: "Englisch", code: "EN")
        ]
        var loadedLanguages = Self.load([VocabularyLanguage].self, key: vocabularyLanguagesStorageKey, unreadable: &unreadable) ?? defaultLanguages
        for language in defaultLanguages where !loadedLanguages.contains(where: { $0.id == language.id }) { loadedLanguages.append(language) }
        vocabularyLanguages = loadedLanguages

        let defaultPair = VocabularyLanguagePair(id: Self.defaultVocabularyLanguagePairID, sourceLanguageID: Self.defaultGermanLanguageID, targetLanguageID: Self.defaultEnglishLanguageID)
        var loadedPairs = Self.load([VocabularyLanguagePair].self, key: vocabularyLanguagePairsStorageKey, unreadable: &unreadable) ?? [defaultPair]
        if !loadedPairs.contains(where: { $0.id == defaultPair.id }) { loadedPairs.insert(defaultPair, at: 0) }
        vocabularyLanguagePairs = loadedPairs
        calendarEntries = Self.load([CalendarEntry].self, key: calendarStorageKey, unreadable: &unreadable) ?? []
        let savedSelectedPairID = UserDefaults.standard.string(forKey: selectedVocabularyLanguagePairKey).flatMap(UUID.init(uuidString:))
        selectedVocabularyLanguagePairID = savedSelectedPairID.flatMap { id in loadedPairs.first(where: { $0.id == id })?.id } ?? defaultPair.id

        let loadedDecks = Self.load([VocabularyDeck].self, key: vocabularyDeckStorageKey, unreadable: &unreadable) ?? []
        vocabularyDecks = loadedDecks.map { deck in
            var migrated = deck
            if migrated.languagePairID == nil { migrated.languagePairID = defaultPair.id }
            return migrated
        }
        let loadedVocabulary = Self.load([VocabularyEntry].self, key: vocabularyStorageKey, unreadable: &unreadable) ?? []
        vocabulary = loadedVocabulary.map { entry in
            var migrated = entry
            if migrated.languagePairID == nil { migrated.languagePairID = defaultPair.id }
            return migrated
        }
        activities = Self.load([StudyActivity].self, key: activityStorageKey, unreadable: &unreadable) ?? []
        termSubjects = Self.load([TermSubject].self, key: "learncards.termSubjects.v1", unreadable: &unreadable) ?? []
        terms = Self.load([TermCard].self, key: "learncards.terms.v1", unreadable: &unreadable) ?? []
        if let saved = Self.load([Deck].self, key: storageKey, unreadable: &unreadable) {
            decks = saved
        } else {
            decks = [Deck(name: "Willkommen bei Lernkarten", emoji: "👋", cards: [
                Flashcard(question: "Was sind Karteikarten?", answer: "Ein Lernformat mit einer Frage auf der Vorderseite und einer Antwort auf der Rückseite."),
                Flashcard(question: "Was bedeutet verteiltes Lernen?", answer: "Lernstoff wird über mehrere Zeitpunkte verteilt wiederholt."),
                Flashcard(question: "Was sind Alkane?", answer: "Kohlenwasserstoffe, die ausschließlich aus Kohlenstoff- und Wasserstoffatomen bestehen."),
                Flashcard(question: "Was kennzeichnet eine homologe Reihe?", answer: "Aufeinanderfolgende Verbindungen unterscheiden sich jeweils um eine CH₂-Gruppe.")
            ])]
        }
        saveVocabularyLanguages()
        saveVocabularyLanguagePairs()
        saveVocabularyDecks()
        saveVocabulary()
        isLoading = false
        refreshDueItems()
    }

    /// Setzt Karten und Vokabeln wieder auf fällig, deren Wiedervorlage-Tag erreicht ist.
    /// Läuft beim Start und immer, wenn die App in den Vordergrund kommt.
    func refreshDueItems(now: Date = Date()) {
        // Abgeleiteter Zustand: Jedes Gerät berechnet ihn selbst, deshalb zählt er nicht als Änderung für den Sync.
        tracksChanges = false
        defer { tracksChanges = true }
        let tomorrow = ReviewSchedule.dueDate(afterDays: 1, from: now)
        var updatedDecks = decks
        var decksChanged = false
        for deckIndex in updatedDecks.indices {
            for cardIndex in updatedDecks[deckIndex].cards.indices where !updatedDecks[deckIndex].cards[cardIndex].dueToday {
                if let due = updatedDecks[deckIndex].cards[cardIndex].nextDue {
                    if due <= now { updatedDecks[deckIndex].cards[cardIndex].dueToday = true; decksChanged = true }
                } else {
                    // Vor Einführung der Wiedervorlage gelernt: einmalig für morgen einplanen.
                    updatedDecks[deckIndex].cards[cardIndex].intervalDays = 1
                    updatedDecks[deckIndex].cards[cardIndex].nextDue = tomorrow
                    decksChanged = true
                }
            }
        }
        if decksChanged { decks = updatedDecks }

        var updatedVocabulary = vocabulary
        var vocabularyChanged = false
        for index in updatedVocabulary.indices where !updatedVocabulary[index].dueToday {
            if let due = updatedVocabulary[index].nextDue {
                if due <= now { updatedVocabulary[index].dueToday = true; vocabularyChanged = true }
            } else {
                updatedVocabulary[index].intervalDays = 1
                updatedVocabulary[index].nextDue = tomorrow
                vocabularyChanged = true
            }
        }
        if vocabularyChanged { vocabulary = updatedVocabulary }

        var updatedTerms = terms
        var termsChanged = false
        for index in updatedTerms.indices where !updatedTerms[index].dueToday {
            if let due = updatedTerms[index].nextDue, due <= now { updatedTerms[index].dueToday = true; termsChanged = true }
        }
        if termsChanged { terms = updatedTerms }
    }

    // MARK: Synchronisierung

    private func noteLocalChange() {
        guard !isLoading, tracksChanges else { return }
        changeCounter += 1
        hasUnsyncedChanges = true
        guard LearningAPI.shared.hasSession else { return }
        // Kurz warten, damit eine Lernsitzung nicht nach jeder Karte hochlädt.
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            // Vor dem Start austragen: `sync()` bricht einen noch wartenden Auftrag ab, nicht sich selbst.
            self.pushTask = nil
            await self.sync()
        }
    }

    private func makeSnapshot() -> CloudSnapshot {
        CloudSnapshot(decks: decks, vocabulary: vocabulary, vocabularyDecks: vocabularyDecks, vocabularyLanguages: vocabularyLanguages,
                      vocabularyLanguagePairs: vocabularyLanguagePairs, calendarEntries: calendarEntries, activities: activities, studyDays: studyDays,
                      termSubjects: termSubjects, terms: terms)
    }

    /// Nur das Willkommens-Deck, nichts gelernt, nichts angelegt: Dann darf ein Cloud-Stand ohne Rückfrage übernommen werden.
    private var isPristine: Bool {
        let untouchedDecks = decks.isEmpty || (decks.count == 1 && decks[0].name == "Willkommen bei Lernkarten" && decks[0].cards.allSatisfy { $0.timesSeen == 0 })
        return untouchedDecks && vocabulary.isEmpty && vocabularyDecks.isEmpty && calendarEntries.isEmpty && activities.isEmpty && terms.isEmpty && termSubjects.isEmpty
    }

    private func apply(_ snapshot: CloudSnapshot, revision: Int) {
        tracksChanges = false
        decks = snapshot.decks
        vocabulary = snapshot.vocabulary
        vocabularyDecks = snapshot.vocabularyDecks
        var languages = snapshot.vocabularyLanguages
        for language in [VocabularyLanguage(id: Self.defaultGermanLanguageID, name: "Deutsch", code: "DE"), VocabularyLanguage(id: Self.defaultEnglishLanguageID, name: "Englisch", code: "EN")]
        where !languages.contains(where: { $0.id == language.id }) { languages.append(language) }
        vocabularyLanguages = languages
        var pairs = snapshot.vocabularyLanguagePairs
        if !pairs.contains(where: { $0.id == Self.defaultVocabularyLanguagePairID }) {
            pairs.insert(VocabularyLanguagePair(id: Self.defaultVocabularyLanguagePairID, sourceLanguageID: Self.defaultGermanLanguageID, targetLanguageID: Self.defaultEnglishLanguageID), at: 0)
        }
        vocabularyLanguagePairs = pairs
        if !pairs.contains(where: { $0.id == selectedVocabularyLanguagePairID }) { selectedVocabularyLanguagePairID = Self.defaultVocabularyLanguagePairID }
        calendarEntries = snapshot.calendarEntries
        activities = snapshot.activities
        studyDays = snapshot.studyDays
        termSubjects = snapshot.termSubjects
        terms = snapshot.terms
        tracksChanges = true
        syncedRevision = revision
        hasUnsyncedChanges = false
        refreshDueItems()
    }

    /// Gleicht den lokalen Stand mit der Cloud ab. Ohne Anmeldung passiert nichts.
    func sync() async {
        guard LearningAPI.shared.hasSession, syncState != .syncing, syncConflict == nil else { return }
        pushTask?.cancel()
        syncState = .syncing
        do {
            try await reconcile(retryOnConflict: true)
            if syncConflict == nil { lastSyncedAt = Date() }
            syncState = .idle
        } catch {
            syncState = .failed(LearningAPI.shared.userFacingMessage(for: error, language: language))
        }
    }

    private func reconcile(retryOnConflict: Bool) async throws {
        let remote = try await LearningAPI.shared.fetchSnapshot()
        let known = syncedRevision
        if remote.revision == known {
            if hasUnsyncedChanges { try await upload(onto: remote.revision, retryOnConflict: retryOnConflict) }
            return
        }
        guard let cloud = remote.snapshot else {
            // Die Cloud ist noch leer: Dieses Gerät liefert den ersten Stand.
            try await upload(onto: remote.revision, retryOnConflict: retryOnConflict)
            return
        }
        if (known != nil && !hasUnsyncedChanges) || (known == nil && isPristine) {
            apply(cloud, revision: remote.revision)
            return
        }
        syncConflict = SyncConflict(remote: cloud, remoteRevision: remote.revision)
    }

    private func upload(onto revision: Int, retryOnConflict: Bool) async throws {
        let changesAtStart = changeCounter
        do {
            syncedRevision = try await LearningAPI.shared.pushSnapshot(makeSnapshot(), revision: revision)
            // Änderungen während des Hochladens bleiben als offen markiert.
            if changeCounter == changesAtStart { hasUnsyncedChanges = false } else { noteLocalChange() }
        } catch let LearningAPIError.http(status, _, _) where status == 409 && retryOnConflict {
            try await reconcile(retryOnConflict: false)
        }
    }

    /// Entscheidung des Nutzers bei einem Konflikt: Cloud-Stand übernehmen oder den Stand dieses Geräts hochladen.
    func resolveSyncConflict(_ conflict: SyncConflict, useCloud: Bool) async {
        syncConflict = nil
        if useCloud {
            apply(conflict.remote, revision: conflict.remoteRevision)
            lastSyncedAt = Date()
            return
        }
        syncState = .syncing
        do {
            try await upload(onto: conflict.remoteRevision, retryOnConflict: false)
            lastSyncedAt = Date()
            syncState = .idle
        } catch {
            syncState = .failed(LearningAPI.shared.userFacingMessage(for: error, language: language))
        }
    }

    /// Nach Abmelden oder Kontolöschung: Die lokalen Daten bleiben, gelten aber als noch nie synchronisiert.
    func forgetSyncState() {
        pushTask?.cancel()
        syncedRevision = nil
        syncConflict = nil
        lastSyncedAt = nil
        syncState = .idle
    }

    func addDeck(name: String, emoji: String = "📚", parentID: UUID? = nil, cards: [Flashcard] = [], accentColor: String = "purple") {
        decks.insert(Deck(name: name.isEmpty ? "Neues Deck" : name, emoji: emoji, accentColor: accentColor, cards: cards, parentID: parentID), at: 0)
    }

    func updateDeck(_ id: UUID, name: String, emoji: String, examDate: Date?, stopDays: Int, targetGrade: Double?, accentColor: String) {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return }
        decks[index].name = name
        decks[index].emoji = emoji
        decks[index].accentColor = accentColor
        decks[index].examDate = examDate
        decks[index].newCardsStopDaysBeforeExam = stopDays
        decks[index].targetGrade = targetGrade
    }

    func addCalendarEntry(title: String, date: Date, kind: CalendarEntryKind, deckID: UUID?, note: String) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        calendarEntries.append(CalendarEntry(title: cleanedTitle, date: date, kind: kind, deckID: deckID, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func updateCalendarEntry(_ entry: CalendarEntry) {
        guard let index = calendarEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.title.isEmpty else { return }
        calendarEntries[index] = updated
    }

    func removeCalendarEntry(_ id: UUID) { calendarEntries.removeAll { $0.id == id } }

    var allCalendarEntries: [CalendarEntry] {
        let calendar = Calendar.current
        let deckExams = decks.compactMap { deck -> CalendarEntry? in
            guard let date = deck.examDate else { return nil }
            let hasExplicitExam = calendarEntries.contains { $0.kind == .exam && $0.deckID == deck.id && calendar.isDate($0.date, inSameDayAs: date) }
            guard !hasExplicitExam else { return nil }
            let examLabel = language == "Englisch" ? "Exam" : "Prüfung"
            return CalendarEntry(id: deck.id, title: "\(deck.emoji) \(deck.name) · \(examLabel)", date: date, kind: .exam, deckID: deck.id)
        }
        return (calendarEntries + deckExams).sorted { $0.date < $1.date }
    }

    func calendarEntries(on date: Date) -> [CalendarEntry] {
        allCalendarEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func addCards(_ drafts: [CardDraft], to deckID: UUID) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else { return }
        decks[index].cards.append(contentsOf: drafts.map { Flashcard(question: $0.question, answer: $0.answer) })
    }

    var selectedVocabularyLanguagePair: VocabularyLanguagePair {
        vocabularyLanguagePairs.first(where: { $0.id == selectedVocabularyLanguagePairID }) ?? vocabularyLanguagePairs[0]
    }

    func vocabularyLanguage(_ id: UUID) -> VocabularyLanguage? { vocabularyLanguages.first(where: { $0.id == id }) }

    @discardableResult
    func addVocabularyLanguage(name: String, code: String) -> UUID? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbreviation = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !title.isEmpty, !abbreviation.isEmpty,
              !vocabularyLanguages.contains(where: { $0.code.caseInsensitiveCompare(abbreviation) == .orderedSame }) else { return nil }
        let item = VocabularyLanguage(name: title, code: abbreviation)
        vocabularyLanguages.append(item)
        return item.id
    }

    @discardableResult
    func addVocabularyLanguagePair(sourceLanguageID: UUID, targetLanguageID: UUID) -> UUID? {
        guard sourceLanguageID != targetLanguageID,
              vocabularyLanguages.contains(where: { $0.id == sourceLanguageID }),
              vocabularyLanguages.contains(where: { $0.id == targetLanguageID }) else { return nil }
        if let existing = vocabularyLanguagePairs.first(where: { $0.sourceLanguageID == sourceLanguageID && $0.targetLanguageID == targetLanguageID }) {
            selectedVocabularyLanguagePairID = existing.id
            return existing.id
        }
        let pair = VocabularyLanguagePair(sourceLanguageID: sourceLanguageID, targetLanguageID: targetLanguageID)
        vocabularyLanguagePairs.insert(pair, at: 0)
        selectedVocabularyLanguagePairID = pair.id
        return pair.id
    }

    /// Ein Unterordner kann nur unter einem Hauptordner desselben Sprachpaars liegen (eine Ebene).
    private func validVocabularyParent(_ parentID: UUID?, pairID: UUID, excluding id: UUID? = nil) -> UUID? {
        guard let parentID, parentID != id,
              let parent = vocabularyDecks.first(where: { $0.id == parentID }),
              parent.languagePairID == pairID, parent.parentID == nil else { return nil }
        // Ein Ordner mit eigenen Unterordnern kann selbst kein Unterordner werden.
        if let id, vocabularyDecks.contains(where: { $0.parentID == id }) { return nil }
        return parentID
    }

    @discardableResult
    func addVocabularyDeck(name: String, emoji: String = "", languagePairID: UUID? = nil, parentID: UUID? = nil) -> UUID? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let pair = languagePairID ?? selectedVocabularyLanguagePairID
        let deck = VocabularyDeck(name: title, emoji: emoji, languagePairID: pair, parentID: validVocabularyParent(parentID, pairID: pair))
        // Unterordner direkt hinter ihren Hauptordner, neue Hauptordner nach vorn.
        if let parent = deck.parentID, let index = vocabularyDecks.lastIndex(where: { $0.id == parent || $0.parentID == parent }) {
            vocabularyDecks.insert(deck, at: index + 1)
        } else {
            vocabularyDecks.insert(deck, at: 0)
        }
        return deck.id
    }

    func updateVocabularyDeck(_ id: UUID, name: String, emoji: String, parentID: UUID?? = nil) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = vocabularyDecks.firstIndex(where: { $0.id == id }) else { return }
        var deck = vocabularyDecks[index]
        deck.name = title
        deck.emoji = emoji
        if let parentID { deck.parentID = validVocabularyParent(parentID, pairID: deck.languagePairID ?? selectedVocabularyLanguagePairID, excluding: id) }
        vocabularyDecks[index] = deck
    }

    /// Unterordner eines Vokabelordners.
    func vocabularySubfolders(of id: UUID) -> [VocabularyDeck] { vocabularyDecks.filter { $0.parentID == id } }

    /// Der Ordner und seine Unterordner: der Umfang, den Lernen, Feed und Tutor bei diesem Ordner nehmen.
    func vocabularyScope(_ id: UUID) -> Set<UUID> { Set([id] + vocabularySubfolders(of: id).map(\.id)) }

    /// Anzeigename mit Hauptordner, z. B. „Englisch › Unit 1“.
    func vocabularyDeckPath(_ deck: VocabularyDeck) -> String {
        guard let parent = deck.parentID.flatMap({ id in vocabularyDecks.first(where: { $0.id == id }) }) else { return deck.name }
        return "\(parent.name) › \(deck.name)"
    }

    /// Löscht einen Ordner. Seine Unterordner werden mitgelöscht oder zu eigenen Hauptordnern.
    func removeVocabularyDeck(_ id: UUID, deleteEntries: Bool = false, deleteSubfolders: Bool = true) {
        let removed: Set<UUID> = deleteSubfolders ? vocabularyScope(id) : [id]
        var updated = vocabulary
        if deleteEntries { updated.removeAll { $0.deckID.map(removed.contains) ?? false } }
        else { for index in updated.indices where updated[index].deckID.map(removed.contains) ?? false { updated[index].deckID = nil } }
        vocabulary = updated
        var folders = vocabularyDecks.filter { !removed.contains($0.id) }
        for index in folders.indices where folders[index].parentID == id { folders[index].parentID = nil }
        vocabularyDecks = folders
    }

    func addVocabulary(term: String, translation: String, example: String, synonyms: [String] = [], difficulty: Int = 1, deckID: UUID? = nil, languagePairID: UUID? = nil, pronunciation: String = "") {
        let word = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !meaning.isEmpty else { return }
        let cleanedSynonyms = synonyms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        vocabulary.insert(VocabularyEntry(term: word, translation: meaning, pronunciation: pronunciation.trimmingCharacters(in: .whitespacesAndNewlines), example: example.trimmingCharacters(in: .whitespacesAndNewlines), synonyms: cleanedSynonyms, difficulty: min(max(difficulty, 1), 3), deckID: deckID, languagePairID: languagePairID ?? selectedVocabularyLanguagePairID), at: 0)
    }

    func updateVocabulary(_ id: UUID, term: String, translation: String, example: String, synonyms: [String], difficulty: Int, deckID: UUID?, pronunciation: String = "") {
        let word = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !meaning.isEmpty, let index = vocabulary.firstIndex(where: { $0.id == id }) else { return }
        vocabulary[index].term = word
        vocabulary[index].translation = meaning
        vocabulary[index].pronunciation = pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
        vocabulary[index].example = example.trimmingCharacters(in: .whitespacesAndNewlines)
        vocabulary[index].synonyms = synonyms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        vocabulary[index].difficulty = min(max(difficulty, 1), 3)
        vocabulary[index].deckID = deckID
    }

    func removeVocabulary(_ id: UUID) { vocabulary.removeAll { $0.id == id } }

    /// Dreht in einem Ordner alle Vokabeln um, deren Begriff und Übersetzung vertauscht aussehen.
    /// Gibt die Anzahl der gedrehten Einträge zurück.
    @discardableResult
    func fixVocabularyDirection(inDeck deckID: UUID) -> Int {
        guard let pairID = vocabularyDecks.first(where: { $0.id == deckID })?.languagePairID,
              let pair = vocabularyLanguagePairs.first(where: { $0.id == pairID }),
              let source = vocabularyLanguage(pair.sourceLanguageID)?.code,
              let target = vocabularyLanguage(pair.targetLanguageID)?.code else { return 0 }
        var updated = vocabulary
        var count = 0
        let scope = vocabularyScope(deckID)
        for index in updated.indices where updated[index].deckID.map(scope.contains) ?? false {
            let entry = updated[index]
            guard VocabularyDirection.looksSwapped(term: entry.term, translation: entry.translation, sourceCode: source, targetCode: target) else { continue }
            updated[index].term = entry.translation
            updated[index].translation = entry.term
            count += 1
        }
        // Eine Zuweisung: Jede Änderung am Array speichert den gesamten Bestand.
        if count > 0 { vocabulary = updated }
        return count
    }

    func toggleVocabularyPin(_ id: UUID) {
        guard let index = vocabulary.firstIndex(where: { $0.id == id }) else { return }
        vocabulary[index].isPinned.toggle()
    }

    // MARK: Begriffe

    @discardableResult
    func addTermSubject(name: String, emoji: String = "") -> UUID? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if let existing = termSubjects.first(where: { $0.name.caseInsensitiveCompare(title) == .orderedSame }) { return existing.id }
        let subject = TermSubject(name: title, emoji: emoji)
        termSubjects.insert(subject, at: 0)
        return subject.id
    }

    func updateTermSubject(_ id: UUID, name: String, emoji: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = termSubjects.firstIndex(where: { $0.id == id }) else { return }
        termSubjects[index].name = title
        termSubjects[index].emoji = emoji
    }

    func removeTermSubject(_ id: UUID, deleteTerms: Bool) {
        if deleteTerms { terms.removeAll { $0.subjectID == id } }
        else {
            var updated = terms
            for index in updated.indices where updated[index].subjectID == id { updated[index].subjectID = nil }
            terms = updated
        }
        termSubjects.removeAll { $0.id == id }
    }

    func termSubject(_ id: UUID?) -> TermSubject? { id.flatMap { id in termSubjects.first(where: { $0.id == id }) } }

    /// Fügt Begriffe hinzu und überspringt solche, die es im Fach schon gibt. Gibt die Anzahl der neuen zurück.
    @discardableResult
    func addTerms(_ drafts: [(term: String, definition: String, example: String)], subjectID: UUID?) -> Int {
        var known = Set(terms.filter { $0.subjectID == subjectID }.map { $0.term.lowercased().trimmingCharacters(in: .whitespaces) })
        var fresh: [TermCard] = []
        for draft in drafts {
            let term = draft.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = draft.definition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !definition.isEmpty, known.insert(term.lowercased()).inserted else { continue }
            fresh.append(TermCard(subjectID: subjectID, term: term, definition: definition, example: draft.example.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if !fresh.isEmpty { terms = fresh + terms }
        return fresh.count
    }

    func updateTerm(_ id: UUID, term: String, definition: String, example: String, subjectID: UUID?) {
        guard let index = terms.firstIndex(where: { $0.id == id }) else { return }
        var card = terms[index]
        card.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        card.definition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        card.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
        card.subjectID = subjectID
        guard !card.term.isEmpty, !card.definition.isEmpty else { return }
        terms[index] = card
    }

    func removeTerm(_ id: UUID) { terms.removeAll { $0.id == id } }

    func toggleTermPin(_ id: UUID) {
        guard let index = terms.firstIndex(where: { $0.id == id }) else { return }
        terms[index].isPinned.toggle()
    }

    func recordTerm(_ id: UUID, correct: Bool, duration: TimeInterval = 0) {
        guard let index = terms.firstIndex(where: { $0.id == id }) else { return }
        let answeredAt = Date()
        var card = terms[index]
        card.timesSeen += 1
        let interval = ReviewSchedule.nextInterval(current: card.intervalDays, rating: correct ? .good : .wrong)
        card.intervalDays = interval
        card.dueToday = interval == 0
        card.nextDue = interval == 0 ? nil : ReviewSchedule.dueDate(afterDays: interval, from: answeredAt)
        if !correct { card.lapses = (card.lapses ?? 0) + 1 }
        terms[index] = card
        recordPractice(duration: duration)
    }

    func recordVocabulary(_ id: UUID, correct: Bool, duration: TimeInterval = 0) {
        guard let index = vocabulary.firstIndex(where: { $0.id == id }) else { return }
        let answeredAt = Date()
        // Eine Zuweisung statt mehrerer: Jede Änderung am Array speichert den gesamten Bestand.
        var entry = vocabulary[index]
        entry.timesSeen += 1
        let interval = ReviewSchedule.nextInterval(current: entry.intervalDays, rating: correct ? .good : .wrong)
        entry.intervalDays = interval
        entry.dueToday = interval == 0
        entry.nextDue = interval == 0 ? nil : ReviewSchedule.dueDate(afterDays: interval, from: answeredAt)
        vocabulary[index] = entry
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: answeredAt) ?? .distantPast
        activities = activities.filter { $0.answeredAt >= cutoff } + [StudyActivity(answeredAt: answeredAt, durationSeconds: max(duration, 0))]
        recordStudyDay(answeredAt)
    }

    func record(_ rating: CardRating, cardID: UUID, deckID: UUID, duration: TimeInterval = 0) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let cardIndex = decks[deckIndex].cards.firstIndex(where: { $0.id == cardID }) else { return }
        let answeredAt = Date()
        // Eine Zuweisung statt mehrerer: Jede Änderung am Array speichert alle Decks.
        var card = decks[deckIndex].cards[cardIndex]
        card.timesSeen += 1
        let interval = ReviewSchedule.nextInterval(current: card.intervalDays, rating: rating)
        if rating != .hard { card.intervalDays = interval }  // „Mühsam“ bleibt fällig, behält aber den Abstand.
        card.lastRating = rating
        if rating == .wrong { card.lapses = (card.lapses ?? 0) + 1 }
        if rating == .hard { card.hardCount = (card.hardCount ?? 0) + 1 }
        card.dueToday = interval == 0
        card.nextDue = interval == 0 ? nil : ReviewSchedule.dueDate(afterDays: interval, from: answeredAt)
        decks[deckIndex].cards[cardIndex] = card
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: answeredAt) ?? .distantPast
        activities = activities.filter { $0.answeredAt >= cutoff } + [StudyActivity(answeredAt: answeredAt, durationSeconds: max(duration, 0))]
        recordStudyDay(answeredAt)
    }

    /// Lernzeit für Übungen, die keine eigenen Karten bewerten (z. B. vom Tutor erstellte Tests).
    func recordPractice(duration: TimeInterval) {
        let answeredAt = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: answeredAt) ?? .distantPast
        activities = activities.filter { $0.answeredAt >= cutoff } + [StudyActivity(answeredAt: answeredAt, durationSeconds: max(duration, 0))]
        recordStudyDay(answeredAt)
    }

    // MARK: Tests

    /// Karten eines Decks einschließlich seiner direkten Unterdecks.
    func cardsIncludingSubdecks(of deckID: UUID) -> [Flashcard] {
        (decks.first(where: { $0.id == deckID })?.cards ?? []) + children(of: deckID).flatMap(\.cards)
    }

    /// Tests, die heute angeboten werden. Dieselben Regeln prüft das Backend noch einmal, bevor der Tutor schreibt.
    func testOffers(now: Date = Date()) -> [DailyTestOffer] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var offers: [DailyTestOffer] = []
        var seen = Set<String>()
        for entry in allCalendarEntries {
            guard let deckID = entry.deckID, decks.contains(where: { $0.id == deckID }) else { continue }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: entry.date)).day ?? -1
            guard (0...DailyTestOffer.examWindowDays).contains(days) else { continue }
            let cards = cardsIncludingSubdecks(of: deckID)
            // Ein Deck mit mehreren Einträgen am selben Tag bekommt nur einen Test.
            guard cards.count >= DailyTestOffer.minExamCards, seen.insert("\(deckID)-\(days)").inserted else { continue }
            offers.append(DailyTestOffer(kind: .exam, reference: entry.id.uuidString, title: entry.title, examDate: entry.date, cards: cards))
        }
        let hard = decks.flatMap(\.cards).filter(\.isHard)
        if hard.count >= DailyTestOffer.minWeakCards {
            offers.append(DailyTestOffer(kind: .weak, reference: "", title: t("Schwere Karten"), examDate: nil, cards: hard))
        }
        return offers.filter { !completedTestKeys.contains(Self.testKey($0, day: today)) }
    }

    private static func testKey(_ offer: DailyTestOffer, day: Date) -> String { "\(offer.id)@\(Int(day.timeIntervalSinceReferenceDate))" }

    func markTestCompleted(_ offer: DailyTestOffer) {
        let today = Calendar.current.startOfDay(for: Date())
        // Nur die Einträge von heute behalten; ältere werden nie wieder gebraucht.
        let suffix = "@\(Int(today.timeIntervalSinceReferenceDate))"
        completedTestKeys = completedTestKeys.filter { $0.hasSuffix(suffix) }.union([Self.testKey(offer, day: today)])
    }

    private func recordStudyDay(_ date: Date) {
        let calendar = Calendar.current
        guard !studyDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) else { return }
        studyDays.append(calendar.startOfDay(for: date))
    }

    func removeDeck(_ deckID: UUID) {
        var ids: Set<UUID> = [deckID]
        var changed = true
        while changed {
            let children = decks.filter { $0.parentID.map(ids.contains) ?? false }.map(\.id)
            let oldCount = ids.count
            ids.formUnion(children)
            changed = ids.count != oldCount
        }
        decks.removeAll { ids.contains($0.id) }
        for index in calendarEntries.indices where calendarEntries[index].deckID.map(ids.contains) ?? false {
            calendarEntries[index].deckID = nil
        }
    }

    func clearAllData() {
        decks = []
        vocabulary = []
        vocabularyDecks = []
        vocabularyLanguages = [
            VocabularyLanguage(id: Self.defaultGermanLanguageID, name: "Deutsch", code: "DE"),
            VocabularyLanguage(id: Self.defaultEnglishLanguageID, name: "Englisch", code: "EN")
        ]
        vocabularyLanguagePairs = [VocabularyLanguagePair(id: Self.defaultVocabularyLanguagePairID, sourceLanguageID: Self.defaultGermanLanguageID, targetLanguageID: Self.defaultEnglishLanguageID)]
        selectedVocabularyLanguagePairID = Self.defaultVocabularyLanguagePairID
        activities = []
        studyDays = []
        calendarEntries = []
        termSubjects = []
        terms = []
    }

    func children(of deckID: UUID) -> [Deck] { decks.filter { $0.parentID == deckID } }

    var currentStreak: Int {
        let calendar = Calendar.current
        let studiedDays = Set(studyDays.map { calendar.startOfDay(for: $0) } + activities.map { calendar.startOfDay(for: $0.answeredAt) })
        let today = calendar.startOfDay(for: Date())
        var day = studiedDays.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        guard studiedDays.contains(day) else { return 0 }
        var streak = 0
        while studiedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    var studySecondsThisWeek: TimeInterval {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return activities.filter { week.contains($0.answeredAt) }.reduce(0) { $0 + $1.durationSeconds }
    }

    var studyTimeThisWeekLabel: String {
        let minutes = Int(studySecondsThisWeek / 60)
        if minutes == 0 { return studySecondsThisWeek > 0 ? (language == "Englisch" ? "< 1 min" : "< 1 Min.") : (language == "Englisch" ? "0 min" : "0 Min.") }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return language == "Englisch" ? "\(minutes) min" : "\(minutes) Min." }
        return language == "Englisch" ? "\(hours) h \(rest) min" : "\(hours) Std. \(rest) Min."
    }

    var studyDatesThisWeek: [Date] {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    var studySecondsByDayThisWeek: [TimeInterval] {
        let calendar = Calendar.current
        return studyDatesThisWeek.compactMap { day in
            guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
            return activities.filter { interval.contains($0.answeredAt) }.reduce(0) { $0 + $1.durationSeconds }
        }
    }

    func t(_ german: String) -> String { language == "Englisch" ? (Self.englishText[german] ?? german) : german }
    func tf(_ german: String, _ values: CVarArg...) -> String { String(format: t(german), locale: Locale(identifier: language == "Englisch" ? "en_US" : "de_DE"), arguments: values) }

    private static let englishText: [String: String] = [
        "Mittelstufe": "Lower secondary",
        "Oberstufe": "Upper secondary",
        "Uni": "University",
        "Stufe": "Level",
        "Stärken": "Strengths",
        "Üben lohnt sich": "Worth practising",
        "%d Formeln": "%d formulas",
        "Stärke": "Strength",
        "Schwäche": "Weakness",
        "Im Training": "Practising",
        "%d Aufgaben gelöst · nächste Stufe %d von 5": "%d exercises solved · next level %d of 5",
        "Stufe %d": "Level %d",
        "Aufgabe erstellen": "Create exercise",
        "Formeln": "Formulas",
        "Die KI erstellt deine Aufgabe …": "The AI is writing your exercise …",
        "AUFGABE": "EXERCISE",
        "Tipp anzeigen": "Show hint",
        "Rechenweg": "Working",
        "Schritt hinzufügen": "Add step",
        "Ergebnis": "Result",
        "z. B. x = 2": "e.g. x = 2",
        "Schritt": "Step",
        "Schritt löschen": "Delete step",
        "Richtig gelöst": "Solved correctly",
        "Teilweise richtig": "Partly correct",
        "Noch nicht richtig": "Not right yet",
        "Der erste Fehler steckt in Schritt %d.": "The first mistake is in step %d.",
        "Lösung zeigen": "Show solution",
        "Nächste Aufgabe": "Next exercise",
        "Aktiviere die KI-Funktionen in den Einstellungen, um Aufgaben zu erhalten. Die Formeln stehen dir auch so zur Verfügung.": "Turn on the AI features in Settings to get exercises. The formulas are available either way.",
        "Melde dich in den Einstellungen an, um Aufgaben zu erhalten. Die Formeln stehen dir auch so zur Verfügung.": "Sign in under Settings to get exercises. The formulas are available either way.",
        "Begriffe": "Terms",
        "Begriffe suchen": "Search terms",
        "Fach erstellen": "Create subject",
        "Fach bearbeiten": "Edit subject",
        "Fach löschen": "Delete subject",
        "Fach löschen?": "Delete subject?",
        "Fach und Begriffe löschen": "Delete subject and terms",
        "Nur Fach löschen": "Delete subject only",
        "Möchtest du die Begriffe in diesem Fach ebenfalls löschen?": "Do you also want to delete the terms in this subject?",
        "Begriff hinzufügen": "Add term",
        "Begriff bearbeiten": "Edit term",
        "Begriff": "Term",
        "Erklärung": "Explanation",
        "Beispiel oder Merksatz": "Example or mnemonic",
        "Fach": "Subject",
        "Kein Fach": "No subject",
        "z. B. Biologie": "e.g. Biology",
        "%d Begriffe": "%d terms",
        "Begriffe lernen": "Study terms",
        "Noch keine Fächer": "No subjects yet",
        "Noch keine Begriffe": "No terms yet",
        "Erklärung zeigen": "Show explanation",
        "Erklärung verbergen": "Hide explanation",
        "ERKLÄRUNG": "EXPLANATION",
        "BEGRIFF": "TERM",
        "Geschafft! 🎉": "Done! 🎉",
        "%d von %d Begriffen gewusst": "Knew %d of %d terms",
        "Bereich": "Area",
        "Mathe": "Maths",
        "Üben mit": "Practise with",
        "Begriffe üben": "Practise terms",
        "Erklären": "Explain",
        "allen Fächern": "all subjects",
        "Neues Fach": "New subject",
        "Begriffe ergänzen": "Add terms",
        "%d Begriffe hinzugefügt": "%d terms added",
        "Anheften": "Pin",
        "Optionen": "Options",
        "Bearbeiten": "Edit",
        "Ordner löschen": "Delete folder",
        "Ordner erstellen": "Create folder",
        "Neuer Ordner": "New folder",
        "Ordnername": "Folder name",
        "Ordner bearbeiten": "Edit folder",
        "Unterordner erstellen": "Create subfolder",
        "Ordner, Unterordner und Vokabeln löschen": "Delete folder, subfolders and vocabulary",
        "Nur Ordner löschen, Unterordner behalten": "Delete folder only, keep subfolders",
        "Behältst du die Unterordner, werden sie zu eigenen Ordnern. Ihre Vokabeln bleiben darin.": "If you keep the subfolders, they become folders of their own. Their vocabulary stays in them.",
        "Kein übergeordneter Ordner": "No parent folder",
        "Unterordner erscheinen unter ihrem Ordner. Wählst du den Ordner aus, gehören ihre Vokabeln dazu.": "Subfolders appear below their folder. Selecting the folder includes their vocabulary.",
        "Sprachrichtung prüfen": "Check language direction",
        "Sprachrichtung geprüft": "Language direction checked",
        "%d Vokabeln wurden umgedreht.": "%d entries were flipped.",
        "Alle Vokabeln stehen in der richtigen Richtung.": "All entries are in the right direction.",
        "Teil %d von %d · %d Vokabeln": "Part %d of %d · %d entries",
        "%d Vokabeln gelesen, weitere folgen …": "%d vocabulary entries read, more to come …",
        "Nicht alle Vokabeln konnten gelesen werden. Du kannst den Rest mit einem weiteren Auftrag ergänzen.": "Not all vocabulary could be read. You can add the rest with another request.",
        "KI-Funktionen aktivieren?": "Turn on AI features?",
        "Zustimmen und aktivieren": "Agree and turn on",
        "Nicht jetzt": "Not now",
        "Aktiviere die KI-Funktionen in den Einstellungen, um sie zu nutzen.": "Turn on the AI features under Settings to use them.",
        "Für KI-Funktionen werden die von dir gewählten Inhalte (Texte, Karten, Fotos, Gesprächsverlauf) über unseren Server an Google Gemini übertragen. Abgleich und Lernen funktionieren auch ohne.": "For AI features, the content you choose (texts, cards, photos, conversation) is sent via our server to Google Gemini. Sync and studying work without them.",
        "Wenn du KI-Funktionen nutzt, werden die dafür gewählten Inhalte – Texte, Karten, Fotos, PDFs und der Gesprächsverlauf – über unseren Server an Google (Gemini) übertragen und dort verarbeitet. Sende keine vertraulichen oder fremden personenbezogenen Daten. Du kannst die Zustimmung jederzeit hier widerrufen.": "When you use AI features, the content you choose – texts, cards, photos, PDFs and the conversation – is sent via our server to Google (Gemini) and processed there. Do not send confidential information or other people's personal data. You can withdraw your consent here at any time.",
        "Termin heute": "Date is today",
        "Termin morgen": "Date is tomorrow",
        "Termin in %d Tagen": "Date in %d days",
        "Kalendereintrag geändert": "Calendar entry changed",
        "Kalendereintrag gelöscht": "Calendar entry deleted",
        "Deck umbenannt": "Deck renamed",
        "Test gestartet": "Test started",
        "Termin ändern": "Change date",
        "Termin löschen": "Delete date",
        "Deck umbenennen": "Rename deck",
        "Test starten": "Start test",
        "Neuer Titel": "New title",
        "Neues Datum": "New date",
        "Neuer Name": "New name",
        "Der Eintrag wird aus dem Kalender entfernt.": "The entry will be removed from the calendar.",
        "Alle Karten des Decks als Probeprüfung, ohne KI-Bewertung.": "All cards of the deck as a mock exam, without AI grading.",
        "Test-Erinnerungen": "Test reminders",
        "Mitteilungen sind für diese App ausgeschaltet. Erlaube sie in den iOS-Einstellungen unter „Lernkarten“.": "Notifications are turned off for this app. Allow them in iOS Settings under “Lernkarten”.",
        "Du bekommst eine Mitteilung, wenn ein Test zu einem Termin mit Deck bereitsteht oder genug schwere Karten für einen Tagestest da sind.": "You get a notification when a test for a date with a linked deck is ready or when there are enough difficult cards for a daily test.",
        "Schwere Karten": "Difficult cards",
        "Tests für dich": "Tests for you",
        "Karten, die dir schwergefallen sind": "Cards you found difficult",
        "Du übst mit deinen vorhandenen Karten.": "You are practising with your existing cards.",
        "Unterschiedliche Stände": "Different versions",
        "Cloud-Stand übernehmen": "Use cloud version",
        "Stand dieses Geräts hochladen": "Upload this device's version",
        "Später entscheiden": "Decide later",
        "In der Cloud liegen %d Decks und %d Vokabeln, auf diesem Gerät %d Decks und %d Vokabeln. Beide Stände wurden unabhängig voneinander geändert. Der nicht gewählte Stand wird überschrieben.": "The cloud holds %d decks and %d vocabulary entries, this device %d decks and %d vocabulary entries. Both were changed independently. The version you don't choose will be overwritten.",
        "Rechtliches": "Legal",
        "Datenschutzerklärung": "Privacy policy",
        "Nutzungsbedingungen": "Terms of use",
        "Impressum": "Legal notice",
        "Deine Lerndaten liegen auf diesem Gerät und in deinem Konto. Löschen entfernt sie an beiden Orten.": "Your learning data is stored on this device and in your account. Deleting removes it from both.",
        "Ohne Anmeldung bleiben Decks, Vokabeln und Termine nur auf diesem Gerät.": "Without an account, decks, vocabulary and dates stay on this device only.",
        "Alle Decks, Karten, Vokabeln, Termine und dein Lernfortschritt werden von diesem Gerät und aus deinem Konto entfernt. Das lässt sich nicht rückgängig machen.": "All decks, cards, vocabulary, dates and your progress will be removed from this device and from your account. This cannot be undone.",
        "Konto löschen?": "Delete account?",
        "Konto unwiderruflich löschen": "Delete account permanently",
        "Konto löschen": "Delete account",
        "Dein Konto, die in der Cloud gespeicherten Lerndaten und die Nutzungszähler werden vom Server gelöscht. Die Daten auf diesem Gerät bleiben erhalten.": "Your account, the learning data stored in the cloud and the usage counters will be deleted from the server. The data on this device is kept.",
        "Entwickler-Anmeldung (E-Mail)": "Developer sign-in (email)",
        "Mit einem Konto werden deine Lerndaten gesichert und zwischen deinen Geräten abgeglichen. Die KI-Funktionen aktivierst du danach gesondert. Mit der Anmeldung akzeptierst du die Nutzungsbedingungen und die Datenschutzerklärung.": "With an account your learning data is backed up and synced between your devices. You turn on the AI features separately afterwards. By signing in you accept the terms of use and the privacy policy.",
        "Angemeldet als": "Signed in as",
        "KI-Anfragen (24 Stunden)": "AI requests (24 hours)",
        "Unbegrenzt": "Unlimited",
        "Synchronisierung": "Sync",
        "Jetzt abgleichen": "Sync now",
        "Wird abgeglichen …": "Syncing …",
        "Noch nicht abgeglichen": "Not synced yet",
        "Zuletzt abgeglichen:": "Last synced:",
        "Die Anmeldung mit Apple hat nicht geklappt. Bitte versuche es erneut.": "Signing in with Apple didn't work. Please try again.",
        "Foto aufnehmen": "Take photo",
        "Mit der Kamera": "With the camera",
        "Aus der Mediathek": "From your library",
        "Auf diesem Gerät ist keine Kamera verfügbar.": "No camera is available on this device.",
        "Die App darf nicht auf die Kamera zugreifen. Erlaube den Zugriff in den iOS-Einstellungen unter „Lernkarten“.": "The app isn't allowed to use the camera. Allow access in iOS Settings under “Lernkarten”.",
        "Anhang wird vorbereitet …": "Preparing attachment …",
        "Anhang entfernen": "Remove attachment",
        "Foto auswählen": "Choose photo",
        "PDF auswählen": "Choose PDF",
        "Datei anhängen": "Attach file",
        "%d Seiten": "%d pages",
        "Gespeicherte Daten nicht lesbar": "Saved data unreadable",
        "Ein Teil deiner gespeicherten Daten konnte nicht geladen werden. Eine Sicherung der Rohdaten bleibt auf diesem Gerät erhalten.": "Some of your saved data could not be loaded. A backup of the raw data is kept on this device.",
        "Termine": "Dates",
        "Morgen": "Tomorrow",
        "in %d Tagen": "in %d days",
        "Wieder fällig am": "Due again on",
        "Alle Daten löschen?": "Delete all data?",
        "Alles unwiderruflich löschen": "Delete everything permanently",
        "Alle Decks, Karten, Vokabeln, Termine und dein Lernfortschritt werden von diesem Gerät entfernt. Das lässt sich nicht rückgängig machen.": "All decks, cards, vocabulary, dates and your progress will be removed from this device. This cannot be undone.",
        "ANTWORT": "ANSWER",
        "FRAGE": "QUESTION",
        "Melde dich in den Einstellungen an, um die KI-Funktionen zu nutzen.": "Sign in under Settings to use the AI features.",
        "Privatpilot-Backend": "Private pilot backend",
        "Status": "Status",
        "Angemeldet": "Signed in",
        "Nicht angemeldet": "Not signed in",
        "Anmelden": "Sign in",
        "Abmelden": "Sign out",
        "Privatpilot-Konto": "Private pilot account",
        "Einladungscode": "Invitation code",
        "Das Passwort muss mindestens 12 Zeichen lang sein. Der Einladungscode ist in Railway gesetzt.": "Password must be at least 12 characters. The invitation code is configured in Railway.",
        "Konto erstellen": "Create account",
        "Ich habe schon ein Konto": "I already have an account",
        "Konto mit Einladungscode erstellen": "Create account with invitation code",
        "E-Mail": "Email",
        "Passwort": "Password",
        "Privatpilot-Anmeldung": "Private pilot sign-in",
        "KI-Anfragen werden mit einer Anmeldung an das private Railway-Backend gesendet. Das Sitzungstoken wird geschützt im iOS-Schlüsselbund gespeichert; dein Passwort wird nicht gespeichert.": "AI requests are sent to the private Railway backend after sign-in. The session token is stored securely in the iOS Keychain; your password is not stored.",
        "Backend": "Backend",
        "KI-Anfragen laufen über das private Railway-Backend. Der Server speichert Nutzungszähler sowie geschätzte Tokenkosten. Anwendungsinhalte und Passwörter werden nicht in Serverprotokolle geschrieben. Wenn du KI-Funktionen nutzt, werden die ausgewählten Inhalte an Gemini übertragen.": "AI requests go through the private Railway backend. The server stores usage counters and estimated token costs. App content and passwords are not written to server logs. When you use AI features, selected content is sent to Gemini.",
        "Lokal auf deinem Gerät": "Stored on your device",
        "Decks, Karten, Vokabeln und Lernfortschritt bleiben in dieser Pilotversion lokal in der App gespeichert. Es gibt keine Cloud-Synchronisierung.": "Decks, flashcards, vocabulary and study progress stay in the app on this device during the pilot. There is no cloud sync.",
        "KI-Funktionen": "AI features",
        "Wenn du eine KI-Funktion verwendest, werden die dafür ausgewählten Texte, Fragen, Antworten, der Chatverlauf oder ein Bild über das Backend an Google Gemini übertragen. Sende keine vertraulichen oder personenbezogenen Inhalte. Je nach Gemini-Tarif kann Google API-Inhalte zur Produktverbesserung verwenden. Prüfe vor dem Pilotstart die Bedingungen deines Google API-Tarifs.": "When you use an AI feature, the selected text, questions, answers, chat history or image is sent through the backend to Google Gemini. Do not submit confidential or personal information. Depending on your Gemini plan, Google may use API content to improve its products. Check the terms of your Google API plan before the pilot.",
        "Sicherheit und Betriebsdaten": "Security and operational data",
        "Das Backend verarbeitet vorübergehend deine IP-Adresse für die Begrenzung von Anmeldeversuchen. Es speichert Nutzungszähler und ungefähre Tokenkosten für Pilotlimits. Anwendungsinhalte und Passwörter werden nicht in Serverprotokolle geschrieben. HTTPS ist für den Fernzugriff erforderlich.": "The backend temporarily processes your IP address to limit sign-in attempts. It stores usage counters and estimated token costs for pilot limits. App content and passwords are not written to server logs. HTTPS is required for remote access.",
        "Heute": "Today",
        "Mehr": "More",
        "Planung": "Planning",
        "Kalender": "Calendar",
        "Datenschutz": "Privacy",
        "Datenschutzhinweise": "Privacy notice",
        "Lokaler Modus": "Local mode",
        "KI-Backend": "AI backend",
        "Lokaler Server": "Local server",
        "Lokale Daten": "Local data",
        "Decks, Vokabeln und Termine bleiben auf diesem Gerät.": "Decks, vocabulary, and events stay on this device.",
        "Datenschutzhinweise · lokaler Test": "Privacy notice · local test",
        "Profil und Anmeldung": "Profile and sign-in",
        "Das Profil- und Anmeldesystem ist für den lokalen Test ausgeschaltet. Es wird kein Konto angelegt und kein Sitzungstoken gespeichert.": "Profiles and sign-in are disabled for local testing. No account or session token is created.",
        "Backend im lokalen Test": "Backend during local testing",
        "Der lokale Server akzeptiert nur Verbindungen vom Mac und speichert Nutzungszähler sowie geschätzte Tokenkosten. Anwendungsinhalte und Passwörter werden nicht in Serverprotokolle geschrieben. Wenn du KI-Funktionen nutzt, werden die ausgewählten Inhalte an Gemini übertragen.": "The local server accepts connections only from the Mac and stores usage counters and estimated token costs. App content and passwords are not written to server logs. When you use AI features, selected content is sent to Gemini.",
        "Du kannst alle lokal gespeicherten App-Daten in den Einstellungen löschen. Der Server speichert keine Decks oder Vokabeln.": "You can delete all locally stored app data in Settings. The server does not store decks or vocabulary.",
        "Lernwerkzeuge": "Study tools",
        "App": "App",
        "Erfolgreich gespeichert": "Saved successfully",
        "Deck bereit": "Deck ready",
        "%d Karten hinzugefügt": "%d cards added",
        "%d Vokabeln hinzugefügt": "%d vocabulary items added",
        "Kalendereintrag erstellt": "Calendar event created",
        "Einige Vorschläge konnten nicht übernommen werden.": "Some proposals could not be applied.",
        "Es konnte nichts übernommen werden.": "Nothing could be applied.",
        "Öffnen": "Open",
        "Eintrag": "Event",
        "Termin": "Event details",
        "Titel": "Title",
        "Art": "Type",
        "Prüfung": "Exam",
        "Test": "Test",
        "Abgabe": "Assignment",
        "Sonstiges": "Other",
        "Deck (optional)": "Deck (optional)",
        "Deck zuordnen": "Link a deck",
        "Kein Deck": "No deck",
        "Notiz (optional)": "Note (optional)",
        "Zusätzliche Informationen": "Additional information",
        "Neuer Eintrag": "New event",
        "Eintrag bearbeiten": "Edit event",
        "Keine Einträge": "No events",
        "Für diesen Tag sind keine Tests oder Prüfungen eingetragen.": "No tests or exams are planned for this day.",
        "Keine anstehenden Termine. Füge einen Test oder eine Prüfung hinzu.": "No upcoming events. Add a test or exam.",
        "%d Termine": "%d events",
        "Tutor": "Tutor",
        "Guten Tag 👋": "Hello 👋",
        "Dein Lernmoment wartet.": "Your next study session is waiting.",
        "Neues Deck": "New deck",
        "Karte suchen": "Search cards",
        "KI-Karteikarten": "AI flashcards",
        "KI-Karteikarten erstellen": "Create AI flashcards",
        "Einstellungen": "Settings",
        "Support": "Support",
        "OK": "OK",
        "Deine Streak": "Your streak",
        "Lerne heute weiter, um dranzubleiben.": "Study today to keep it going.",
        "Heute lernen": "Study today",
        "Dein Lernmaterial": "Your study material",
        "Tag": "day",
        "Tage": "days",
        "Heutige Aufgaben": "Today's tasks",
        "Erledige deine Lernaufgaben für heute": "Complete today's study tasks",
        "Alle Decks lernen  ·  %d Karten": "Study all decks · %d cards",
        "Anstehende Prüfungen": "Upcoming exams",
        "Verwalten": "Manage",
        "Lege in den Deck-Einstellungen einen Prüfungstermin fest.": "Set an exam date in a deck's settings.",
        "Lernzeit diese Woche": "Study time this week",
        "Geschätzte Lernzeit diese Woche": "Estimated study time this week",
        "Sekunden": "seconds",
        "Foto-Größenlimit: 6 MB. PDF-Größenlimit: 20 MB und maximal 250 Seiten.": "Photo limit: 6 MB. PDF limit: 20 MB and 250 pages.",
        "Das Foto konnte nicht geladen werden. Bitte versuche ein anderes Bild.": "The photo could not be loaded. Please try another image.",
        "Das Foto ist größer als 6 MB. Bitte wähle ein kleineres Bild.": "The photo is larger than 6 MB. Please choose a smaller image.",
        "Lokal eingeschätzt": "Estimated locally",
        "Die KI-Bewertung ist nicht verfügbar. Bewerte deine Antwort selbst.": "AI evaluation is unavailable. Rate your answer yourself.",
        "Hier ist stattdessen eine lokale Übersicht der Karten.": "Here is a local summary of the cards instead.",
        "Quiz: Auswahlfrage mit Antwortoptionen und Lösung.": "Quiz: multiple-choice question with options and the correct answer.",
        "Frage & Antwort: offene Frage auf der Vorderseite, Musterantwort auf der Rückseite.": "Question & answer: open question on the front, sample answer on the back.",
        "Deckfarbe": "Deck color",
        "Streak-Regel": "Streak rules",
        "Lernzeit-Regel": "Study time rules",
        "Deine Decks": "Your decks",
        "Deck suchen": "Search decks",
        "Noch keine Decks": "No decks yet",
        "Erstelle ein Deck oder generiere Karten aus deinem Lernmaterial.": "Create a deck or generate cards from your study material.",
        "Emoji": "Emoji",
        "Unterdeck": "Subdeck",
        "Gehört zu": "Belongs to",
        "Kein übergeordnetes Deck": "No parent deck",
        "Deckname": "Deck name",
        "Abbrechen": "Cancel",
        "Erstellen": "Create",
        "Karten": "cards",
        "heute": "today",
        "Prüfungsziel": "Exam goal",
        "Prüfung festlegen": "Set an exam date",
        "Prüfung am": "Exam date",
        "Letzte neue Karte: %d Tage vorher": "Last new card %d days before",
        "Wunschnote festlegen": "Set a target grade",
        "Gewünschte Note": "Target grade",
        "Vorschau Lernplan": "Study plan preview",
        "Tage bis zur Prüfung": "Days until exam",
        "Neue Karten insgesamt": "New cards total",
        "Richtwert pro Lerntag": "Target per study day",
        "Deck und Lernziel löschen": "Delete deck and goal",
        "Deck löschen?": "Delete deck?",
        "Deck und Unterdecks löschen": "Delete deck and subdecks",
        "Alle Karten und Unterdecks dieses Decks werden entfernt.": "All cards and subdecks in this deck will be removed.",
        "Passe dein Ziel an": "Adjust your goal",
        "Sichern": "Save",
        "Deck": "Deck",
        "Dein Lernplan": "Your study plan",
        "Ziel: Note %0.1f": "Target grade: %0.1f",
        "Wissen": "Mastery",
        "heute fällig": "due today",
        "Prüfung in %d Tagen": "Exam in %d days",
        "Karten heute zu wiederholen": "cards to review today",
        "Zusammenfassung": "Summary",
        "Probeprüfung": "Practice exam",
        "Unterdecks": "Subdecks",
        "Erstelle Unterdecks, um Lerninhalte zu ordnen.": "Create subdecks to organize your study material.",
        "Karte": "Card",
        "Fällig": "Due",
        "Deck und Lernziel bearbeiten": "Edit deck and goal",
        "Unterdeck erstellen": "Create subdeck",
        "KI-Zusammenfassung erstellen": "Create AI summary",
        "Erstelle aus den Karten in diesem Deck eine kompakte Übersicht.": "Create a concise overview from the cards in this deck.",
        "Noch keine Zusammenfassung": "No summary yet",
        "Zusammenfassung wird erstellt …": "Creating summary …",
        "Mit KI zusammenfassen": "Summarize with AI",
        "Schließen": "Close",
        "Frage": "Question",
        "Antwort": "Answer",
        "Neue Karte": "New card",
        "Karte bearbeiten": "Edit card",
        "Speichern": "Save",
        "Mach Lernstoff zu Karten": "Turn study material into cards",
        "Lade ein Foto oder PDF hoch. Die KI erstellt daraus einen Kartensatz.": "Upload a photo or PDF. AI will turn it into flashcards.",
        "Material hinzufügen": "Add material",
        "Foto": "Photo",
        "Anpassen": "Customize",
        "Kartentyp": "Card type",
        "Frage & Antwort": "Question & answer",
        "Quiz": "Quiz",
        "Zieldeck": "Target deck",
        "Erstelle zuerst ein Deck.": "Create a deck first.",
        "Karteikarten erstellen": "Create flashcards",
        "Wähle die Karten aus, die du übernehmen möchtest. Tippe auf den Text, um eine Karte zu bearbeiten.": "Select the cards you want to add. Tap the text to edit a card.",
        "Alle auswählen": "Select all",
        "Alle abwählen": "Deselect all",
        "Karte auswählen": "Select card",
        "Karte abwählen": "Deselect card",
        "Übernehmen · %d": "Add · %d",
        "Bild entfernen": "Remove image",
        "Vorschau": "Preview",
        "Verwerfen": "Discard",
        "Bestätigen": "Confirm",
        "Frag mich alles": "Ask me anything",
        "Auch zu deinen PDFs und Lernkarten.": "About your PDFs and flashcards, too.",
        "Stelle eine Frage …": "Ask a question …",
        "KI-Tutor": "AI tutor",
        "Der Tutor nutzt deine Lernkarten als Kontext, wenn welche vorhanden sind.": "The tutor uses your flashcards as context when available.",
        "Allgemeiner Lerncoach": "General study tutor",
        "Keine gespeicherten Lernkarten.": "No saved flashcards.",
        "Tutor-Anfrage fehlgeschlagen: %@": "Tutor request failed: %@",
        "Frage: %s": "Question: %s",
        "Antwort: %s": "Answer: %s",
        "Frag mich, warum die Antwort so lautet oder lass dir das Thema erklären.": "Ask why this is the answer or have me explain the topic.",
        "Stelle eine Frage zu dieser Karte": "Ask a question about this card",
        "KI-Lerncoach": "AI study coach",
        "Plan": "Plan",
        "Kostenlos": "Free",
        "KI-Credits": "AI credits",
        "Nach API-Nutzung": "Based on API usage",
        "Sprache": "Language",
        "Erscheinungsbild": "Appearance",
        "Hell": "Light",
        "Dunkel": "Dark",
        "System": "System",
        "Karten pro Sitzung: %d": "Cards per session: %d",
        "Zufällige Lernreihenfolge": "Random study order",
        "KI-Evaluierung": "AI evaluation",
        "KI-Evaluierung vorauswählen": "Preselect AI evaluation",
        "Wie möchtest du lernen?": "How would you like to study?",
        "Bewertungsmethode": "Answer feedback",
        "Mit KI": "With AI",
        "Ohne KI": "Without AI",
        "Tippe deine Antwort ein. Die KI bewertet sie und gibt Feedback.": "Type your answer. AI will evaluate it and give feedback.",
        "Tippe die Karte an, decke die Antwort auf und bewerte dich selbst.": "Tap the card to reveal the answer, then rate yourself.",
        "Probeprüfung starten": "Start practice exam",
        "Lernen starten": "Start studying",
        "Tippe auf die Karte, um die Antwort zu sehen.": "Tap the card to reveal the answer.",
        "Konto": "Account",
        "Demo-Modus · lokal gespeichert": "Demo mode · stored locally",
        "Daten auf diesem Gerät löschen": "Delete data on this device",
        "PROBEPRÜFUNG": "PRACTICE EXAM",
        "WIEDERHOLUNG": "REVIEW",
        "Gib deine Antwort ein …": "Type your answer …",
        "Deine Antwort": "Your answer",
        "Musterlösung": "Reference answer",
        "Lösung": "Solution",
        "Informationen zu Eulio": "About Eulio",
        "Eulio denkt nach …": "Eulio is thinking …",
        "Eulio schreibt deinen Test …": "Eulio is writing your test …",
        "Eulio hat noch nichts gespeichert. Wähle aus, welche Vorschläge übernommen werden sollen.": "Eulio has not saved anything yet. Choose which proposals to apply.",
        "Eulio ist dein KI-Tutor. Er erklärt dir Themen, übt Vokabeln und Begriffe mit dir und legt auf Wunsch Karten, Vokabeln und Termine an – erst nach deiner Bestätigung. Über die Büroklammer kannst du ein Foto oder PDF anhängen.": "Eulio is your AI tutor. It explains topics, practises vocabulary and terms with you and, on request, creates cards, vocabulary and dates – only after you confirm. Use the paper clip to attach a photo or PDF.",
        "Lege ein Fach an, zum Beispiel Biologie oder Jura, und sammle dort deine Fachbegriffe. Eulio, dein KI-Tutor, kann sie auch für dich erstellen.": "Create a subject such as Biology or Law and collect your technical terms there. Eulio, your AI tutor, can also create them for you.",
        "Eulio ist momentan nicht erreichbar. Prüfe die Backend-Verbindung.": "Eulio is unavailable right now. Check the backend connection.",
        "Eulio": "Eulio",
        "Dein KI-Tutor": "Your AI tutor",
        "Hallo, ich bin Eulio": "Hi, I'm Eulio",
        "Ablehnen": "Decline",
        "Übernehmen": "Apply",
        "Karten ergänzen": "Add cards",
        "Neuer Termin": "New date",
        "Begriffe-Tutor": "Glossary tutor",
        "Lern-Tutor für Schule und Uni": "Study tutor for school and university",
        "Tastatur schließen": "Hide keyboard",
        "Erstelle 10 Begriffe zum Thema Zellbiologie.": "Create 10 terms about cell biology.",
        "Erkläre mir einfach den Begriff ": "Explain this term simply: ",
        "Lege das Fach Geschichte an.": "Create the subject History.",
        "Lass dir Begriffe einfach erklären oder frag sie ab.": "Get terms explained simply or quiz yourself.",
        "Keine Antwort eingegeben.": "No answer entered.",
        "Begründung": "Explanation",
        "Nächste Frage": "Next question",
        "Ich weiß die Antwort nicht": "I don't know the answer",
        "Wie leicht fiel dir die Antwort?": "How easy was that?",
        "Falsch": "Wrong",
        "Mühsam": "Hard",
        "Gut": "Good",
        "Einfach": "Easy",
        "Selbst bewertet.": "Self-rated.",
        "Du wusstest die Antwort nicht.": "You didn't know the answer.",
        "Deine Lernsession ist beendet! 🎉": "Study session complete! 🎉",
        "Deine Leistung": "Your results",
        "Abfragen": "prompts",
        "Lernen beenden": "Finish studying",
        "Weiterlernen": "Keep studying",
        "Keine Karten": "No cards",
        "Antwort anzeigen": "Show answer",
        "Decks": "Decks",
        "Vokabeln": "Vocabulary",
        "Feed": "Feed",
        "Karten-Feed": "Card feed",
        "Lernkarten": "Flashcards",
        "Feed-Typ": "Feed type",
        "Feed ist leer": "Feed is empty",
        "Füge Karten in deinen Decks hinzu, dann erscheinen sie hier.": "Add cards to your decks and they will appear here.",
        "Lege Vokabeln an, dann erscheinen sie hier.": "Add vocabulary and it will appear here.",
        "Tippen für die Antwort": "Tap for the answer",
        "Tippen für die Vorderseite": "Tap for the front",
        "Wische nach oben für die nächste Karte": "Swipe up for the next card",
        "Noch keine Karten": "No cards yet",
        "Keine Treffer": "No results",
        "Erstelle oder importiere Karten, um sie hier zu durchsuchen.": "Create or import cards to search them here.",
        "Versuche einen anderen Suchbegriff.": "Try another search term.",
        "Karten, Antworten oder Decks suchen": "Search cards, answers, or decks",
        "Noch keine Vokabeln": "No vocabulary yet",
        "Lege dein erstes Wortpaar an.": "Add your first word pair.",
        "Vokabel": "Word",
        "%d Vokabeln": "%d words",
        "Tippen, um die Übersetzung zu sehen": "Tap to reveal the translation",
        "Vokabeln suchen": "Search vocabulary",
        "Wortpaar": "Word pair",
        "Übersetzung": "Translation",
        "Lautschrift der Übersetzung (IPA, optional)": "Translation pronunciation (IPA, optional)",
        "Lautschrift (IPA) übernehmen": "Include pronunciation (IPA)",
        "Beispiel (optional)": "Example (optional)",
        "Beispielsatz": "Example sentence",
        "Beispielsätze übernehmen": "Include example sentences",
        "Vokabel hinzufügen": "Add vocabulary",
        "Löschen": "Delete",
        "KI": "AI",
        "Dein Plan": "Your plan",
        "Anwendung": "App",
        "Deutsch": "German",
        "Englisch": "English",
        "Name": "Name",
        "Deck löschen": "Delete deck",
        "Deck nicht gefunden": "Deck not found",
        "Karteikarten": "Flashcards",
        "PDF": "PDF",
        "1  ·  Anpassen": "1 · Customize",
        "Zusätzliche Anweisungen (optional)": "Additional instructions (optional)",
        "2  ·  Zieldeck": "2 · Target deck",
        "KI gerade nicht erreichbar. Hier ist eine lokale Übersicht der Karten.": "AI is unavailable. Here is a local overview of the cards.",
        "Mit Gemini erstellt.": "Created with Gemini.",
        "Schreibe uns bei Fragen oder Problemen. Der Support-Bereich wird im nächsten Schritt ergänzt.": "Contact us if you need help. Support details will be added in a future update.",
        "Eine Streak zählt aufeinanderfolgende lokale Kalendertage, an denen du mindestens eine Lernkarte bewertet oder eine Vokabel gelernt hast. Hast du heute noch nicht gelernt, bleibt sie bis einschließlich gestern erhalten. Nach einem ausgelassenen Tag beginnt sie wieder bei null.": "A streak counts consecutive local calendar days on which you rate at least one flashcard or study a vocabulary word. If you have not studied today, it remains active through yesterday. Missing a full day resets it to zero.",
        "Die Zeit ist eine Schätzung: Pro beantworteter Lernkarte oder Vokabel zählen die Sekunden vom Anzeigen bis zur Bewertung. Denkzeit und Wartezeit auf die KI sind darin enthalten. Gezählt wird ab Wochenbeginn nach dem Kalender deines Geräts; die Balken zeigen dieselben Tage wie die Gesamtzeit. Längere Pausen können die Zeit erhöhen.": "This is an estimate: for every answered flashcard or vocabulary word, elapsed seconds from display to rating are counted. Thinking time and AI response time are included. The week starts according to your device calendar, and the bars cover the same days as the total. Long pauses can increase the estimate.",
        "Wunschnote": "Target grade",
        "English": "English",
        "Noch keine Prüfungen": "No exams yet",
        "KI-Backend nicht erreichbar. Starte das Backend und prüfe den API-Schlüssel.": "AI backend unavailable. Start the backend and check the API key.",
        "KI nicht erreichbar · lokal eingeschätzt": "AI unavailable · locally estimated",
        "Lokale Einschätzung": "Local estimate",
        "Lernen": "Study",
        "%d Karten": "%d cards",
        "%d Karten · %d heute": "%d cards · %d today",
        "%d heute fällig": "%d due today",
        "%d Karten heute zu wiederholen": "%d cards to review today",
        "%d Karten heute fällig": "%d cards due today",
        "Lernen · %d Fragen": "Study · %d prompts",
        "%d Abfragen · %d Karten im Deck": "%d prompts · %d cards in deck",
        "%d neue Karten · etwa %d pro Lerntag": "%d new cards · about %d per study day",
        "Noch %d neue Karten · etwa %d pro Lerntag": "%d new cards left · about %d per study day",
        "Wunschnote: %0.1f": "Target grade: %0.1f",
        "Frage: %@": "Question: %@",
        "Antwort: %@": "Answer: %@",
        "%d Tg.": "%d days",
        "Vorschau · %d": "Preview · %d",
        "Noch keine Prüfung eingetragen": "No exam added yet",
        "Die Erfassung beginnt mit deinen nächsten Lernsessions.": "Tracking starts with your next study sessions.",
        "Deck erstellen": "Create deck",
        "Deck auswählen": "Select a deck",
        "Eintrag hinzufügen": "Add calendar entry",
        "Nachricht senden": "Send message",
        "Weitere Optionen": "More options",
        "Informationen zur Streak": "Streak information",
        "Informationen zur Lernzeit": "Study time information",
        "Doppeltippen, um Karte zu bearbeiten": "Double-tap to edit this card",
        "KI-Zusammenfassung nicht verfügbar. Lokale Übersicht wird angezeigt.": "AI summary unavailable. Showing a local overview instead.",
        "Antwort bewerten lassen": "Evaluate answer",
        "CSV exportieren": "Export CSV",
        "Symbol": "Icon",
        "Alle": "All",
        "Anpinnen": "Pin",
        "Lösen": "Unpin",
        "Synonyme": "Synonyms",
        "Synonyme (durch Komma trennen)": "Synonyms (comma separated)",
        "Bereits im Wörterbuch": "Already in vocabulary",
        "Lernoptionen": "Study options",
        "Schwierigkeit": "Difficulty",
        "Leicht": "Easy",
        "Mittel": "Medium",
        "Schwer": "Hard",
        "Tippen": "Type",
        "TIPPMODUS": "TYPING",
        "LERNKARTEN": "FLASHCARDS",
        "Vokabeln lernen": "Study vocabulary",
        "Überlege dir die Übersetzung und tippe zum Aufdecken.": "Think of the translation, then tap to reveal it.",
        "Antwort zeigen": "Show answer",
        "Nochmal": "Again",
        "Nicht gewusst": "Didn't know it",
        "Gewusst": "Got it",
        "Übersetzung eintippen": "Type the translation",
        "Richtig": "Correct",
        "Noch nicht ganz": "Not quite",
        "Gesuchte Antwort": "Expected answer",
        "Akzeptierte Synonyme": "Accepted synonyms",
        "Prüfen": "Check",
        "Nächste Vokabel": "Next word",
        "Lerneinheit abgeschlossen": "Study session complete",
        "%d von %d richtig": "%d of %d correct",
        "%d Vokabeln geübt": "%d words practiced",
        "Kein Symbol": "No icon",
        "Umfang": "Number of words",
        "%d Wörter": "%d words",
        "Abfragerichtung": "Direction",
        "Sprache erraten": "Guess the language",
        "Sprache A → B": "Language A → B",
        "Sprache B → A": "Language B → A",
        "Lerneinheit vorbereiten": "Prepare study session",
        "Schwerere und seltener geübte Wörter kommen mit höherer Chance in den Quizpool. Jedes Wort bleibt auswählbar.": "Harder and less-practiced words have a higher chance of entering the quiz pool. Every word remains eligible.",
        "Starten": "Start",
        "Deck bearbeiten": "Edit deck",
        "Deckoptionen": "Deck options",
        "Übersetzung anzeigen": "Show translation",
        "Vorderseite anzeigen": "Show front side",
        "Tippen, um die Vorder- oder Rückseite umzuschalten": "Tap to switch between front and back",
        "Vokabel bearbeiten": "Edit word",
        "Vokabeloptionen": "Word options",
        "Sprachpaare": "Language pairs",
        "Sprachpaar hinzufügen": "Add language pair",
        "Sprache hinzufügen": "Add language",
        "Sprachpaar": "Language pair",
        "Ausgangssprache": "Source language",
        "Zielsprache": "Target language",
        "Sprachname": "Language name",
        "Kürzel, z. B. FR": "Code, e.g. FR",
        "Das Kürzel wird im Sprachumschalter angezeigt.": "The code appears in the language switcher.",
        "Hinzufügen": "Add",
        "Kürzel bereits vorhanden": "Code already exists",
        "Bitte wähle ein noch nicht verwendetes Kürzel.": "Choose a code that is not already in use.",
        "Jedes Sprachpaar erhält eigene Vokabeln, Ordner und Quizrunden.": "Each language pair has its own words, folders, and quizzes.",
        "Vokabeln üben": "Practice vocabulary",
        "Alltagssituation": "Real-life dialogue",
        "Vokabeln abfragen": "Quiz me",
        "Vokabel-Tutor": "Vocabulary tutor",
        "Keine Vokabeln im ausgewählten Ordner.": "No vocabulary in the selected folder.",
        "Zusätzlicher Lernkarten-Kontext:": "Additional flashcard context:",
        "Übe deine Vokabeln in Dialogen und Abfragen.": "Practice your vocabulary in dialogues and quizzes.",
        "Wähle ein Sprachpaar und einen Vokabelordner. Der Tutor übt mit diesen Wörtern Dialoge und Abfragen.": "Choose a language pair and a vocabulary folder. The tutor will practice dialogues and quizzes with those words.",
        "Vorschlag zur Prüfung": "Review proposal",
        "Es wurde noch nichts gespeichert. Bitte präzisiere den Auftrag oder nenne das Ziel-Deck.": "Nothing was saved yet. Please clarify the request or name the target deck.",
        "Alle ablehnen": "Reject all",
        "Ausgewählte übernehmen": "Apply selected",
        "Neues Unterdeck": "New subdeck",
        "Kalendereintrag": "Calendar entry",
        "Unterdeck in": "Subdeck in",
        "Karten für": "Cards for",
        "Hauptdeck wird ebenfalls erstellt": "Main deck will also be created",
        "Automatisch": "Automatic",
        "Vokabeln erstellen": "Create vocabulary",
        "Decks & Lernkarten": "Decks & flashcards",
        "Neuer Vokabelordner": "New vocabulary folder",
        "Vokabeln ergänzen": "Add vocabulary",
        "%d Vorschläge wurden übernommen.": "%d proposals were applied.",
        "%d Vorschläge übernommen, %d konnten nicht zugeordnet werden.": "%d proposals applied; %d could not be matched.",
        "%d Karten · %d Decks": "%d cards · %d decks",
        "Vokabelordner löschen?": "Delete vocabulary folder?",
        "Ordner und Vokabeln löschen": "Delete folder and vocabulary",
        "Nur Ordner löschen": "Delete folder only",
        "Möchtest du die Vokabeln in diesem Ordner ebenfalls löschen?": "Do you also want to delete the vocabulary in this folder?"

    ]

    private func save() {
        guard let data = try? JSONEncoder().encode(decks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        noteLocalChange()
    }

    private func saveActivities() {
        guard let data = try? JSONEncoder().encode(activities) else { return }
        UserDefaults.standard.set(data, forKey: activityStorageKey)
        noteLocalChange()
    }

    private func saveStudyDays() {
        guard let data = try? JSONEncoder().encode(studyDays) else { return }
        UserDefaults.standard.set(data, forKey: studyDaysStorageKey)
        noteLocalChange()
    }

    private func saveCalendarEntries() {
        guard let data = try? JSONEncoder().encode(calendarEntries) else { return }
        UserDefaults.standard.set(data, forKey: calendarStorageKey)
        noteLocalChange()
    }

    private func saveVocabulary() {
        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        UserDefaults.standard.set(data, forKey: vocabularyStorageKey)
        noteLocalChange()
    }

    private func saveVocabularyDecks() {
        guard let data = try? JSONEncoder().encode(vocabularyDecks) else { return }
        UserDefaults.standard.set(data, forKey: vocabularyDeckStorageKey)
        noteLocalChange()
    }

    private func saveVocabularyLanguages() {
        guard let data = try? JSONEncoder().encode(vocabularyLanguages) else { return }
        UserDefaults.standard.set(data, forKey: vocabularyLanguagesStorageKey)
        noteLocalChange()
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        noteLocalChange()
    }

    private func saveVocabularyLanguagePairs() {
        guard let data = try? JSONEncoder().encode(vocabularyLanguagePairs) else { return }
        UserDefaults.standard.set(data, forKey: vocabularyLanguagePairsStorageKey)
        noteLocalChange()
    }
}

// MARK: - Test-Erinnerungen

/// Mitteilungen zu Tests. Standardmäßig plant die App sie selbst auf dem Gerät. Sendet das Backend Push
/// (Konto meldet `serverPush`), plant die App keine eigenen, damit nichts doppelt ankommt.
@MainActor
enum TestReminders {
    private static let enabledKey = "learncards.testReminders.enabled"
    private static let serverPushKey = "learncards.testReminders.serverPush"
    private static let deviceTokenKey = "learncards.push.deviceToken"
    private static let identifierPrefix = "test."
    /// iOS behält höchstens 64 geplante Mitteilungen; hier bleibt deutlich Luft.
    private static let maxPlanned = 30

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var serverSendsPush: Bool {
        get { UserDefaults.standard.bool(forKey: serverPushKey) }
        set { UserDefaults.standard.set(newValue, forKey: serverPushKey) }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Plant die Erinnerungen der nächsten Tage neu. Läuft, wenn die App in den Hintergrund geht und wenn sich die Einstellung ändert.
    static func reschedule(store: LearningStore) async {
        let center = UNUserNotificationCenter.current()
        let planned = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: planned)
        guard isEnabled, !serverSendsPush else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let calendar = Calendar.current
        let now = Date()
        let english = store.language == "Englisch"
        var requests: [UNNotificationRequest] = []

        func add(_ identifier: String, at date: Date, title: String, body: String) {
            guard date > now, requests.count < maxPlanned else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            requests.append(UNNotificationRequest(identifier: identifierPrefix + identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }

        // Vor jedem Termin mit Deck: drei, zwei und einen Tag vorher am Nachmittag, am Tag selbst morgens.
        for entry in store.allCalendarEntries {
            guard let deckID = entry.deckID, store.cardsIncludingSubdecks(of: deckID).count >= DailyTestOffer.minExamCards else { continue }
            let examDay = calendar.startOfDay(for: entry.date)
            for daysBefore in (0...DailyTestOffer.examWindowDays).reversed() {
                guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: examDay),
                      let moment = calendar.date(bySettingHour: daysBefore == 0 ? 7 : 16, minute: daysBefore == 0 ? 30 : 0, second: 0, of: day) else { continue }
                add("exam.\(entry.id.uuidString).\(daysBefore)", at: moment,
                    title: english ? "Practice test ready" : "Test zur Vorbereitung",
                    body: english ? "Your test for “\(entry.title)” is ready." : "Dein Test für „\(entry.title)“ ist bereit.")
            }
        }
        // Schwere Karten bleiben schwer, bis sie gelernt sind: an den nächsten drei Tagen erinnern.
        if store.decks.flatMap(\.cards).filter(\.isHard).count >= DailyTestOffer.minWeakCards {
            for offset in 1...3 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                      let moment = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day) else { continue }
                add("weak.\(offset)", at: moment,
                    title: english ? "Your daily test" : "Dein Tagestest",
                    body: english ? "A short test with cards you found difficult is waiting." : "Ein kurzer Test mit Karten, die dir schwergefallen sind, wartet.")
            }
        }
        for request in requests { try? await center.add(request) }
#if DEBUG
        print("[TestReminders] planned \(requests.count): \(requests.map(\.identifier).joined(separator: ", "))")
#endif
    }

    // MARK: Server-Push
    // APPLE-DEVELOPER: Die folgenden Funktionen werden zurzeit nirgends aufgerufen. Server-Push braucht den
    // bezahlten Apple-Developer-Account; bis dahin plant `reschedule` die Erinnerungen auf dem Gerät.

    /// Fragt iOS nach der Geräte-Kennung für Push. Die Antwort kommt über den App-Delegate.
    static func registerForPushIfWanted() {
        guard isEnabled, LearningAPI.shared.hasSession else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func didReceive(deviceToken: Data, language: String) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: deviceTokenKey)
        guard isEnabled, LearningAPI.shared.hasSession else { return }
#if DEBUG
        let sandbox = true
#else
        let sandbox = false
#endif
        try? await LearningAPI.shared.registerDevice(token: token, sandbox: sandbox, language: language == "Englisch" ? "en" : "de")
    }

    /// Vor dem Abmelden oder beim Abschalten: Das Backend soll dieses Gerät nicht mehr benachrichtigen.
    static func unregisterDevice() async {
        guard let token = UserDefaults.standard.string(forKey: deviceTokenKey) else { return }
        await LearningAPI.shared.removeDevice(token: token)
        serverSendsPush = false
    }
}
