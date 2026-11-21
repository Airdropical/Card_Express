import SwiftUI

struct DeckDetailView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    var onDeckDeleted: (() -> Void)? = nil
    var onDeckOpened: ((UUID) -> Void)? = nil
    @State private var studySetupMode: StudyMode?
    @State private var pendingSession: StudySessionConfiguration?
    @State private var activeSession: StudySessionConfiguration?
    @State private var showingEditor: Flashcard?
    @State private var showingSubdeck = false
    @State private var showingGoal = false
    @State private var showingSummary = false
    @State private var showingAIImport = false
    @State private var confirmingDelete = false
    @State private var openedDeckID: UUID?
    private var deck: Deck? { store.decks.first { $0.id == deckID } }

    var body: some View {
        Group {
            if let deck {
                ScrollView {
                    // Lazy: Bei großen Decks werden nur die sichtbaren Kartenzeilen gebaut.
                    LazyVStack(spacing: 16) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Text("\(deck.emoji)  \(deck.name)").font(.title2.bold()); Spacer(); Button { showingGoal = true } label: { Image(systemName: "pencil").foregroundStyle(Palette.purple).padding(10).background(Palette.lilac, in: Circle()) }.accessibilityLabel(store.t("Deck und Lernziel bearbeiten")) }
                                Text(store.tf("%d Karten", deck.cards.count)).font(.subheadline).foregroundStyle(Palette.muted)
                                HStack(spacing: 16) {
                                    ZStack { Circle().stroke(Palette.lilac, lineWidth: 8); Circle().trim(from: 0, to: progress(deck)).stroke(Palette.purple, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)); VStack(spacing: 1) { Text("\(Int(progress(deck) * 100)) %").font(.headline); Text(store.t("Wissen")).font(.caption).foregroundStyle(Palette.muted) } }.frame(width: 82, height: 82)
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let date = deck.examDate { Label(store.tf("Prüfung in %d Tagen", daysUntil(date)), systemImage: "calendar").font(.subheadline) }
                                        Label(store.tf("%d Karten heute zu wiederholen", deck.cards.filter(\.dueToday).count), systemImage: "rectangle.stack").font(.subheadline)
                                        if let grade = deck.targetGrade { Label(store.tf("Wunschnote: %0.1f", grade), systemImage: "scope").font(.subheadline) }
                                    }
                                }
                                if !deck.cards.isEmpty { Button { studySetupMode = .review } label: { Label(store.tf("Lernen · %d Fragen", min(store.sessionSize, deck.cards.count)), systemImage: "play.fill") }.buttonStyle(PrimaryButtonStyle()) }
                            }
                        }
                        if deck.examDate != nil { goalPlan(deck) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                Button { showingSummary = true } label: { Label(store.t("Zusammenfassung"), systemImage: "text.alignleft").fixedSize(horizontal: true, vertical: false).padding(.horizontal, 15).padding(.vertical, 13).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 13)) }.foregroundStyle(Palette.purple)
                                Button { studySetupMode = .exam } label: { Label(store.t("Probeprüfung"), systemImage: "graduationcap").fixedSize(horizontal: true, vertical: false).padding(.horizontal, 15).padding(.vertical, 13).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 13)) }.foregroundStyle(Palette.purple).disabled(deck.cards.isEmpty)
                            }.font(.subheadline.weight(.semibold))
                        }
                        HStack { Text(store.t("Unterdecks")).font(.headline); Spacer(); Button { showingSubdeck = true } label: { Label(store.t("Erstellen"), systemImage: "plus").font(.subheadline).foregroundStyle(Palette.purple) } }
                        ForEach(store.children(of: deckID)) { child in
                            NavigationLink { DeckDetailView(deckID: child.id, onDeckDeleted: onDeckDeleted, onDeckOpened: onDeckOpened) } label: { SurfaceCard { HStack(spacing: 12) { RoundedRectangle(cornerRadius: 3).fill(Palette.deckAccent(child.accentColor)).frame(width: 5, height: 34); Text(child.name).foregroundStyle(Palette.ink); Spacer(); Text(store.tf("%d Karten", child.cards.count)).font(.caption).foregroundStyle(Palette.muted); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted) } } }.buttonStyle(.plain)
                        }
                        if store.children(of: deckID).isEmpty { Text(store.t("Erstelle Unterdecks, um Lerninhalte zu ordnen.")).font(.subheadline).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading) }
                        HStack { Text(store.t("Karteikarten")).font(.headline); Spacer(); Button { showingEditor = Flashcard(question: "", answer: "") } label: { Label(store.t("Karte"), systemImage: "plus") }.foregroundStyle(Palette.purple); Button { showingAIImport = true } label: { Image(systemName: "sparkles") }.foregroundStyle(Palette.purple).accessibilityLabel(store.t("KI-Karteikarten erstellen")) }
                        ForEach(deck.cards) { card in
                            DeckFlashcardRow(card: card) { showingEditor = card }
                        }
                    }.padding(18)
                }.background(Palette.canvas)
                    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                    .sheet(item: $studySetupMode, onDismiss: {
                        if let pendingSession {
                            activeSession = pendingSession
                            self.pendingSession = nil
                        }
                    }) { mode in
                        StudySessionSetupSheet(mode: mode, defaultUseAI: store.aiEvaluation) { useAI in
                            pendingSession = StudySessionConfiguration(mode: mode, useAI: useAI)
                            studySetupMode = nil
                        }
                    }
                    .fullScreenCover(item: $activeSession) { session in
                        StudySessionView(deckID: deckID, mode: session.mode, useAI: session.useAI)
                    }
                    .navigationDestination(isPresented: Binding(get: { openedDeckID != nil }, set: { if !$0 { openedDeckID = nil } })) {
                        if let openedDeckID { DeckDetailView(deckID: openedDeckID) }
                    }
                    .sheet(item: $showingEditor) { card in CardEditorSheet(deckID: deckID, card: card) }
                    .sheet(isPresented: $showingSubdeck) { NewDeckSheet(parentID: deckID) }
                    .sheet(isPresented: $showingGoal) { if let current = store.decks.first(where: { $0.id == deckID }) { DeckGoalSheet(deck: current) } }
                    .sheet(isPresented: $showingSummary) { if let current = store.decks.first(where: { $0.id == deckID }) { DeckSummarySheet(deck: current) } }
                    .sheet(isPresented: $showingAIImport) { AIImportView(initialDeckID: deckID) { savedDeckID in
                        showingAIImport = false
                        guard savedDeckID != deckID else { return }
                        if let onDeckOpened { onDeckOpened(savedDeckID) }
                        else { openedDeckID = savedDeckID }
                    } }
                    .confirmationDialog(store.t("Deck löschen?"), isPresented: $confirmingDelete, titleVisibility: .visible) { Button(store.t("Deck und Unterdecks löschen"), role: .destructive) { store.removeDeck(deckID); returnToDecks() }; Button(store.t("Abbrechen"), role: .cancel) {} } message: { Text(store.t("Alle Karten und Unterdecks dieses Decks werden entfernt.")) }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button { showingSubdeck = true } label: { Label(store.t("Unterdeck erstellen"), systemImage: "folder.badge.plus") }; Button { showingGoal = true } label: { Label(store.t("Deck und Lernziel bearbeiten"), systemImage: "pencil") }; Button(role: .destructive) { confirmingDelete = true } label: { Label(store.t("Deck löschen"), systemImage: "trash") } } label: { Image(systemName: "ellipsis.circle") } } }
            } else { ContentUnavailableView(store.t("Deck nicht gefunden"), systemImage: "rectangle.stack") }
        }
        .onChange(of: deck == nil) { _, missing in if missing { returnToDecks() } }
    }

    private func returnToDecks() {
        if let onDeckDeleted { onDeckDeleted() } else { dismiss() }
    }

    private func progress(_ deck: Deck) -> CGFloat {
        guard !deck.cards.isEmpty else { return 0 }
        return CGFloat(deck.cards.filter { !$0.dueToday }.count) / CGFloat(deck.cards.count)
    }
    private func daysUntil(_ date: Date) -> Int { max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0, 0) }
    private func goalPlan(_ deck: Deck) -> some View {
        let unseen = deck.cards.filter { $0.timesSeen == 0 }.count
        let remainingDays = max(daysUntil(deck.examDate ?? Date()) - deck.newCardsStopDaysBeforeExam, 1)
        let daily = Int(ceil(Double(unseen) / Double(remainingDays)))
        return SurfaceCard { VStack(alignment: .leading, spacing: 7) { Label(store.t("Dein Lernplan"), systemImage: "calendar.badge.clock").font(.headline); Text(store.tf("Letzte neue Karte: %d Tage vorher", deck.newCardsStopDaysBeforeExam)).font(.subheadline); Text(store.tf("Noch %d neue Karten · etwa %d pro Lerntag", unseen, daily)).font(.subheadline).foregroundStyle(Palette.muted); if let grade = deck.targetGrade { Text(store.tf("Ziel: Note %0.1f", grade)).font(.subheadline).foregroundStyle(Palette.purple) } }.frame(maxWidth: .infinity, alignment: .leading) }
    }
}

private struct DeckFlashcardRow: View {
    @Environment(LearningStore.self) private var store
    let card: Flashcard
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            SurfaceCard {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.question)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !card.dueToday, let nextDue = card.nextDue {
                            Text(store.t("Wieder fällig am") + " " + nextDue.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer(minLength: 8)
                    if card.dueToday {
                        Text(store.t("Fällig"))
                            .font(.caption.bold())
                            .foregroundStyle(Palette.purple)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Palette.lilac, in: Capsule())
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.question)
        .accessibilityHint(store.t("Doppeltippen, um Karte zu bearbeiten"))
    }
}
