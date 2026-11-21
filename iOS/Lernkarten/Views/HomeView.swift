import SwiftUI

struct HomeView: View {
    @Environment(LearningStore.self) private var store
    @Binding var tab: AppTab
    let openAI: () -> Void
    let openDeck: (UUID) -> Void
    @State private var showingSettings = false
    @State private var showingCardSearch = false
    @State private var showingCalendar = false
    @State private var activeTest: DailyTestOffer?
    @State private var metricHelp: MetricHelp?
    private var flashcardCount: Int { store.decks.reduce(0) { $0 + $1.cards.count } }
    private var vocabularyCount: Int { store.vocabulary.count }
    private var upcomingCalendarEntries: [CalendarEntry] { store.allCalendarEntries.filter { Calendar.current.startOfDay(for: $0.date) >= Calendar.current.startOfDay(for: Date()) }.prefix(3).map { $0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(store.t("Guten Tag 👋")).font(.title2.bold()); Text(store.t("Dein Lernmoment wartet.")).foregroundStyle(Palette.muted) }; Spacer(); Menu {
                        Button { tab = .decks } label: { Label(store.t("Neues Deck"), systemImage: "plus") }
                        Button { showingCardSearch = true } label: { Label(store.t("Karte suchen"), systemImage: "magnifyingglass") }
                        Button { tab = .more; openAI() } label: { Label(store.t("KI-Karteikarten"), systemImage: "sparkles") }
                        Divider()
                        Button { showingSettings = true } label: { Label(store.t("Einstellungen"), systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 27)).foregroundStyle(Palette.purple) }.accessibilityLabel(store.t("Weitere Optionen")) }
                    testsCard
                    SurfaceCard { HStack(spacing: 14) { Text(store.t("🔥")).font(.system(size: 34)); VStack(alignment: .leading, spacing: 4) { HStack { Text(store.t("Deine Streak")).font(.headline); Button { metricHelp = .streak } label: { Image(systemName: "info.circle").foregroundStyle(Palette.muted) }.buttonStyle(.plain).accessibilityLabel(store.t("Informationen zur Streak")) }; Text(store.t("Lerne heute weiter, um dranzubleiben.")).font(.subheadline).foregroundStyle(Palette.muted) }; Spacer(); Text("\(store.currentStreak) \(store.t(store.currentStreak == 1 ? "Tag" : "Tage"))").font(.headline).foregroundStyle(Palette.purple) } }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.t("Dein Lernmaterial")).font(.headline)
                            HStack(spacing: 10) {
                                Button { tab = .decks } label: { dueLearningTile(title: store.t("Karten"), count: flashcardCount, symbol: "rectangle.stack") }
                                Button { tab = .vocabulary } label: { dueLearningTile(title: store.t("Vokabeln"), count: vocabularyCount, symbol: "character.book.closed") }
                            }.buttonStyle(.plain)
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(store.t("Termine"), systemImage: "calendar").font(.headline)
                                Spacer()
                                Button(store.t("Kalender")) { showingCalendar = true }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.purple)
                            }
                            if upcomingCalendarEntries.isEmpty {
                                Text(store.t("Keine anstehenden Termine. Füge einen Test oder eine Prüfung hinzu."))
                                    .font(.subheadline).foregroundStyle(Palette.muted)
                            } else {
                                ForEach(upcomingCalendarEntries) { entry in
                                    Button { if let deckID = entry.deckID, store.decks.contains(where: { $0.id == deckID }) { openDeck(deckID) } else { showingCalendar = true } } label: {
                                        HStack(spacing: 12) {
                                            RoundedRectangle(cornerRadius: 3).fill(entry.kind == .exam ? Palette.purple : Palette.lilac).frame(width: 4, height: 38)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                                                Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Palette.muted)
                                            }
                                            Spacer()
                                            Text(daysLabel(entry.date)).font(.caption.weight(.semibold)).foregroundStyle(Palette.purple)
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(store.t("Lernzeit diese Woche")).font(.headline); Button { metricHelp = .time } label: { Image(systemName: "info.circle").foregroundStyle(Palette.muted) }.buttonStyle(.plain).accessibilityLabel(store.t("Informationen zur Lernzeit")); Spacer() }
                            Text(store.studyTimeThisWeekLabel).font(.title2.bold()).foregroundStyle(Palette.purple)
                            let values = store.studySecondsByDayThisWeek
                            let dates = store.studyDatesThisWeek
                            let maxValue = max(values.max() ?? 0, 1)
                            HStack(alignment: .bottom, spacing: 8) {
                                ForEach(values.indices, id: \.self) { i in
                                    VStack(spacing: 5) {
                                        Spacer(minLength: 0)
                                        RoundedRectangle(cornerRadius: 5).fill(Calendar.current.isDateInToday(dates[i]) ? Palette.purple : Palette.lilac).frame(height: max(5, CGFloat(values[i] / maxValue) * 58))
                                        Text(dates[i].formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(Palette.muted)
                                    }.frame(maxWidth: .infinity).accessibilityLabel("\(dates[i].formatted(date: .complete, time: .omitted)), \(Int(values[i])) \(store.t("Sekunden"))")
                                }
                            }.frame(height: 78)
                        }
                    }
                }.padding(18)
            }.background(Palette.canvas).toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showingSettings) { SettingsView() }
                .sheet(isPresented: $showingCardSearch) { CardSearchView() }
                .sheet(isPresented: $showingCalendar) { CalendarView() }
                .fullScreenCover(item: $activeTest) { offer in DailyTestView(offer: offer) }
                .sheet(item: $metricHelp) { kind in MetricHelpSheet(kind: kind) }
        }
    }
    /// Tests, die der Tutor heute schreiben kann: vor einem Termin mit Deck und aus schweren Karten.
    @ViewBuilder private var testsCard: some View {
        let offers = store.testOffers()
        if !offers.isEmpty {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(store.t("Tests für dich"), systemImage: "checklist").font(.headline)
                    ForEach(offers) { offer in
                        Button { activeTest = offer } label: {
                            HStack(spacing: 12) {
                                Image(systemName: offer.kind == .exam ? "graduationcap.fill" : "bolt.fill")
                                    .foregroundStyle(Palette.purple).frame(width: 38, height: 38).background(Palette.lilac, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(offer.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                                    Text(offer.examDate.map(examLabel) ?? store.t("Karten, die dir schwergefallen sind"))
                                        .font(.caption).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Text(store.t("Starten")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.purple)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func examLabel(_ date: Date) -> String {
        let days = daysRemaining(date)
        if days == 0 { return store.t("Termin heute") }
        if days == 1 { return store.t("Termin morgen") }
        return store.tf("Termin in %d Tagen", days)
    }

    private func daysLabel(_ date: Date) -> String {
        let days = daysRemaining(date)
        if days == 0 { return store.t("Heute") }
        if days == 1 { return store.t("Morgen") }
        return store.tf("in %d Tagen", days)
    }

    private func dueLearningTile(title: String, count: Int, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Palette.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(Palette.muted)
                Text("\(count)").font(.headline).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Palette.muted)
        }.padding(12).frame(maxWidth: .infinity).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 14))
    }
    private func daysRemaining(_ date: Date) -> Int { max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0, 0) }
}

private enum MetricHelp: String, Identifiable { case streak, time; var id: String { rawValue } }

private struct MetricHelpSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: MetricHelp
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.t(kind == .streak ? "Eine Streak zählt aufeinanderfolgende lokale Kalendertage, an denen du mindestens eine Lernkarte bewertet oder eine Vokabel gelernt hast. Hast du heute noch nicht gelernt, bleibt sie bis einschließlich gestern erhalten. Nach einem ausgelassenen Tag beginnt sie wieder bei null." : "Die Zeit ist eine Schätzung: Pro beantworteter Lernkarte oder Vokabel zählen die Sekunden vom Anzeigen bis zur Bewertung. Denkzeit und Wartezeit auf die KI sind darin enthalten. Gezählt wird ab Wochenbeginn nach dem Kalender deines Geräts; die Balken zeigen dieselben Tage wie die Gesamtzeit. Längere Pausen können die Zeit erhöhen."))
                    .font(.body).foregroundStyle(Palette.ink)
                Text(store.t("Die Erfassung beginnt mit deinen nächsten Lernsessions.")).font(.footnote).foregroundStyle(Palette.muted)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24).background(Palette.canvas)
                .navigationTitle(store.t(kind == .streak ? "Streak-Regel" : "Lernzeit-Regel")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Schließen")) { dismiss() } } }
        }.presentationDetents([.medium])
    }
}

/// Lädt einen vom Tutor geschriebenen Test und führt ihn durch. Ohne Tutor (keine Anmeldung, Limit erreicht,
/// keine Verbindung) wird stattdessen mit den vorhandenen Karten geübt.
private struct DailyTestView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let offer: DailyTestOffer
    @State private var questions: [Flashcard]?
    @State private var fallbackNote: String?

    var body: some View {
        Group {
            if let questions {
                // Der Hinweis steht im Inhalt: Als Leiste über der Ansicht würde er Titel und Schließen-Knopf verdecken.
                StudySessionView(deckID: UUID(), mode: .exam, useAI: false, customCards: questions, customTitle: offer.title, customNotice: fallbackNote) {
                    store.markTestCompleted(offer)
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text(store.t("Eulio schreibt deinen Test …")).font(.headline)
                    Text(offer.title).font(.subheadline).foregroundStyle(Palette.muted)
                    Button(store.t("Abbrechen")) { dismiss() }.padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard questions == nil else { return }
        do {
            let drafts = try await LearningAPI.shared.dailyTest(for: offer)
            guard !drafts.isEmpty else { throw LearningAPIError.message("leer") }
            questions = drafts.map { Flashcard(question: $0.question, answer: $0.answer) }
        } catch {
            let reason = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
            fallbackNote = reason + " " + store.t("Du übst mit deinen vorhandenen Karten.")
            questions = Array(offer.cards.shuffled().prefix(10))
        }
    }
}
