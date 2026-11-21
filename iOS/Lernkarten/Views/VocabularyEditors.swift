import SwiftUI
import UniformTypeIdentifiers

struct VocabularyCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Gleichheit ohne Groß-/Kleinschreibung und Akzente, ohne die ganze Liste zu normalisieren.
    func matches(_ other: String) -> Bool {
        compare(other, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

// MARK: - Vokabel

struct VocabularyEditorSheet: View {
    private enum Field: Hashable { case term, translation, pronunciation, synonyms, example }

    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let defaultDeckID: UUID?
    let entry: VocabularyEntry?
    /// Sprachpaar, zu dem die Vokabel gehört. Ohne Angabe: Paar des bearbeiteten Eintrags, sonst das global gewählte.
    let languagePairID: UUID?
    @State private var term: String
    @State private var translation: String
    @State private var pronunciation: String
    @State private var example: String
    @State private var synonyms: String
    @State private var difficulty: Int
    @State private var deckID: UUID?
    @FocusState private var focus: Field?

    init(defaultDeckID: UUID? = nil, entry: VocabularyEntry? = nil, languagePairID: UUID? = nil) {
        self.defaultDeckID = defaultDeckID
        self.entry = entry
        self.languagePairID = languagePairID
        // Startwerte direkt setzen (statt in `onAppear`): kein leeres Formular beim Öffnen.
        _term = State(initialValue: entry?.term ?? "")
        _translation = State(initialValue: entry?.translation ?? "")
        _pronunciation = State(initialValue: entry?.pronunciation ?? "")
        _example = State(initialValue: entry?.example ?? "")
        _synonyms = State(initialValue: entry?.synonyms.joined(separator: ", ") ?? "")
        _difficulty = State(initialValue: entry?.difficulty ?? 1)
        _deckID = State(initialValue: entry != nil ? entry?.deckID : defaultDeckID)
    }

    private var pairID: UUID { languagePairID ?? entry?.languagePairID ?? store.selectedVocabularyLanguagePairID }
    private var decks: [VocabularyDeck] { store.vocabularyDecks.filter { $0.languagePairID == pairID } }
    private var orderedDecks: [VocabularyDeck] {
        let ids = Set(decks.map(\.id))
        let tops = decks.filter { $0.parentID.map { !ids.contains($0) } ?? true }
        return tops.flatMap { top in [top] + decks.filter { $0.parentID == top.id } }
    }

    /// Dieses Wortpaar (gleiche Vokabel und Übersetzung) gibt es im selben Sprachpaar schon.
    private var isDuplicate: Bool {
        let word = term.trimmed, meaning = translation.trimmed
        guard !word.isEmpty, !meaning.isEmpty else { return false }
        return store.vocabulary.contains { other in
            other.id != entry?.id && other.languagePairID == pairID
                && other.term.matches(word) && other.translation.matches(meaning)
        }
    }

    private var canSave: Bool { !term.trimmed.isEmpty && !translation.trimmed.isEmpty && !isDuplicate }

    private var parsedSynonyms: [String] {
        var seen = Set<String>()
        return synonyms
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.t("Vokabel"), text: $term)
                        .focused($focus, equals: .term).submitLabel(.next).onSubmit { focus = .translation }
                    TextField(store.t("Übersetzung"), text: $translation)
                        .focused($focus, equals: .translation).submitLabel(.next).onSubmit { focus = .pronunciation }
                    TextField(store.t("Lautschrift der Übersetzung (IPA, optional)"), text: $pronunciation)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .pronunciation).submitLabel(.next).onSubmit { focus = .synonyms }
                    TextField(store.t("Synonyme (durch Komma trennen)"), text: $synonyms)
                        .focused($focus, equals: .synonyms).submitLabel(.next).onSubmit { focus = .example }
                } header: {
                    Text(store.t("Wortpaar"))
                } footer: {
                    if isDuplicate {
                        Text(store.t("Dieses Wortpaar gibt es bereits.")).foregroundStyle(Palette.red)
                    }
                }
                Section(store.t("Beispiel (optional)")) {
                    TextField(store.t("Beispielsatz"), text: $example, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .example)
                }
                Section(store.t("Lernoptionen")) {
                    Picker(store.t("Schwierigkeit"), selection: $difficulty) {
                        Text(store.t("Leicht")).tag(1); Text(store.t("Mittel")).tag(2); Text(store.t("Schwer")).tag(3)
                    }
                    Picker(store.t("Deck"), selection: $deckID) {
                        // `nil` heißt hier „ohne Ordner“. „Alle“ wäre irreführend.
                        Text(store.t("Kein Ordner")).tag(UUID?.none)
                        // Hauptordner, jeweils gefolgt von ihren Unterordnern.
                        ForEach(orderedDecks) { deck in
                            Text(deck.parentID == nil ? "\(deck.emoji) \(deck.name)" : "    \(store.vocabularyDeckPath(deck))").tag(Optional(deck.id))
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(store.t(entry == nil ? "Vokabel hinzufügen" : "Vokabel bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Sichern"), action: save).disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.t("Fertig")) { focus = nil }
                }
            }
            .task {
                // Gelöschter Ordner: Auswahl zurücksetzen, sonst zeigt das Menü nichts an.
                if let id = deckID, !decks.contains(where: { $0.id == id }) { deckID = nil }
            }
        }.presentationDetents([.medium, .large])
    }

    private func save() {
        if let entry {
            store.updateVocabulary(entry.id, term: term, translation: translation, example: example, synonyms: parsedSynonyms, difficulty: difficulty, deckID: deckID, pronunciation: pronunciation)
        } else {
            store.addVocabulary(term: term, translation: translation, example: example, synonyms: parsedSynonyms, difficulty: difficulty, deckID: deckID, languagePairID: pairID, pronunciation: pronunciation)
        }
        dismiss()
    }
}

// MARK: - Ordner

struct VocabularyDeckEditorSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deck: VocabularyDeck?
    let languagePairID: UUID?
    @State private var name: String
    @State private var emoji: String
    @State private var parentID: UUID?
    @FocusState private var nameFocused: Bool
    private let emojis = ["📚", "🇬🇧", "🇫🇷", "🇪🇸", "🇮🇹", "🧠", "✈️", "💼", "🗂️", "✨"]

    init(deck: VocabularyDeck? = nil, languagePairID: UUID? = nil, parentID: UUID? = nil) {
        self.deck = deck
        self.languagePairID = languagePairID
        _name = State(initialValue: deck?.name ?? "")
        _emoji = State(initialValue: deck?.emoji ?? "")
        _parentID = State(initialValue: deck?.parentID ?? parentID)
    }

    /// Mögliche Hauptordner: im selben Sprachpaar, selbst kein Unterordner und nicht dieser Ordner.
    private var parentOptions: [VocabularyDeck] {
        store.vocabularyDecks.filter { $0.languagePairID == pairID && $0.parentID == nil && $0.id != deck?.id }
    }

    /// Ein Ordner, der selbst Unterordner hat, bleibt Hauptordner (es gibt nur eine Ebene).
    private var canBeSubfolder: Bool { deck.map { store.vocabularySubfolders(of: $0.id).isEmpty } ?? true }

    private var pairID: UUID { languagePairID ?? deck?.languagePairID ?? store.selectedVocabularyLanguagePairID }

    /// Zwei Ordner gleichen Namens im selben Sprachpaar machen die Zuordnung (z. B. durch den Tutor) mehrdeutig.
    private var nameTaken: Bool {
        let title = name.trimmed
        guard !title.isEmpty else { return false }
        return store.vocabularyDecks.contains { $0.id != deck?.id && $0.languagePairID == pairID && $0.name.matches(title) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.t("Neuer Ordner"), text: $name)
                        .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                } header: {
                    Text(store.t("Ordnername"))
                } footer: {
                    if nameTaken { Text(store.t("Einen Ordner mit diesem Namen gibt es bereits.")).foregroundStyle(Palette.red) }
                }
                if canBeSubfolder, !parentOptions.isEmpty {
                    Section {
                        Picker(store.t("Gehört zu"), selection: $parentID) {
                            Text(store.t("Kein übergeordneter Ordner")).tag(UUID?.none)
                            ForEach(parentOptions) { option in Text("\(option.emoji) \(option.name)").tag(Optional(option.id)) }
                        }
                    } footer: {
                        Text(store.t("Unterordner erscheinen unter ihrem Ordner. Wählst du den Ordner aus, gehören ihre Vokabeln dazu."))
                    }
                }
                Section(store.t("Symbol")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        Button { emoji = "" } label: {
                            Image(systemName: "nosign").font(.title2).frame(maxWidth: .infinity).padding(8)
                                .background(emoji.isEmpty ? Palette.lilac : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityLabel(store.t("Kein Symbol"))
                        ForEach(emojis, id: \.self) { value in
                            Button(value) { emoji = value }.font(.title2).frame(maxWidth: .infinity).padding(8)
                                .background(emoji == value ? Palette.lilac : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.buttonStyle(.plain)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(store.t(deck == nil ? (parentID == nil ? "Ordner erstellen" : "Unterordner erstellen") : "Ordner bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t(deck == nil ? "Erstellen" : "Sichern")) {
                        if let deck { store.updateVocabularyDeck(deck.id, name: name, emoji: emoji, parentID: .some(canBeSubfolder ? parentID : nil)) }
                        else { store.addVocabularyDeck(name: name, emoji: emoji, languagePairID: pairID, parentID: parentID) }
                        dismiss()
                    }.disabled(name.trimmed.isEmpty || nameTaken)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.t("Fertig")) { nameFocused = false }
                }
            }
            .task { if deck == nil { nameFocused = true } }
        }.presentationDetents([.medium, .large])
    }
}

// MARK: - Sprache

struct VocabularyLanguageEditorSheet: View {
    private enum Field: Hashable { case name, code }

    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var code = ""
    @State private var showingDuplicateCode = false
    @FocusState private var focus: Field?

    private var codeTaken: Bool {
        let value = code.trimmed
        return !value.isEmpty && store.vocabularyLanguages.contains { $0.code.caseInsensitiveCompare(value) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(store.t("Sprachname"), text: $name)
                        .focused($focus, equals: .name).submitLabel(.next).onSubmit { focus = .code }
                    TextField(store.t("Kürzel, z. B. FR"), text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .code).submitLabel(.done).onSubmit { focus = nil }
                        .onChange(of: code) { _, value in
                            // Nur Buchstaben und Ziffern, höchstens 4 Zeichen.
                            let cleaned = String(value.filter { $0.isLetter || $0.isNumber }.uppercased().prefix(4))
                            if cleaned != value { code = cleaned }
                        }
                } header: {
                    Text(store.t("Sprache"))
                } footer: {
                    if codeTaken {
                        Text(store.t("Kürzel bereits vorhanden")).foregroundStyle(Palette.red)
                    } else {
                        Text(store.t("Das Kürzel wird im Sprachumschalter angezeigt."))
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(store.t("Sprache hinzufügen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Hinzufügen")) {
                        if store.addVocabularyLanguage(name: name, code: code) != nil { dismiss() }
                        else { showingDuplicateCode = true }
                    }.disabled(name.trimmed.isEmpty || code.trimmed.isEmpty || codeTaken)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.t("Fertig")) { focus = nil }
                }
            }
            .alert(store.t("Kürzel bereits vorhanden"), isPresented: $showingDuplicateCode) {
                Button(store.t("OK"), role: .cancel) { }
            } message: { Text(store.t("Bitte wähle ein noch nicht verwendetes Kürzel.")) }
        }.presentationDetents([.medium, .large])
    }
}

// MARK: - Sprachpaar

struct VocabularyLanguagePairEditorSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Wird mit der ID des neuen (oder bereits vorhandenen) Sprachpaars aufgerufen.
    let onCreated: ((UUID) -> Void)?
    @State private var sourceLanguageID: UUID?
    @State private var targetLanguageID: UUID?

    init(onCreated: ((UUID) -> Void)? = nil) { self.onCreated = onCreated }

    private var sameLanguage: Bool { sourceLanguageID != nil && sourceLanguageID == targetLanguageID }

    /// Der Store wählt ein vorhandenes Paar nur aus, statt ein zweites anzulegen.
    private var existingPair: VocabularyLanguagePair? {
        guard let sourceLanguageID, let targetLanguageID else { return nil }
        return store.vocabularyLanguagePairs.first { $0.sourceLanguageID == sourceLanguageID && $0.targetLanguageID == targetLanguageID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(store.t("Ausgangssprache"), selection: $sourceLanguageID) {
                        ForEach(store.vocabularyLanguages) { language in Text("\(language.name) (\(language.code))").tag(Optional(language.id)) }
                    }
                    Picker(store.t("Zielsprache"), selection: $targetLanguageID) {
                        ForEach(store.vocabularyLanguages) { language in Text("\(language.name) (\(language.code))").tag(Optional(language.id)) }
                    }
                } header: {
                    Text(store.t("Sprachpaar"))
                } footer: {
                    if sameLanguage {
                        Text(store.t("Wähle zwei verschiedene Sprachen.")).foregroundStyle(Palette.red)
                    } else if existingPair != nil {
                        Text(store.t("Dieses Sprachpaar gibt es bereits. Es wird ausgewählt."))
                    } else {
                        Text(store.t("Jedes Sprachpaar erhält eigene Vokabeln, Ordner und Quizrunden."))
                    }
                }
            }
            .navigationTitle(store.t("Sprachpaar hinzufügen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t(existingPair == nil ? "Erstellen" : "Auswählen")) {
                        guard let sourceLanguageID, let targetLanguageID,
                              let id = store.addVocabularyLanguagePair(sourceLanguageID: sourceLanguageID, targetLanguageID: targetLanguageID) else { return }
                        onCreated?(id)
                        dismiss()
                    }.disabled(sourceLanguageID == nil || targetLanguageID == nil || sameLanguage)
                }
            }
            .onAppear {
                if sourceLanguageID == nil { sourceLanguageID = store.selectedVocabularyLanguagePair.sourceLanguageID }
                if targetLanguageID == nil { targetLanguageID = store.selectedVocabularyLanguagePair.targetLanguageID }
            }
        }.presentationDetents([.medium, .large])
    }
}
