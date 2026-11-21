import SwiftUI

// MARK: - Begriffe

/// Lexikon-Bereich: Fächer mit Fachbegriffen und ihren Erklärungen.
struct TermsView: View {
    @Environment(LearningStore.self) private var store
    @State private var selectedSubjectID: UUID?
    @State private var search = ""
    @State private var revealed: Set<UUID> = []
    @State private var editingTerm: TermCard?
    @State private var showingAddTerm = false
    @State private var showingAddSubject = false
    @State private var editingSubject: TermSubject?
    @State private var deletingSubject: TermSubject?
    @State private var studyCards: TermStudyConfiguration?

    private var scoped: [TermCard] {
        store.terms.filter { selectedSubjectID == nil || $0.subjectID == selectedSubjectID }
    }

    private var visible: [TermCard] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? scoped : scoped.filter {
            $0.term.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.definition.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(store.t("Begriffe")).font(.largeTitle.bold())
                        Spacer()
                        Group {
                            Button { showingAddSubject = true } label: {
                                Image(systemName: "folder.badge.plus").font(.headline).padding(12).background(Palette.lilac, in: Circle())
                            }.accessibilityLabel(store.t("Fach erstellen"))
                            Button { showingAddTerm = true } label: {
                                Image(systemName: "plus").font(.headline).padding(12).background(Palette.lilac, in: Circle())
                            }.accessibilityLabel(store.t("Begriff hinzufügen"))
                        }.foregroundStyle(Palette.purple)
                    }
                    Text(store.tf("%d Begriffe", visible.count)).font(.caption).foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField(store.t("Begriffe suchen"), text: $search)
                    }.padding(13).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    subjectChips
                    Button {
                        studyCards = TermStudyConfiguration(cards: scoped)
                    } label: {
                        Label(store.t("Begriffe lernen"), systemImage: "rectangle.on.rectangle.angled")
                            .frame(maxWidth: .infinity).padding(13).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain).foregroundStyle(Palette.purple).disabled(scoped.isEmpty)
                    if store.termSubjects.isEmpty && store.terms.isEmpty {
                        ContentUnavailableView(store.t("Noch keine Fächer"), systemImage: "books.vertical",
                                               description: Text(store.t("Lege ein Fach an, zum Beispiel Biologie oder Jura, und sammle dort deine Fachbegriffe. Eulio, dein KI-Tutor, kann sie auch für dich erstellen.")))
                            .frame(minHeight: 250)
                    } else if visible.isEmpty {
                        ContentUnavailableView(store.t(search.isEmpty ? "Noch keine Begriffe" : "Keine Treffer"), systemImage: "text.book.closed")
                            .frame(minHeight: 200)
                    } else {
                        ForEach(visible) { card in termRow(card) }
                    }
                }.padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddTerm) { TermEditorSheet(card: nil, defaultSubjectID: selectedSubjectID) }
            .sheet(item: $editingTerm) { card in TermEditorSheet(card: card, defaultSubjectID: card.subjectID) }
            .sheet(isPresented: $showingAddSubject) { TermSubjectEditorSheet(subject: nil) }
            .sheet(item: $editingSubject) { subject in TermSubjectEditorSheet(subject: subject) }
            .fullScreenCover(item: $studyCards) { config in TermStudyView(cards: config.cards) }
            .confirmationDialog(store.t("Fach löschen?"), isPresented: Binding(get: { deletingSubject != nil }, set: { if !$0 { deletingSubject = nil } }), titleVisibility: .visible, presenting: deletingSubject) { subject in
                Button(store.t("Fach und Begriffe löschen"), role: .destructive) { remove(subject, deleteTerms: true) }
                Button(store.t("Nur Fach löschen")) { remove(subject, deleteTerms: false) }
                Button(store.t("Abbrechen"), role: .cancel) {}
            } message: { _ in
                Text(store.t("Möchtest du die Begriffe in diesem Fach ebenfalls löschen?"))
            }
            .onChange(of: store.termSubjects.map(\.id)) { _, ids in
                if let id = selectedSubjectID, !ids.contains(id) { selectedSubjectID = nil }
            }
        }
    }

    private func remove(_ subject: TermSubject, deleteTerms: Bool) {
        if selectedSubjectID == subject.id { selectedSubjectID = nil }
        store.removeTermSubject(subject.id, deleteTerms: deleteTerms)
    }

    private var subjectChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "🌐 " + store.t("Alle"), count: store.terms.count, active: selectedSubjectID == nil) { selectedSubjectID = nil }
                ForEach(store.termSubjects) { subject in
                    chip(title: "\(subject.emoji) \(subject.name)".trimmingCharacters(in: .whitespaces),
                         count: store.terms.filter { $0.subjectID == subject.id }.count,
                         active: selectedSubjectID == subject.id) { selectedSubjectID = subject.id }
                        .contextMenu {
                            Button { editingSubject = subject } label: { Label(store.t("Fach bearbeiten"), systemImage: "pencil") }
                            Button(role: .destructive) { deletingSubject = subject } label: { Label(store.t("Fach löschen"), systemImage: "trash") }
                        }
                }
            }
        }
    }

    private func chip(title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { action() } } label: {
            HStack(spacing: 5) { Text(title); if active { Text("· \(count)").foregroundStyle(Palette.muted) } }
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 9)
                .background(active ? Palette.purple.opacity(0.14) : Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? Palette.purple.opacity(0.35) : Palette.muted.opacity(0.12)))
        }.buttonStyle(.plain).foregroundStyle(Palette.ink)
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func termRow(_ card: TermCard) -> some View {
        let isOpen = revealed.contains(card.id)
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.term).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                        if selectedSubjectID == nil, let subject = store.termSubject(card.subjectID) {
                            Text("\(subject.emoji) \(subject.name)".trimmingCharacters(in: .whitespaces)).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer()
                    if card.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Palette.purple) }
                    Menu {
                        Button { editingTerm = card } label: { Label(store.t("Bearbeiten"), systemImage: "pencil") }
                        Button { store.toggleTermPin(card.id) } label: { Label(store.t(card.isPinned ? "Lösen" : "Anheften"), systemImage: "pin") }
                        Button(role: .destructive) { store.removeTerm(card.id) } label: { Label(store.t("Löschen"), systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Palette.muted)
                    }.accessibilityLabel(store.t("Optionen"))
                }
                if isOpen {
                    Text(card.definition).font(.body).foregroundStyle(Palette.ink)
                    if !card.example.isEmpty {
                        Text(card.example).font(.subheadline).italic().foregroundStyle(Palette.muted)
                    }
                }
                HStack {
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.2)) { if isOpen { revealed.remove(card.id) } else { revealed.insert(card.id) } } } label: {
                        Image(systemName: isOpen ? "eye.slash" : "eye").foregroundStyle(Palette.muted)
                    }.accessibilityLabel(store.t(isOpen ? "Erklärung verbergen" : "Erklärung zeigen"))
                }
            }
        }
    }
}

private struct TermStudyConfiguration: Identifiable {
    let id = UUID()
    let cards: [TermCard]
}

// MARK: - Editoren

struct TermEditorSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let card: TermCard?
    @State private var term: String
    @State private var definition: String
    @State private var example: String
    @State private var subjectID: UUID?

    init(card: TermCard?, defaultSubjectID: UUID?) {
        self.card = card
        _term = State(initialValue: card?.term ?? "")
        _definition = State(initialValue: card?.definition ?? "")
        _example = State(initialValue: card?.example ?? "")
        _subjectID = State(initialValue: card?.subjectID ?? defaultSubjectID)
    }

    private var canSave: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Begriff")) {
                    TextField(store.t("Begriff"), text: $term)
                    TextField(store.t("Erklärung"), text: $definition, axis: .vertical).lineLimit(3...8)
                }
                Section(store.t("Beispiel (optional)")) {
                    TextField(store.t("Beispiel oder Merksatz"), text: $example, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Picker(store.t("Fach"), selection: $subjectID) {
                        Text(store.t("Kein Fach")).tag(UUID?.none)
                        ForEach(store.termSubjects) { subject in Text("\(subject.emoji) \(subject.name)").tag(Optional(subject.id)) }
                    }
                }
            }
            .navigationTitle(store.t(card == nil ? "Begriff hinzufügen" : "Begriff bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Sichern")) {
                        if let card { store.updateTerm(card.id, term: term, definition: definition, example: example, subjectID: subjectID) }
                        else { store.addTerms([(term, definition, example)], subjectID: subjectID) }
                        dismiss()
                    }.disabled(!canSave)
                }
            }
        }.presentationDetents([.medium, .large])
    }
}

struct TermSubjectEditorSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let subject: TermSubject?
    @State private var name: String
    @State private var emoji: String
    private let emojis = ["🧬", "⚖️", "💻", "📈", "🧪", "🩺", "🏛️", "🌍", "🧠", "📐"]

    init(subject: TermSubject?) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _emoji = State(initialValue: subject?.emoji ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Fach")) { TextField(store.t("z. B. Biologie"), text: $name) }
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
            .navigationTitle(store.t(subject == nil ? "Fach erstellen" : "Fach bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t(subject == nil ? "Erstellen" : "Sichern")) {
                        if let subject { store.updateTermSubject(subject.id, name: name, emoji: emoji) }
                        else { store.addTermSubject(name: name, emoji: emoji) }
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.medium, .large])
    }
}

// MARK: - Lernen

/// Karteikarten für Begriffe: Begriff vorn, Erklärung hinten, selbst bewerten.
struct TermStudyView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cards: [TermCard]
    @State private var queue: [TermCard] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var known = 0
    @State private var startedAt = Date()

    private var current: TermCard? { queue.indices.contains(index) ? queue[index] : nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let current {
                    HStack {
                        Text("\(index + 1) / \(queue.count)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                        Spacer()
                        if let subject = store.termSubject(current.subjectID) {
                            Text("\(subject.emoji) \(subject.name)".trimmingCharacters(in: .whitespaces)).font(.caption.bold()).foregroundStyle(Palette.purple)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Palette.lilac, in: Capsule())
                        }
                    }
                    ScrollView {
                        SurfaceCard {
                            VStack(spacing: 14) {
                                Text(store.t(revealed ? "ERKLÄRUNG" : "BEGRIFF")).font(.caption.bold()).foregroundStyle(Palette.muted)
                                Text(current.term).font(.system(.title, design: .rounded).weight(.semibold)).multilineTextAlignment(.center)
                                if revealed {
                                    Divider()
                                    Text(current.definition).font(.body).multilineTextAlignment(.center)
                                    if !current.example.isEmpty {
                                        Text(current.example).font(.subheadline).italic().foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                                    }
                                }
                            }.frame(maxWidth: .infinity, minHeight: 260)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { revealed = true } }
                    }
                    if revealed {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { ratingButtons(current) }
                            VStack(spacing: 10) { ratingButtons(current) }
                        }
                    } else {
                        Button(store.t("Erklärung zeigen")) { withAnimation(.easeOut(duration: 0.2)) { revealed = true } }.buttonStyle(PrimaryButtonStyle())
                    }
                } else {
                    Spacer()
                    Text(store.t("Geschafft! 🎉")).font(.title.bold())
                    Text(store.tf("%d von %d Begriffen gewusst", known, queue.count)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button(store.t("Fertig")) { dismiss() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(18)
            .background(Palette.canvas)
            .navigationTitle(store.t("Begriffe lernen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                        .accessibilityLabel(store.t("Lernen beenden"))
                }
            }
            .onAppear {
                guard queue.isEmpty else { return }
                // Fällige zuerst, höchstens so viele wie eine Lernsitzung.
                let due = cards.filter(\.dueToday).shuffled()
                let rest = cards.filter { !$0.dueToday }.shuffled()
                queue = Array((due + rest).prefix(max(store.sessionSize, 1)))
                startedAt = Date()
            }
        }
    }

    @ViewBuilder private func ratingButtons(_ card: TermCard) -> some View {
        Button { rate(card, correct: false) } label: {
            Label(store.t("Nicht gewusst"), systemImage: "xmark").font(.body.weight(.semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity).padding(.vertical, 15).padding(.horizontal, 10)
                .foregroundStyle(Palette.red).background(Palette.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
        Button { rate(card, correct: true) } label: {
            Label(store.t("Gewusst"), systemImage: "checkmark").font(.body.weight(.semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity).padding(.vertical, 15).padding(.horizontal, 10)
                .foregroundStyle(.white).background(Palette.purple, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func rate(_ card: TermCard, correct: Bool) {
        store.recordTerm(card.id, correct: correct, duration: Date().timeIntervalSince(startedAt))
        if correct { known += 1 }
        revealed = false
        startedAt = Date()
        withAnimation(.easeOut(duration: 0.2)) { index += 1 }
    }
}
