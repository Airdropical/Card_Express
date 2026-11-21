import SwiftUI

struct CardSearchView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [CardSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.decks.flatMap { deck in
            deck.cards.compactMap { card in
                guard needle.isEmpty || deck.name.localizedCaseInsensitiveContains(needle) || card.question.localizedCaseInsensitiveContains(needle) || card.answer.localizedCaseInsensitiveContains(needle) else { return nil }
                return CardSearchResult(deck: deck, card: card)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty {
                    ContentUnavailableView(store.t(query.isEmpty ? "Noch keine Karten" : "Keine Treffer"), systemImage: "magnifyingglass", description: Text(store.t(query.isEmpty ? "Erstelle oder importiere Karten, um sie hier zu durchsuchen." : "Versuche einen anderen Suchbegriff.")))
                } else {
                    ForEach(results) { item in
                        NavigationLink { DeckDetailView(deckID: item.deck.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.card.question).font(.headline).foregroundStyle(Palette.ink)
                                Text(item.card.answer).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(2)
                                Label("\(item.deck.emoji)  \(item.deck.name)", systemImage: "rectangle.stack").font(.caption).foregroundStyle(Palette.purple)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: store.t("Karten, Antworten oder Decks suchen"))
            .scrollContentBackground(.hidden).background(Palette.canvas)
            .navigationTitle(store.t("Karte suchen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Schließen")) { dismiss() } } }
        }
    }
}

private struct CardSearchResult: Identifiable {
    var deck: Deck
    var card: Flashcard
    var id: UUID { card.id }
}
