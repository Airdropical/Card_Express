import SwiftUI

// Benötigt `FlipCard` aus CardFlipAnimation.swift.

struct VocabularyStudyView: View {
    enum Mode: String, Identifiable { case cards, typing; var id: String { rawValue } }
    enum Direction: String, CaseIterable, Identifiable { case aToB, bToA; var id: String { rawValue } }

    private static let cardRadius: CGFloat = 28

    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entries: [VocabularyEntry]
    let mode: Mode
    let direction: Direction
    let requestedCount: Int
    @State private var order: [VocabularyEntry] = []
    @State private var prepared = false
    @State private var index = 0
    @State private var revealed = false
    @State private var response = ""
    @State private var checked: Bool?
    @State private var correctCount = 0
    @State private var completed = false
    @State private var startedAt = Date()
    @State private var resultCount = 0
    @State private var lastResultCorrect = false
    @FocusState private var inputFocused: Bool

    private var current: VocabularyEntry? { order.indices.contains(index) ? order[index] : nil }

    // Annahme: IPA und Synonyme gehören zur Übersetzung (so beschreibt es auch der Editor).
    // Bei A→B ist die Übersetzung die Antwort, bei B→A die Frage.
    private func questionText(_ entry: VocabularyEntry) -> String { direction == .aToB ? entry.term : entry.translation }
    private func answerText(_ entry: VocabularyEntry) -> String { direction == .aToB ? entry.translation : entry.term }

    /// Synonyme zählen nur dort als richtig, wo die Übersetzung gesucht wird (A→B).
    private func acceptedAnswers(_ entry: VocabularyEntry) -> Set<String> {
        var values = [answerText(entry)]
        if direction == .aToB { values += entry.synonyms }
        return Set(values.map(normalize).filter { !$0.isEmpty })
    }

    var body: some View {
        NavigationStack {
            content
                .background(Palette.canvas)
                .navigationTitle(store.t("Vokabeln lernen"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Palette.muted) }
                            .accessibilityLabel(store.t("Lernen beenden"))
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(store.t("Fertig")) { inputFocused = false }
                    }
                }
                .sensoryFeedback(trigger: resultCount) { _, _ in
                    lastResultCorrect ? SensoryFeedback.success : SensoryFeedback.warning
                }
                // `.task` statt `onAppear` + Guard: Die Reihenfolge wird genau einmal gemischt,
                // auch wenn der View erneut erscheint.
                .task { prepareIfNeeded() }
        }
    }

    @ViewBuilder private var content: some View {
        if completed {
            results.padding(20)
        } else if let current {
            session(current)
        } else if prepared {
            emptyState.padding(20)
        } else {
            ProgressView()
        }
    }

    // MARK: Sitzung

    private func session(_ current: VocabularyEntry) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(index + 1) / \(order.count)").foregroundStyle(Palette.muted)
                Spacer()
                Text(store.t(mode == .cards ? "LERNKARTEN" : "TIPPMODUS"))
                    .font(.caption.bold()).foregroundStyle(Palette.purple)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Palette.lilac, in: Capsule())
            }
            // Fortschritt = bereits beantwortete Karten (nicht die aktuelle mitgezählt).
            ProgressView(value: Double(index), total: Double(max(order.count, 1))).tint(Palette.purple)

            ScrollView {
                studyCard(current)
                    .id(current.id)
                    .transition(.opacity)
                    .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            // Verhindert Abschneiden der Karte beim Drehen (Abheben und Perspektive).
            .scrollClipDisabled()
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(current) }
        .task(id: current.id) { await focusInputIfNeeded() }
    }

    @ViewBuilder private func studyCard(_ current: VocabularyEntry) -> some View {
        if mode == .cards {
            // Vorder- und Rückseite getrennt: Der Wechsel passiert bei 90° und nichts erscheint gespiegelt.
            FlipCard(isFlipped: revealed, cornerRadius: Self.cardRadius) {
                cardFace(current, showsAnswer: false)
            } back: {
                cardFace(current, showsAnswer: true)
            }
            .contentShape(Rectangle())
            .onTapGesture { reveal(id: current.id) }
        } else {
            cardFace(current, showsAnswer: false)
        }
    }

    private func cardFace(_ current: VocabularyEntry, showsAnswer: Bool) -> some View {
        let questionIsTranslation = direction == .bToA
        return ZStack {
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous).fill(Palette.surface)
            VStack(spacing: 18) {
                Text(questionText(current))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 190)
                VocabularySpeechButton(text: questionText(current), languageCode: languageCode(forTranslation: questionIsTranslation, entry: current), label: store.t("Frage anhören"))
                // Die Frage ist die Übersetzung: IPA und Synonyme gehören direkt dazu.
                if questionIsTranslation { translationDetails(current) }

                if mode == .cards {
                    if showsAnswer {
                        Divider()
                        HStack(alignment: .center, spacing: 6) {
                            Text(answerText(current)).font(.title2.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(Palette.ink)
                            VocabularySpeechButton(text: answerText(current), languageCode: languageCode(forTranslation: !questionIsTranslation, entry: current), label: store.t("Antwort anhören"))
                        }.frame(maxWidth: .infinity)
                        if !questionIsTranslation { translationDetails(current) }
                        if !current.example.isEmpty {
                            Text(current.example).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        }
                    } else {
                        Text(store.t("Überlege dir die Übersetzung und tippe zum Aufdecken.")).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                } else {
                    typingBlock(current, questionIsTranslation: questionIsTranslation)
                }
            }
            .padding(22)
        }
    }

    private func typingBlock(_ current: VocabularyEntry, questionIsTranslation: Bool) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "character.cursor.ibeam").foregroundStyle(Palette.purple)
                TextField(store.t("Übersetzung eintippen"), text: $response)
                    .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($inputFocused).submitLabel(.done)
                    // Nach der Prüfung ist das Feld gesperrt, sonst ließe sich die Antwort nachträglich ändern.
                    .disabled(checked != nil)
                    .onSubmit { checkAnswer(id: current.id) }
            }
            .padding(.horizontal, 15).padding(.vertical, 14)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(inputFocused ? Palette.purple.opacity(0.7) : Palette.muted.opacity(0.16), lineWidth: inputFocused ? 1.5 : 1))
            .opacity(checked == nil ? 1 : 0.7)

            if let checked {
                Label(checked ? store.t("Richtig") : store.t("Noch nicht ganz"), systemImage: checked ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(checked ? .green : .orange).font(.headline)
                if !checked { Text("\(store.t("Gesuchte Antwort")): \(answerText(current))").font(.subheadline).foregroundStyle(Palette.muted) }
                if !questionIsTranslation { translationDetails(current) }
            }
        }
    }

    /// IPA und Synonyme der Übersetzung.
    @ViewBuilder private func translationDetails(_ entry: VocabularyEntry) -> some View {
        if !entry.pronunciation.isEmpty {
            Text(entry.pronunciation).font(.subheadline.monospaced()).foregroundStyle(Palette.purple)
        }
        if !entry.synonyms.isEmpty {
            let accepted = mode == .typing && direction == .aToB
            Text("\(store.t(accepted ? "Akzeptierte Synonyme" : "Synonyme")): \(entry.synonyms.joined(separator: ", "))")
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
    }

    // MARK: Aktionsleiste

    @ViewBuilder private func ratingButtons(_ current: VocabularyEntry) -> some View {
        Button { rate(correct: false, id: current.id) } label: {
            Label(store.t("Nicht gewusst"), systemImage: "xmark")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15).padding(.horizontal, 10)
                .foregroundStyle(Palette.red)
                .background(Palette.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
        Button { rate(correct: true, id: current.id) } label: {
            Label(store.t("Gewusst"), systemImage: "checkmark")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15).padding(.horizontal, 10)
                .foregroundStyle(.white)
                .background(Palette.purple, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder private func actionBar(_ current: VocabularyEntry) -> some View {
        VStack(spacing: 10) {
            if mode == .cards {
                if revealed {
                    // Nebeneinander, solange beide Beschriftungen einzeilig passen; bei großer Systemschrift untereinander.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { ratingButtons(current) }
                        VStack(spacing: 10) { ratingButtons(current) }
                    }
                } else {
                    Button { reveal(id: current.id) } label: {
                        Text(store.t("Antwort zeigen")).frame(maxWidth: .infinity).padding(16)
                            .background(Palette.purple, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
                    }
                }
            } else {
                let canCheck = checked != nil || !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    if checked == nil { checkAnswer(id: current.id) } else { advance(id: current.id) }
                } label: {
                    Text(store.t(checked == nil ? "Prüfen" : "Nächste Vokabel")).frame(maxWidth: .infinity).padding(16)
                        .background(Palette.purple, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
                        .opacity(canCheck ? 1 : 0.45)
                }
                .disabled(!canCheck)
                if checked == nil {
                    // Ohne diesen Weg käme man bei einer unbekannten Vokabel nicht weiter, ohne etwas einzutippen.
                    Button(store.t("Weiß ich nicht")) { giveUp(id: current.id) }
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.canvas)
    }

    // MARK: Ergebnis

    private var results: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 58)).foregroundStyle(Palette.purple)
            Text(store.t("Lerneinheit abgeschlossen")).font(.title.bold()).multilineTextAlignment(.center)
            Text(store.tf("%d von %d richtig", correctCount, order.count)).font(.title3).foregroundStyle(Palette.muted)
            Text(store.tf("%d Vokabeln geübt", order.count)).font(.subheadline).foregroundStyle(Palette.muted)
            Spacer()
            Button(store.t("Schließen")) { dismiss() }.frame(maxWidth: .infinity).padding(16).background(Palette.purple, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 48)).foregroundStyle(Palette.muted)
            Text(store.t("Keine Vokabeln zum Lernen")).font(.title3.bold()).foregroundStyle(Palette.ink)
            Spacer()
            Button(store.t("Schließen")) { dismiss() }.frame(maxWidth: .infinity).padding(16).background(Palette.purple, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
        }.buttonStyle(.plain)
    }

    // MARK: Logik

    private func prepareIfNeeded() {
        guard !prepared else { return }
        order = weightedOrder()
        startedAt = Date()
        prepared = true
    }

    private func focusInputIfNeeded() async {
        guard mode == .typing, checked == nil else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        inputFocused = true
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private func languageCode(forTranslation translation: Bool, entry: VocabularyEntry) -> String {
        let pair = entry.languagePairID.flatMap { id in store.vocabularyLanguagePairs.first(where: { $0.id == id }) }
            ?? store.selectedVocabularyLanguagePair
        let languageID = translation ? pair.targetLanguageID : pair.sourceLanguageID
        return store.vocabularyLanguage(languageID)?.code ?? "en"
    }

    /// Die Karten-ID wird mit jeder Aktion mitgegeben. Ein zweiter, sehr schneller Tipp auf
    /// dieselbe Schaltfläche trifft dann nicht versehentlich schon die nächste Vokabel
    /// und wird nicht doppelt gewertet.
    private func isCurrent(_ id: UUID) -> Bool { !completed && current?.id == id }

    private func reveal(id: UUID) {
        guard isCurrent(id), !revealed else { return }
        revealed = true
    }

    private func rate(correct: Bool, id: UUID) {
        guard isCurrent(id), revealed, let entry = current else { return }
        commit(correct, entry)
        goNext()
    }

    private func checkAnswer(id: UUID) {
        guard isCurrent(id), checked == nil, let entry = current else { return }
        let given = normalize(response)
        // Leere Eingabe wird nicht als falsche Antwort gewertet.
        guard !given.isEmpty else { return }
        inputFocused = false
        let isCorrect = acceptedAnswers(entry).contains(given)
        checked = isCorrect
        commit(isCorrect, entry)
    }

    private func giveUp(id: UUID) {
        guard isCurrent(id), checked == nil, let entry = current else { return }
        inputFocused = false
        checked = false
        commit(false, entry)
    }

    private func advance(id: UUID) {
        guard isCurrent(id), checked != nil else { return }
        goNext()
    }

    /// Gewertet wird im Moment der Antwort. So ist die Dauer exakt und nichts geht verloren,
    /// wenn der Nutzer nach der Prüfung die Sitzung beendet.
    private func commit(_ correct: Bool, _ entry: VocabularyEntry) {
        store.recordVocabulary(entry.id, correct: correct, duration: Date().timeIntervalSince(startedAt))
        if correct { correctCount += 1 }
        lastResultCorrect = correct
        resultCount += 1
    }

    private func goNext() {
        if index + 1 >= order.count {
            withAnimation(.easeInOut(duration: 0.2)) { completed = true }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                index += 1
                revealed = false
                response = ""
                checked = nil
            }
            startedAt = Date()
        }
    }

    private func weightedOrder() -> [VocabularyEntry] {
        let requested = min(max(requestedCount, 1), entries.count)
        guard requested > 0 else { return [] }
        func weight(_ entry: VocabularyEntry) -> Double {
            let dueBoost = entry.dueToday ? 2.0 : 1.0
            let difficultyBoost = 0.85 + Double(min(max(entry.difficulty, 1), 3)) * 0.2
            let exposurePenalty = sqrt(Double(max(entry.timesSeen, 0) + 1))
            return dueBoost * difficultyBoost / exposurePenalty
        }
        guard store.randomOrder else { return entries.sorted { weight($0) > weight($1) }.prefix(requested).map { $0 } }
        var pool = entries
        var result: [VocabularyEntry] = []
        while result.count < requested, !pool.isEmpty {
            let weights = pool.map(weight)
            let total = weights.reduce(0, +)
            var selection = Double.random(in: 0..<total)
            var selectedIndex = weights.count - 1
            for index in weights.indices {
                selection -= weights[index]
                if selection < 0 { selectedIndex = index; break }
            }
            result.append(pool.remove(at: selectedIndex))
        }
        return result
    }
}

/// Enthält die Vokabeln zum Zeitpunkt des Starts. Die Sitzung hängt damit nicht mehr von der Liste
/// des Eltern-Views ab (Suche, Ordner), die sich bei jeder Antwort neu berechnet.
struct VocabularyStudyConfiguration: Identifiable {
    let id = UUID()
    let mode: VocabularyStudyView.Mode
    let count: Int
    let direction: VocabularyStudyView.Direction
    let entries: [VocabularyEntry]
}

struct VocabularyStudySetupSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: VocabularyStudyView.Mode
    let maximumCount: Int
    /// Kürzel des angezeigten Sprachpaars (nicht zwingend das global gewählte).
    let sourceCode: String
    let targetCode: String
    let onStart: (Int, VocabularyStudyView.Direction) -> Void
    @State private var count = 1
    @State private var direction: VocabularyStudyView.Direction = .aToB

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Umfang")) {
                    HStack {
                        Stepper(value: $count, in: 1...max(maximumCount, 1)) {
                            Text(store.tf("%d Wörter", count))
                        }
                        Button(store.t("Alle")) { count = max(maximumCount, 1) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(Palette.purple)
                            .disabled(count >= maximumCount)
                    }
                }
                Section(store.t("Abfragerichtung")) {
                    Picker(store.t("Sprache erraten"), selection: $direction) {
                        Text("\(sourceCode) → \(targetCode)").tag(VocabularyStudyView.Direction.aToB)
                        Text("\(targetCode) → \(sourceCode)").tag(VocabularyStudyView.Direction.bToA)
                    }.pickerStyle(.segmented)
                }
                Section {
                    Text(store.t("Schwerere und seltener geübte Wörter kommen mit höherer Chance in den Quizpool. Jedes Wort bleibt auswählbar.")).font(.footnote).foregroundStyle(Palette.muted)
                }
            }
            .navigationTitle(store.t("Lerneinheit vorbereiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Starten")) { onStart(count, direction); dismiss() }
                        .disabled(maximumCount == 0)
                }
            }
            .onAppear { count = max(min(maximumCount, 10), 1) }
        }.presentationDetents([.medium, .large])
    }
}
