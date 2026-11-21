import SwiftUI

struct DecksView: View {
    @Environment(LearningStore.self) private var store
    @Binding var openDeckID: UUID?
    @State private var showNewDeck = false
    @State private var search = ""
    @State private var path: [UUID] = []
    private var visibleDecks: [Deck] { store.decks.filter { $0.parentID == nil && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text(store.t("Deine Decks")).font(.largeTitle.bold()); Spacer(); Button { showNewDeck = true } label: { Image(systemName: "plus").font(.headline).padding(12).background(Palette.lilac, in: Circle()) }.accessibilityLabel(store.t("Deck erstellen")) }
                    HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted); TextField(store.t("Deck suchen"), text: $search) }.padding(13).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    ForEach(visibleDecks) { deck in
                        NavigationLink(value: deck.id) {
                            SurfaceCard { HStack(spacing: 14) { RoundedRectangle(cornerRadius: 3).fill(Palette.deckAccent(deck.accentColor)).frame(width: 5, height: 48); Text(deck.emoji).font(.title2); VStack(alignment: .leading, spacing: 5) { Text(deck.name).font(.headline).foregroundStyle(Palette.ink); Text(store.tf("%d Karten · %d Decks", deck.cards.count, store.children(of: deck.id).count) + (deck.examDate.map { " · \(store.t("Prüfung")) \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")).font(.subheadline).foregroundStyle(Palette.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Palette.muted) } }
                        }.buttonStyle(.plain)
                    }
                    if visibleDecks.isEmpty { ContentUnavailableView(store.t("Noch keine Decks"), systemImage: "rectangle.stack", description: Text(store.t("Erstelle ein Deck oder generiere Karten aus deinem Lernmaterial."))) }
                    // Der große Knopf erscheint nur, solange es noch keine Decks gibt; sonst genügt das Plus oben.
                    if store.decks.isEmpty { Button { showNewDeck = true } label: { Label(store.t("Neues Deck"), systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle()) }
                }.padding(18)
            }.background(Palette.canvas).toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { id in
                    DeckDetailView(deckID: id, onDeckDeleted: { path = [] }, onDeckOpened: { targetID in path = [targetID] })
                }
                .onChange(of: openDeckID) { _, deckID in
                    guard let deckID else { return }
                    path = [deckID]
                    openDeckID = nil
                }
            .sheet(isPresented: $showNewDeck) { NewDeckSheet() }
        }
    }
}

struct NewDeckSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "📚"
    @State private var accentColor = "purple"
    @State private var parentID: UUID?
    private let emojis = ["📚", "👋", "🧪", "🧬", "🌍", "📐", "🎨", "💡", "🗣️", "💻", "🪴", "⭐️", "🧠", "🎓", "📝", "🔬", "🌱", "⚡️"]
    init(parentID: UUID? = nil) { _parentID = State(initialValue: parentID) }
    var body: some View {
        NavigationStack { Form {
            TextField(store.t("Deckname"), text: $name).textInputAutocapitalization(.sentences)
            Section(store.t("Deckfarbe")) { deckColorPicker }
            Section(store.t("Emoji")) { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) { ForEach(emojis, id: \.self) { item in Button { emoji = item } label: { Text(item).font(.title2).frame(maxWidth: .infinity).padding(8).background(emoji == item ? Palette.lilac : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) } } }
            Section(store.t("Unterdeck")) { Picker(store.t("Gehört zu"), selection: $parentID) { Text(store.t("Kein übergeordnetes Deck")).tag(nil as UUID?); ForEach(store.decks) { deck in Text("\(deck.emoji)  \(deck.name)").tag(Optional(deck.id)) } } }
        }
            .navigationTitle(store.t("Neues Deck")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(store.t("Erstellen")) { store.addDeck(name: name, emoji: emoji, parentID: parentID, accentColor: accentColor); dismiss() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) } }
        }.presentationDetents([.medium])
    }

    private var deckColorPicker: some View {
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
}
