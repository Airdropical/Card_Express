import SwiftUI
import UIKit
import Observation
import PhotosUI
import UniformTypeIdentifiers

/// Ein Bild oder PDF, über das im Tutor gesprochen wird. Bleibt angehängt, bis es entfernt wird.
private struct TutorAttachment {
    var name: String
    var detail: String
    var preview: UIImage?
    var payload: TutorAttachmentPayload
}

// MARK: - Modelle

private enum TutorActionMode: String, CaseIterable, Identifiable {
    case automatic, vocabulary, decks
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .automatic: return "Automatisch"
        case .vocabulary: return "Vokabeln erstellen"
        case .decks: return "Decks & Lernkarten"
        }
    }
    var symbol: String {
        switch self {
        case .automatic: return "sparkles"
        case .vocabulary: return "character.book.closed"
        case .decks: return "rectangle.stack"
        }
    }
}

private enum TutorPracticeMode: String {
    case conversation
    case quiz
    case termsQuiz = "terms_quiz"
    case termsExplain = "terms_explain"
}

/// Womit der Tutor gerade übt: Vokabeln eines Sprachpaars oder Begriffe eines Fachs.
private enum TutorArea: String, CaseIterable, Identifiable {
    case vocabulary, terms
    var id: String { rawValue }
}

private enum TutorOpenTarget: Identifiable {
    case deck(UUID)
    case vocabulary(deckID: UUID, pairID: UUID)

    var id: String {
        switch self {
        case .deck(let id): return "deck-\(id)"
        case .vocabulary(let deckID, let pairID): return "vocabulary-\(deckID)-\(pairID)"
        }
    }
}

private struct TutorTestTarget: Identifiable { let id: UUID }

private struct TutorAppliedResult: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    let destination: TutorOpenTarget?
}

/// Schlüssel für einen Vorschlag im Plan (Aktion + Position). Ersetzt die bisherigen
/// String-Schlüssel ("2:5"): schneller zu hashen und ohne String-Präfix-Vergleiche.
private struct PlanKey: Hashable {
    let action: Int
    let item: Int
}

/// Auswahlzustand der Vorschlagskarte. Liegt in der Karte selbst, damit ein Antippen
/// nur diese Karte neu berechnet und nicht den gesamten Chat.
private struct PlanSelection {
    var actions: Set<Int>
    var vocabulary: Set<PlanKey>
    var flashcards: Set<PlanKey>
    var includeExamples = false
    var includePronunciations = true

    init(plan: TutorAgentPlan, duplicates: Set<PlanKey>) {
        // Löschen wird nie vorausgewählt: Der Vorschlag kann auch aus angehängtem Material stammen.
        actions = Set(plan.actions.indices.filter { plan.actions[$0].type != "delete_calendar_entry" })
        flashcards = Set(plan.actions.indices.flatMap { actionIndex in
            (plan.actions[actionIndex].cards ?? []).indices.map { PlanKey(action: actionIndex, item: $0) }
        })
        vocabulary = Set(plan.actions.indices.flatMap { actionIndex in
            (plan.actions[actionIndex].vocabularyEntries ?? []).indices
                .map { PlanKey(action: actionIndex, item: $0) }
                .filter { !duplicates.contains($0) }
        })
    }
}

private struct VocabularyStats {
    /// Anzahl pro Ordner (nil = ohne Ordner), unabhängig von der aktuellen Auswahl.
    var counts: [UUID?: Int] = [:]
    var total = 0
}

/// Eingabetext liegt in einem eigenen Observable. Der Chat selbst liest ihn nie in `body`,
/// daher löst jeder Tastendruck nur eine Neuberechnung des Eingabefelds aus.
@MainActor @Observable
private final class ComposerModel {
    var text = ""
    var focusToken = 0
}

private enum VocabKey {
    nonisolated static func make(_ term: String, _ translation: String) -> String {
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return normalized(term) + "\u{1F}" + normalized(translation)
    }
}

private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

@MainActor
private func resolveActivePair(store: LearningStore, selectedPairID: UUID?) -> VocabularyLanguagePair {
    store.vocabularyLanguagePairs.first(where: { $0.id == (selectedPairID ?? store.selectedVocabularyLanguagePairID) })
        ?? store.selectedVocabularyLanguagePair
}

private func chatBubbleShape(isAssistant: Bool) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: 16,
        bottomLeadingRadius: isAssistant ? 5 : 16,
        bottomTrailingRadius: isAssistant ? 16 : 5,
        topTrailingRadius: 16,
        style: .continuous
    )
}

// MARK: - Chat

struct AssistantChatView: View {
    private static let bottomID = "assistant-chat-bottom"
    private static let starterPrompts = [
        "Erstelle 10 Vokabeln zum Thema Reisen.",
        "Erkläre mir den Unterschied zwischen ähnlichen Wörtern: ",
        "Erstelle Lernkarten zum Thema "
    ]
    private static let termStarterPrompts = [
        "Erstelle 10 Begriffe zum Thema Zellbiologie.",
        "Erkläre mir einfach den Begriff ",
        "Lege das Fach Geschichte an."
    ]
    /// Eine Etappe gilt als voll, wenn mindestens so viele neue Vokabeln kamen (das Backend liefert bis zu 60).
    private static let vocabularyBatchThreshold = 40
    private static let maxVocabularyRounds = 8
    /// Länge eines Dokumentteils beim Übernehmen von Vokabeln: etwa 20 bis 25 Einträge einer Liste.
    /// Bewusst klein: Die KI liefert pro Antwort erfahrungsgemäß nur gut 30 Einträge, auch wenn mehr erlaubt sind.
    private static let documentPartCharacters = 1_100
    private static let maxDocumentParts = 20
    /// Kurze Zeilen bedeuten viele Einträge auf wenig Text; deshalb zählt auch die Zeilenzahl.
    private static let documentPartLines = 26

    /// Teilt ein Dokument an Zeilengrenzen in Stücke von etwa `documentPartCharacters` Zeichen.
    /// Bei sehr langen Dokumenten werden die Stücke größer, damit es höchstens `maxDocumentParts` werden.
    static func documentParts(_ text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let size = max(documentPartCharacters, text.count / maxDocumentParts + 1)
        var parts: [String] = []
        let maxLines = max(documentPartLines, lines.count / maxDocumentParts + 1)
        var current = ""
        var currentLines = 0
        for line in lines {
            if !current.isEmpty, current.count + line.count + 1 > size || currentLines >= maxLines {
                parts.append(current)
                current = ""
                currentLines = 0
            }
            current += (current.isEmpty ? "" : "\n") + line
            currentLines += 1
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(current) }
        return parts
    }
    private static let maxVocabularyPerAction = 500
    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @Environment(LearningStore.self) private var store
    @State private var composer = ComposerModel()
    @State private var messages: [TutorMessage] = []
    @State private var loading = false
    /// Fortschritt, während Vokabeln aus einem Anhang in mehreren Etappen gelesen werden.
    @State private var progressNote: String?
    @State private var applying = false
    @State private var showInfo = false
    @State private var errorText: String?
    @State private var selectedPairID: UUID?
    @State private var selectedVocabularyDeckID: UUID?
    @State private var pendingPlan: TutorAgentPlan?
    @State private var planToken = UUID()
    @State private var duplicateEntries: Set<PlanKey> = []
    @State private var appliedResults: [TutorAppliedResult] = []
    @State private var openCreatedContent: TutorOpenTarget?
    @State private var tutorActionMode: TutorActionMode = .automatic
    @State private var activePracticeMode: TutorPracticeMode?
    @State private var tutorArea: TutorArea = .vocabulary
    /// Neu gemischt bei jedem Start einer Übung; innerhalb der Übung bleibt die Reihenfolge gleich.
    @State private var practiceSeed = UUID()
    @State private var selectedTermSubjectID: UUID?
    @State private var attachment: TutorAttachment?
    @State private var loadingAttachment = false
    @State private var showingPhotoPicker = false
    @State private var showingPDFPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    /// Vom Tutor gestarteter Test über ein vorhandenes Deck.
    @State private var testDeck: TutorTestTarget?

    private var activePair: VocabularyLanguagePair {
        resolveActivePair(store: store, selectedPairID: selectedPairID)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(store.t("Üben mit"), selection: $tutorArea) {
                    Text(store.t("Vokabeln")).tag(TutorArea.vocabulary)
                    Text(store.t("Begriffe")).tag(TutorArea.terms)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 6)
                if tutorArea == .vocabulary {
                    VocabularyContextBar(
                        selectedPairID: $selectedPairID,
                        selectedDeckID: $selectedVocabularyDeckID,
                        loading: loading
                    ) { conversation in
                        Task { await startPractice(conversation: conversation) }
                    }
                } else {
                    TermContextBar(selectedSubjectID: $selectedTermSubjectID, loading: loading) { explain in
                        Task { await startTermPractice(explain: explain) }
                    }
                }
                messageList
                if let errorText {
                    ErrorMessageCard(message: errorText)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }
                if loadingAttachment || attachment != nil { attachmentChip }
                ChatComposer(model: composer, actionMode: $tutorActionMode, isLoading: loading,
                             onAttachPhoto: { showingPhotoPicker = true }, onAttachPDF: { showingPDFPicker = true }) { text in
                    Task { await send(message: text) }
                }
            }
            .background(Palette.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Eulio").font(.title3.bold()).foregroundStyle(Palette.ink)
                        Text(store.t("Dein KI-Tutor")).font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
                    }
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInfo = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel(store.t("Informationen zu Eulio"))
                }
            }
            .alert("Eulio", isPresented: $showInfo) {
                Button(store.t("OK"), role: .cancel) {}
            } message: {
                Text(store.t("Eulio ist dein KI-Tutor. Er erklärt dir Themen, übt Vokabeln und Begriffe mit dir und legt auf Wunsch Karten, Vokabeln und Termine an – erst nach deiner Bestätigung. Über die Büroklammer kannst du ein Foto oder PDF anhängen."))
            }
            .onAppear { selectedPairID = store.selectedVocabularyLanguagePairID }
#if DEBUG
            // Nur in Entwicklungs-Builds: ein PDF vorab anhängen, für automatisierte Tests im Simulator.
            .task {
                if attachment == nil, let path = ProcessInfo.processInfo.environment["LERNKARTEN_TEST_ATTACHMENT"] {
                    await attachPDF(.success([URL(fileURLWithPath: path)]))
                }
            }
#endif
            .onChange(of: store.selectedVocabularyLanguagePairID) { _, id in
                selectedPairID = id
                selectedVocabularyDeckID = nil
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                pickedPhoto = nil
                Task { await attachPhoto(item) }
            }
            .fileImporter(isPresented: $showingPDFPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                Task { await attachPDF(result) }
            }
            .fullScreenCover(item: $testDeck) { target in
                StudySessionView(deckID: target.id, mode: .exam, useAI: false)
            }
            .sheet(item: $openCreatedContent) { destination in
                NavigationStack {
                    switch destination {
                    case .deck(let id):
                        DeckDetailView(deckID: id)
                    case .vocabulary(let deckID, let pairID):
                        VocabularyView(initialSelectedDeckID: deckID, languagePairID: pairID)
                    }
                }
            }
        }
    }

    // MARK: Anhang

    private var attachmentChip: some View {
        HStack(spacing: 10) {
            if loadingAttachment {
                ProgressView().frame(width: 36, height: 36)
                Text(store.t("Anhang wird vorbereitet …")).font(.subheadline).foregroundStyle(Palette.muted)
                Spacer()
            } else if let attachment {
                Group {
                    if let preview = attachment.preview {
                        Image(uiImage: preview).resizable().scaledToFill()
                    } else {
                        Image(systemName: "doc.text.fill").font(.title3).foregroundStyle(Palette.purple)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.lilac)
                    }
                }
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                    Text(attachment.detail).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { self.attachment = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Palette.muted)
                }
                .accessibilityLabel(store.t("Anhang entfernen"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 14).padding(.top, 6)
    }

    @MainActor private func attachPhoto(_ item: PhotosPickerItem) async {
        guard let original = try? await item.loadTransferable(type: Data.self) else {
            errorText = store.t("Das Foto konnte nicht geladen werden. Bitte versuche ein anderes Bild.")
            return
        }
        await attachImage { AIImportView.jpegForUpload(from: original) }
    }

    /// Verkleinern und als JPEG kodieren, im Hintergrund.
    @MainActor private func attachImage(_ prepare: @escaping @Sendable () -> (data: Data, preview: UIImage)?) async {
        errorText = nil
        loadingAttachment = true
        defer { loadingAttachment = false }
        guard let prepared = await Task.detached(priority: .userInitiated, operation: prepare).value,
              prepared.data.count <= ImportLimits.photoBytes else {
            errorText = store.t("Das Foto konnte nicht geladen werden. Bitte versuche ein anderes Bild.")
            return
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(prepared.data.count), countStyle: .file)
        attachment = TutorAttachment(
            name: store.t("Foto"), detail: size, preview: prepared.preview,
            payload: TutorAttachmentPayload(name: "Foto", imageBase64: prepared.data.base64EncodedString())
        )
    }

    @MainActor private func attachPDF(_ result: Result<[URL], Error>) async {
        errorText = nil
        guard let url = try? result.get().first else { return }
        loadingAttachment = true
        defer { loadingAttachment = false }
        do {
            let payload = try await Task.detached(priority: .userInitiated) { try AIImportView.extractPDF(from: url) }.value
            attachment = TutorAttachment(
                name: payload.name, detail: store.tf("%d Seiten", payload.pages), preview: nil,
                payload: TutorAttachmentPayload(name: payload.name, documentText: payload.text)
            )
        } catch {
            errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        let copyTitle = store.t("Kopieren")
                        ForEach(messages) { message in
                            // `.equatable()`: bestehende Nachrichten werden nicht neu berechnet,
                            // wenn sich nur Ladezustand, Plan o. Ä. ändern.
                            ChatMessageRow(message: message, copyTitle: copyTitle).equatable()
                        }
                    }
                    if !appliedResults.isEmpty {
                        AppliedResultsCard(results: appliedResults) { openCreatedContent = $0 }
                    }
                    if let pendingPlan, !pendingPlan.actions.isEmpty {
                        planCard(pendingPlan)
                    }
                    if loading {
                        TypingBubble(label: progressNote ?? store.t("Eulio denkt nach …"))
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: loading) { _, _ in scrollToBottom(proxy) }
            .onChange(of: pendingPlan != nil) { _, _ in scrollToBottom(proxy) }
            .onChange(of: appliedResults.count) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(Palette.purple)
            Text(store.t("Hallo, ich bin Eulio")).font(.title2.bold()).foregroundStyle(Palette.ink)
            Text(store.t(tutorArea == .terms ? "Lass dir Begriffe einfach erklären oder frag sie ab." : "Übe deine Vokabeln in Dialogen und Abfragen."))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(tutorArea == .terms ? Self.termStarterPrompts : Self.starterPrompts, id: \.self) { prompt in
                    Button {
                        composer.text = store.t(prompt)
                        composer.focusToken += 1
                    } label: {
                        Label(store.t(prompt).trimmingCharacters(in: .whitespaces), systemImage: "sparkles")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.muted.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func planCard(_ plan: TutorAgentPlan) -> some View {
        let pair = activePair
        return AgentPlanCard(
            plan: plan,
            duplicates: duplicateEntries,
            sourceCode: store.vocabularyLanguage(pair.sourceLanguageID)?.code ?? "A",
            targetCode: store.vocabularyLanguage(pair.targetLanguageID)?.code ?? "B",
            onReject: {
                pendingPlan = nil
                duplicateEntries = []
            },
            onApply: { selection in
                Task { await applySelectedActions(plan, selection: selection) }
            }
        )
        .id(planToken)
    }

    // MARK: Senden

    @MainActor private func startTermPractice(explain: Bool) async {
        let subjectName = store.termSubject(selectedTermSubjectID)?.name ?? store.t("allen Fächern")
        let practiceMode: TutorPracticeMode = explain ? .termsExplain : .termsQuiz
        let request = explain
            ? "Erkläre mir die Begriffe aus \(subjectName) in einfacher Sprache. Fang mit einem wichtigen Begriff an und frag danach, welchen ich als Nächstes verstehen möchte."
            : "Frag mich die Begriffe aus \(subjectName) ab. Immer nur einen Begriff, verrate die Erklärung nicht vor meiner Antwort und gib danach kurzes Feedback."
        messages = []
        errorText = nil
        practiceSeed = UUID()
        activePracticeMode = practiceMode
        await send(message: request, mode: practiceMode.rawValue)
    }

    /// Mischt die Liste für eine Übung, damit nicht jede Abfrage mit denselben Wörtern beginnt.
    /// Stabil innerhalb einer Übung (gleicher Seed), sonst würde der Tutor Wörter doppelt fragen.
    private func practiceOrder<T>(_ items: [T], id: (T) -> UUID) -> [T] {
        guard activePracticeMode != nil else { return items }
        let seed = practiceSeed.uuidString
        return items.sorted { (seed + id($0).uuidString).hashValue < (seed + id($1).uuidString).hashValue }
    }

    /// Begriffe des gewählten Fachs als Kontext für Abfrage und Erklären.
    private func makeTermContext() -> String {
        let cards = practiceOrder(store.terms.filter { selectedTermSubjectID == nil || $0.subjectID == selectedTermSubjectID }, id: \.id)
        let subject = store.termSubject(selectedTermSubjectID)?.name ?? "Alle Fächer"
        guard !cards.isEmpty else { return "Fach: \(subject). Keine Begriffe gespeichert." }
        let lines = cards.prefix(150).map { "- \($0.term): \($0.definition)" }.joined(separator: "\n")
        return String("Fach: \(subject)\nBegriffe des Lernenden:\n\(lines)".prefix(9000))
    }

    @MainActor private func startPractice(conversation: Bool) async {
        let pair = activePair
        let sourceName = store.vocabularyLanguage(pair.sourceLanguageID)?.name ?? "Sprache A"
        let targetName = store.vocabularyLanguage(pair.targetLanguageID)?.name ?? "Sprache B"
        let practiceMode: TutorPracticeMode = conversation ? .conversation : .quiz
        let request = conversation
            ? "Lass uns eine kurze Alltagssituation auf \(targetName) üben. Nutze Vokabeln aus meinem ausgewählten Ordner. Stelle mir nur eine Frage auf einmal und warte auf meine Antwort."
            : "Prüfe mich mit den Vokabeln aus meinem ausgewählten Ordner von \(sourceName) nach \(targetName). Zeige immer nur ein Wort, verrate die Übersetzung nicht vor meiner Antwort und gib danach kurzes Feedback."
        messages = []
        errorText = nil
        practiceSeed = UUID()
        activePracticeMode = practiceMode
        await send(message: request, mode: practiceMode.rawValue)
    }

    @MainActor private func send(message: String, mode: String? = nil) async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !loading else { return }
        pendingPlan = nil
        duplicateEntries = []
        appliedResults = []
        messages.append(TutorMessage(role: "user", text: text))
        errorText = nil
        loading = true
        defer { loading = false; progressNote = nil }
        let tutorMode = mode ?? activePracticeMode?.rawValue ?? "chat"

        let pair = activePair
        let sourceName = store.vocabularyLanguage(pair.sourceLanguageID)?.name ?? "Sprache A"
        let targetName = store.vocabularyLanguage(pair.targetLanguageID)?.name ?? "Sprache B"

        if mode == nil && (isActionRequest(text) || tutorActionMode != .automatic) {
            activePracticeMode = nil
            do {
                // Unterordner als Pfad („Englisch › Unit 1“), damit der Tutor sie gezielt ansprechen kann.
                let folders = store.vocabularyDecks.filter { $0.languagePairID == pair.id }.map(store.vocabularyDeckPath)
                let calendar = store.calendarEntries.sorted { $0.date < $1.date }.map { "\(LearningAPI.dayString($0.date)) · \($0.title)" }
                let payload = attachment?.payload
                func requestPlan(message: String = text, excluding terms: [String] = [], attachment part: TutorAttachmentPayload? = payload) async throws -> TutorAgentPlan {
                    try await LearningAPI.shared.planTutorActions(
                        message: message,
                        decks: store.decks.map(\.name),
                        language: store.language,
                        mode: tutorActionMode.rawValue,
                        sourceLanguage: sourceName,
                        targetLanguage: targetName,
                        vocabularyFolders: folders,
                        calendarEntries: calendar,
                        excludeTerms: terms,
                        termSubjects: store.termSubjects.map { subject in "\(subject.name) (\(store.terms.filter { $0.subjectID == subject.id }.count))" },
                        attachment: part
                    )
                }
                func vocabularyEntries(of plan: TutorAgentPlan) -> [TutorVocabularyDraft] {
                    plan.actions.first(where: { $0.type == "create_vocabulary_folder" || $0.type == "add_vocabulary" })?.vocabularyEntries ?? []
                }
                // Lange Dokumente: schon die erste Anfrage bekommt nur Teil 1. Mit dem ganzen Dokument wurde die
                // Antwort bei ~200 Vokabeln zu lang (abgeschnitten), und der ganze Import schlug fehl.
                let parts = payload?.documentText.map(Self.documentParts) ?? []
                func partNote(_ index: Int) -> String {
                    store.language == "Englisch"
                        ? "\n(Part \(index + 1) of \(parts.count) of the attached document. Take over every vocabulary entry in this part. term is always \(sourceName), translation always \(targetName), even if the table lists them the other way round.)"
                        : "\n(Teil \(index + 1) von \(parts.count) des angehängten Dokuments. Übernimm alle Vokabeln aus diesem Teil. term ist immer \(sourceName), translation immer \(targetName), auch wenn die Tabelle andersherum aufgebaut ist.)"
                }
                func partPayload(_ index: Int) -> TutorAttachmentPayload {
                    TutorAttachmentPayload(name: "\(payload?.name ?? "") (\(index + 1)/\(parts.count))", documentText: parts[index])
                }
                func firstRequest(_ index: Int) async throws -> TutorAgentPlan {
                    let message = parts.count > 1 ? String(text.prefix(1300)) + partNote(index) : text
                    let attachment = parts.count > 1 ? partPayload(index) : payload
                    if let plan = await retrying({ try await requestPlan(message: message, attachment: attachment) }) { return plan }
                    return try await requestPlan(message: message, attachment: attachment)
                }
                func hasVocabulary(_ plan: TutorAgentPlan) -> Bool {
                    plan.actions.contains { $0.type == "create_vocabulary_folder" || $0.type == "add_vocabulary" }
                }
                // Ein Deckblatt ohne Vokabeln liefert keinen Vokabel-Vorschlag: dann mit dem nächsten Teil beginnen.
                var firstPart = 0
                var plan = try await firstRequest(0)
                while parts.count > 1, !hasVocabulary(plan), firstPart < min(2, parts.count - 1) {
                    firstPart += 1
                    plan = try await firstRequest(firstPart)
                }
                let sourceCode = store.vocabularyLanguage(pair.sourceLanguageID)?.code ?? ""
                let targetCode = store.vocabularyLanguage(pair.targetLanguageID)?.code ?? ""
                // Auch ohne Anhang: Vertauschte Einträge werden vor dem Vorschlag umgedreht.
                for index in plan.actions.indices where plan.actions[index].vocabularyEntries != nil {
                    plan.actions[index].vocabularyEntries = VocabularyDirection.oriented(plan.actions[index].vocabularyEntries ?? [], sourceCode: sourceCode, targetCode: targetCode)
                }
                if payload != nil, let vocabIndex = plan.actions.firstIndex(where: { $0.type == "create_vocabulary_folder" || $0.type == "add_vocabulary" }) {
                    var collected: [TutorVocabularyDraft] = []
                    var seen = Set<String>()
                    func add(_ entries: [TutorVocabularyDraft]) -> Int {
                        let entries = VocabularyDirection.oriented(entries, sourceCode: sourceCode, targetCode: targetCode)
                        let fresh = entries.filter { seen.insert(VocabKey.make($0.term, $0.translation)).inserted }
                        collected.append(contentsOf: fresh)
                        return fresh.count
                    }
                    var failedParts = 0
                    if parts.count > 1 {
                        _ = add(plan.actions[vocabIndex].vocabularyEntries ?? [])
                        // Lange Dokumente werden Teil für Teil gelesen: Jeder Teil ist kurz genug, dass die KI alle
                        // Einträge darin vollständig übernimmt. Die erste Anfrage (ein Teil) gibt Ordner und Aktionstyp vor.
                        for index in parts.indices where index > firstPart {
                            progressNote = store.tf("Teil %d von %d · %d Vokabeln", index + 1, parts.count, collected.count)
                            if let next = await retrying({ try await requestPlan(message: String(text.prefix(1300)) + partNote(index), attachment: partPayload(index)) }) {
                                _ = add(vocabularyEntries(of: next))
                            } else {
                                failedParts += 1
                            }
                        }
                    } else {
                        // Bild oder kurzes Dokument: weiterfragen, solange neue Einträge kommen.
                        _ = add(plan.actions[vocabIndex].vocabularyEntries ?? [])
                        var round = 1
                        var lastFresh = collected.count
                        while lastFresh > 0, collected.count >= Self.vocabularyBatchThreshold, round < Self.maxVocabularyRounds {
                            round += 1
                            progressNote = store.tf("%d Vokabeln gelesen, weitere folgen …", collected.count)
                            guard let next = await retrying({ try await requestPlan(excluding: collected.map { "\($0.term) → \($0.translation)" }) }) else { failedParts += 1; break }
                            lastFresh = add(vocabularyEntries(of: next))
                        }
                    }
                    if failedParts > 0 {
                        errorText = store.t("Nicht alle Vokabeln konnten gelesen werden. Du kannst den Rest mit einem weiteren Auftrag ergänzen.")
                    }
                    plan.actions[vocabIndex].vocabularyEntries = Array(collected.prefix(Self.maxVocabularyPerAction))
                    progressNote = nil
                }
                // Die Duplikat-Erkennung normalisiert jede Vokabel (teuer) und läuft deshalb im Hintergrund.
                let known = store.vocabulary.filter { $0.languagePairID == pair.id }
                let duplicates = await Task.detached(priority: .userInitiated) {
                    AssistantChatView.duplicateKeys(in: plan, known: known)
                }.value
                #if DEBUG
                debugLog("[TutorAgent][plan] actions_count=\(plan.actions.count)")
                for (index, action) in plan.actions.enumerated() {
                    debugLog("[TutorAgent][plan] #\(index + 1) type=\(action.type) deck=\(action.deckName ?? "-") subdeck=\(action.subdeckName ?? "-") parent=\(action.parentDeck ?? "-") cards=\(action.cards?.count ?? 0) vocab=\(action.vocabularyEntries?.count ?? 0) createParent=\(action.createParentDeck.map { String($0) } ?? "-")")
                }
                #endif
                let reply = plan.actions.isEmpty && plan.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? store.t("Es wurde noch nichts gespeichert. Bitte präzisiere den Auftrag oder nenne das Ziel-Deck.")
                    : plan.reply
                messages.append(TutorMessage(role: "assistant", text: reply))
                if !plan.actions.isEmpty {
                    duplicateEntries = duplicates
                    planToken = UUID()
                    pendingPlan = plan
                }
            } catch {
                errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
            }
            return
        }

        let deckFilter = selectedVocabularyDeckID
        let deckScope = deckFilter.map(store.vocabularyScope)
        let activeVocabulary = practiceOrder(store.vocabulary.filter {
            $0.languagePairID == pair.id && (deckScope == nil || ($0.deckID.map { deckScope!.contains($0) } ?? false))
        }, id: \.id)
        let selectedDeckName = deckFilter.flatMap { id in
            store.vocabularyDecks.first(where: { $0.id == id && $0.languagePairID == pair.id }).map(store.vocabularyDeckPath)
        } ?? store.t("Alle")
        let vocabularyLines = activeVocabulary.prefix(100).map { entry in
            var line = "\(entry.term) → \(entry.translation)"
            if !entry.pronunciation.isEmpty { line += " (\(entry.pronunciation))" }
            if !entry.synonyms.isEmpty { line += " (Synonyme: \(entry.synonyms.joined(separator: ", ")))" }
            return line
        }.joined(separator: "\n")
        let vocabularyContext = activeVocabulary.isEmpty ? store.t("Keine Vokabeln im ausgewählten Ordner.") : vocabularyLines
        let flashcardContext = tutorMode == "chat" ? makeFlashcardContext() : ""
        let isTermMode = tutorMode.hasPrefix("terms")
        let context = isTermMode ? makeTermContext() : """
        \(tutorMode == "chat" ? makeLearnerOverview() : "")
        Aktives Sprachpaar: \(sourceName) → \(targetName). Ausgewählter Ordner: \(selectedDeckName).
        Vokabeln des ausgewählten Bereichs:
        \(vocabularyContext)
        \(flashcardContext.isEmpty ? "" : "Zusätzlicher Lernkarten-Kontext:\n\(flashcardContext)")
        """
        let history = Array(messages.dropLast())
        do {
            let reply = try await LearningAPI.shared.tutor(
                question: store.t(tutorMode == "chat" ? "Lern-Tutor für Schule und Uni" : isTermMode ? "Begriffe-Tutor" : "Vokabel-Tutor"),
                answer: String(context.prefix(9000)),
                message: text,
                history: history,
                language: store.language,
                mode: tutorMode,
                sourceLanguage: sourceName,
                targetLanguage: targetName,
                // Abfrage und Dialog üben nur mit den Vokabeln; der Anhang gehört zum freien Gespräch.
                attachment: tutorMode == "chat" ? attachment?.payload : nil
            )
            messages.append(TutorMessage(role: "assistant", text: reply.reply))
        } catch {
            errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
        }
    }

    /// Was der Tutor im freien Gespräch über den Lernstand weiß: Termine, Decks mit Fortschritt und schwere Karten.
    /// Bewusst knapp gehalten, weil es mit jeder Nachricht mitgesendet wird.
    private func makeLearnerOverview() -> String {
        let today = Calendar.current.startOfDay(for: Date())
        var lines = ["Heute ist \(LearningAPI.dayString(today))."]
        let upcoming = store.allCalendarEntries.filter { $0.date >= today }.prefix(6)
        if !upcoming.isEmpty {
            lines.append("Anstehende Termine:")
            for entry in upcoming {
                let deck = entry.deckID.flatMap { id in store.decks.first(where: { $0.id == id })?.name }
                lines.append("- \(LearningAPI.dayString(entry.date)): \(entry.title)\(deck.map { " (Deck: \($0))" } ?? "")")
            }
        }
        if !store.decks.isEmpty {
            lines.append("Decks (Karten gesamt / heute fällig / schwer):")
            for deck in store.decks.prefix(15) {
                lines.append("- \(deck.name): \(deck.cards.count) / \(deck.cards.filter(\.dueToday).count) / \(deck.cards.filter(\.isHard).count)")
            }
        }
        var hard: [String] = []
        outer: for deck in store.decks {
            for card in deck.cards where card.isHard {
                hard.append("- \(deck.name): \(card.question.prefix(120))")
                if hard.count == 12 { break outer }
            }
        }
        if !hard.isEmpty { lines.append("Karten, die dem Lernenden schwerfallen:"); lines.append(contentsOf: hard) }
        if !store.termSubjects.isEmpty {
            lines.append("Fächer im Bereich Begriffe: " + store.termSubjects.map { subject in "\(subject.name) (\(store.terms.filter { $0.subjectID == subject.id }.count))" }.joined(separator: ", "))
        }
        return String(lines.joined(separator: "\n").prefix(2500))
    }

    /// Bricht nach 20 Karten ab. Vorher wurden die Texte aller Karten aller Decks gebaut
    /// und danach auf 20 gekürzt.
    private func makeFlashcardContext() -> String {
        var lines: [String] = []
        outer: for deck in store.decks {
            for card in deck.cards {
                lines.append("\(deck.name) — Frage: \(card.question) Antwort: \(card.answer)")
                if lines.count == 20 { break outer }
            }
        }
        return String(lines.joined(separator: "\n").prefix(2500))
    }

    /// Viele Anfragen kurz hintereinander (PDF in Teilen) stoßen an das Minutenlimit der KI.
    /// Dann kurz warten und es noch zweimal versuchen, statt den Teil zu verlieren.
    private func retrying<T>(_ request: () async throws -> T) async -> T? {
        for pause in [4, 10, 0] {
            do { return try await request() } catch {
                guard pause > 0, !Task.isCancelled else { return nil }
                try? await Task.sleep(for: .seconds(pause))
            }
        }
        return nil
    }

    private func isActionRequest(_ text: String) -> Bool {
        let names = store.decks.map(\.name) + store.vocabularyDecks.map(\.name) + store.termSubjects.map(\.name) + store.calendarEntries.map(\.title)
        return TutorIntent.isActionRequest(text, knownNames: names)
    }

    private nonisolated static func duplicateKeys(in plan: TutorAgentPlan, known: [VocabularyEntry]) -> Set<PlanKey> {
        var knownKeys = Set(known.map { VocabKey.make($0.term, $0.translation) })
        var duplicates = Set<PlanKey>()
        for (actionIndex, action) in plan.actions.enumerated() {
            for (entryIndex, entry) in (action.vocabularyEntries ?? []).enumerated() {
                if !knownKeys.insert(VocabKey.make(entry.term, entry.translation)).inserted {
                    duplicates.insert(PlanKey(action: actionIndex, item: entryIndex))
                }
            }
        }
        return duplicates
    }

    // MARK: Vorschläge übernehmen

    @MainActor private func applySelectedActions(_ plan: TutorAgentPlan, selection: PlanSelection) async {
        guard !applying else { return }
        applying = true
        defer { applying = false }
        pendingPlan = nil
        duplicateEntries = []

        let pair = activePair
        let selected = selection.actions.sorted().compactMap { index -> (Int, TutorAgentAction)? in
            guard plan.actions.indices.contains(index) else { return nil }
            var action = plan.actions[index]
            if let cards = action.cards {
                action.cards = cards.enumerated()
                    .filter { selection.flashcards.contains(PlanKey(action: index, item: $0.offset)) }
                    .map(\.element)
            }
            return (index, action)
        }

        // Vorhandene Vokabeln werden einmal (im Hintergrund) normalisiert, statt für jeden neuen
        // Eintrag die gesamte Vokabelliste erneut zu durchsuchen und zu normalisieren.
        var existingKeys = Set<String>()
        if selected.contains(where: { $0.1.type == "create_vocabulary_folder" || $0.1.type == "add_vocabulary" }) {
            let snapshot = store.vocabulary.filter { $0.languagePairID == pair.id }
            existingKeys = await Task.detached(priority: .userInitiated) {
                Set(snapshot.map { VocabKey.make($0.term, $0.translation) })
            }.value
        }

        var diagnostics: [(Int, String)] = []
        var results: [TutorAppliedResult] = []
        // Im selben Durchgang umbenannte Decks bleiben unter ihrem alten Namen auffindbar.
        var renamedDecks: [String: UUID] = [:]
        func log(_ index: Int, _ text: String) { diagnostics.append((index, text)) }
        func clean(_ value: String?) -> String { (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        /// „Englisch › Unit 1“, „Englisch > Unit 1“ oder „Englisch / Unit 1“: Hauptordner und Unterordner.
        func folderPath(_ name: String) -> (parent: String?, child: String) {
            for separator in [" › ", " > ", " / ", "›", ">"] where name.contains(separator) {
                let parts = name.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if parts.count >= 2 { return (parts[0], parts[1...].joined(separator: " ")) }
            }
            return (nil, name)
        }
        func pairFolder(named name: String) -> VocabularyDeck? {
            let path = folderPath(name)
            let candidates = store.vocabularyDecks.filter { $0.languagePairID == pair.id && $0.name.caseInsensitiveCompare(path.child) == .orderedSame }
            guard let parentName = path.parent else { return candidates.first(where: { $0.parentID == nil }) ?? candidates.first }
            return candidates.first { deck in
                deck.parentID.flatMap { id in store.vocabularyDecks.first(where: { $0.id == id }) }?.name.caseInsensitiveCompare(parentName) == .orderedSame
            }
        }
        /// Legt den Ordner an; bei einem Pfad auch den Hauptordner, falls er fehlt.
        func createFolder(named name: String) {
            let path = folderPath(name)
            guard let parentName = path.parent else { store.addVocabularyDeck(name: name, emoji: "", languagePairID: pair.id); return }
            if pairFolder(named: parentName) == nil { store.addVocabularyDeck(name: parentName, emoji: "", languagePairID: pair.id) }
            let parent = pairFolder(named: parentName)
            store.addVocabularyDeck(name: path.child, emoji: "", languagePairID: pair.id, parentID: parent?.parentID == nil ? parent?.id : nil)
        }

        // Resolve/create main decks before processing child decks and cards.
        for (index, action) in selected where action.type == "create_deck" {
            let name = clean(action.deckName)
            guard !name.isEmpty else { log(index, "SKIP create_deck: deckName fehlt"); continue }
            if !store.decks.contains(where: { $0.parentID == nil && $0.name.caseInsensitiveCompare(name) == .orderedSame }) { store.addDeck(name: name) }
            if let deck = store.decks.first(where: { $0.parentID == nil && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                results.append(TutorAppliedResult(title: deck.name, detail: store.t("Deck bereit"), symbol: "rectangle.stack.fill", destination: .deck(deck.id)))
            }
            log(index, "OK create_deck: Hauptdeck '\(name)'")
        }

        for (index, action) in selected where action.type == "create_deck_tree" {
            let mainName = clean(action.deckName), childName = clean(action.subdeckName)
            guard !mainName.isEmpty, !childName.isEmpty else {
                log(index, "SKIP create_deck_tree: deckName='\(mainName)' subdeckName='\(childName)'"); continue
            }
            var main = store.decks.first(where: { $0.parentID == nil && $0.name.caseInsensitiveCompare(mainName) == .orderedSame })
            if main == nil { store.addDeck(name: mainName); main = store.decks.first(where: { $0.parentID == nil && $0.name.caseInsensitiveCompare(mainName) == .orderedSame }) }
            guard let main else { log(index, "SKIP create_deck_tree: Hauptdeck '\(mainName)' konnte nicht angelegt werden"); continue }
            var child = store.decks.first(where: { $0.parentID == main.id && $0.name.caseInsensitiveCompare(childName) == .orderedSame })
            if child == nil { store.addDeck(name: childName, parentID: main.id); child = store.decks.first(where: { $0.parentID == main.id && $0.name.caseInsensitiveCompare(childName) == .orderedSame }) }
            guard let child, let childIndex = store.decks.firstIndex(where: { $0.id == child.id }) else { log(index, "SKIP create_deck_tree: Unterdeck '\(mainName) > \(childName)' konnte nicht angelegt werden"); continue }
            let cards = (action.cards ?? []).prefix(20).filter { !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { Flashcard(question: $0.question, answer: $0.answer) }
            store.decks[childIndex].cards.append(contentsOf: cards)
            results.append(TutorAppliedResult(title: "\(main.name) › \(child.name)", detail: store.tf("%d Karten hinzugefügt", cards.count), symbol: "rectangle.stack.fill", destination: .deck(child.id)))
            log(index, "OK create_deck_tree: '\(mainName) > \(childName)' +\(cards.count) Karten")
        }

        let remaining = selected.filter { $0.1.type != "create_deck" && $0.1.type != "create_deck_tree" }.sorted { left, right in
            func priority(_ type: String) -> Int { type == "create_subdeck" ? 0 : (type == "create_cards" ? 1 : 2) }
            return priority(left.1.type) < priority(right.1.type)
        }
        for (index, action) in remaining {
            if action.type == "create_vocabulary_folder" || action.type == "add_vocabulary" {
                let folderName = clean(action.folderName)
                guard !folderName.isEmpty, let entries = action.vocabularyEntries, !entries.isEmpty else { log(index, "SKIP \(action.type): Ordnername oder Vokabeln fehlen"); continue }
                var folder = pairFolder(named: folderName)
                if folder == nil, action.type == "create_vocabulary_folder" {
                    createFolder(named: folderName)
                    folder = pairFolder(named: folderName)
                }
                guard let folder else { log(index, "SKIP \(action.type): Vokabelordner '\(folderName)' existiert in aktivem Sprachpaar nicht"); continue }
                let chosen = entries.enumerated()
                    .filter { selection.vocabulary.contains(PlanKey(action: index, item: $0.offset)) }
                    .prefix(Self.maxVocabularyPerAction).map(\.element)
                guard !chosen.isEmpty else { log(index, "SKIP \(action.type): keine Vokabeln ausgewählt"); continue }
                var addedCount = 0
                var duplicateCount = 0
                for entry in chosen {
                    // `insert` meldet zugleich, ob der Eintrag schon existiert oder im selben Durchgang vorkam.
                    guard existingKeys.insert(VocabKey.make(entry.term, entry.translation)).inserted else {
                        duplicateCount += 1
                        continue
                    }
                    store.addVocabulary(term: entry.term, translation: entry.translation, example: selection.includeExamples ? entry.example : "", synonyms: entry.synonyms, difficulty: entry.difficulty, deckID: folder.id, languagePairID: pair.id, pronunciation: selection.includePronunciations ? entry.pronunciation : "")
                    addedCount += 1
                }
                log(index, "OK \(action.type): '\(folderName)' +\(addedCount) Vokabeln\(duplicateCount > 0 ? ", \(duplicateCount) Duplikate übersprungen" : "")")
                results.append(TutorAppliedResult(title: folder.name, detail: store.tf("%d Vokabeln hinzugefügt", addedCount), symbol: "character.book.closed.fill", destination: .vocabulary(deckID: folder.id, pairID: pair.id)))
            } else if action.type == "create_subdeck" {
                let parentName = clean(action.parentDeck), name = clean(action.deckName)
                guard !parentName.isEmpty, !name.isEmpty else { log(index, "SKIP create_subdeck: parentDeck='\(parentName)' deckName='\(name)'"); continue }
                var parent = findDeck(named: parentName)
                let requestedMainDecks = selected.filter { $0.1.type == "create_deck" }.map { clean($0.1.deckName) }.filter { !$0.isEmpty }
                if parent == nil, let matchingName = requestedMainDecks.first(where: { normalizedDeckReference($0).caseInsensitiveCompare(normalizedDeckReference(parentName)) == .orderedSame }) {
                    parent = findDeck(named: matchingName)
                }
                if parent == nil, requestedMainDecks.count == 1 {
                    parent = findDeck(named: requestedMainDecks[0])
                }
                if parent == nil, action.createParentDeck == true {
                    let parentTitle = normalizedDeckReference(parentName)
                    if !parentTitle.isEmpty { store.addDeck(name: parentTitle); parent = findDeck(named: parentTitle) }
                }
                guard let parent else { log(index, "SKIP create_subdeck: Parent '\(parentName)' nicht gefunden; vorhandene Decks=[\(store.decks.map(\.name).joined(separator: ", "))]"); continue }
                var child = store.decks.first(where: { $0.parentID == parent.id && $0.name.caseInsensitiveCompare(name) == .orderedSame })
                if child == nil { store.addDeck(name: name, parentID: parent.id); child = store.decks.first(where: { $0.parentID == parent.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) }
                guard let child, let childIndex = store.decks.firstIndex(where: { $0.id == child.id }) else { log(index, "SKIP create_subdeck: Kind '\(parent.name) > \(name)' konnte nicht erstellt werden"); continue }
                let cards = (action.cards ?? []).prefix(20).filter { !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { Flashcard(question: $0.question, answer: $0.answer) }
                store.decks[childIndex].cards.append(contentsOf: cards)
                results.append(TutorAppliedResult(title: "\(parent.name) › \(child.name)", detail: store.tf("%d Karten hinzugefügt", cards.count), symbol: "rectangle.stack.fill", destination: .deck(child.id)))
                log(index, "OK create_subdeck: '\(parent.name) > \(name)' +\(cards.count) Karten")
            } else if action.type == "create_cards" {
                let target = clean(action.deckName)
                let parent = clean(action.parentDeck)
                guard let deck = findDeck(named: target, parentName: parent.isEmpty ? nil : parent) else { log(index, "SKIP create_cards: Ziel '\(parent.isEmpty ? target : parent + " > " + target)' nicht eindeutig gefunden; vorhandene Decks=[\(store.decks.map(\.name).joined(separator: ", "))]"); continue }
                let cards = (action.cards ?? []).prefix(20).filter { !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                guard !cards.isEmpty else { log(index, "SKIP create_cards: keine gültigen Karten"); continue }
                store.addCards(Array(cards), to: deck.id)
                results.append(TutorAppliedResult(title: deck.name, detail: store.tf("%d Karten hinzugefügt", cards.count), symbol: "rectangle.stack.fill", destination: .deck(deck.id)))
                log(index, "OK create_cards: '\(deck.name)' +\(cards.count) Karten")
            } else if action.type == "create_calendar_entry" {
                let title = clean(action.title), dateString = clean(action.dateISO)
                guard !title.isEmpty, let date = calendarDate(dateString) else { log(index, "SKIP create_calendar_entry: Titel oder Datum ungültig (title='\(title)' date='\(dateString)')"); continue }
                let kind = CalendarEntryKind(rawValue: action.kind ?? "other") ?? .other
                let deckID = action.deckName.flatMap { findDeck(named: $0)?.id }
                store.addCalendarEntry(title: title, date: date, kind: kind, deckID: deckID, note: action.note ?? "")
                results.append(TutorAppliedResult(title: title, detail: store.t("Kalendereintrag erstellt"), symbol: "calendar", destination: nil))
                log(index, "OK create_calendar_entry: '\(title)' am \(dateString)")
            } else if action.type == "create_term_subject" || action.type == "add_terms" {
                let subjectName = clean(action.subjectName)
                guard !subjectName.isEmpty else { log(index, "SKIP \(action.type): Fach fehlt"); continue }
                let existing = store.termSubjects.first(where: { $0.name.caseInsensitiveCompare(subjectName) == .orderedSame })
                guard let subjectID = existing?.id ?? store.addTermSubject(name: subjectName) else { log(index, "SKIP \(action.type): Fach konnte nicht angelegt werden"); continue }
                let entries = (action.termEntries ?? []).map { (term: $0.term, definition: $0.definition, example: $0.example) }
                let added = store.addTerms(entries, subjectID: subjectID)
                results.append(TutorAppliedResult(title: subjectName, detail: store.tf("%d Begriffe hinzugefügt", added), symbol: "text.book.closed.fill", destination: nil))
                log(index, "OK \(action.type): '\(subjectName)' +\(added) Begriffe")
            } else if action.type == "update_calendar_entry" {
                let title = clean(action.title), newTitle = clean(action.newTitle), newDate = calendarDate(clean(action.newDateISO))
                guard var entry = store.calendarEntries.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }), !newTitle.isEmpty || newDate != nil else {
                    log(index, "SKIP update_calendar_entry: Eintrag '\(title)' nicht gefunden oder keine Änderung"); continue
                }
                if !newTitle.isEmpty { entry.title = newTitle }
                if let newDate { entry.date = newDate }
                store.updateCalendarEntry(entry)
                results.append(TutorAppliedResult(title: entry.title, detail: store.t("Kalendereintrag geändert"), symbol: "calendar", destination: nil))
                log(index, "OK update_calendar_entry: '\(title)'")
            } else if action.type == "delete_calendar_entry" {
                let title = clean(action.title)
                guard let entry = store.calendarEntries.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
                    log(index, "SKIP delete_calendar_entry: Eintrag '\(title)' nicht gefunden"); continue
                }
                store.removeCalendarEntry(entry.id)
                results.append(TutorAppliedResult(title: entry.title, detail: store.t("Kalendereintrag gelöscht"), symbol: "calendar.badge.minus", destination: nil))
                log(index, "OK delete_calendar_entry: '\(title)'")
            } else if action.type == "rename_deck" {
                let newName = clean(action.newName)
                guard let deck = findDeck(named: clean(action.deckName)), !newName.isEmpty else { log(index, "SKIP rename_deck: Deck nicht gefunden oder neuer Name fehlt"); continue }
                store.updateDeck(deck.id, name: newName, emoji: deck.emoji, examDate: deck.examDate, stopDays: deck.newCardsStopDaysBeforeExam, targetGrade: deck.targetGrade, accentColor: deck.accentColor)
                renamedDecks[deck.name.lowercased()] = deck.id
                results.append(TutorAppliedResult(title: newName, detail: store.t("Deck umbenannt"), symbol: "rectangle.stack.fill", destination: .deck(deck.id)))
                log(index, "OK rename_deck: '\(deck.name)' → '\(newName)'")
            } else if action.type == "start_test" {
                let wanted = clean(action.deckName)
                let target = findDeck(named: wanted) ?? renamedDecks[wanted.lowercased()].flatMap { id in store.decks.first(where: { $0.id == id }) }
                guard let deck = target, !deck.cards.isEmpty else { log(index, "SKIP start_test: Deck nicht gefunden oder leer"); continue }
                results.append(TutorAppliedResult(title: deck.name, detail: store.t("Test gestartet"), symbol: "graduationcap.fill", destination: .deck(deck.id)))
                testDeck = TutorTestTarget(id: deck.id)
                log(index, "OK start_test: '\(deck.name)'")
            } else {
                log(index, "SKIP unbekannter Aktionstyp: '\(action.type)'")
            }
        }
        let applied = diagnostics.filter { $0.1.hasPrefix("OK") }.count
        let skipped = diagnostics.count - applied
        debugLog("[TutorAgent][apply]\n\(diagnostics.map { "#\($0.0 + 1) \($0.1)" }.joined(separator: "\n"))")
        appliedResults = results
        if results.isEmpty { errorText = store.t("Es konnte nichts übernommen werden.") }
        else if skipped > 0 { errorText = store.t("Einige Vorschläge konnten nicht übernommen werden.") }
        else { errorText = nil }
    }

    private func normalizedDeckReference(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: " (parent:", options: .caseInsensitive) { value = String(value[..<range.lowerBound]) }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'“”„"))
        return value.components(separatedBy: CharacterSet(charactersIn: ">›/")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.last ?? value
    }

    private func findDeck(named raw: String, parentName: String? = nil) -> Deck? {
        let normalized = normalizedDeckReference(raw)
        let matches = store.decks.filter { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }
        if let parentName {
            let normalizedParent = normalizedDeckReference(parentName)
            let parentIDs = Set(store.decks.filter { $0.name.caseInsensitiveCompare(normalizedParent) == .orderedSame }.map(\.id))
            let children = matches.filter { $0.parentID.map(parentIDs.contains) ?? false }
            if children.count == 1 { return children.first }
            if children.count > 1 { return nil }
        }
        return matches.count == 1 ? matches.first : nil
    }

    private func calendarDate(_ isoDate: String) -> Date? {
        guard let date = Self.isoDayFormatter.date(from: isoDate) else { return nil }
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        return Calendar.current.date(from: DateComponents(year: components.year, month: components.month, day: components.day))
    }
}

// MARK: - Nachrichten

/// Eine Chat-Blase. `Equatable`, damit SwiftUI sie überspringt, solange sich die Nachricht nicht ändert.
private struct ChatMessageRow: View, Equatable {
    let message: TutorMessage
    let copyTitle: String

    static func == (lhs: ChatMessageRow, rhs: ChatMessageRow) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.text == rhs.message.text
            && lhs.message.role == rhs.message.role
            && lhs.copyTitle == rhs.copyTitle
    }

    private var isAssistant: Bool { message.role == "assistant" }

    private var content: Text {
        if isAssistant,
           let attributed = try? AttributedString(
               markdown: message.text,
               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            return Text(attributed)
        }
        return Text(message.text)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isAssistant { Spacer(minLength: 44) }
            content
                .foregroundStyle(isAssistant ? Palette.ink : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(isAssistant ? Palette.lilac : Palette.purple, in: chatBubbleShape(isAssistant: isAssistant))
                .contextMenu {
                    Button { UIPasteboard.general.string = message.text } label: {
                        Label(copyTitle, systemImage: "doc.on.doc")
                    }
                }
            if isAssistant { Spacer(minLength: 44) }
        }
    }
}

private struct TypingBubble: View {
    let label: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.purple)
                    .symbolEffect(.pulse)
                Text(label).font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.lilac, in: chatBubbleShape(isAssistant: true))
            Spacer(minLength: 44)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AppliedResultsCard: View {
    @Environment(LearningStore.self) private var store
    let results: [TutorAppliedResult]
    let onOpen: (TutorOpenTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("Erfolgreich gespeichert"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.green)
            ForEach(results) { result in
                HStack(spacing: 12) {
                    Image(systemName: result.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.purple)
                        .frame(width: 34, height: 34)
                        .background(Palette.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(result.detail).font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 4)
                    if let destination = result.destination {
                        Button(store.t("Öffnen")) { onOpen(destination) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.purple.opacity(0.16)))
    }
}

// MARK: - Eingabe

private struct ChatComposer: View {
    @Environment(LearningStore.self) private var store
    @Bindable var model: ComposerModel
    @Binding var actionMode: TutorActionMode
    let isLoading: Bool
    let onAttachPhoto: () -> Void
    let onAttachPDF: () -> Void
    let onSend: (String) -> Void
    @FocusState private var focused: Bool

    /// Bricht beim ersten Nicht-Leerzeichen ab, statt den ganzen Text zu trimmen.
    private var canSend: Bool { !isLoading && model.text.contains { !$0.isWhitespace } }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                ForEach(TutorActionMode.allCases) { mode in
                    Button { actionMode = mode } label: {
                        Label(store.t(mode.titleKey), systemImage: actionMode == mode ? "checkmark" : mode.symbol)
                    }
                }
            } label: {
                Image(systemName: actionMode.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.purple)
                    .frame(width: 36, height: 36)
                    .background(Palette.lilac, in: Circle())
            }
            .accessibilityLabel(store.t(actionMode.titleKey))

            Menu {
                Button { focused = false; onAttachPhoto() } label: { Label(store.t("Foto auswählen"), systemImage: "photo") }
                Button { focused = false; onAttachPDF() } label: { Label(store.t("PDF auswählen"), systemImage: "doc.text") }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.purple)
                    .frame(width: 36, height: 36)
                    .background(Palette.lilac, in: Circle())
            }
            .disabled(isLoading)
            .accessibilityLabel(store.t("Datei anhängen"))

            TextField(store.t("Stelle eine Frage …"), text: $model.text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.vertical, 7)

            Button(action: submit) {
                Group {
                    if isLoading {
                        ProgressView().tint(Palette.purple)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? Palette.purple : Palette.muted.opacity(0.45))
                    }
                }
                .frame(width: 36, height: 36)
            }
            .disabled(!canSend)
            .accessibilityLabel(store.t("Nachricht senden"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(focused ? Palette.purple.opacity(0.45) : Palette.muted.opacity(0.12), lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        // Bei offener Tastatur schwebt „Schließen“ über dem unteren Rand; der Abstand hält den Senden-Knopf frei.
        .padding(.bottom, focused ? 52 : 10)
        .onChange(of: model.focusToken) { _, _ in focused = true }
        // Ein mehrzeiliges Feld löst `onSubmit` nicht aus: Die Senden-Taste der Tastatur fügt einen Zeilenumbruch ein.
        .onChange(of: model.text) { _, text in
            guard text.hasSuffix("\n") else { return }
            model.text = String(text.dropLast())
            submit()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                    .accessibilityLabel(store.t("Tastatur schließen"))
            }
        }
    }

    private func submit() {
        guard canSend else { return }
        let text = model.text
        model.text = ""
        focused = false
        onSend(text)
    }
}

// MARK: - Vokabel-Kontext

private struct VocabularyContextBar: View {
    @Environment(LearningStore.self) private var store
    @Binding var selectedPairID: UUID?
    @Binding var selectedDeckID: UUID?
    let loading: Bool
    let onPractice: (_ conversation: Bool) -> Void

    /// Ein Durchlauf statt einer Filterung pro Chip.
    private func stats(for pairID: UUID) -> VocabularyStats {
        var result = VocabularyStats()
        for entry in store.vocabulary where entry.languagePairID == pairID {
            result.counts[entry.deckID, default: 0] += 1
            // Hauptordner zählen die Vokabeln ihrer Unterordner mit.
            if let deckID = entry.deckID, let parent = store.vocabularyDecks.first(where: { $0.id == deckID })?.parentID {
                result.counts[parent, default: 0] += 1
            }
            result.total += 1
        }
        return result
    }

    var body: some View {
        let pair = resolveActivePair(store: store, selectedPairID: selectedPairID)
        let decks = store.vocabularyDecks.filter { $0.languagePairID == pair.id }
        let stats = stats(for: pair.id)
        let selectedCount = selectedDeckID.map { stats.counts[$0] ?? 0 } ?? stats.total
        let source = store.vocabularyLanguage(pair.sourceLanguageID)
        let target = store.vocabularyLanguage(pair.targetLanguageID)

        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(store.t("Vokabeln üben")).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Menu {
                    ForEach(store.vocabularyLanguagePairs) { option in
                        if let left = store.vocabularyLanguage(option.sourceLanguageID), let right = store.vocabularyLanguage(option.targetLanguageID) {
                            Button {
                                selectedPairID = option.id
                                selectedDeckID = nil
                            } label: {
                                if option.id == pair.id { Label("\(left.code) → \(right.code)", systemImage: "checkmark") }
                                else { Text("\(left.code) → \(right.code)") }
                            }
                        }
                    }
                } label: {
                    Label("\(source?.code ?? "A") → \(target?.code ?? "B")", systemImage: "character.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Palette.lilac, in: Capsule())
                }
                .accessibilityLabel("\(source?.name ?? "Sprache A") → \(target?.name ?? "Sprache B")")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    FolderChip(title: store.t("Alle"), count: stats.total, active: selectedDeckID == nil) {
                        withAnimation(.snappy) { selectedDeckID = nil }
                    }
                    ForEach(decks.filter { $0.parentID == nil }) { deck in
                        let children = decks.filter { $0.parentID == deck.id }
                        let open = selectedDeckID == deck.id || children.contains(where: { $0.id == selectedDeckID })
                        FolderChip(
                            title: "\(deck.emoji) \(deck.name)".trimmingCharacters(in: .whitespaces),
                            count: stats.counts[deck.id] ?? 0,
                            active: open
                        ) {
                            withAnimation(.snappy) { selectedDeckID = deck.id }
                        }
                        // Unterordner erscheinen direkt hinter ihrem Ordner, sobald er ausgewählt ist.
                        if open {
                            ForEach(children) { child in
                                FolderChip(title: "↳ \(child.name)", count: stats.counts[child.id] ?? 0, active: selectedDeckID == child.id) {
                                    withAnimation(.snappy) { selectedDeckID = child.id }
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                practiceButton(title: "Alltagssituation", symbol: "bubble.left.and.bubble.right", conversation: true, enabled: !loading && selectedCount > 0)
                practiceButton(title: "Vokabeln abfragen", symbol: "questionmark.circle", conversation: false, enabled: !loading && selectedCount > 0)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.canvas)
    }

    private func practiceButton(title: String, symbol: String, conversation: Bool, enabled: Bool) -> some View {
        PracticeButton(title: store.t(title), symbol: symbol, enabled: enabled) { onPractice(conversation) }
    }
}

/// Übungsstart in der Vokabel- und der Begriffeleiste; beide sehen dadurch gleich aus.
private struct PracticeButton: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(Palette.purple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(Palette.purple.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

private struct FolderChip: View {
    let title: String
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title) · \(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(active ? Palette.purple.opacity(0.14) : Palette.surface, in: Capsule())
                .overlay(Capsule().stroke(active ? Palette.purple.opacity(0.32) : Palette.muted.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Vorschlagskarte

private struct AgentPlanCard: View {
    @Environment(LearningStore.self) private var store
    let plan: TutorAgentPlan
    let duplicates: Set<PlanKey>
    let sourceCode: String
    let targetCode: String
    let onReject: () -> Void
    let onApply: (PlanSelection) -> Void
    @State private var selection: PlanSelection

    init(plan: TutorAgentPlan, duplicates: Set<PlanKey>, sourceCode: String, targetCode: String,
         onReject: @escaping () -> Void, onApply: @escaping (PlanSelection) -> Void) {
        self.plan = plan
        self.duplicates = duplicates
        self.sourceCode = sourceCode
        self.targetCode = targetCode
        self.onReject = onReject
        self.onApply = onApply
        _selection = State(initialValue: PlanSelection(plan: plan, duplicates: duplicates))
    }

    private var hasVocabulary: Bool {
        plan.actions.contains { !($0.vocabularyEntries ?? []).isEmpty }
    }

    private var hasSelectedProposal: Bool {
        plan.actions.indices.contains { index in
            let action = plan.actions[index]
            if let cards = action.cards, !cards.isEmpty {
                return cards.indices.contains { selection.flashcards.contains(PlanKey(action: index, item: $0)) }
            }
            if let entries = action.vocabularyEntries, !entries.isEmpty {
                return selection.actions.contains(index) && entries.indices.contains { selection.vocabulary.contains(PlanKey(action: index, item: $0)) }
            }
            return selection.actions.contains(index)
        }
    }

    /// Wie viele Dinge „Übernehmen“ anlegt: einzelne Vokabeln und Karten, sonst ganze Aktionen.
    private var selectedCount: Int {
        plan.actions.indices.reduce(0) { total, index in
            let action = plan.actions[index]
            if let cards = action.cards, !cards.isEmpty {
                return total + cards.indices.filter { selection.flashcards.contains(PlanKey(action: index, item: $0)) }.count
            }
            if let entries = action.vocabularyEntries, !entries.isEmpty {
                guard selection.actions.contains(index) else { return total }
                return total + entries.indices.filter { selection.vocabulary.contains(PlanKey(action: index, item: $0)) }.count
            }
            return total + (selection.actions.contains(index) ? 1 : 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("Vorschlag zur Prüfung"), systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(store.t("Eulio hat noch nichts gespeichert. Wähle aus, welche Vorschläge übernommen werden sollen."))
                .font(.caption)
                .foregroundStyle(Palette.muted)
            ForEach(plan.actions.indices, id: \.self) { index in
                actionSection(index)
            }
            if hasVocabulary {
                Toggle(store.t("Lautschrift übernehmen"), isOn: $selection.includePronunciations).font(.caption).tint(Palette.purple)
                Toggle(store.t("Beispielsätze übernehmen"), isOn: $selection.includeExamples).font(.caption).tint(Palette.purple)
            }
            HStack(spacing: 10) {
                Button(store.t("Ablehnen"), action: onReject)
                    .buttonStyle(SecondaryButtonStyle())
                Button(selectedCount > 0 ? "\(store.t("Übernehmen")) (\(selectedCount))" : store.t("Übernehmen")) { onApply(selection) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!hasSelectedProposal)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Palette.lilac, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    @ViewBuilder private func actionSection(_ index: Int) -> some View {
        let action = plan.actions[index]
        if !(action.vocabularyEntries ?? []).isEmpty {
            vocabularySection(index, action)
        } else if !(action.cards ?? []).isEmpty {
            cardsSection(index, action)
        } else {
            simpleSection(index, action)
        }
    }

    private func checkIcon(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? Palette.purple : Palette.muted)
    }

    /// Kopf einer Aktion: farbiges Symbol, Art der Aktion klein darüber, Name als Überschrift, Details, Auswahl rechts.
    private func actionHeader(_ action: TutorAgentAction, detail: String? = nil, check: some View) -> some View {
        let icon = actionIcon(action)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(icon.color)
                .frame(width: 34, height: 34)
                .background(icon.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(actionKind(action)).font(.caption.weight(.semibold)).foregroundStyle(icon.color)
                Text(actionName(action)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                let text = detail ?? actionDescription(action)
                if !text.isEmpty {
                    Text(text).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.leading).padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            check
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func actionIcon(_ action: TutorAgentAction) -> (symbol: String, color: Color) {
        switch action.type {
        case "create_vocabulary_folder", "add_vocabulary": return ("character.book.closed", Palette.purple)
        case "create_deck", "create_deck_tree", "create_subdeck": return ("rectangle.stack.badge.plus", Palette.purple)
        case "create_cards": return ("plus.rectangle.on.rectangle", Palette.purple)
        case "create_term_subject", "add_terms": return ("text.book.closed", Palette.purple)
        case "update_calendar_entry": return ("calendar.badge.clock", Palette.blue)
        case "delete_calendar_entry": return ("trash", Palette.red)
        case "rename_deck": return ("pencil", Palette.orange)
        case "start_test": return ("graduationcap", Palette.green)
        default: return ("calendar.badge.plus", Palette.blue)
        }
    }

    private func actionKind(_ action: TutorAgentAction) -> String {
        switch action.type {
        case "create_vocabulary_folder": return store.t("Neuer Vokabelordner")
        case "add_vocabulary": return store.t("Vokabeln ergänzen")
        case "create_deck", "create_deck_tree": return store.t("Neues Deck")
        case "create_subdeck": return store.t("Neues Unterdeck")
        case "create_cards": return store.t("Karten ergänzen")
        case "create_term_subject": return store.t("Neues Fach")
        case "add_terms": return store.t("Begriffe ergänzen")
        case "update_calendar_entry": return store.t("Termin ändern")
        case "delete_calendar_entry": return store.t("Termin löschen")
        case "rename_deck": return store.t("Deck umbenennen")
        case "start_test": return store.t("Test starten")
        default: return store.t("Neuer Termin")
        }
    }

    private func actionName(_ action: TutorAgentAction) -> String {
        switch action.type {
        case "create_vocabulary_folder", "add_vocabulary": return action.folderName ?? "?"
        case "create_deck_tree": return "\(action.deckName ?? "?") › \(action.subdeckName ?? "?")"
        case "create_term_subject", "add_terms": return action.subjectName ?? "?"
        case "update_calendar_entry", "delete_calendar_entry": return action.title ?? "?"
        case "create_deck", "create_subdeck", "create_cards", "rename_deck", "start_test": return action.deckName ?? "?"
        default: return action.title ?? store.t("Kalendereintrag")
        }
    }

    private func vocabularySection(_ index: Int, _ action: TutorAgentAction) -> some View {
        let entries = action.vocabularyEntries ?? []
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                if selection.actions.contains(index) {
                    selection.actions.remove(index)
                } else {
                    selection.actions.insert(index)
                    selection.vocabulary.formUnion(entries.indices.map { PlanKey(action: index, item: $0) }.filter { !duplicates.contains($0) })
                }
            } label: {
                actionHeader(action, check: checkIcon(selection.actions.contains(index)))
            }
            .buttonStyle(.plain)

            ForEach(Array(entries.enumerated()), id: \.offset) { number, entry in
                let key = PlanKey(action: index, item: number)
                let isDuplicate = duplicates.contains(key)
                let isSelected = selection.vocabulary.contains(key)
                Button {
                    guard !isDuplicate else { return }
                    if isSelected { selection.vocabulary.remove(key) }
                    else { selection.vocabulary.insert(key); selection.actions.insert(index) }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        checkIcon(isSelected)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(number + 1). \(entry.term) → \(entry.translation)").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                            if !entry.pronunciation.isEmpty { Text(entry.pronunciation).font(.caption2.monospaced()).foregroundStyle(Palette.purple) }
                            if selection.includeExamples && !entry.example.isEmpty { Text(entry.example).font(.caption).foregroundStyle(Palette.muted) }
                            if !entry.synonyms.isEmpty { Text("\(store.t("Synonyme")): \(entry.synonyms.joined(separator: ", "))").font(.caption2).foregroundStyle(Palette.muted) }
                            if isDuplicate { Text(store.t("Bereits im Wörterbuch")).font(.caption2.weight(.semibold)).foregroundStyle(Palette.red) }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDuplicate)
                .opacity(isDuplicate ? 0.65 : 1)
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cardsSection(_ index: Int, _ action: TutorAgentAction) -> some View {
        let cards = action.cards ?? []
        let selectedCount = cards.indices.filter { selection.flashcards.contains(PlanKey(action: index, item: $0)) }.count
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                let keys = cards.indices.map { PlanKey(action: index, item: $0) }
                if selectedCount == cards.count {
                    selection.flashcards.subtract(keys)
                    selection.actions.remove(index)
                } else {
                    selection.flashcards.formUnion(keys)
                    selection.actions.insert(index)
                }
            } label: {
                actionHeader(action, detail: "\(selectedCount)/\(cards.count) \(store.t("Karten ausgewählt")) · \(actionDescription(action))",
                             check: Image(systemName: selectedCount == 0 ? "circle" : (selectedCount == cards.count ? "checkmark.circle.fill" : "minus.circle.fill"))
                                .font(.title3)
                                .foregroundStyle(selectedCount == 0 ? Palette.muted : Palette.purple))
            }
            .buttonStyle(.plain)

            ForEach(Array(cards.enumerated()), id: \.offset) { number, card in
                let key = PlanKey(action: index, item: number)
                let isSelected = selection.flashcards.contains(key)
                Button {
                    if isSelected { selection.flashcards.remove(key) } else { selection.flashcards.insert(key) }
                    if selection.flashcards.contains(where: { $0.action == index }) { selection.actions.insert(index) }
                    else { selection.actions.remove(index) }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        checkIcon(isSelected)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(number + 1). \(card.question)").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text(card.answer).font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func simpleSection(_ index: Int, _ action: TutorAgentAction) -> some View {
        Button {
            if selection.actions.contains(index) { selection.actions.remove(index) } else { selection.actions.insert(index) }
        } label: {
            actionHeader(action, check: checkIcon(selection.actions.contains(index)))
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actionDescription(_ action: TutorAgentAction) -> String {
        if action.type == "create_deck_tree" { return "\(action.cards?.count ?? 0) \(store.t("Karten"))" }
        if action.type == "create_vocabulary_folder" || action.type == "add_vocabulary" {
            return "\(action.vocabularyEntries?.count ?? 0) \(store.t("Vokabeln")) · \(sourceCode) → \(targetCode)"
        }
        if action.type == "create_subdeck" {
            let parentPlan = action.createParentDeck == true ? " · \(store.t("Hauptdeck wird ebenfalls erstellt"))" : ""
            return "\(store.t("Unterdeck in")) \(action.parentDeck ?? "?") · \(action.cards?.count ?? 0) \(store.t("Karten"))\(parentPlan)"
        }
        if action.type == "create_cards" {
            let parent = action.parentDeck.map { " · \(store.t("Deck")): \($0)" } ?? ""
            return "\(action.cards?.count ?? 0) \(store.t("Karten"))\(parent)"
        }
        if action.type == "create_term_subject" || action.type == "add_terms" {
            let entries = action.termEntries ?? []
            let preview = entries.prefix(4).map(\.term).joined(separator: ", ")
            return "\(entries.count) \(store.t("Begriffe"))" + (preview.isEmpty ? "" : " · \(preview)\(entries.count > 4 ? " …" : "")")
        }
        if action.type == "update_calendar_entry" {
            return [action.newTitle.map { "\(store.t("Neuer Titel")): \($0)" }, action.newDateISO.map { "\(store.t("Neues Datum")): \($0)" }].compactMap { $0 }.joined(separator: " · ")
        }
        if action.type == "delete_calendar_entry" { return store.t("Der Eintrag wird aus dem Kalender entfernt.") }
        if action.type == "rename_deck" { return "\(store.t("Neuer Name")): \(action.newName ?? "?")" }
        if action.type == "start_test" { return store.t("Alle Karten des Decks als Probeprüfung, ohne KI-Bewertung.") }
        let linkedDeck = action.deckName.map { " · \(store.t("Deck")): \($0)" } ?? ""
        return "\(action.dateISO ?? "") · \(action.kind ?? "other")\(linkedDeck)"
    }
}


// MARK: - Begriffe im Tutor

/// Fachauswahl und Übungsknöpfe für Begriffe, analog zur Vokabelleiste.
private struct TermContextBar: View {
    @Environment(LearningStore.self) private var store
    @Binding var selectedSubjectID: UUID?
    let loading: Bool
    let onPractice: (_ explain: Bool) -> Void

    var body: some View {
        let count = store.terms.filter { selectedSubjectID == nil || $0.subjectID == selectedSubjectID }.count
        VStack(alignment: .leading, spacing: 9) {
            Text(store.t("Begriffe üben")).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    FolderChip(title: store.t("Alle"), count: store.terms.count, active: selectedSubjectID == nil) {
                        withAnimation(.snappy) { selectedSubjectID = nil }
                    }
                    ForEach(store.termSubjects) { subject in
                        FolderChip(
                            title: "\(subject.emoji) \(subject.name)".trimmingCharacters(in: .whitespaces),
                            count: store.terms.filter { $0.subjectID == subject.id }.count,
                            active: selectedSubjectID == subject.id
                        ) { withAnimation(.snappy) { selectedSubjectID = subject.id } }
                    }
                }
            }
            HStack(spacing: 8) {
                practiceButton(title: "Erklären", symbol: "lightbulb", explain: true, enabled: !loading && count > 0)
                practiceButton(title: "Abfragen", symbol: "questionmark.circle", explain: false, enabled: !loading && count > 0)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.canvas)
    }

    private func practiceButton(title: String, symbol: String, explain: Bool, enabled: Bool) -> some View {
        PracticeButton(title: store.t(title), symbol: symbol, enabled: enabled) { onPractice(explain) }
    }
}
