import SwiftUI

struct CalendarView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset = 0
    @State private var showingNewEntry = false
    @State private var editingEntry: CalendarEntry?

    private var selectedEntries: [CalendarEntry] { store.calendarEntries(on: selectedDate) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(selectedDate.formatted(.dateTime.month(.wide).year()).capitalized)
                        .font(.title2.bold())
                    Spacer()
                    Button(store.t("Heute")) {
                        selectedDate = Calendar.current.startOfDay(for: Date())
                        weekOffset = 0
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.purple)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

                TabView(selection: $weekOffset) {
                    ForEach(-52...52, id: \.self) { offset in
                        weekPage(offset: offset).tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 88)
                .onChange(of: weekOffset) { _, offset in
                    let days = datesInWeek(offset: offset)
                    if !days.contains(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }), let first = days.first {
                        selectedDate = first
                    }
                }

                Divider().padding(.top, 10)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedDate.formatted(date: .complete, time: .omitted)).font(.headline)
                        Text(store.tf("%d Termine", selectedEntries.count)).font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { showingNewEntry = true } label: {
                        Label(store.t("Eintrag"), systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.purple)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if selectedEntries.isEmpty {
                    ContentUnavailableView(store.t("Keine Einträge"), systemImage: "calendar", description: Text(store.t("Für diesen Tag sind keine Tests oder Prüfungen eingetragen.")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(selectedEntries) { entry in
                            entryRow(entry)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Palette.canvas)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Palette.canvas)
                }
                Spacer(minLength: 0)
            }
            .background(Palette.canvas)
            .navigationTitle(store.t("Kalender"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(store.t("Schließen")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewEntry = true } label: { Image(systemName: "plus") }
                        .tint(Palette.purple)
                        .accessibilityLabel(store.t("Eintrag hinzufügen"))
                }
            }
            .sheet(isPresented: $showingNewEntry) { CalendarEntryFormView(date: selectedDate) }
            .sheet(item: $editingEntry) { entry in CalendarEntryFormView(entry: entry) }
        }
        .preferredColorScheme(store.appearance == "Hell" ? .light : store.appearance == "Dunkel" ? .dark : nil)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func weekPage(offset: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(datesInWeek(offset: offset), id: \.self) { date in
                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDateInToday(date)
                Button { selectedDate = date } label: {
                    VStack(spacing: 7) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : Palette.muted)
                        Text(date.formatted(.dateTime.day()))
                            .font(.headline.weight(isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .white : Palette.ink)
                        Circle()
                            .fill(hasEntries(on: date) ? (isSelected ? .white : Palette.purple) : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(isSelected ? Palette.purple : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        if isToday && !isSelected {
                            RoundedRectangle(cornerRadius: 18).stroke(Palette.lilac, lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func entryRow(_ entry: CalendarEntry) -> some View {
        let saved = store.calendarEntries.contains(where: { $0.id == entry.id })
        if saved {
            Button { editingEntry = entry } label: { entryCard(entry) }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.removeCalendarEntry(entry.id) } label: { Label(store.t("Löschen"), systemImage: "trash") }
                }
                .contextMenu {
                    Button(role: .destructive) { store.removeCalendarEntry(entry.id) } label: {
                        Label(store.t("Löschen"), systemImage: "trash")
                    }
                }
        } else if let deckID = entry.deckID {
            NavigationLink { DeckDetailView(deckID: deckID) } label: { entryCard(entry) }
                .buttonStyle(.plain)
        } else {
            entryCard(entry)
        }
    }

    private func entryCard(_ entry: CalendarEntry) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color(for: entry.kind))
                .frame(width: 4, height: 54)
            Image(systemName: icon(for: entry.kind))
                .font(.title3.weight(.semibold))
                .foregroundStyle(color(for: entry.kind))
                .frame(width: 38, height: 38)
                .background(color(for: entry.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text(kindLabel(entry.kind)).font(.caption.weight(.medium)).foregroundStyle(color(for: entry.kind))
                    if let deck = entry.deckID.flatMap({ id in store.decks.first(where: { $0.id == id }) }) {
                        Text("·").foregroundStyle(Palette.muted)
                        Text("\(deck.emoji) \(deck.name)").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(Palette.muted).lineLimit(2) }
            }
            Spacer(minLength: 0)
            if entry.deckID != nil { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func datesInWeek(offset: Int) -> [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: Date())
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        guard let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: start) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func hasEntries(on date: Date) -> Bool { !store.calendarEntries(on: date).isEmpty }
    private func kindLabel(_ kind: CalendarEntryKind) -> String {
        switch kind {
        case .exam: return store.t("Prüfung")
        case .test: return store.t("Test")
        case .assignment: return store.t("Abgabe")
        case .other: return store.t("Sonstiges")
        }
    }
    private func icon(for kind: CalendarEntryKind) -> String {
        switch kind { case .exam: return "graduationcap.fill"; case .test: return "checkmark.seal.fill"; case .assignment: return "doc.text.fill"; case .other: return "calendar" }
    }
    private func color(for kind: CalendarEntryKind) -> Color {
        switch kind { case .exam: return Palette.purple; case .test: return .orange; case .assignment: return .blue; case .other: return .teal }
    }
}

private struct CalendarEntryFormView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var kind: CalendarEntryKind
    @State private var deckID: UUID?
    @State private var note: String

    private let entry: CalendarEntry?

    init(entry: CalendarEntry? = nil, date: Date = Date()) {
        self.entry = entry
        _title = State(initialValue: entry?.title ?? "")
        _date = State(initialValue: entry?.date ?? Calendar.current.startOfDay(for: date))
        _kind = State(initialValue: entry?.kind ?? .test)
        _deckID = State(initialValue: entry?.deckID)
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Termin")) {
                    TextField(store.t("Titel"), text: $title)
                    Picker(store.t("Art"), selection: $kind) {
                        ForEach(CalendarEntryKind.allCases) { value in Text(label(value)).tag(value) }
                    }
                    DatePicker(store.t("Datum"), selection: $date, displayedComponents: .date)
                }
                Section(store.t("Deck (optional)")) {
                    Picker(store.t("Deck zuordnen"), selection: $deckID) {
                        Text(store.t("Kein Deck")).tag(nil as UUID?)
                        ForEach(store.decks) { deck in Text("\(deck.emoji) \(deck.name)").tag(Optional(deck.id)) }
                    }
                }
                Section(store.t("Notiz (optional)")) {
                    TextField(store.t("Zusätzliche Informationen"), text: $note, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(store.t(entry == nil ? "Neuer Eintrag" : "Eintrag bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Sichern")) { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(store.appearance == "Hell" ? .light : store.appearance == "Dunkel" ? .dark : nil)
    }

    private func save() {
        if var entry {
            entry.title = title
            entry.date = date
            entry.kind = kind
            entry.deckID = deckID
            entry.note = note
            store.updateCalendarEntry(entry)
        } else {
            store.addCalendarEntry(title: title, date: date, kind: kind, deckID: deckID, note: note)
        }
        dismiss()
    }

    private func label(_ kind: CalendarEntryKind) -> String {
        switch kind { case .exam: return store.t("Prüfung"); case .test: return store.t("Test"); case .assignment: return store.t("Abgabe"); case .other: return store.t("Sonstiges") }
    }
}
