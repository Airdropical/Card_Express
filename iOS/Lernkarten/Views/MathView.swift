import SwiftUI

// MARK: - Übersicht

/// Mathe-Bereich: Formelsammlung je Thema, KI-Aufgaben mit Rechenweg und Stärken/Schwächen aus dem Backend.
struct MathView: View {
    @Environment(LearningStore.self) private var store
    @AppStorage("learncards.math.level") private var levelRaw = MathLevel.middle.rawValue
    @State private var profile: [String: MathTopicStanding] = [:]

    private var level: MathLevel { MathLevel(rawValue: levelRaw) ?? .middle }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.t("Mathe")).font(.largeTitle.bold())
                    Picker(store.t("Stufe"), selection: $levelRaw) {
                        ForEach(MathLevel.allCases) { item in Text(store.t(item.titleKey)).tag(item.rawValue) }
                    }.pickerStyle(.segmented)
                    if !LearningAPI.shared.canUseAI {
                        Label(store.t(LearningAPI.shared.hasSession
                            ? "Aktiviere die KI-Funktionen in den Einstellungen, um Aufgaben zu erhalten. Die Formeln stehen dir auch so zur Verfügung."
                            : "Melde dich in den Einstellungen an, um Aufgaben zu erhalten. Die Formeln stehen dir auch so zur Verfügung."),
                              systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Palette.muted)
                    }
                    summary
                    ForEach(MathCatalog.topics(for: level)) { topic in
                        NavigationLink(value: topic) { topicRow(topic) }.buttonStyle(.plain)
                    }
                }.padding(18)
            }
            .background(Palette.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MathTopic.self) { topic in
                MathTopicView(topic: topic, standing: profile[topic.id]) { updated in profile[topic.id] = updated }
            }
            .task { await loadProfile() }
            .refreshable { await loadProfile() }
        }
    }

    @MainActor private func loadProfile() async {
        guard LearningAPI.shared.canUseAI, let loaded = try? await LearningAPI.shared.mathProfile() else { return }
        profile = loaded.topics
    }

    /// Stärken und Schwächen der aktuellen Stufe auf einen Blick.
    @ViewBuilder private var summary: some View {
        let topics = MathCatalog.topics(for: level)
        let strong = topics.filter { profile[$0.id]?.status == "strength" }
        let weak = topics.filter { profile[$0.id]?.status == "weakness" }
        if !strong.isEmpty || !weak.isEmpty {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    if !strong.isEmpty {
                        Label(store.t("Stärken") + ": " + strong.map(\.name).joined(separator: ", "), systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(Palette.green)
                    }
                    if !weak.isEmpty {
                        Label(store.t("Üben lohnt sich") + ": " + weak.map(\.name).joined(separator: ", "), systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Palette.orange)
                    }
                }.font(.subheadline.weight(.medium))
            }
        }
    }

    private func topicRow(_ topic: MathTopic) -> some View {
        let standing = profile[topic.id]
        return SurfaceCard {
            HStack(spacing: 14) {
                Image(systemName: topic.symbol).font(.title3).foregroundStyle(Palette.purple)
                    .frame(width: 44, height: 44).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(topic.name).font(.headline).foregroundStyle(Palette.ink)
                    Text(store.tf("%d Formeln", topic.formulas.count)).font(.caption).foregroundStyle(Palette.muted)
                    if let mastery = standing?.mastery {
                        ProgressView(value: mastery).tint(statusColor(standing?.status))
                    }
                }
                Spacer()
                if let standing, standing.status != "new" { StatusBadge(status: standing.status) }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Palette.muted)
            }
        }
    }
}

private func statusColor(_ status: String?) -> Color {
    switch status {
    case "strength": return Palette.green
    case "weakness": return Palette.orange
    default: return Palette.purple
    }
}

private struct StatusBadge: View {
    @Environment(LearningStore.self) private var store
    let status: String
    var body: some View {
        let title = status == "strength" ? "Stärke" : status == "weakness" ? "Schwäche" : "Im Training"
        Text(store.t(title)).font(.caption.bold()).foregroundStyle(statusColor(status))
            .padding(.horizontal, 8).padding(.vertical, 4).background(statusColor(status).opacity(0.12), in: Capsule())
    }
}

// MARK: - Thema

private struct MathTopicView: View {
    @Environment(LearningStore.self) private var store
    let topic: MathTopic
    let standing: MathTopicStanding?
    let onStandingChange: (MathTopicStanding) -> Void
    @State private var difficulty: Int?
    @State private var practising: MathPractice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(topic.name).font(.title2.bold())
                            Spacer()
                            if let standing, standing.status != "new" { StatusBadge(status: standing.status) }
                        }
                        if let standing, standing.attempts > 0 {
                            Text(store.tf("%d Aufgaben gelöst · nächste Stufe %d von 5", standing.attempts, standing.nextDifficulty))
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Picker(store.t("Schwierigkeit"), selection: $difficulty) {
                            Text(store.t("Automatisch")).tag(Int?.none)
                            ForEach(1...5, id: \.self) { value in Text(store.tf("Stufe %d", value)).tag(Optional(value)) }
                        }
                        Button { practising = MathPractice(difficulty: difficulty) } label: {
                            Label(store.t("Aufgabe erstellen"), systemImage: "sparkles")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!LearningAPI.shared.canUseAI)
                        .opacity(LearningAPI.shared.canUseAI ? 1 : 0.5)
                    }
                }
                Text(store.t("Formeln")).font(.headline)
                ForEach(topic.formulas) { formula in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(formula.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            Text(formula.formula).font(.system(.body, design: .serif)).textSelection(.enabled)
                            if !formula.note.isEmpty { Text(formula.note).font(.caption).foregroundStyle(Palette.muted) }
                        }
                    }
                }
            }.padding(18)
        }
        .background(Palette.canvas)
        .navigationTitle(topic.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $practising) { practice in
            MathTaskView(topic: topic, fixedDifficulty: practice.difficulty, onStandingChange: onStandingChange)
        }
    }
}

private struct MathPractice: Identifiable {
    let id = UUID()
    let difficulty: Int?
}

// MARK: - Aufgabe und Rechenweg

private struct MathStep: Identifiable, Equatable {
    let id = UUID()
    var text = ""
}

private struct MathTaskView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let topic: MathTopic
    let fixedDifficulty: Int?
    let onStandingChange: (MathTopicStanding) -> Void

    @State private var task: MathTask?
    @State private var loading = false
    @State private var errorText: String?
    @State private var showingHint = false
    @State private var showingSolution = false
    @State private var steps = [MathStep()]
    @State private var answer = ""
    @State private var checking = false
    @State private var result: MathCheckResult?
    @State private var gaveUp = false
    @State private var recentQuestions: [String] = []
    @FocusState private var focus: UUID?
    @FocusState private var answerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let task { taskContent(task) }
                    else if loading { loadingCard }
                    if let errorText { ErrorMessageCard(message: errorText) }
                }.padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas)
            .navigationTitle(topic.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                        .accessibilityLabel(store.t("Schließen"))
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { if task == nil { await loadTask() } }
        }
    }

    private var loadingCard: some View {
        SurfaceCard {
            VStack(spacing: 12) {
                ProgressView()
                Text(store.t("Die KI erstellt deine Aufgabe …")).font(.subheadline).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    @ViewBuilder private func taskContent(_ task: MathTask) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.t("AUFGABE")).font(.caption.bold()).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(store.tf("Stufe %d", task.difficulty)).font(.caption.bold()).foregroundStyle(Palette.purple)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Palette.lilac, in: Capsule())
                }
                Text(task.question).font(.system(.title3, design: .serif)).textSelection(.enabled)
                if !task.hint.isEmpty {
                    if showingHint {
                        Label(task.hint, systemImage: "lightbulb").font(.subheadline).foregroundStyle(Palette.muted)
                    } else {
                        Button { withAnimation { showingHint = true } } label: { Label(store.t("Tipp anzeigen"), systemImage: "lightbulb") }
                            .font(.subheadline).foregroundStyle(Palette.purple)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text(store.t("Rechenweg")).font(.headline)
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                stepRow(index: index, step: step)
            }
            Button {
                let new = MathStep()
                steps.append(new)
                focus = new.id
            } label: { Label(store.t("Schritt hinzufügen"), systemImage: "plus.circle") }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.purple)
                .disabled(result != nil || steps.count >= 40)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("Ergebnis")).font(.headline)
            TextField(store.t("z. B. x = 2"), text: $answer)
                .font(.system(.body, design: .serif))
                .focused($answerFocused)
                .submitLabel(.done)
                .onSubmit { answerFocused = false }
                .padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .disabled(result != nil)
        }

        if let result { resultCard(result, task: task) }
    }

    private func stepRow(index: Int, step: MathStep) -> some View {
        let isWrong = result.map { $0.firstErrorStep == index + 1 } ?? false
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1).").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(isWrong ? Palette.red : Palette.muted)
                .frame(width: 26, alignment: .trailing).padding(.top, 12)
            TextField(store.t("Schritt"), text: Binding(get: { steps.indices.contains(index) ? steps[index].text : "" },
                                                        set: { if steps.indices.contains(index) { steps[index].text = $0 } }), axis: .vertical)
                .font(.system(.body, design: .serif))
                .focused($focus, equals: step.id)
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isWrong ? Palette.red : .clear, lineWidth: 1.5))
                .disabled(result != nil)
            if steps.count > 1 && result == nil {
                Button { steps.removeAll { $0.id == step.id } } label: {
                    Image(systemName: "minus.circle").foregroundStyle(Palette.muted)
                }.padding(.top, 12).accessibilityLabel(store.t("Schritt löschen"))
            }
        }
    }

    private func resultCard(_ result: MathCheckResult, task: MathTask) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                if gaveUp {
                    // Aufgegeben: keine Bewertung zeigen, nur die Lösung.
                    Label(store.t("Lösung"), systemImage: "lightbulb.fill").font(.headline).foregroundStyle(Palette.purple)
                } else {
                    Label(store.t(result.correct ? "Richtig gelöst" : result.score > 0 ? "Teilweise richtig" : "Noch nicht richtig"),
                          systemImage: result.correct ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.headline).foregroundStyle(result.correct ? Palette.green : result.score > 0 ? Palette.orange : Palette.red)
                    Text(result.feedback).font(.body)
                }
                if !gaveUp && result.firstErrorStep > 0 {
                    Text(store.tf("Der erste Fehler steckt in Schritt %d.", result.firstErrorStep)).font(.subheadline).foregroundStyle(Palette.red)
                }
                DisclosureGroup(store.t("Musterlösung"), isExpanded: $showingSolution) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(task.solutionSteps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)").font(.system(.subheadline, design: .serif))
                        }
                        Text(task.finalAnswer.contains("=") ? "→ \(task.finalAnswer)" : "= \(task.finalAnswer)").font(.system(.subheadline, design: .serif).weight(.semibold))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }.tint(Palette.purple)
            }
        }
    }

    /// Mathezeichen über der Tastatur; sie werden ans Ende des gerade bearbeiteten Feldes angefügt.
    private var symbolBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MathCatalog.symbols, id: \.self) { symbol in
                        Button(symbol) { insert(symbol) }
                            .font(.system(.body, design: .serif)).frame(minWidth: 34, minHeight: 34)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            // Die Schritt-Felder sind mehrzeilig, Return schließt die Tastatur dort nicht.
            Button { dismissKeyboard() } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.body.weight(.semibold)).foregroundStyle(Palette.purple)
                    .frame(width: 44, height: 34)
                    .background(Palette.lilac, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(store.t("Tastatur schließen"))
        }
    }

    private func dismissKeyboard() {
        focus = nil
        answerFocused = false
    }

    private func insert(_ symbol: String) {
        if answerFocused { answer += symbol; return }
        guard let id = focus, let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].text += symbol
    }

    @ViewBuilder private var bottomBar: some View {
        if task != nil {
            VStack(spacing: 10) {
            // Beim Schreiben: Mathezeichen direkt über den Knöpfen, damit sie neben der Tastatur erreichbar sind.
            if result == nil && (focus != nil || answerFocused) { symbolBar }
            HStack(spacing: 12) {
                if result == nil {
                    Button(store.t("Lösung zeigen")) { withAnimation { showingSolution = true }; Task { await check(givingUp: true) } }
                        .buttonStyle(SecondaryButtonStyle()).disabled(checking)
                    Button { Task { await check(givingUp: false) } } label: {
                        if checking { ProgressView().tint(.white) } else { Text(store.t("Prüfen")) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(checking || answer.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button(store.t("Nächste Aufgabe")) { Task { await loadTask() } }.buttonStyle(PrimaryButtonStyle()).disabled(loading)
                }
            }
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
            .background(.bar)
        }
    }

    @MainActor private func loadTask() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let next = try await LearningAPI.shared.mathTask(topic: topic, difficulty: fixedDifficulty, language: store.language, recentQuestions: recentQuestions)
            task = next
            recentQuestions.append(next.question)
            steps = [MathStep()]
            answer = ""
            result = nil
            showingHint = false
            showingSolution = false
        } catch {
            errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
        }
    }

    /// Prüft den Rechenweg. „Lösung zeigen“ zählt als nicht gelöst, damit die Schwierigkeit passend sinkt.
    @MainActor private func check(givingUp: Bool) async {
        guard let task else { return }
        checking = true
        errorText = nil
        focus = nil
        answerFocused = false
        defer { checking = false }
        do {
            let filled = steps.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let checked = try await LearningAPI.shared.mathCheck(topic: topic, task: task, steps: givingUp ? [] : filled, answer: givingUp ? "" : answer, language: store.language)
            gaveUp = givingUp
            withAnimation { result = checked }
            if givingUp { showingSolution = true }
            onStandingChange(checked.topic)
            store.recordPractice(duration: 0)
        } catch {
            errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
        }
    }
}
