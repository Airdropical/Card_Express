import SwiftUI

@main
struct WordExpressApp: App {
    @StateObject private var content = ContentStore()
    @StateObject private var profile = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(content)
                .environmentObject(profile)
                .tint(AppDesign.accent)
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("learningLanguage") private var learningLanguage = Language.en.rawValue
    @AppStorage("explanationLanguage") private var explanationLanguage = Language.de.rawValue

    private var learning: Binding<Language> {
        Binding(get: { Language(rawValue: learningLanguage) ?? .en }, set: { learningLanguage = $0.rawValue })
    }
    private var explaining: Binding<Language> {
        Binding(get: { Language(rawValue: explanationLanguage) ?? .de }, set: { explanationLanguage = $0.rawValue })
    }

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(learningLanguage: learning, explanationLanguage: explaining)
            }
            .tabItem { Label("Heute", systemImage: "sun.max") }

            NavigationStack {
                WordListView(learningLanguage: learning, explanationLanguage: explaining)
            }
            .tabItem { Label("Wörter", systemImage: "text.book.closed") }

            NavigationStack {
                QuizView(learningLanguage: learning, explanationLanguage: explaining)
            }
            .tabItem { Label("Quiz", systemImage: "sparkles.rectangle.stack") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .onAppear { syncProfileSettings() }
        .onChange(of: learningLanguage) { _, _ in syncProfileSettings() }
        .onChange(of: explanationLanguage) { _, _ in syncProfileSettings() }
    }

    private func syncProfileSettings() {
        profile.updateLanguageSettings(
            learning: Language(rawValue: learningLanguage) ?? .en,
            explanation: Language(rawValue: explanationLanguage) ?? .de
        )
    }
}

struct HomeView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var profile: ProfileStore
    @Binding var learningLanguage: Language
    @Binding var explanationLanguage: Language

    private var entries: [LemmaEntry] { content.entries.filter { $0.lemma.language == learningLanguage } }
    private var featured: LemmaEntry? { entries.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                languageControls
                HStack(spacing: 12) {
                    MetricCard(value: "\(profile.profile.statsSnapshot.currentStreakDays)", label: "TAGE IN FOLGE", symbol: "flame")
                    MetricCard(value: "\(profile.profile.statsSnapshot.savedLemmaCount)", label: "GESPEICHERT", symbol: "folder")
                    MetricCard(value: "\(profile.profile.statsSnapshot.favoriteLemmaCount)", label: "FAVORITEN", symbol: "heart")
                }
                if let featured, let sense = featured.senses.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Wort für heute")
                        NavigationLink {
                            WordDetailView(entry: featured, initialSense: sense, learningLanguage: learningLanguage, explanationLanguage: explanationLanguage)
                        } label: {
                            WordCard(entry: featured, sense: sense, learningLanguage: learningLanguage, explanationLanguage: explanationLanguage)
                        }
                        .buttonStyle(.plain)
                    }
                }
                GlassCard {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(AppDesign.accent)
                            .frame(width: 46, height: 46)
                            .background(AppDesign.accent.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dein nächster Schritt")
                                .font(.headline)
                            Text("Markiere Wörter für dein persönliches Quiz.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(AppDesign.canvas)
        .navigationTitle("Word Express")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Eyebrow(text: "Deine Wörter. Klar erklärt.")
            Text("Lernen,\nWort für Wort.")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .tracking(-1.2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ein ruhiger Ort für neue Wörter und Bedeutungen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var languageControls: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Ich lerne")
                    Picker("Lernsprache", selection: $learningLanguage) {
                        ForEach(Language.allCases) { language in Text(language.name).tag(language) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.headline)
                }
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Erklärung auf")
                    Picker("Erklärungssprache", selection: $explanationLanguage) {
                        ForEach(Language.allCases) { language in Text(language.name).tag(language) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.headline)
                }
            }
        }
    }
}

struct MetricCard: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        GlassCard(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol).foregroundStyle(AppDesign.accent)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Text(label).font(.caption2.weight(.semibold)).tracking(0.7).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WordListView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var profile: ProfileStore
    @Binding var learningLanguage: Language
    @Binding var explanationLanguage: Language
    @State private var search = ""
    @State private var selectedLevel = "Alle"
    @State private var favoritesOnly = false
    private let levels = ["Alle", "A1", "A2", "B1", "B2", "C1", "C2"]

    private var filtered: [LemmaEntry] {
        content.entries.filter { entry in
            guard entry.lemma.language == learningLanguage else { return false }
            guard selectedLevel == "Alle" || entry.lemma.level == selectedLevel else { return false }
            guard !favoritesOnly || entry.senses.contains(where: { profile.wordState(for: $0.id, lemmaId: entry.lemma.id).favorite }) else { return false }
            return search.isEmpty || entry.lemma.text.localizedCaseInsensitiveContains(search) || entry.senses.contains { $0.shortMeaning.localizedCaseInsensitiveContains(search) || $0.translation.text.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        List {
            Section {
                languageControls
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                HStack(spacing: 8) {
                    Menu {
                        ForEach(levels, id: \.self) { level in
                            Button(level) { selectedLevel = level }
                        }
                    } label: {
                        Label(selectedLevel == "Alle" ? "Alle Niveaus" : selectedLevel, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        Label("Favoriten", systemImage: favoritesOnly ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                    .tint(favoritesOnly ? .pink : nil)
                    Spacer()
                    Text("\(filtered.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if let error = content.loadError {
                ContentUnavailableView("Wortdaten fehlen", systemImage: "exclamationmark.triangle", description: Text(error))
                    .listRowSeparator(.hidden)
            } else if filtered.isEmpty {
                ContentUnavailableView(search.isEmpty ? "Keine Wörter" : "Nichts gefunden", systemImage: "text.book.closed", description: Text("Passe Suche oder Filter an."))
                    .listRowSeparator(.hidden)
            } else {
                Section("Wörter") {
                    ForEach(filtered) { entry in
                        NavigationLink(value: entry.id) {
                            WordListRow(entry: entry, profile: profile)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppDesign.canvas)
        .searchable(text: $search, prompt: "Wort oder Übersetzung")
        .navigationTitle("Wortliste")
        .navigationDestination(for: String.self) { lemmaId in
            if let entry = content.entries.first(where: { $0.lemma.id == lemmaId }), let sense = entry.senses.first {
                WordDetailView(entry: entry, initialSense: sense, learningLanguage: learningLanguage, explanationLanguage: explanationLanguage)
            }
        }
    }

    private var languageControls: some View {
        GlassCard(padding: 14) {
            HStack {
                languagePicker(title: "Lerne", selection: $learningLanguage)
                Spacer()
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.tertiary)
                Spacer()
                languagePicker(title: "Erklärung", selection: $explanationLanguage)
            }
        }
    }

    private func languagePicker(title: String, selection: Binding<Language>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(text: title)
            Picker(title, selection: selection) {
                ForEach(Language.allCases) { language in Text(language.name).tag(language) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

struct WordListRow: View {
    let entry: LemmaEntry
    @ObservedObject var profile: ProfileStore

    private var firstSense: Sense? { entry.senses.first }
    private var isFavorite: Bool { entry.senses.contains { profile.wordState(for: $0.id, lemmaId: entry.lemma.id).favorite } }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.lemma.text).font(.headline)
                if let firstSense { Text(firstSense.shortMeaning).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            LevelBadge(level: entry.lemma.level)
            if isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink) }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
