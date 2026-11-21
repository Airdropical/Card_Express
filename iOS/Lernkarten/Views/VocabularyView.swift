import SwiftUI
import UniformTypeIdentifiers

/// Alles, was die Liste braucht, in einem Durchlauf über die Vokabeln berechnet.
/// Vorher wurden Filter, Suche und Sortierung pro Body etwa siebenmal wiederholt
/// und jeder Ordner-Chip hat die gesamte Liste erneut durchlaufen.
private struct VocabularyListData {
    let pair: VocabularyLanguagePair
    let source: VocabularyLanguage?
    let target: VocabularyLanguage?
    let decks: [VocabularyDeck]
    /// Hauptordner (ohne gültigen übergeordneten Ordner) und ihre Unterordner.
    let topDecks: [VocabularyDeck]
    let children: [UUID: [VocabularyDeck]]
    /// Alle Vokabeln des Sprachpaars.
    let total: Int
    /// Anzahl pro Ordner, unabhängig von Auswahl und Suche. Bei Hauptordnern einschließlich der Unterordner.
    let deckCounts: [UUID?: Int]
    /// Sichtbare Liste: Ordner + Suche, angepinnte zuerst.
    let entries: [VocabularyEntry]
    /// Export und Ordnerumfang ohne Suchfilter.
    let exportEntries: [VocabularyEntry]

    var sourceCode: String { source?.code ?? "A" }
    var targetCode: String { target?.code ?? "B" }
}

struct VocabularyView: View {
    @Environment(LearningStore.self) private var store
    /// Gesetzt, wenn die Ansicht für ein bestimmtes Sprachpaar geöffnet wurde (z. B. aus dem Tutor-Chat).
    /// Dann gilt die Auswahl nur lokal und ändert nicht die globale Auswahl der App.
    @State private var scopedPairID: UUID?
    @State private var showingAdd = false
    @State private var showingDeckEditor = false
    @State private var showingLanguageEditor = false
    @State private var showingLanguagePairEditor = false
    @State private var editingVocabularyDeck: VocabularyDeck?
    @State private var deletingVocabularyDeck: VocabularyDeck?
    @State private var confirmingVocabularyDeckDeletion = false
    /// Ergebnis von „Sprachrichtung prüfen“: Anzahl der umgedrehten Vokabeln.
    @State private var directionFixCount: Int?
    @State private var creatingSubfolderFor: VocabularyDeck?
    @State private var editingVocabularyEntry: VocabularyEntry?
    @State private var showingCSVExporter = false
    @State private var csvDocument = VocabularyCSVDocument(text: "")
    @State private var exportError: String?
    @State private var studyMode: VocabularyStudyView.Mode?
    @State private var showingStudySetup = false
    @State private var pendingStudy: VocabularyStudyConfiguration?
    @State private var activeStudy: VocabularyStudyConfiguration?
    @State private var selectedDeckID: UUID?
    @State private var revealed: Set<UUID> = []
    @State private var search = ""
    @State private var appliedSearch = ""
    @FocusState private var searchFocused: Bool

    init(initialSelectedDeckID: UUID? = nil, languagePairID: UUID? = nil) {
        _scopedPairID = State(initialValue: languagePairID)
        _selectedDeckID = State(initialValue: initialSelectedDeckID)
    }

    private var selectedLanguagePair: VocabularyLanguagePair {
        scopedPairID.flatMap { id in store.vocabularyLanguagePairs.first(where: { $0.id == id }) } ?? store.selectedVocabularyLanguagePair
    }

    private func makeListData() -> VocabularyListData {
        let pair = selectedLanguagePair
        let decks = store.vocabularyDecks.filter { $0.languagePairID == pair.id }
        let ids = Set(decks.map(\.id))
        // Ein Unterordner, dessen Hauptordner fehlt, wird wie ein Hauptordner behandelt.
        let parentOf: [UUID: UUID] = Dictionary(uniqueKeysWithValues: decks.compactMap { deck in
            deck.parentID.flatMap { ids.contains($0) && $0 != deck.id ? (deck.id, $0) : nil }
        })
        let topDecks = decks.filter { parentOf[$0.id] == nil }
        let children = Dictionary(grouping: decks.filter { parentOf[$0.id] != nil }) { parentOf[$0.id]! }
        // Ein ausgewählter Hauptordner zeigt auch die Vokabeln seiner Unterordner.
        let scope: Set<UUID>? = selectedDeckID.map { id in Set([id] + (children[id] ?? []).map(\.id)) }
        var counts: [UUID?: Int] = [:]
        var total = 0
        var scoped: [VocabularyEntry] = []
        for entry in store.vocabulary where entry.languagePairID == pair.id {
            total += 1
            counts[entry.deckID, default: 0] += 1
            if let deckID = entry.deckID, let parent = parentOf[deckID] { counts[parent, default: 0] += 1 }
            if scope == nil || entry.deckID.map({ scope!.contains($0) }) == true { scoped.append(entry) }
        }
        let query = appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? scoped : scoped.filter { Self.matches($0, query: query) }
        // Zwei Filter statt `sorted`: Die Reihenfolge innerhalb der Gruppen bleibt garantiert erhalten.
        let ordered = matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
        return VocabularyListData(
            pair: pair,
            source: store.vocabularyLanguage(pair.sourceLanguageID),
            target: store.vocabularyLanguage(pair.targetLanguageID),
            decks: decks, topDecks: topDecks, children: children, total: total, deckCounts: counts,
            entries: ordered, exportEntries: scoped
        )
    }

    /// Ohne Groß-/Kleinschreibung und Akzente, schneller als `localizedCaseInsensitiveContains`.
    private static func matches(_ entry: VocabularyEntry, query: String) -> Bool {
        func hit(_ value: String) -> Bool { value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return hit(entry.term) || hit(entry.translation) || hit(entry.example) || hit(entry.pronunciation) || entry.synonyms.contains(where: hit)
    }

    var body: some View {
        let data = makeListData()
        NavigationStack {
            ScrollView {
                // Lazy: Bei vielen Vokabeln werden nur sichtbare Karten gebaut.
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.t("Vokabeln")).font(.largeTitle.bold())
                        }
                        Spacer()
                        Button { showingDeckEditor = true } label: { Image(systemName: "folder.badge.plus").font(.headline).padding(12).background(Palette.lilac, in: Circle()) }
                            .accessibilityLabel(store.t("Ordner erstellen"))
                        Button { showingAdd = true } label: { Image(systemName: "plus").font(.headline).padding(12).background(Palette.lilac, in: Circle()) }
                            .accessibilityLabel(store.t("Vokabel hinzufügen"))
                    }
                    HStack {
                        Text(store.tf("%d Vokabeln", data.entries.count)).font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        languagePairMenu(data)
                    }
                    searchField
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            folderChip(name: store.t("Alle"), emoji: "🌐", id: nil, data: data)
                            ForEach(data.topDecks) { deck in
                                folderChip(name: deck.name, emoji: deck.emoji, id: deck.id, data: data,
                                           hasChildren: !(data.children[deck.id] ?? []).isEmpty)
                            }
                        }
                    }
                    subfolderRow(data)
                    Button {
                        csvDocument = VocabularyCSVDocument(text: csvText(for: data.exportEntries, data: data))
                        showingCSVExporter = true
                    } label: {
                        Label(store.t("CSV exportieren"), systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(12)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).foregroundStyle(Palette.ink).disabled(data.exportEntries.isEmpty)
                    HStack(spacing: 10) {
                        Button { studyMode = .cards; showingStudySetup = true } label: { Label(store.t("Lernkarten"), systemImage: "rectangle.on.rectangle.angled").frame(maxWidth: .infinity).padding(13).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 16)) }
                            .disabled(data.entries.isEmpty)
                        Button { studyMode = .typing; showingStudySetup = true } label: { Label(store.t("Tippen"), systemImage: "keyboard").frame(maxWidth: .infinity).padding(13).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 16)) }
                            .disabled(data.entries.isEmpty)
                    }.buttonStyle(.plain).foregroundStyle(Palette.purple)
                    if data.entries.isEmpty {
                        ContentUnavailableView(store.t(appliedSearch.isEmpty ? "Noch keine Vokabeln" : "Keine Treffer"), systemImage: "character.book.closed", description: Text(store.t(appliedSearch.isEmpty ? "Lege dein erstes Wortpaar an." : "Versuche einen anderen Suchbegriff."))).frame(minHeight: 250)
                    } else {
                        ForEach(data.entries) { entry in vocabularyCard(entry, data: data) }
                    }
                }.padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas)
            .alert(store.t("Sprachrichtung geprüft"), isPresented: Binding(get: { directionFixCount != nil }, set: { if !$0 { directionFixCount = nil } })) {
                Button(store.t("OK"), role: .cancel) {}
            } message: {
                Text((directionFixCount ?? 0) > 0 ? store.tf("%d Vokabeln wurden umgedreht.", directionFixCount ?? 0) : store.t("Alle Vokabeln stehen in der richtigen Richtung."))
            }
            .confirmationDialog(store.t("Vokabelordner löschen?"), isPresented: $confirmingVocabularyDeckDeletion, titleVisibility: .visible) {
                if let deletingVocabularyDeck {
                    let hasSubfolders = !store.vocabularySubfolders(of: deletingVocabularyDeck.id).isEmpty
                    Button(store.t(hasSubfolders ? "Ordner, Unterordner und Vokabeln löschen" : "Ordner und Vokabeln löschen"), role: .destructive) { removeFolder(deletingVocabularyDeck, includingEntries: true) }
                    Button(store.t(hasSubfolders ? "Nur Ordner löschen, Unterordner behalten" : "Nur Ordner löschen")) { removeFolder(deletingVocabularyDeck, includingEntries: false) }
                }
                Button(store.t("Abbrechen"), role: .cancel) { deletingVocabularyDeck = nil }
            } message: {
                if let deletingVocabularyDeck, !store.vocabularySubfolders(of: deletingVocabularyDeck.id).isEmpty {
                    Text(store.t("Behältst du die Unterordner, werden sie zu eigenen Ordnern. Ihre Vokabeln bleiben darin."))
                } else {
                    Text(store.t("Möchtest du die Vokabeln in diesem Ordner ebenfalls löschen?"))
                }
            }
            .alert(store.t("Export fehlgeschlagen"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button(store.t("OK"), role: .cancel) { }
            } message: { Text(exportError ?? "") }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.t("Schließen")) { searchFocused = false }
                }
            }
            // Gefiltert wird erst kurz nach dem letzten Tastendruck, nicht bei jedem Zeichen.
            .task(id: search) {
                if search.isEmpty { appliedSearch = ""; return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                appliedSearch = search
            }
            // Sprachpaar gewechselt (hier oder an anderer Stelle der App): Ordnerauswahl und Aufdeck-Status zurücksetzen.
            .onChange(of: data.pair.id) { _, _ in
                selectedDeckID = nil
                revealed = []
            }
            // Ausgewählter Ordner wurde gelöscht (z. B. über den Tutor): zurück auf „Alle“.
            .onChange(of: data.decks.map(\.id)) { _, ids in
                if let id = selectedDeckID, !ids.contains(id) { selectedDeckID = nil }
            }
            // Alle Sheets bekommen das angezeigte Sprachpaar, nicht das global gewählte.
            .sheet(isPresented: $showingAdd) { VocabularyEditorSheet(defaultDeckID: selectedDeckID, languagePairID: data.pair.id) }
            .sheet(item: $editingVocabularyEntry) { entry in VocabularyEditorSheet(entry: entry, languagePairID: entry.languagePairID) }
            .sheet(isPresented: $showingDeckEditor) { VocabularyDeckEditorSheet(languagePairID: data.pair.id) }
            .sheet(item: $creatingSubfolderFor) { parent in VocabularyDeckEditorSheet(languagePairID: parent.languagePairID, parentID: parent.id) }
            .sheet(isPresented: $showingLanguageEditor) { VocabularyLanguageEditorSheet() }
            .sheet(isPresented: $showingLanguagePairEditor) {
                VocabularyLanguagePairEditorSheet { id in
                    if scopedPairID != nil { scopedPairID = id }
                }
            }
            .sheet(item: $editingVocabularyDeck) { deck in VocabularyDeckEditorSheet(deck: deck, languagePairID: deck.languagePairID) }
            .sheet(isPresented: $showingStudySetup, onDismiss: {
                if let pendingStudy { activeStudy = pendingStudy; self.pendingStudy = nil }
            }) {
                VocabularyStudySetupSheet(mode: studyMode ?? .cards, maximumCount: data.entries.count, sourceCode: data.sourceCode, targetCode: data.targetCode) { count, direction in
                    // Die Vokabeln werden beim Start eingefroren. Die Sitzung hängt danach nicht mehr von dieser Liste ab.
                    pendingStudy = VocabularyStudyConfiguration(mode: studyMode ?? .cards, count: count, direction: direction, entries: data.entries)
                }
            }
            .fileExporter(isPresented: $showingCSVExporter, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: exportFilename(data)) { result in
                if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                    exportError = error.localizedDescription
                }
            }
            .fullScreenCover(item: $activeStudy) { config in
                VocabularyStudyView(entries: config.entries, mode: config.mode, direction: config.direction, requestedCount: config.count)
            }
        }
    }

    // MARK: Suche

    /// Eigenes Suchfeld statt `.searchable`: Das System-Suchfeld hängt an der Navigationsleiste,
    /// und die ist hier ausgeblendet.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
            TextField(store.t("Vokabeln suchen"), text: $search)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.t("Löschen"))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().stroke(searchFocused ? Palette.purple.opacity(0.45) : Palette.muted.opacity(0.12), lineWidth: searchFocused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    // MARK: Export

    private func exportFilename(_ data: VocabularyListData) -> String {
        let deckName = selectedDeckID.flatMap { id in data.decks.first(where: { $0.id == id }).map(store.vocabularyDeckPath) } ?? "Vokabeln"
        let safeName = deckName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(data.sourceCode)-\(data.targetCode)-\(safeName)"
    }

    private func csvText(for values: [VocabularyEntry], data: VocabularyListData) -> String {
        let sourceName = data.source?.name ?? "Language A"
        let targetName = data.target?.name ?? "Language B"
        let rows = [["source_language", "target_language", "term", "translation", "pronunciation_ipa", "synonyms", "example", "difficulty", "pinned"]] + values.map {
            [sourceName, targetName, $0.term, $0.translation, $0.pronunciation, $0.synonyms.joined(separator: "; "), $0.example, String($0.difficulty), $0.isPinned ? "true" : "false"]
        }
        // BOM: Ohne ihn zeigt Excel Umlaute und Akzente falsch an.
        return "\u{FEFF}" + rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private func csvField(_ value: String) -> String {
        var text = value
        // Zellen, die mit =, +, -, @ beginnen, wertet Excel als Formel (CSV-Injection, relevant bei KI-erzeugtem Inhalt).
        // Ein vorangestelltes Apostroph macht sie zu Text.
        if let first = text.first, "=+-@\t\r".contains(first) { text = "'" + text }
        return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: Ordner

    /// Der ausgewählte Hauptordner: direkt gewählt oder als Elternordner des gewählten Unterordners.
    private func activeTopID(_ data: VocabularyListData) -> UUID? {
        guard let id = selectedDeckID else { return nil }
        if data.topDecks.contains(where: { $0.id == id }) { return id }
        return data.children.first(where: { $0.value.contains(where: { $0.id == id }) })?.key
    }

    /// Zweite Reihe: erscheint nur, wenn der gewählte Hauptordner Unterordner hat.
    @ViewBuilder private func subfolderRow(_ data: VocabularyListData) -> some View {
        if let top = activeTopID(data), let kids = data.children[top], !kids.isEmpty {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        subfolderChip(name: store.t("Alle"), id: top, data: data)
                        ForEach(kids) { kid in subfolderChip(name: kid.name, id: kid.id, data: data) }
                    }
                }
            }
            .padding(.leading, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func subfolderChip(name: String, id: UUID, data: VocabularyListData) -> some View {
        let deck = data.decks.first(where: { $0.id == id && $0.parentID != nil })
        return subfolderChipBody(name: name, id: id, data: data)
            .contextMenu {
                if let deck {
                    Button { editingVocabularyDeck = deck } label: { Label(store.t("Ordner bearbeiten"), systemImage: "pencil") }
                    Button { directionFixCount = store.fixVocabularyDirection(inDeck: deck.id) } label: { Label(store.t("Sprachrichtung prüfen"), systemImage: "arrow.left.arrow.right") }
                    Button(role: .destructive) { requestFolderDeletion(deck) } label: { Label(store.t("Ordner löschen"), systemImage: "trash") }
                }
            }
    }

    private func subfolderChipBody(name: String, id: UUID, data: VocabularyListData) -> some View {
        let active = selectedDeckID == id
        let count = data.deckCounts[id] ?? 0
        return Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selectedDeckID = id } } label: {
            HStack(spacing: 4) { Text(name); Text("\(count)").foregroundStyle(Palette.muted) }
                .font(.footnote.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                .background(active ? Palette.purple.opacity(0.14) : Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? Palette.purple.opacity(0.35) : Palette.muted.opacity(0.12)))
        }.buttonStyle(.plain).foregroundStyle(active ? Palette.purple : Palette.ink)
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func folderChip(name: String, emoji: String, id: UUID?, data: VocabularyListData, hasChildren: Bool = false) -> some View {
        // Ein Hauptordner bleibt hervorgehoben, solange einer seiner Unterordner gewählt ist.
        let active = id == nil ? selectedDeckID == nil : activeTopID(data) == id
        // Zahl aus dem vorberechneten Wörterbuch, kein erneuter Durchlauf pro Chip.
        let count = id.map { data.deckCounts[$0] ?? 0 } ?? data.total
        return Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selectedDeckID = id } } label: {
            HStack(spacing: 5) {
                Text(emoji); Text(name)
                if active { Text("· \(count)").foregroundStyle(Palette.muted) }
                if hasChildren { Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Palette.muted).rotationEffect(.degrees(active ? 180 : 0)) }
            }
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 9)
                .background(active ? Palette.purple.opacity(0.14) : Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? Palette.purple.opacity(0.35) : Palette.muted.opacity(0.12)))
        }.buttonStyle(.plain).foregroundStyle(Palette.ink)
            .accessibilityAddTraits(active ? .isSelected : [])
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: active)
            .contextMenu {
                if let id, let deck = data.decks.first(where: { $0.id == id }) {
                    Button { editingVocabularyDeck = deck } label: { Label(store.t("Ordner bearbeiten"), systemImage: "pencil") }
                    if deck.parentID == nil {
                        Button { creatingSubfolderFor = deck } label: { Label(store.t("Unterordner erstellen"), systemImage: "folder.badge.plus") }
                    }
                    Button { directionFixCount = store.fixVocabularyDirection(inDeck: deck.id) } label: { Label(store.t("Sprachrichtung prüfen"), systemImage: "arrow.left.arrow.right") }
                    Button(role: .destructive) { requestFolderDeletion(deck) } label: { Label(store.t("Ordner löschen"), systemImage: "trash") }
                }
            }
    }

    private func requestFolderDeletion(_ deck: VocabularyDeck) {
        deletingVocabularyDeck = deck
        confirmingVocabularyDeckDeletion = true
    }

    private func removeFolder(_ deck: VocabularyDeck, includingEntries: Bool) {
        if selectedDeckID == deck.id { selectedDeckID = nil }
        let scope = store.vocabularyScope(deck.id)
        if let selected = selectedDeckID, scope.contains(selected) { selectedDeckID = nil }
        if includingEntries {
            revealed.subtract(store.vocabulary.filter { $0.deckID.map(scope.contains) ?? false }.map(\.id))
        }
        // „Nur Ordner löschen“ behält die Unterordner als eigene Ordner, „mit Vokabeln“ löscht alles darunter.
        store.removeVocabularyDeck(deck.id, deleteEntries: includingEntries, deleteSubfolders: includingEntries)
        deletingVocabularyDeck = nil
    }

    // MARK: Sprachpaar

    private func languagePairMenu(_ data: VocabularyListData) -> some View {
        Menu {
            Section(store.t("Sprachpaare")) {
                ForEach(store.vocabularyLanguagePairs) { option in
                    if let left = store.vocabularyLanguage(option.sourceLanguageID), let right = store.vocabularyLanguage(option.targetLanguageID) {
                        Button {
                            // Mit festem Sprachpaar nur lokal wechseln. Sonst ändert sich die globale Auswahl.
                            // Ordnerauswahl und Aufdeck-Status setzt `onChange(of: data.pair.id)` zurück.
                            if scopedPairID != nil { scopedPairID = option.id }
                            else { store.selectedVocabularyLanguagePairID = option.id }
                        } label: {
                            if option.id == data.pair.id { Label("\(left.name) → \(right.name)", systemImage: "checkmark").font(.caption) }
                            else { Text("\(left.name) → \(right.name)").font(.caption) }
                        }
                    }
                }
            }
            Section {
                Button { showingLanguagePairEditor = true } label: { Label(store.t("Sprachpaar hinzufügen"), systemImage: "arrow.left.arrow.right") }
                Button { showingLanguageEditor = true } label: { Label(store.t("Sprache hinzufügen"), systemImage: "plus") }
            }
        } label: {
            // Textstile statt fester 11 pt: skaliert mit der Systemschriftgröße.
            HStack(spacing: 5) {
                Text(data.sourceCode).font(.caption.bold())
                Image(systemName: "arrow.right").font(.caption2)
                Text(data.targetCode).font(.caption.bold())
                Image(systemName: "chevron.down").font(.caption2)
            }.lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 9).padding(.vertical, 7).background(Palette.lilac, in: Capsule())
        }.accessibilityLabel("\(data.source?.name ?? "Sprache A") → \(data.target?.name ?? "Sprache B")")
    }

    // MARK: Karte

    private func vocabularyCard(_ entry: VocabularyEntry, data: VocabularyListData) -> some View {
        let isRevealed = revealed.contains(entry.id)
        let difficultyLabel = store.t(["Leicht", "Mittel", "Schwer"][min(max(entry.difficulty - 1, 0), 2)])
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Button { toggleReveal(entry.id) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(isRevealed ? entry.translation : entry.term).font(.title3.bold()).foregroundStyle(Palette.ink)
                            if isRevealed {
                                if !entry.pronunciation.isEmpty {
                                    Text(entry.pronunciation).font(.caption.monospaced()).foregroundStyle(Palette.purple)
                                }
                                if !entry.synonyms.isEmpty { Text("\(store.t("Synonyme")): \(entry.synonyms.joined(separator: ", "))").font(.subheadline).foregroundStyle(Palette.muted) }
                                if !entry.example.isEmpty { Text(entry.example).font(.subheadline).foregroundStyle(Palette.muted) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityHint(store.t("Tippen, um die Vorder- oder Rückseite umzuschalten"))
                    VocabularySpeechButton(
                        text: isRevealed ? entry.translation : entry.term,
                        languageCode: languageCode(for: isRevealed, pair: data.pair),
                        label: store.t("Vokabel anhören"),
                        size: .caption
                    )
                    // Das Anpinnen liegt im Menü. Oben bleibt nur ein Hinweis, wenn angepinnt,
                    // und die Menü-Schaltfläche hat die empfohlene Tippfläche von 44 pt.
                    if entry.isPinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(Palette.purple)
                            .padding(.top, 6)
                            .accessibilityLabel(store.t("Angepinnt"))
                    }
                    Menu {
                        Button { editingVocabularyEntry = entry } label: { Label(store.t("Bearbeiten"), systemImage: "pencil") }
                        Button { store.toggleVocabularyPin(entry.id) } label: { Label(store.t(entry.isPinned ? "Lösen" : "Anpinnen"), systemImage: entry.isPinned ? "pin.slash" : "pin") }
                        Button(role: .destructive) { store.removeVocabulary(entry.id) } label: { Label(store.t("Löschen"), systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Palette.muted)
                            .frame(width: 44, height: 32).contentShape(Rectangle())
                    }.accessibilityLabel(store.t("Vokabeloptionen"))
                }
                HStack {
                    HStack(spacing: 3) {
                        ForEach(1...3, id: \.self) { level in
                            Circle().fill(level <= entry.difficulty ? Palette.purple.opacity(0.65) : Palette.muted.opacity(0.2)).frame(width: 5, height: 5)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(store.t("Schwierigkeit")): \(difficultyLabel)")
                    Spacer()
                    Button { toggleReveal(entry.id) } label: {
                        Image(systemName: isRevealed ? "rectangle.on.rectangle" : "eye")
                            .font(.caption.weight(.medium)).foregroundStyle(Palette.muted).frame(width: 44, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(store.t(isRevealed ? "Vorderseite anzeigen" : "Übersetzung anzeigen"))
                }
            }
        }.contextMenu {
            Button { editingVocabularyEntry = entry } label: { Label(store.t("Bearbeiten"), systemImage: "pencil") }
            Button { store.toggleVocabularyPin(entry.id) } label: { Label(store.t(entry.isPinned ? "Lösen" : "Anpinnen"), systemImage: entry.isPinned ? "pin.slash" : "pin") }
            Button(role: .destructive) { store.removeVocabulary(entry.id) } label: { Label(store.t("Löschen"), systemImage: "trash") }
        }
    }

    private func toggleReveal(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if revealed.contains(id) { revealed.remove(id) } else { revealed.insert(id) }
        }
    }

    private func languageCode(for translation: Bool, pair: VocabularyLanguagePair) -> String {
        let languageID = translation ? pair.targetLanguageID : pair.sourceLanguageID
        return store.vocabularyLanguage(languageID)?.code ?? "en"
    }
}
