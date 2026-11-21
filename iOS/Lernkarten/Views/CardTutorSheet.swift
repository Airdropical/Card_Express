import SwiftUI

struct CardTutorSheet: View {
    @Environment(LearningStore.self) private var store
    let card: Flashcard
    @State private var messages: [TutorMessage] = []
    @State private var input = ""
    @State private var loading = false
    @State private var errorText: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Text(store.tf("Frage: %@", card.question)).font(.headline)
                        Text(store.tf("Antwort: %@", card.answer)).font(.subheadline).foregroundStyle(Palette.muted)
                        if messages.isEmpty { Text(store.t("Frag mich, warum die Antwort so lautet oder lass dir das Thema erklären.")).padding(14).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 14)) }
                        ForEach(messages) { message in HStack { if message.role == "assistant" { Text(message.text).padding(14).background(Palette.lilac, in: RoundedRectangle(cornerRadius: 15)); Spacer(minLength: 40) } else { Spacer(minLength: 40); Text(message.text).padding(14).foregroundStyle(.white).background(Palette.purple, in: RoundedRectangle(cornerRadius: 15)) } } }
                        if let errorText { ErrorMessageCard(message: errorText) }
                    }.padding()
                }
                HStack { TextField(store.t("Stelle eine Frage zu dieser Karte"), text: $input, axis: .vertical).lineLimit(1...3); Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(Palette.purple) }.accessibilityLabel(store.t("Nachricht senden")).disabled(input.isEmpty || loading) }.padding().background(Palette.surface)
            }.background(Palette.canvas).navigationTitle(store.t("KI-Lerncoach")).navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.large])
    }
    @MainActor private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        input = ""; messages.append(TutorMessage(role: "user", text: text)); loading = true; defer { loading = false }
        do { let reply = try await LearningAPI.shared.tutor(question: card.question, answer: card.answer, message: text, history: Array(messages.dropLast()), language: store.language); messages.append(TutorMessage(role: "assistant", text: reply.reply)); errorText = nil }
        catch { errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language) }
    }
}
