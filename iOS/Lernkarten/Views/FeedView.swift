import SwiftUI

// Benötigt `FlipCard` aus CardFlipAnimation.swift.

// MARK: - Modelle

private enum FeedMode: Hashable {
    case flashcards, vocabulary

    var historyKey: String { "feedImpressionCounts_\(self == .flashcards ? "flashcards" : "vocabulary")" }
}

/// Eine Karte im Feed. Eigener Typ statt `FeedCard`, damit Vorder-/Rückseite, Sprachcodes und
/// der Text für die Sprachausgabe an einer Stelle liegen.
private struct FeedEntry: Equatable {
    let id: String
    let isVocabulary: Bool
    let front: String
    let back: String
    /// Nur die Übersetzung (ohne Lautschrift und Beispiel) für die Sprachausgabe der Rückseite.
    let backSpeech: String
    let detail: String
    let sourceLanguageCode: String
    let targetLanguageCode: String
    /// Lautschrift und Beispielsatz stehen kleiner unter der Übersetzung.
    var pronunciation: String = ""
    var example: String = ""
}

private struct FeedSnapshot {
    var order: [String] = []
    var items: [String: FeedEntry] = [:]
}

/// Ein Eintrag der Warteschlange. Die eigene ID (statt des Index) hält Scroll-Position,
/// „aufgedeckt“-Status und Impressions stabil, auch wenn sich die Queue ändert.
/// Gespeichert wird nur die Karten-ID: bearbeitete Karten erscheinen sofort mit neuem Text.
private struct QueuedCard: Identifiable {
    let id = UUID()
    let cardID: String
}

private struct SpeechInfo {
    let text: String
    let code: String
}

// MARK: - Verlauf (nicht beobachtet)

/// Zähler und Speicherung liegen außerhalb von `@State`: Eine Änderung löst kein Neuzeichnen aus.
/// Gespeichert wird entprellt, nicht bei jeder Seite.
@MainActor
private final class FeedHistory {
    private(set) var counts: [String: Int] = [:]
    private var recorded: Set<UUID> = []
    private var key = ""
    private var loaded = false
    private var saveTask: Task<Void, Never>?

    func load(key: String, keeping validIDs: Set<String>) {
        guard !loaded else { return }
        loaded = true
        self.key = key
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        // Zähler gelöschter Karten und Vokabeln fallen hier raus.
        counts = decoded.filter { validIDs.contains($0.key) }
        if counts.count != decoded.count { scheduleSave() }
    }

    func hasRecorded(_ queueID: UUID) -> Bool { recorded.contains(queueID) }

    func recordImpression(queueID: UUID, cardID: String) {
        guard recorded.insert(queueID).inserted else { return }
        counts[cardID, default: 0] += 1
        scheduleSave()
    }

    func resetSession() { recorded.removeAll() }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persist()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        guard !key.isEmpty, let data = try? JSONEncoder().encode(counts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Feed

struct FeedView: View {
    @Environment(LearningStore.self) private var store
    @State private var mode: FeedMode = .flashcards

    var body: some View {
        NavigationStack {
            let snapshot = makeSnapshot()
            VStack(spacing: 0) {
                Picker(store.t("Feed-Typ"), selection: $mode) {
                    Text(store.t("Lernkarten")).tag(FeedMode.flashcards)
                    Text(store.t("Vokabeln")).tag(FeedMode.vocabulary)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                if snapshot.order.isEmpty {
                    ContentUnavailableView(
                        store.t("Feed ist leer"),
                        systemImage: mode == .flashcards ? "rectangle.stack" : "character.book.closed",
                        description: Text(store.t(mode == .flashcards
                                                  ? "Füge Karten in deinen Decks hinzu, dann erscheinen sie hier."
                                                  : "Lege Vokabeln an, dann erscheinen sie hier."))
                    )
                } else {
                    // `.id(mode)`: Beim Moduswechsel entsteht der Pager komplett neu (eigene Queue, eigener Verlauf).
                    // Das ersetzt den früheren doppelten Reset durch zwei `onChange`-Handler.
                    FeedPager(mode: mode, snapshot: snapshot, allKnownIDs: { allKnownIDs() })
                        .id(mode)
                }
            }
            .background(Palette.canvas)
            .navigationTitle(store.t("Karten-Feed"))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Einmal pro Auswertung des Bodys, nicht bei jedem Zugriff. Der Pager hält Scroll- und
    /// Aufdeck-Zustand selbst, deshalb läuft dieser Body nur bei Änderungen am Store oder Modus.
    private func makeSnapshot() -> FeedSnapshot {
        var snapshot = FeedSnapshot()
        switch mode {
        case .flashcards:
            for deck in store.decks {
                let detail = "\(deck.emoji)  \(deck.name)"
                for card in deck.cards {
                    let id = card.id.uuidString
                    snapshot.order.append(id)
                    snapshot.items[id] = FeedEntry(
                        id: id, isVocabulary: false,
                        front: card.question, back: card.answer, backSpeech: "",
                        detail: detail, sourceLanguageCode: "", targetLanguageCode: ""
                    )
                }
            }
        case .vocabulary:
            // Sprachpaar und Codes sind für alle gefilterten Einträge gleich, daher einmal vor der Schleife.
            let pairID = store.selectedVocabularyLanguagePairID
            let pair = store.selectedVocabularyLanguagePair
            let sourceCode = store.vocabularyLanguage(pair.sourceLanguageID)?.code ?? "en"
            let targetCode = store.vocabularyLanguage(pair.targetLanguageID)?.code ?? "de"
            let detail = store.t("Vokabel")
            for entry in store.vocabulary where entry.languagePairID == pairID {
                let id = entry.id.uuidString
                snapshot.order.append(id)
                snapshot.items[id] = FeedEntry(
                    id: id, isVocabulary: true,
                    front: entry.term, back: entry.translation, backSpeech: entry.translation,
                    detail: detail, sourceLanguageCode: sourceCode, targetLanguageCode: targetCode,
                    pronunciation: entry.pronunciation, example: entry.example
                )
            }
        }
        return snapshot
    }

    /// Alle existierenden IDs des Modus (bei Vokabeln über alle Sprachpaare), damit nur Zähler
    /// wirklich gelöschter Einträge entfernt werden und nicht die eines anderen Sprachpaars.
    private func allKnownIDs() -> Set<String> {
        switch mode {
        case .flashcards: return Set(store.decks.flatMap { $0.cards.map { $0.id.uuidString } })
        case .vocabulary: return Set(store.vocabulary.map { $0.id.uuidString })
        }
    }
}

// MARK: - Pager

private struct FeedPager: View {
    let mode: FeedMode
    let snapshot: FeedSnapshot
    let allKnownIDs: () -> Set<String>

    @Environment(\.scenePhase) private var scenePhase
    @State private var history = FeedHistory()
    @State private var queue: [QueuedCard] = []
    @State private var revealed: Set<UUID> = []
    @State private var scrollID: UUID?
    @State private var generation = 0
    @State private var isPreparing = false

    private let batchSize = 10
    private let prepareAheadCount = 4

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(queue) { queued in
                    if let entry = snapshot.items[queued.cardID] {
                        FeedPage(entry: entry, isRevealed: revealed.contains(queued.id)) {
                            toggleReveal(queued.id)
                        }
                        .containerRelativeFrame(.vertical)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrollID)
        // Neuer Aufbau => neue Scroll-Instanz, sonst bliebe die alte Position stehen.
        .id(generation)
        .task { start() }
        .onChange(of: scrollID) { _, id in pageChanged(id) }
        .onChange(of: snapshot.order) { _, _ in snapshotChanged() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { history.flush() } }
        .onDisappear { history.flush() }
    }

    // MARK: Zustand

    /// Läuft bei jedem Erscheinen, baut die Queue aber nur auf, wenn noch keine existiert.
    /// Beim Zurückwechseln auf den Tab bleiben Position und Aufdeck-Status erhalten.
    private func start() {
        history.load(key: mode.historyKey, keeping: allKnownIDs())
        guard queue.isEmpty else { return }
        rebuild()
    }

    private func rebuild() {
        generation += 1
        isPreparing = false
        revealed.removeAll()
        history.resetSession()
        let ids = Self.makeBatch(ids: snapshot.order, counts: history.counts, previousID: nil, count: batchSize)
        queue = ids.map { QueuedCard(cardID: $0) }
        scrollID = queue.first?.id
    }

    private func toggleReveal(_ id: UUID) {
        if revealed.contains(id) { revealed.remove(id) } else { revealed.insert(id) }
    }

    /// Eine Seite zählt erst, wenn sie tatsächlich eingerastet ist, nicht schon beim Vorladen durch `LazyVStack`.
    private func pageChanged(_ id: UUID?) {
        guard let id, let index = queue.firstIndex(where: { $0.id == id }) else { return }
        history.recordImpression(queueID: id, cardID: queue[index].cardID)
        prepareMoreIfNeeded(after: index)
    }

    /// Karten wurden hinzugefügt oder gelöscht. Die Queue bleibt erhalten (kein Sprung an den Anfang),
    /// nur gelöschte Karten werden entfernt. Neue Karten kommen über die nächsten Batches dazu.
    private func snapshotChanged() {
        let valid = Set(snapshot.order)
        let kept = queue.filter { valid.contains($0.cardID) }
        if kept.count != queue.count {
            queue = kept
            revealed.formIntersection(Set(kept.map(\.id)))
        }
        if queue.isEmpty {
            rebuild()
        } else if let current = scrollID, let index = queue.firstIndex(where: { $0.id == current }) {
            prepareMoreIfNeeded(after: index)
        } else {
            scrollID = queue.first?.id
        }
    }

    // MARK: Batches

    private func prepareMoreIfNeeded(after index: Int) {
        guard !isPreparing,
              queue.count - index <= prepareAheadCount,
              !snapshot.order.isEmpty else { return }
        isPreparing = true
        let currentGeneration = generation
        let ids = snapshot.order
        let size = batchSize
        let previousID = queue.last?.cardID
        // Bereits eingeplante, aber noch nicht gesehene Karten zählen mit,
        // damit sie im nächsten Batch nicht sofort wieder bevorzugt werden.
        var counts = history.counts
        for queued in queue where !history.hasRecorded(queued.id) {
            counts[queued.cardID, default: 0] += 1
        }
        let weights = counts

        Task { @MainActor in
            let batch = await Task.detached(priority: .utility) {
                FeedPager.makeBatch(ids: ids, counts: weights, previousID: previousID, count: size)
            }.value
            guard currentGeneration == generation else { return }
            queue.append(contentsOf: batch.map { QueuedCard(cardID: $0) })
            isPreparing = false
        }
    }

    /// Gewichtete Zufallsauswahl: je seltener eine Karte gesehen wurde, desto wahrscheinlicher kommt sie.
    /// Keine Karte zweimal direkt hintereinander (außer es gibt nur eine).
    private nonisolated static func makeBatch(ids: [String], counts: [String: Int], previousID: String?, count: Int) -> [String] {
        guard !ids.isEmpty else { return [] }
        var virtualCounts = counts
        var result: [String] = []
        result.reserveCapacity(count)
        var previous = previousID
        let hasAlternatives = ids.count > 1

        func weight(_ id: String) -> Double { 1.0 / (1.0 + Double(virtualCounts[id, default: 0])) }

        for _ in 0..<count {
            var total = 0.0
            for id in ids where !(hasAlternatives && id == previous) { total += weight(id) }
            var choice = Double.random(in: 0..<total)
            var selected: String?
            var lastCandidate: String?
            for id in ids where !(hasAlternatives && id == previous) {
                lastCandidate = id
                choice -= weight(id)
                if choice < 0 { selected = id; break }
            }
            // Fallback bei Rundungsfehlern: letzter Kandidat, nicht der erste (sonst leichte Verzerrung).
            let pick = selected ?? lastCandidate ?? ids[0]
            result.append(pick)
            virtualCounts[pick, default: 0] += 1
            previous = pick
        }
        return result
    }
}

// MARK: - Seite

private struct FeedPage: View {
    @Environment(LearningStore.self) private var store
    let entry: FeedEntry
    let isRevealed: Bool
    let flip: () -> Void

    private var frontSpeech: SpeechInfo? {
        entry.isVocabulary ? SpeechInfo(text: entry.front, code: entry.sourceLanguageCode) : nil
    }

    private var backSpeech: SpeechInfo? {
        entry.isVocabulary ? SpeechInfo(text: entry.backSpeech, code: entry.targetLanguageCode) : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Palette.lilac, Palette.canvas], startPoint: .topLeading, endPoint: .bottomTrailing)

            // Vorder- und Rückseite sind getrennte Views. Der Seitenwechsel passiert exakt bei 90°.
            FlipCard(isFlipped: isRevealed, cornerRadius: 30) {
                face(text: entry.front, speech: frontSpeech, hint: "Tippen für die Antwort")
            } back: {
                face(text: entry.back, speech: backSpeech, hint: "Tippen für die Vorderseite", pronunciation: entry.pronunciation, example: entry.example)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 54)
            .contentShape(Rectangle())
            .onTapGesture(perform: flip)

            HStack(spacing: 8) {
                Image(systemName: "hand.draw")
                Text(store.t("Wische nach oben für die nächste Karte"))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.muted)
            .padding(.bottom, 14)
        }
    }

    private func face(text: String, speech: SpeechInfo?, hint: String, pronunciation: String = "", example: String = "") -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Palette.surface)
            VStack(spacing: 22) {
                Label(entry.detail, systemImage: entry.isVocabulary ? "character.book.closed" : "rectangle.stack")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.muted)
                Text(text)
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    // Lange Antworten verkleinern sich, statt abgeschnitten zu werden.
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                if !pronunciation.isEmpty {
                    Text(pronunciation)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Palette.purple)
                        .multilineTextAlignment(.center)
                        .padding(.top, -12)
                }
                if !example.isEmpty {
                    Text(example)
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                if let speech, !speech.text.isEmpty {
                    VocabularySpeechButton(
                        text: speech.text,
                        languageCode: speech.code,
                        label: store.t("Vokabel anhören"),
                        size: .title3
                    )
                }
                Text(store.t(hint)).font(.subheadline).foregroundStyle(Palette.muted)
            }
            .padding(28)
        }
    }
}
