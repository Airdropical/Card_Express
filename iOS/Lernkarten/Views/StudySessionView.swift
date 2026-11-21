import SwiftUI
import NaturalLanguage

enum StudyMode: String, Identifiable { case review, exam; var id: String { rawValue } }

struct StudySessionConfiguration: Identifiable {
    let id = UUID()
    let mode: StudyMode
    let useAI: Bool
}

struct StudySessionSetupSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: StudyMode
    let defaultUseAI: Bool
    let onStart: (Bool) -> Void
    @State private var useAI: Bool

    init(mode: StudyMode, defaultUseAI: Bool, onStart: @escaping (Bool) -> Void) {
        self.mode = mode
        self.defaultUseAI = defaultUseAI
        self.onStart = onStart
        _useAI = State(initialValue: defaultUseAI && LearningAPI.shared.canUseAI)
    }
    private let signedIn = LearningAPI.shared.canUseAI

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(store.t("Wie möchtest du lernen?")).font(.title2.bold())
                Picker(store.t("Bewertungsmethode"), selection: $useAI) {
                    Text(store.t("Mit KI")).tag(true)
                    Text(store.t("Ohne KI")).tag(false)
                }.pickerStyle(.segmented)
                Label(store.t(useAI
                    ? "Tippe deine Antwort ein. Die KI bewertet sie und gibt Feedback."
                    : "Tippe die Karte an, decke die Antwort auf und bewerte dich selbst."),
                    systemImage: useAI ? "sparkles" : "hand.tap")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                if useAI && !signedIn {
                    ErrorMessageCard(message: store.t(LearningAPI.shared.hasSession ? "Aktiviere die KI-Funktionen in den Einstellungen, um sie zu nutzen." : "Melde dich in den Einstellungen an, um die KI-Funktionen zu nutzen."))
                }
                Spacer()
                Button(store.t(mode == .exam ? "Probeprüfung starten" : "Lernen starten")) {
                    onStart(useAI)
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(useAI && !signedIn).opacity(useAI && !signedIn ? 0.5 : 1)
            }.padding(22).background(Palette.canvas)
                .navigationTitle(store.t(mode == .exam ? "Probeprüfung" : "Lernen"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } } }
        }.presentationDetents([.medium])
    }
}

struct StudySessionView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    let mode: StudyMode
    let useAI: Bool
    /// Für Tests, die nicht aus den Karten eines Decks bestehen (z. B. vom Tutor geschriebene Fragen).
    /// Ihre Bewertungen ändern keine Wiedervorlage; nur die Lernzeit zählt.
    var customCards: [Flashcard]? = nil
    var customTitle: String? = nil
    /// Hinweis über der ersten Karte, z. B. warum statt eines Tutor-Tests die eigenen Karten kommen.
    var customNotice: String? = nil
    var onFinished: (() -> Void)? = nil
    init(deckID: UUID, mode: StudyMode = .review, useAI: Bool = true, customCards: [Flashcard]? = nil, customTitle: String? = nil, customNotice: String? = nil, onFinished: (() -> Void)? = nil) {
        self.deckID = deckID; self.mode = mode; self.useAI = useAI
        self.customCards = customCards; self.customTitle = customTitle; self.customNotice = customNotice; self.onFinished = onFinished
    }
    @State private var queue: [Flashcard] = []
    @State private var cursor = 0
    @State private var answer = ""
    @State private var evaluation: Evaluation?
    @State private var result = SessionResult()
    @State private var isEvaluating = false
    @State private var errorText: String?
    @State private var showingTutor = false
    @State private var finished = false
    @State private var selfAnswerVisible = false
    @State private var questionStartedAt = Date()
    private var deck: Deck? { store.decks.first { $0.id == deckID } }
    private var current: Flashcard? { queue.indices.contains(cursor) ? queue[cursor] : nil }
    private var cardAnswerVisible: Bool { selfAnswerVisible || evaluation != nil }

    var body: some View {
        NavigationStack {
            Group {
                if finished { resultView }
                else if let current { cardView(current) }
                else { ContentUnavailableView(store.t("Keine Karten"), systemImage: "rectangle.stack") }
            }.background(Palette.canvas).toolbar {
                ToolbarItem(placement: .principal) { Text(customTitle ?? deck?.name ?? store.t("Lernen")).font(.headline).lineLimit(1) }
                ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.accessibilityLabel(store.t("Lernen beenden")) }
            }
        }.onAppear { prepareSession(); questionStartedAt = Date() }
            .onChange(of: finished) { _, done in if done { onFinished?() } }
            .sheet(isPresented: $showingTutor) { if let current { CardTutorSheet(card: current) } }
    }

    @ViewBuilder private func cardView(_ card: Flashcard) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                if let customNotice, cursor == 0 {
                    Text(customNotice).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                HStack { Text("\(min(cursor + 1, displayTotal)) / \(displayTotal)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted); Spacer(); Text(store.t(mode == .exam ? "PROBEPRÜFUNG" : "WIEDERHOLUNG")).font(.caption.bold()).foregroundStyle(Palette.purple).padding(.horizontal, 10).padding(.vertical, 6).background(Palette.lilac, in: Capsule()) }.padding(.horizontal, 20)
                GeometryReader { geo in Capsule().fill(Palette.lilac).overlay(alignment: .leading) { Capsule().fill(Palette.purple).frame(width: geo.size.width * min(CGFloat(answeredCount) / CGFloat(max(displayTotal, 1)), 1)) } }.frame(height: 6).padding(.horizontal, 20)
                    .animation(.easeOut(duration: 0.25), value: answeredCount)
                    .accessibilityHidden(true)
                SurfaceCard {
                    VStack(spacing: 14) {
                        Text(store.t(cardAnswerVisible ? "ANTWORT" : "FRAGE")).font(.caption.bold()).foregroundStyle(Palette.muted)
                        if cardAnswerVisible {
                            Text(card.question).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                            Divider()
                        }
                        Text(cardAnswerVisible ? card.answer : card.question)
                            .font(.system(.title2, design: .rounded).weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
                    .cardFlipFace(isFlipped: cardAnswerVisible)
                }
                .cardFlipContainer(isFlipped: cardAnswerVisible)
                .padding(.horizontal, 18)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture {
                    guard !useAI else { return }
                    selfAnswerVisible.toggle()
                }
                .accessibilityAddTraits(useAI ? [] : .isButton)
                if let evaluation {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            if useAI {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(store.t("Deine Antwort")).font(.caption.bold()).foregroundStyle(Palette.muted)
                                    Text(answer.isEmpty ? store.t("Keine Antwort eingegeben.") : answer).font(.body)
                                }
                                Divider()
                            }
                            Text("\(store.t(evaluation.rating.title)) · \(evaluation.feedback)").font(.subheadline).foregroundStyle(evaluation.rating.color)
                        }
                    }.padding(.horizontal, 18)
                }
            }.padding(.top, 12).padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            bottomBar(card).padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
                .frame(maxWidth: .infinity).background(.bar)
        }
    }

    /// Alle Aktionen sitzen unten in Daumenreichweite; die Karte darüber scrollt bei langen Texten.
    @ViewBuilder private func bottomBar(_ card: Flashcard) -> some View {
        if evaluation != nil {
            HStack(spacing: 12) {
                if useAI { Button(store.t("Begründung")) { showingTutor = true }.buttonStyle(.bordered).controlSize(.large) }
                Button(store.t("Nächste Frage")) { goNext() }.buttonStyle(PrimaryButtonStyle())
            }
        } else if useAI {
            VStack(spacing: 10) {
                if let errorText {
                    ErrorMessageCard(message: errorText)
                    Text(store.t("Die KI-Bewertung ist nicht verfügbar. Bewerte deine Antwort selbst."))
                        .font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                    selfRateRow(card)
                }
                HStack(spacing: 10) { TextField(store.t("Gib deine Antwort ein …"), text: $answer, axis: .vertical).lineLimit(1...4); Button { Task { await submit() } } label: { Group { if isEvaluating { ProgressView().tint(.white) } else { Image(systemName: "sparkles").font(.title2) } }.foregroundStyle(.white).frame(width: 26, height: 26).padding(13).background(Palette.purple.opacity(isEvaluating || answer.isEmpty ? 0.45 : 1), in: Circle()) }.accessibilityLabel(store.t("Antwort bewerten lassen")).disabled(isEvaluating || answer.isEmpty) }
                    .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.06)))
                Button(store.t("Ich weiß die Antwort nicht")) { revealUnknown() }.font(.subheadline).foregroundStyle(Palette.muted).disabled(isEvaluating)
            }
        } else if selfAnswerVisible {
            VStack(spacing: 10) {
                Text(store.t("Wie leicht fiel dir die Antwort?")).font(.subheadline.weight(.medium))
                selfRateRow(card)
            }
        } else {
            Button(store.t("Antwort zeigen")) { selfAnswerVisible = true }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private func selfRateRow(_ card: Flashcard) -> some View {
        HStack(spacing: 8) {
            selfRateButton(store.t("Falsch"), rating: .wrong, card: card)
            selfRateButton(store.t("Mühsam"), rating: .hard, card: card)
            selfRateButton(store.t("Gut"), rating: .good, card: card)
            selfRateButton(store.t("Einfach"), rating: .easy, card: card)
        }
    }

    private var resultView: some View {
        VStack(spacing: 24) {
            Text(store.t("Deine Lernsession ist beendet! 🎉")).font(.title2.bold()).multilineTextAlignment(.center).padding(.top, 30)
            Text(store.t("Deine Leistung")).font(.headline)
            VStack(spacing: 12) { scoreRow(store.t("Einfach"), value: result.easy, color: Palette.green); scoreRow(store.t("Gut"), value: result.good, color: Palette.blue); scoreRow(store.t("Mühsam"), value: result.hard, color: Palette.orange); scoreRow(store.t("Falsch"), value: result.wrong, color: Palette.red) }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
            Text(store.tf("%d Abfragen · %d Karten im Deck", result.total, deck?.cards.count ?? queue.count)).font(.subheadline).foregroundStyle(Palette.muted)
            HStack(spacing: 10) { Button(store.t("Lernen beenden")) { dismiss() }.buttonStyle(SecondaryButtonStyle()); Button(store.t("Weiterlernen")) { restart() }.buttonStyle(PrimaryButtonStyle()) }
            Spacer()
        }.padding(20)
    }
    private var displayTotal: Int { queue.count }
    private var answeredCount: Int { cursor + (evaluation == nil ? 0 : 1) }
    private func scoreRow(_ title: String, value: Int, color: Color) -> some View { HStack { Text(title); Spacer(); Text("\(value)").bold().foregroundStyle(color).padding(10).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)) } }
    /// Selbstbewertung zählt sofort und geht direkt zur nächsten Karte, ohne Zwischenschritt.
    private func selfRateButton(_ title: String, rating: CardRating, card: Flashcard) -> some View {
        Button { record(rating, card: card); goNext() } label: {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(rating.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func prepareSession() {
        if let customCards {
            if queue.isEmpty { queue = customCards }
            return
        }
        guard queue.isEmpty, let cards = deck?.cards, !cards.isEmpty else { return }
        if mode == .exam {
            queue = store.randomOrder ? cards.shuffled() : cards
            return
        }
        let due = cards.filter(\.dueToday)
        let notDue = cards.filter { !$0.dueToday }
        let firstCycle = store.randomOrder ? due.shuffled() + notDue.shuffled() : due + notDue
        // Fällige Karten zuerst; jede Karte höchstens einmal pro Sitzung.
        queue = Array(firstCycle.prefix(max(min(store.sessionSize, cards.count), 1)))
    }
    private func restart() { cursor = 0; result = SessionResult(); finished = false; queue = []; prepareSession(); questionStartedAt = Date() }
    @MainActor private func submit() async {
        guard let card = current, evaluation == nil, !isEvaluating else { return }
        isEvaluating = true; errorText = nil; defer { isEvaluating = false }
        do { evaluation = try await LearningAPI.shared.evaluate(question: card.question, expected: card.answer, answer: answer, language: feedbackLanguage(for: card), mode: mode == .exam ? "exam" : "study") }
        catch {
            errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
            return
        }
        record(evaluation!.rating, card: card)
    }

    private func feedbackLanguage(for card: Flashcard) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString("\(card.question)\n\(card.answer)")
        guard let detected = recognizer.dominantLanguage,
              (recognizer.languageHypotheses(withMaximum: 1)[detected] ?? 0) >= 0.35,
              let languageName = Locale(identifier: "en").localizedString(forLanguageCode: detected.rawValue) else {
            return store.language == "Englisch" ? "English" : "German"
        }
        return languageName
    }
    private func revealUnknown() {
        guard let card = current, evaluation == nil, !isEvaluating else { return }
        evaluation = Evaluation(rating: .wrong, feedback: store.t("Du wusstest die Antwort nicht."))
        record(.wrong, card: card)
    }
    private func record(_ rating: CardRating, card: Flashcard) {
        switch rating { case .easy: result.easy += 1; case .good: result.good += 1; case .hard: result.hard += 1; case .wrong: result.wrong += 1 }
        let duration = Date().timeIntervalSince(questionStartedAt)
        if customCards != nil { store.recordPractice(duration: duration) }
        else { store.record(rating, cardID: card.id, deckID: deckID, duration: duration) }
    }
    private func goNext() {
        answer = ""; evaluation = nil; errorText = nil; selfAnswerVisible = false; questionStartedAt = Date()
        if cursor + 1 >= queue.count { finished = true } else { cursor += 1 }
    }
}

private extension CardRating {
    var title: String { switch self { case .easy: "Einfach"; case .good: "Gut"; case .hard: "Mühsam"; case .wrong: "Falsch" } }
    var color: Color { switch self { case .easy: Palette.green; case .good: Palette.blue; case .hard: Palette.orange; case .wrong: Palette.red } }
}
