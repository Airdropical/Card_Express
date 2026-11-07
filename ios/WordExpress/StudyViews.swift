import AVFoundation
import SwiftUI

struct WordCard: View {
    let entry: LemmaEntry
    let sense: Sense
    let learningLanguage: Language
    let explanationLanguage: Language

    private var explanation: Explanation? { sense.explanations.first { $0.explanationLanguage == explanationLanguage } ?? sense.explanations.first }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LevelBadge(level: entry.lemma.level)
                    Text(entry.lemma.wordClass.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.medium)).foregroundStyle(.tertiary)
                }
                Text(entry.lemma.text)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.primary)
                if learningLanguage != explanationLanguage {
                    Label(sense.translation.text, systemImage: "arrow.left.arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppDesign.accent)
                }
                if let explanation {
                    Text(explanation.definition)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WordDetailView: View {
    let entry: LemmaEntry
    let learningLanguage: Language
    let explanationLanguage: Language
    @EnvironmentObject private var profile: ProfileStore
    @State private var selectedSenseId: String
    @State private var showingQuizSettings = false
    @State private var showSpeechError = false
    private let speech = AVSpeechSynthesizer()

    init(entry: LemmaEntry, initialSense: Sense, learningLanguage: Language, explanationLanguage: Language) {
        self.entry = entry
        self.learningLanguage = learningLanguage
        self.explanationLanguage = explanationLanguage
        _selectedSenseId = State(initialValue: initialSense.id)
    }

    private var sense: Sense { entry.senses.first(where: { $0.id == selectedSenseId }) ?? entry.senses[0] }
    private var explanation: Explanation? { sense.explanations.first { $0.explanationLanguage == explanationLanguage } ?? sense.explanations.first }
    private var state: ProfileWordState { profile.wordState(for: sense.id, lemmaId: entry.lemma.id) }
    private var article: String? { sense.article ?? entry.lemma.article }
    private var plural: String? { sense.plural ?? entry.lemma.plural }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            LevelBadge(level: entry.lemma.level)
                            Text(entry.lemma.wordClass.capitalized).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("Bedeutung \((entry.senses.firstIndex(where: { $0.id == sense.id }) ?? 0) + 1) / \(entry.senses.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(entry.lemma.text)
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .tracking(-1)
                            Button(action: speak) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.title3)
                                    .foregroundStyle(AppDesign.accent)
                            }
                            .accessibilityLabel("Wort aussprechen")
                        }
                        if let article { Text("Artikel: \(article)").font(.subheadline).foregroundStyle(.secondary) }
                        if let plural { Text("Plural: \(plural)").font(.subheadline).foregroundStyle(.secondary) }
                        if entry.senses.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(entry.senses) { item in
                                        Button {
                                            selectedSenseId = item.id
                                        } label: {
                                            Text(item.shortMeaning)
                                                .font(.caption.weight(.medium))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(item.id == sense.id ? AppDesign.accent.opacity(0.14) : Color.primary.opacity(0.05), in: Capsule())
                                                .foregroundStyle(item.id == sense.id ? AppDesign.accent : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                if learningLanguage != explanationLanguage {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "Übersetzung · \(sense.translation.language.name)")
                            Text(sense.translation.text).font(.title2.weight(.semibold))
                            if let alternatives = sense.translation.alternatives, !alternatives.isEmpty {
                                Text("Auch: \(alternatives.joined(separator: ", "))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let explanation {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "Einfach erklärt · \(explanation.level)")
                                Text(explanation.definition).font(.body).fixedSize(horizontal: false, vertical: true)
                            }
                            if let memory = explanation.memoryAid, !memory.isEmpty {
                                DetailNote(title: "Merkhilfe", text: memory, symbol: "lightbulb")
                            }
                            if let confusion = explanation.confusion, !confusion.isEmpty {
                                DetailNote(title: "Nicht verwechseln", text: confusion, symbol: "arrow.left.arrow.right")
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow(text: "Beispiele")
                                ForEach(Array(explanation.examples.enumerated()), id: \.offset) { _, example in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(example.sentence).font(.body.weight(.medium))
                                        if let translation = example.translation {
                                            Text(translation).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                actionControls
                if showSpeechError { Text("Die Sprachausgabe ist derzeit nicht verfügbar.").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(20)
        }
        .background(AppDesign.canvas)
        .navigationTitle(entry.lemma.text)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingQuizSettings) {
            QuizSettingsSheet(state: state, lemmaId: entry.lemma.id, senseId: sense.id)
                .environmentObject(profile)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var actionControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    profile.toggleFavorite(senseId: sense.id, lemmaId: entry.lemma.id)
                } label: {
                    Label(state.favorite ? "Favorisiert" : "Favorit", systemImage: state.favorite ? "heart.fill" : "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(state.favorite ? .pink : AppDesign.accent)

                Menu {
                    if profile.profile.folders.isEmpty {
                        Text("Erstelle zuerst einen Ordner im Profil.")
                    }
                    ForEach(profile.profile.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                        Button {
                            profile.toggleFolder(folder, senseId: sense.id, lemmaId: entry.lemma.id)
                        } label: {
                            Label(folderMenuTitle(folder), systemImage: state.savedInFolderIds.contains(folder.folderId) ? "checkmark.circle.fill" : "folder")
                        }
                    }
                } label: {
                    Label(state.isSaved ? "Gespeichert" : "Ordner", systemImage: state.isSaved ? "folder.fill" : "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppDesign.accent)
            }
            HStack(spacing: 10) {
                Button {
                    profile.toggleQuiz(senseId: sense.id, lemmaId: entry.lemma.id)
                } label: {
                    Label(state.quiz.enabled ? "Im Quiz" : "Zum Quiz", systemImage: state.quiz.enabled ? "checkmark.circle.fill" : "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { showingQuizSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Quiz-Kategorien und Schwierigkeit einstellen")
            }
        }
    }

    private func folderMenuTitle(_ folder: WordFolder) -> String {
        guard let parentId = folder.parentFolderId, let parent = profile.profile.folders.first(where: { $0.folderId == parentId }) else { return folder.name }
        return "\(parent.name) / \(folder.name)"
    }

    private func speak() {
        let utterance = AVSpeechUtterance(string: entry.lemma.text)
        utterance.voice = AVSpeechSynthesisVoice(language: entry.lemma.language.rawValue == "de" ? "de-DE" : "en-US")
        speech.speak(utterance)
    }
}

struct DetailNote: View {
    let title: String
    let text: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(AppDesign.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct QuizSettingsSheet: View {
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let state: ProfileWordState
    let lemmaId: String
    let senseId: String
    @State private var difficulty: Int
    @State private var categoriesText: String

    init(state: ProfileWordState, lemmaId: String, senseId: String) {
        self.state = state
        self.lemmaId = lemmaId
        self.senseId = senseId
        _difficulty = State(initialValue: state.quiz.difficulty ?? 3)
        _categoriesText = State(initialValue: state.quiz.categories.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quiz") {
                    Picker("Schwierigkeit", selection: $difficulty) {
                        ForEach(1...5, id: \.self) { Text("Stufe \($0)").tag($0) }
                    }
                    TextField("Kategorien, durch Komma getrennt", text: $categoriesText, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text("Das Quiz verwendet dieselbe Bedeutung und dasselbe Beispielmaterial wie die Wortkarte.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Quiz anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        profile.setDifficulty(difficulty, senseId: senseId, lemmaId: lemmaId)
                        profile.setCategories(categoriesText.split(separator: ",").map(String.init), senseId: senseId, lemmaId: lemmaId)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QuizView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var profile: ProfileStore
    @Binding var learningLanguage: Language
    @Binding var explanationLanguage: Language
    @State private var currentSenseId: String?
    @State private var revealed = false
    @State private var selectedCategory = "Alle"

    private var candidates: [(LemmaEntry, Sense)] {
        let categoryStates = Dictionary(uniqueKeysWithValues: profile.profile.wordStates.map { ($0.senseId, $0) })
        return profile.quizCandidates(from: content)
            .filter { entry, sense in
                guard entry.lemma.language == learningLanguage else { return false }
                guard selectedCategory == "Alle" else { return categoryStates[sense.id]?.quiz.categories.contains(selectedCategory) == true }
                return true
            }
            .sorted { left, right in
                let leftDifficulty = profile.wordState(for: left.1.id, lemmaId: left.0.lemma.id).quiz.difficulty ?? 3
                let rightDifficulty = profile.wordState(for: right.1.id, lemmaId: right.0.lemma.id).quiz.difficulty ?? 3
                return leftDifficulty < rightDifficulty
            }
    }

    private var candidate: (LemmaEntry, Sense)? {
        if let currentSenseId, let selected = candidates.first(where: { $0.1.id == currentSenseId }) { return selected }
        return candidates.first
    }

    private var categories: [String] {
        ["Alle"] + Array(Set(profile.profile.wordStates.filter { $0.quiz.enabled }.flatMap { $0.quiz.categories })).sorted()
    }

    var body: some View {
        Group {
            if let candidate {
                quizCard(candidate.0, sense: candidate.1)
            } else {
                ContentUnavailableView {
                    Label("Noch kein Quiz-Set", systemImage: "sparkles.rectangle.stack")
                } description: {
                    Text("Füge Wörter über die Wortkarte zu deinem Quiz hinzu.")
                } actions: {
                    Text("Öffne einen Eintrag in der Wortliste und tippe auf „Zum Quiz“.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .background(AppDesign.canvas)
        .navigationTitle("Dein Quiz")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(categories, id: \.self) { category in Button(category) { selectedCategory = category; nextQuestion() } }
                } label: {
                    Label(selectedCategory, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onChange(of: learningLanguage) { _, _ in nextQuestion() }
    }

    private func quizCard(_ entry: LemmaEntry, sense: Sense) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Eyebrow(text: selectedCategory == "Alle" ? "Dein Wortschatz" : selectedCategory)
                    Spacer()
                    LevelBadge(level: entry.lemma.level)
                    Text("\(profile.wordState(for: sense.id, lemmaId: entry.lemma.id).quiz.difficulty ?? 3)/5")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(entry.lemma.text)
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .tracking(-1)
                        Text(sense.shortMeaning).font(.subheadline).foregroundStyle(.secondary)
                        if revealed {
                            Divider()
                            Text(sense.translation.text).font(.title2.weight(.semibold)).foregroundStyle(AppDesign.accent)
                            if let explanation = sense.explanations.first(where: { $0.explanationLanguage == explanationLanguage }) {
                                Text(explanation.definition).font(.body)
                                ForEach(Array(explanation.examples.prefix(1).enumerated()), id: \.offset) { _, example in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(example.sentence).font(.subheadline.weight(.medium))
                                        if let translation = example.translation { Text(translation).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        } else {
                            Text("Wie lautet die Bedeutung?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if revealed {
                    HStack(spacing: 12) {
                        Button { answer(entry, sense: sense, correct: false) } label: {
                            Label("Nochmal", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button { answer(entry, sense: sense, correct: true) } label: {
                            Label("Gewusst", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button { withAnimation(.spring(duration: 0.25)) { revealed = true } } label: {
                        Text("Antwort anzeigen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("\(candidates.count) Wörter in diesem Quiz")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    private func answer(_ entry: LemmaEntry, sense: Sense, correct: Bool) {
        profile.recordPractice(senseId: sense.id, lemmaId: entry.lemma.id, correct: correct)
        nextQuestion()
    }

    private func nextQuestion() {
        revealed = false
        let pool = candidates
        guard !pool.isEmpty else { currentSenseId = nil; return }
        if pool.count < 2 { currentSenseId = pool.first?.1.id; return }
        currentSenseId = pool.first(where: { $0.1.id != currentSenseId })?.1.id ?? pool.first?.1.id
    }
}

struct ProfileView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var content: ContentStore
    @State private var showingFolderEditor = false
    @State private var parentFolderId: String?
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var serverURL = ""
    @State private var creatingAccount = false
    @State private var isSubmitting = false
    @State private var accountError: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingDeletePassword = false
    @State private var deletePassword = ""

    private var stats: ProfileStats { profile.profile.statsSnapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Dein Fortschritt")
                    Text("Profil")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .tracking(-0.8)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Tages-Streak", value: "\(stats.currentStreakDays) Tage", symbol: "flame")
                    StatTile(title: "Längste Streak", value: "\(stats.longestStreakDays) Tage", symbol: "bolt")
                    StatTile(title: "Gespeicherte Wörter", value: "\(stats.savedLemmaCount)", symbol: "folder")
                    StatTile(title: "Favoriten", value: "\(stats.favoriteLemmaCount)", symbol: "heart")
                    StatTile(title: "Im Quiz", value: "\(stats.quizLemmaCount)", symbol: "sparkles")
                    StatTile(title: "Übungen", value: "\(stats.totalPracticeCount)", symbol: "checkmark.circle")
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Deine Ordner").font(.title3.weight(.semibold))
                            Text("Hauptordner und Unterordner für gespeicherte Wörter.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { parentFolderId = nil; showingFolderEditor = true } label: {
                            Image(systemName: "plus").font(.headline).frame(width: 38, height: 38)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Ordner hinzufügen")
                    }
                    if profile.profile.folders.isEmpty {
                        GlassCard(padding: 18) {
                            Text("Lege einen Ordner an, um Wörter thematisch zu sammeln.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        GlassCard(padding: 8) {
                            VStack(spacing: 0) {
                                ForEach(profile.profile.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                                    FolderRow(folder: folder, profile: profile)
                                    if folder.id != profile.profile.folders.last?.id { Divider().padding(.leading, 46) }
                                }
                            }
                        }
                    }
                }
                accountSection
            }
            .padding(20)
        }
        .background(AppDesign.canvas)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFolderEditor) {
            FolderEditorView(parentFolderId: parentFolderId)
                .environmentObject(profile)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSubfolderRequested)) { notification in
            parentFolderId = notification.object as? String
            showingFolderEditor = true
        }
        .onAppear { serverURL = profile.apiServerURL }
        .alert("Konto", isPresented: Binding(get: { accountError != nil }, set: { if !$0 { accountError = nil } })) {
            Button("OK", role: .cancel) { accountError = nil }
        } message: { Text(accountError ?? "") }
        .confirmationDialog("Konto und Cloud-Daten löschen?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Weiter", role: .destructive) { showingDeletePassword = true }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Dein Konto und das synchronisierte Profil werden dauerhaft gelöscht. Die lokale App wird anschließend zurückgesetzt.")
        }
        .sheet(isPresented: $showingDeletePassword) {
            deleteAccountSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var accountSection: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: profile.accountEmail == nil ? "Cloud-Synchronisierung" : "Konto verbunden")
                TextField("https://dein-service.up.railway.app", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Serveradresse speichern") {
                    profile.setAPIServerURL(serverURL)
                    content.reloadFromConfiguredServer()
                }
                .font(.caption.weight(.semibold))
                .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let accountEmail = profile.accountEmail {
                    Label(accountEmail, systemImage: "person.crop.circle.fill")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        if profile.isSyncing { ProgressView().controlSize(.small) }
                        Text(profile.syncStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await profile.synchronizeNow() }
                    } label: {
                        Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(profile.isSyncing)
                    HStack {
                        Button("Abmelden") { profile.signOut() }
                        Spacer()
                        Button("Konto löschen", role: .destructive) { showingDeleteConfirmation = true }
                    }
                    .font(.footnote.weight(.medium))
                } else {
                    Text("Ohne Anmeldung bleiben deine Daten lokal. Melde dich an, um sie zwischen Geräten zu synchronisieren.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("E-Mail-Adresse", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    SecureField("Passwort (mindestens 12 Zeichen)", text: $password)
                        .textContentType(creatingAccount ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)
                    if creatingAccount {
                        SecureField("Einladungscode", text: $inviteCode)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(.roundedBorder)
                        if let base = URL(string: serverURL), let privacyURL = URL(string: "/privacy", relativeTo: base) {
                            Link("Datenschutzhinweise", destination: privacyURL)
                                .font(.caption.weight(.medium))
                        }
                    }
                    Button {
                        Task { await submitAccountAction() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(creatingAccount ? "Konto erstellen" : "Anmelden")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (creatingAccount && inviteCode.isEmpty))
                    Button(creatingAccount ? "Ich habe schon ein Konto" : "Ein Konto erstellen") {
                        creatingAccount.toggle()
                        accountError = nil
                    }
                    .font(.caption.weight(.medium))
                }
            }
        }
    }

    private var deleteAccountSheet: some View {
        NavigationStack {
            Form {
                Section("Zur Bestätigung") {
                    SecureField("Passwort", text: $deletePassword)
                        .textContentType(.password)
                }
                Section {
                    Button("Konto und Daten endgültig löschen", role: .destructive) {
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            do {
                                try await profile.deleteAccount(password: deletePassword)
                                showingDeletePassword = false
                                deletePassword = ""
                            } catch { accountError = error.localizedDescription }
                        }
                    }
                    .disabled(deletePassword.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Konto löschen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showingDeletePassword = false } } }
        }
    }

    @MainActor
    private func submitAccountAction() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if creatingAccount {
                try await profile.registerAccount(email: email, password: password, inviteCode: inviteCode)
            } else {
                try await profile.login(email: email, password: password)
            }
            password = ""
            inviteCode = ""
        } catch { accountError = error.localizedDescription }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(AppDesign.accent)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FolderRow: View {
    let folder: WordFolder
    @ObservedObject var profile: ProfileStore

    private var count: Int {
        profile.profile.wordStates.filter { $0.savedInFolderIds.contains(folder.folderId) }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.parentFolderId == nil ? "folder" : "folder.badge.plus")
                .foregroundStyle(AppDesign.accent)
                .frame(width: 32, height: 32)
                .background(AppDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).font(.subheadline.weight(.medium))
                if folder.parentFolderId != nil { Text("Unterordner").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Menu {
                Button("Unterordner hinzufügen", systemImage: "folder.badge.plus") { NotificationCenter.default.post(name: .newSubfolderRequested, object: folder.folderId) }
            } label: {
                Image(systemName: "ellipsis").padding(8).contentShape(Rectangle())
            }
            .accessibilityLabel("Ordneraktionen")
        }
        .padding(10)
    }
}

extension Notification.Name {
    static let newSubfolderRequested = Notification.Name("WordExpressNewSubfolderRequested")
}

struct FolderEditorView: View {
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parentSelection: String?
    let parentFolderId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Neuer Ordner") {
                    TextField("Name", text: $name)
                    Picker("Speicherort", selection: $parentSelection) {
                        Text("Hauptordner").tag(String?.none)
                        ForEach(profile.profile.folders.filter { $0.parentFolderId == nil }) { folder in
                            Text(folder.name).tag(Optional(folder.folderId))
                        }
                    }
                }
            }
            .navigationTitle("Ordner erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        profile.createFolder(name: name, parentId: parentSelection)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { parentSelection = parentFolderId }
        }
    }
}
