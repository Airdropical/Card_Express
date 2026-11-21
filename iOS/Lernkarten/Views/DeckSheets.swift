import SwiftUI

struct DeckGoalSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deck: Deck
    @State private var name: String
    @State private var emoji: String
    @State private var accentColor: String
    @State private var examDate: Date?
    @State private var stopDays: Int
    @State private var targetGrade: Double?
    @State private var confirmingDelete = false
    private let emojis = ["📚", "👋", "🧪", "🧬", "🌍", "📐", "🎨", "💡", "🗣️", "💻", "🪴", "⭐️", "🧠", "🎓", "📝", "🔬", "🌱", "⚡️"]
    init(deck: Deck) { self.deck = deck; _name = State(initialValue: deck.name); _emoji = State(initialValue: deck.emoji); _accentColor = State(initialValue: deck.accentColor); _examDate = State(initialValue: deck.examDate); _stopDays = State(initialValue: deck.newCardsStopDaysBeforeExam); _targetGrade = State(initialValue: deck.targetGrade) }
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Deck")) {
                    TextField(store.t("Name"), text: $name)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) { ForEach(emojis, id: \.self) { item in Button { emoji = item } label: { Text(item).font(.title2).frame(maxWidth: .infinity).padding(7).background(emoji == item ? Palette.lilac : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) } }
                    Text(store.t("Deckfarbe")).font(.caption).foregroundStyle(Palette.muted)
                    HStack(spacing: 14) {
                        ForEach(Palette.deckAccentOptions, id: \.name) { option in
                            Button { accentColor = option.name } label: {
                                Circle().fill(option.color).frame(width: 27, height: 27)
                                    .overlay { if accentColor == option.name { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                                    .padding(4).overlay(Circle().stroke(accentColor == option.name ? option.color : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel(option.name)
                        }
                    }.frame(maxWidth: .infinity)
                }
                Section(store.t("Prüfungsziel")) {
                    Toggle(store.t("Prüfung festlegen"), isOn: Binding(get: { examDate != nil }, set: { examDate = $0 ? (examDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()) : nil }))
                    if examDate != nil {
                        DatePicker(store.t("Prüfung am"), selection: Binding(get: { examDate ?? Date() }, set: { examDate = $0 }), in: Date()..., displayedComponents: .date)
                    Stepper(store.tf("Letzte neue Karte: %d Tage vorher", stopDays), value: $stopDays, in: 0...30)
                    }
                    Toggle(store.t("Wunschnote festlegen"), isOn: Binding(get: { targetGrade != nil }, set: { targetGrade = $0 ? (targetGrade ?? 2.0) : nil }))
                    if targetGrade != nil { Picker(store.t("Gewünschte Note"), selection: Binding(get: { targetGrade ?? 2.0 }, set: { targetGrade = $0 })) { ForEach(10...60, id: \.self) { value in Text(String(format: "%.1f", Double(value) / 10)).tag(Double(value) / 10) } } }
                }
                if let examDate {
                    let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: examDate)).day ?? 0, 0)
                    let newCount = deck.cards.filter { $0.timesSeen == 0 }.count
                    let studyDays = max(days - stopDays, 1)
                    Section(store.t("Vorschau Lernplan")) { LabeledContent(store.t("Tage bis zur Prüfung"), value: "\(days)"); LabeledContent(store.t("Neue Karten insgesamt"), value: "\(newCount)"); LabeledContent(store.t("Richtwert pro Lerntag"), value: "\(Int(ceil(Double(newCount) / Double(studyDays))))") }
                }
                Section { Button(store.t("Deck und Lernziel löschen"), role: .destructive) { confirmingDelete = true } }
            }
            .navigationTitle(store.t("Passe dein Ziel an")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(store.t("Sichern")) { store.updateDeck(deck.id, name: name.isEmpty ? deck.name : name, emoji: emoji, examDate: examDate, stopDays: stopDays, targetGrade: targetGrade, accentColor: accentColor); dismiss() } } }
            .confirmationDialog("Deck löschen?", isPresented: $confirmingDelete, titleVisibility: .visible) { Button(store.t("Deck und Unterdecks löschen"), role: .destructive) { store.removeDeck(deck.id); dismiss() }; Button(store.t("Abbrechen"), role: .cancel) {} }
        }
    }
}

struct DeckSummarySheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deck: Deck
    @State private var summary = ""
    @State private var isLoading = false
    @State private var note: String?
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                if isLoading { ProgressView("Zusammenfassung wird erstellt …").frame(maxWidth: .infinity).padding(.top, 40) }
                else if !summary.isEmpty { Text(summary).font(.body).frame(maxWidth: .infinity, alignment: .leading); if let note { ErrorMessageCard(message: note) } }
                else { ContentUnavailableView(store.t("Noch keine Zusammenfassung"), systemImage: "text.alignleft", description: Text(store.t("Erstelle aus den Karten in diesem Deck eine kompakte Übersicht."))) }
                Button { Task { await generate() } } label: { Label(store.t("Mit KI zusammenfassen"), systemImage: "sparkles").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle()).disabled(isLoading || deck.cards.isEmpty)
            }.padding(20) }.navigationTitle(store.t("Zusammenfassung")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Schließen")) { dismiss() } } }
        }.onAppear { summary = deck.summary }
    }
    @MainActor private func generate() async {
        isLoading = true; defer { isLoading = false }; note = nil
        do { let result = try await LearningAPI.shared.summarize(cards: deck.cards, language: store.language); summary = result.summary; note = store.t("Mit Gemini erstellt.") }
        catch {
            summary = deck.cards.map { "• \($0.question)\n  \($0.answer)" }.joined(separator: "\n\n")
            note = store.t("KI-Zusammenfassung nicht verfügbar. Lokale Übersicht wird angezeigt.")
        }
        if let index = store.decks.firstIndex(where: { $0.id == deck.id }) { store.decks[index].summary = summary }
    }
}

struct CardEditorSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    let card: Flashcard
    @State private var question: String
    @State private var answer: String
    init(deckID: UUID, card: Flashcard) { self.deckID = deckID; self.card = card; _question = State(initialValue: card.question); _answer = State(initialValue: card.answer) }
    var body: some View {
        NavigationStack { Form { Section(store.t("Frage")) { TextEditor(text: $question).frame(minHeight: 90) }; Section(store.t("Antwort")) { TextEditor(text: $answer).frame(minHeight: 130) } }
            .navigationTitle(card.question.isEmpty ? "Neue Karte" : "Karte bearbeiten").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(store.t("Speichern")) { save(); dismiss() }.disabled(question.isEmpty || answer.isEmpty) } }
        }.presentationDetents([.large])
    }
    private func save() {
        guard let di = store.decks.firstIndex(where: { $0.id == deckID }) else { return }
        if let ci = store.decks[di].cards.firstIndex(where: { $0.id == card.id }) { store.decks[di].cards[ci].question = question; store.decks[di].cards[ci].answer = answer }
        else { store.decks[di].cards.append(Flashcard(question: question, answer: answer)) }
    }
}
