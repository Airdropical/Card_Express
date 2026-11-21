import SwiftUI

/// Ziele innerhalb der App. Decks, Vokabeln und Begriffe liegen gemeinsam im Tab „Lernen“.
enum AppTab: Hashable { case home, decks, vocabulary, terms, math, feed, more }

/// Die fünf Plätze der Tab-Leiste.
private enum TabSlot: Hashable { case home, learn, math, feed, more }

enum LearnSection: String, CaseIterable, Identifiable {
    case decks, vocabulary, terms
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .decks: return "Decks"
        case .vocabulary: return "Vokabeln"
        case .terms: return "Begriffe"
        }
    }
    var tab: AppTab {
        switch self {
        case .decks: return .decks
        case .vocabulary: return .vocabulary
        case .terms: return .terms
        }
    }
}

struct MainTabsView: View {
    @Environment(LearningStore.self) private var store
    @State private var tab: AppTab = .home
    @State private var learnSection: LearnSection = .decks
    @State private var moreDestination: MoreDestination?
    @State private var openDeckID: UUID?

    private var slot: Binding<TabSlot> {
        Binding(get: {
            switch tab {
            case .home: return .home
            case .decks, .vocabulary, .terms: return .learn
            case .math: return .math
            case .feed: return .feed
            case .more: return .more
            }
        }, set: { newSlot in
            switch newSlot {
            case .home: tab = .home
            case .learn: tab = learnSection.tab
            case .math: tab = .math
            case .feed: tab = .feed
            case .more: tab = .more
            }
        })
    }

    var body: some View {
        TabView(selection: slot) {
            HomeView(tab: $tab, openAI: { moreDestination = .ai }, openDeck: { deckID in
                tab = .decks
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openDeckID = deckID }
            }).tabItem { Label(store.t("Heute"), systemImage: "house") }.tag(TabSlot.home)
            LearnView(section: $learnSection, openDeckID: $openDeckID)
                .tabItem { Label(store.t("Lernen"), systemImage: "rectangle.stack") }.tag(TabSlot.learn)
            MathView().tabItem { Label(store.t("Mathe"), systemImage: "function") }.tag(TabSlot.math)
            FeedView().tabItem { Label(store.t("Feed"), systemImage: "rectangle.stack.badge.play") }.tag(TabSlot.feed)
            MoreHubView(destination: $moreDestination) { deckID in
                tab = .decks
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openDeckID = deckID }
            }.tabItem { Label(store.t("Mehr"), systemImage: "ellipsis") }.tag(TabSlot.more)
        }
        .tint(Palette.purple)
        // Ein Sprung zu Decks, Vokabeln oder Begriffe (z. B. vom Home-Bildschirm) wählt den passenden Bereich.
        .onChange(of: tab) { _, newTab in
            if let section = LearnSection.allCases.first(where: { $0.tab == newTab }) { learnSection = section }
        }
    }
}

/// Decks, Vokabeln und Begriffe unter einem Tab, umschaltbar oben.
private struct LearnView: View {
    @Environment(LearningStore.self) private var store
    @Binding var section: LearnSection
    @Binding var openDeckID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Picker(store.t("Bereich"), selection: $section) {
                ForEach(LearnSection.allCases) { item in Text(store.t(item.titleKey)).tag(item) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 4)
            Group {
                switch section {
                case .decks: DecksView(openDeckID: $openDeckID)
                case .vocabulary: VocabularyView()
                case .terms: TermsView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Palette.canvas)
    }
}

enum MoreDestination: String, Identifiable {
    case calendar, ai, tutor, settings
    var id: String { rawValue }
}

private struct MoreHubView: View {
    @Environment(LearningStore.self) private var store
    @Binding var destination: MoreDestination?
    let onOpenDeck: (UUID) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section(store.t("Planung")) {
                    Button { destination = .calendar } label: { Label(store.t("Kalender"), systemImage: "calendar") }
                }
                Section(store.t("Lernwerkzeuge")) {
                    Button { destination = .ai } label: { Label(store.t("KI-Karteikarten"), systemImage: "sparkles") }
                    Button { destination = .tutor } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Eulio")
                                Text(store.t("Dein KI-Tutor")).font(.caption).foregroundStyle(Palette.muted)
                            }
                        } icon: { Image(systemName: "bubble.left.and.bubble.right") }
                    }
                }
                Section(store.t("App")) {
                    Button { destination = .settings } label: { Label(store.t("Einstellungen"), systemImage: "gearshape") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle(store.t("Mehr"))
            .sheet(item: $destination) { item in
                switch item {
                case .calendar: CalendarView()
                case .ai: AIImportView { deckID in
                    destination = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onOpenDeck(deckID) }
                }
                case .tutor: AssistantChatView()
                case .settings: SettingsView()
                }
            }
        }
    }
}
