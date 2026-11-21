import SwiftUI
import PhotosUI
import PDFKit
import UIKit
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Limits

enum ImportLimits {
    static let photoBytes = 6 * 1024 * 1024
    static let photoMaxPixels: CGFloat = 2048
    static let pdfBytes = 20 * 1024 * 1024
    static let pdfPages = 250
    static let textCharacters = 120_000
    static let minTextCharacters = 20
    static let instructionCharacters = 500
}

// MARK: - Hilfstypen

private struct SegmentOption<Value: Hashable> {
    let label: String
    var icon: String? = nil
    let value: Value
}

private struct InstructionSuggestion: Identifiable {
    let label: String
    let prompt: String
    var id: String { label }
}

struct PDFPayload: Sendable {
    let text: String
    let pages: Int
    let name: String
}

/// Mehrzeiliges Eingabefeld mit Platzhalter, Fokus-Rahmen und begrenzter Höhe.
/// Der Fokus wird von außen gesteuert, damit die Tastatur jederzeit geschlossen werden kann.
private struct FocusedEditor<Field: Hashable>: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let field: Field
    var focus: FocusState<Field?>.Binding

    var body: some View {
        let isFocused = focus.wrappedValue == field
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused(focus, equals: field)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
        }
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isFocused ? Palette.purple : Color.clear, lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct StepHeader: View {
    let number: Int
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Palette.purple, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Import

struct AIImportView: View {
    private enum MaterialMode: String, CaseIterable, Identifiable {
        case photo, pdf, text
        var id: String { rawValue }
        var title: String {
            switch self {
            case .photo: return "Foto"
            case .pdf: return "PDF"
            case .text: return "Text"
            }
        }
        var icon: String {
            switch self {
            case .photo: return "photo"
            case .pdf: return "doc.richtext"
            case .text: return "text.alignleft"
            }
        }
    }

    private enum Field: Hashable { case text, instructions }

    private static let instructionSuggestions: [InstructionSuggestion] = [
        .init(label: "Nur Kernbegriffe", prompt: "Konzentriere dich auf die wichtigsten Kernbegriffe und Definitionen."),
        .init(label: "Einfache Sprache", prompt: "Formuliere in einfacher, leicht verständlicher Sprache."),
        .init(label: "Mit Beispielen", prompt: "Ergänze kurze Beispiele in den Antworten."),
        .init(label: "Max. 15 Karten", prompt: "Erstelle höchstens 15 Karten.")
    ]

    @Environment(LearningStore.self) private var store

    // Material
    @State private var mode: MaterialMode = .photo
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var photoInfo = ""
    @State private var pdfText = ""
    @State private var pdfName = ""
    @State private var pdfPages = 0
    @State private var pastedText = ""

    // Anpassen
    @State private var style = "Frage und Antwort"
    @State private var cardLanguage = "Deutsch"
    @State private var followsAppLanguage = true
    @State private var instructions = ""
    @State private var targetDeck: UUID?

    // Status
    @State private var drafts: [CardDraft] = []
    @State private var isLoading = false
    @State private var isLoadingMaterial = false
    @State private var errorText: String?
    @State private var statusText: String?
    @State private var showingPreview = false
    @State private var showingFilePicker = false
    @FocusState private var focusedField: Field?

    private var selectedDeck: Deck? { store.decks.first { $0.id == targetDeck } }
    let onCardsAdded: ((UUID) -> Void)?

    init(initialDeckID: UUID? = nil, onCardsAdded: ((UUID) -> Void)? = nil) {
        _targetDeck = State(initialValue: initialDeckID)
        self.onCardsAdded = onCardsAdded
    }

    // MARK: Abgeleitete Werte

    private var trimmedPastedText: String { pastedText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var materialReady: Bool {
        switch mode {
        case .photo: return imageData != nil
        case .pdf: return !pdfText.isEmpty
        case .text: return trimmedPastedText.count >= ImportLimits.minTextCharacters
        }
    }

    private var canGenerate: Bool {
        !isLoading && !isLoadingMaterial && targetDeck != nil && materialReady
    }

    private var missingHint: String? {
        if isLoading || isLoadingMaterial { return nil }
        if store.decks.isEmpty { return store.t("Erstelle zuerst ein Deck.") }
        if !materialReady {
            switch mode {
            case .photo: return store.t("Wähle zuerst ein Foto aus.")
            case .pdf: return store.t("Wähle zuerst ein PDF aus.")
            case .text: return store.t("Gib mindestens 20 Zeichen Text ein.")
            }
        }
        if targetDeck == nil { return store.t("Wähle ein Zieldeck aus.") }
        return nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    materialCard
                    customizeCard
                    deckCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.t("Fertig")) { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField == nil {
                    generateBar.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: focusedField)
            .sensoryFeedback(.selection, trigger: mode)
            .sensoryFeedback(.selection, trigger: style)
            .task {
                if targetDeck == nil { targetDeck = store.decks.first?.id }
                if followsAppLanguage { cardLanguage = store.language }
            }
            .onChange(of: store.language) { _, language in if followsAppLanguage { cardLanguage = language } }
            .onChange(of: selectedPhoto) { _, item in Task { await loadPhoto(item) } }
            .photosPicker(isPresented: $showingPhotoLibrary, selection: $selectedPhoto, matching: .images)
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in Task { await loadCameraImage(image) } }.ignoresSafeArea()
            }
            .onChange(of: pastedText) { _, value in
                if value.count > ImportLimits.textCharacters { pastedText = String(value.prefix(ImportLimits.textCharacters)) }
            }
            .onChange(of: instructions) { _, value in
                if value.count > ImportLimits.instructionCharacters { instructions = String(value.prefix(ImportLimits.instructionCharacters)) }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in loadPDF(result) }
            .sheet(isPresented: $showingPreview) {
                GeneratedCardsPreview(drafts: $drafts, deckID: targetDeck ?? UUID()) { savedDeckID in
                    resetMaterial()
                    statusText = store.t("Karten wurden hinzugefügt.")
                    onCardsAdded?(savedDeckID)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.t("Mach Lernstoff zu Karten"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.ink)
                Text(store.t("Füge ein Foto, ein PDF oder Text hinzu. Die KI erstellt daraus einen Kartensatz."))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.purple)
                .frame(width: 52, height: 52)
                .background(Palette.lilac, in: Circle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    // MARK: 1 · Material

    private var materialCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                StepHeader(number: 1, title: store.t("Material"), subtitle: store.t("Woraus sollen die Karten entstehen?"))
                segmented(
                    MaterialMode.allCases.map { SegmentOption(label: store.t($0.title), icon: $0.icon, value: $0) },
                    selection: mode
                ) { newMode in
                    focusedField = nil
                    withAnimation(.snappy) { mode = newMode }
                }
                Group {
                    switch mode {
                    case .photo: photoContent
                    case .pdf: pdfContent
                    case .text: textContent
                    }
                }
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: mode)
        }
    }

    @ViewBuilder private var photoContent: some View {
        if let previewImage {
            VStack(spacing: 12) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        Button(action: removePhoto) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.55))
                                .padding(8)
                        }
                        .accessibilityLabel(store.t("Bild entfernen"))
                    }
                HStack {
                    Label(photoInfo, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.green)
                    Spacer()
                    Menu {
                        Button { openCamera() } label: { Label(store.t("Foto aufnehmen"), systemImage: "camera") }
                        Button { showingPhotoLibrary = true } label: { Label(store.t("Foto auswählen"), systemImage: "photo.on.rectangle") }
                    } label: {
                        Text(store.t("Ändern")).font(.footnote.weight(.semibold)).foregroundStyle(Palette.purple)
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                Button { openCamera() } label: {
                    dropzone(icon: "camera", title: store.t("Foto aufnehmen"), hint: store.t("Mit der Kamera"), busy: isLoadingMaterial)
                }
                Button { showingPhotoLibrary = true } label: {
                    dropzone(icon: "photo.badge.plus", title: store.t("Foto auswählen"), hint: store.t("Aus der Mediathek"), busy: isLoadingMaterial)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingMaterial)
        }
    }

    @ViewBuilder private var pdfContent: some View {
        if !pdfName.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.purple)
                    .frame(width: 46, height: 46)
                    .background(Palette.lilac, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pdfName).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                    Text("\(pdfPages) \(store.t("Seiten"))").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                Button { showingFilePicker = true } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.body.weight(.semibold)).foregroundStyle(Palette.purple).frame(width: 36, height: 36)
                }
                .accessibilityLabel(store.t("Ändern"))
                Button(role: .destructive, action: removePDF) {
                    Image(systemName: "trash").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .accessibilityLabel(store.t("Entfernen"))
            }
            .buttonStyle(.plain)
            .padding(12)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 16))
        } else {
            Button { showingFilePicker = true } label: {
                dropzone(icon: "doc.badge.plus",
                         title: store.t("PDF auswählen"),
                         hint: store.t("PDF-Größenlimit: 20 MB und maximal 250 Seiten."),
                         busy: isLoadingMaterial)
            }
            .buttonStyle(.plain)
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            FocusedEditor(
                text: $pastedText,
                placeholder: store.t("Füge hier deinen Lernstoff ein, zum Beispiel Notizen, ein Skript oder einen Artikel."),
                minHeight: 180,
                maxHeight: 320,
                field: Field.text,
                focus: $focusedField
            )
            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { strings in
                    let incoming = strings.joined(separator: "\n")
                    guard !incoming.isEmpty else { return }
                    pastedText = pastedText.isEmpty ? incoming : pastedText + "\n" + incoming
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(Palette.purple)

                if !pastedText.isEmpty {
                    Button(role: .destructive) { pastedText = "" } label: {
                        Label(store.t("Leeren"), systemImage: "trash").font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
                Spacer(minLength: 8)
                Text("\(pastedText.count.formatted()) / \(ImportLimits.textCharacters.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private func dropzone(icon: String, title: String, hint: String, busy: Bool) -> some View {
        VStack(spacing: 10) {
            Group {
                if busy {
                    ProgressView().tint(Palette.purple)
                } else {
                    Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.purple)
                }
            }
            .frame(width: 56, height: 56)
            .background(Palette.lilac, in: Circle())
            Text(title).font(.headline).foregroundStyle(Palette.ink).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            Text(hint).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 12)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Palette.purple.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: 2 · Anpassen

    private var customizeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 20) {
                StepHeader(number: 2, title: store.t("Anpassen"), subtitle: store.t("Kartentyp, Sprache und Wünsche"))

                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Kartentyp")
                    HStack(spacing: 10) {
                        styleTile(value: "Frage und Antwort", title: "Frage & Antwort", icon: "text.bubble")
                        styleTile(value: "Quiz", title: "Quiz", icon: "checklist")
                    }
                    Text(store.t(style == "Quiz"
                                 ? "Quiz: Auswahlfrage mit Antwortoptionen und Lösung."
                                 : "Frage & Antwort: offene Frage auf der Vorderseite, Musterantwort auf der Rückseite."))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Sprache")
                    segmented(
                        [
                            SegmentOption(label: store.t("Deutsch"), value: "Deutsch"),
                            SegmentOption(label: store.t("English"), value: "Englisch"),
                            SegmentOption(label: store.t("Automatisch"), value: "Originalsprache")
                        ],
                        selection: cardLanguage
                    ) { language in
                        focusedField = nil
                        cardLanguage = language
                        followsAppLanguage = false
                    }
                }

                instructionsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Zusätzliche Anweisungen (optional)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.instructionSuggestions) { suggestion in
                        let active = instructions.contains(suggestion.prompt)
                        Button { toggleSuggestion(suggestion.prompt) } label: {
                            Label(store.t(suggestion.label), systemImage: active ? "checkmark" : "plus")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(active ? Color.white : Palette.ink)
                                .background(active ? Palette.purple : Palette.lilac, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }
            FocusedEditor(
                text: $instructions,
                placeholder: store.t("z. B. „Nur Kapitel 3“ oder „Jede Karte mit einem Beispiel“"),
                minHeight: 92,
                maxHeight: 180,
                field: Field.instructions,
                focus: $focusedField
            )
            HStack {
                if !instructions.isEmpty {
                    Button { instructions = "" } label: {
                        Label(store.t("Leeren"), systemImage: "xmark.circle.fill").font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.purple)
                }
                Spacer()
                Text("\(instructions.count) / \(ImportLimits.instructionCharacters)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private func fieldLabel(_ key: String) -> some View {
        Text(store.t(key)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
    }

    private func styleTile(value: String, title: String, icon: String) -> some View {
        let selected = style == value
        return Button {
            focusedField = nil
            withAnimation(.snappy) { style = value }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? Palette.purple : Palette.muted)
                Text(store.t(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selected ? Palette.lilac : Palette.canvas, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Palette.purple : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func segmented<Value: Hashable>(_ options: [SegmentOption<Value>], selection: Value, onSelect: @escaping (Value) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { onSelect(option.value) } label: {
                    HStack(spacing: 6) {
                        if let icon = option.icon { Image(systemName: icon) }
                        Text(option.label).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected ? Color.white : Palette.ink)
                    .background(selected ? Palette.purple : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.lilac, in: RoundedRectangle(cornerRadius: 14))
        .animation(.snappy, value: selection)
    }

    // MARK: 3 · Zieldeck

    private var deckCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                StepHeader(number: 3, title: store.t("Zieldeck"), subtitle: store.t("Wohin sollen die Karten?"))
                if store.decks.isEmpty {
                    Label(store.t("Erstelle zuerst ein Deck."), systemImage: "tray")
                        .foregroundStyle(Palette.muted)
                } else {
                    Menu {
                        Picker(store.t("Deck"), selection: $targetDeck) {
                            Text(store.t("Deck auswählen")).tag(UUID?.none)
                            ForEach(store.decks) { Text("\($0.emoji) \($0.name)").tag(Optional($0.id)) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(selectedDeck?.emoji ?? "📚")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Palette.lilac, in: RoundedRectangle(cornerRadius: 12))
                            Text(selectedDeck?.name ?? store.t("Deck auswählen"))
                                .font(.headline)
                                .foregroundStyle(selectedDeck == nil ? Palette.muted : Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(12)
                        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Untere Leiste

    private var generateBar: some View {
        VStack(spacing: 10) {
            if let statusText, !statusText.isEmpty {
                Label(statusText, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorText { ErrorMessageCard(message: errorText) }
            Button {
                focusedField = nil
                Task { await createCards() }
            } label: {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(store.t("Karten werden erstellt …"))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(store.t("Karteikarten erstellen"), systemImage: "sparkles").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canGenerate)
            if let hint = missingHint {
                Text(hint).font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(
            Palette.canvas
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Divider() }
        )
    }

    // MARK: Aktionen

    private func toggleSuggestion(_ prompt: String) {
        let current = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if instructions.contains(prompt) {
            instructions = instructions.replacingOccurrences(of: prompt, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            instructions = current.isEmpty ? prompt : current + " " + prompt
        }
    }

    private func removePhoto() {
        imageData = nil
        previewImage = nil
        selectedPhoto = nil
        photoInfo = ""
        errorText = nil
    }

    private func removePDF() {
        pdfText = ""
        pdfName = ""
        pdfPages = 0
        errorText = nil
    }

    private func resetMaterial() {
        removePhoto()
        removePDF()
        pastedText = ""
    }

    /// Öffnet die Kamera oder erklärt, warum das nicht geht (kein Gerät mit Kamera, Zugriff verweigert).
    private func openCamera() {
        errorText = nil
        if let problem = CameraPicker.unavailableReason { errorText = store.t(problem) } else { showingCamera = true }
    }

    @MainActor private func loadCameraImage(_ image: UIImage) async {
        errorText = nil
        isLoadingMaterial = true
        defer { isLoadingMaterial = false }
        guard let prepared = await Task.detached(priority: .userInitiated, operation: { AIImportView.jpegForUpload(from: image) }).value,
              prepared.data.count <= ImportLimits.photoBytes else {
            errorText = store.t("Das Foto konnte nicht geladen werden. Bitte versuche ein anderes Bild.")
            return
        }
        selectedPhoto = nil
        imageData = prepared.data
        previewImage = prepared.preview
        photoInfo = "\(store.t("Foto")) · \(ByteCountFormatter.string(fromByteCount: Int64(prepared.data.count), countStyle: .file))"
    }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorText = nil
        isLoadingMaterial = true
        defer { isLoadingMaterial = false }
        // Fotos liegen meist als HEIC und in voller Auflösung vor. Das Backend erwartet JPEG,
        // deshalb wird das Bild hier verkleinert und neu kodiert (im Hintergrund).
        guard let original = try? await item.loadTransferable(type: Data.self),
              let prepared = await Task.detached(priority: .userInitiated, operation: { AIImportView.jpegForUpload(from: original) }).value else {
            selectedPhoto = nil
            errorText = store.t("Das Foto konnte nicht geladen werden. Bitte versuche ein anderes Bild.")
            return
        }
        let data = prepared.data
        let image = prepared.preview
        guard data.count <= ImportLimits.photoBytes else {
            selectedPhoto = nil
            errorText = store.t("Das Foto ist größer als 6 MB. Bitte wähle ein kleineres Bild.")
            return
        }
        imageData = data
        previewImage = image
        photoInfo = "\(store.t("Foto")) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }

    /// Verkleinert auf höchstens `photoMaxPixels` an der langen Kante und kodiert als JPEG.
    nonisolated static func jpegForUpload(from data: Data) -> (data: Data, preview: UIImage)? {
        guard let image = UIImage(data: data) else { return nil }
        return jpegForUpload(from: image)
    }

    /// Auch für Kamera-Aufnahmen: Die Ausrichtung des Fotos wird beim Zeichnen übernommen.
    nonisolated static func jpegForUpload(from image: UIImage) -> (data: Data, preview: UIImage)? {
        let longEdge = max(image.size.width, image.size.height) * image.scale
        let ratio = min(1, ImportLimits.photoMaxPixels / max(longEdge, 1))
        let target = CGSize(width: max(1, (image.size.width * image.scale * ratio).rounded()), height: max(1, (image.size.height * image.scale * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return (jpeg, resized)
    }

    @MainActor private func loadPDF(_ result: Result<[URL], Error>) {
        errorText = nil
        let url: URL
        do {
            guard let first = try result.get().first else { return }
            url = first
        } catch {
            errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
            return
        }
        isLoadingMaterial = true
        Task {
            defer { isLoadingMaterial = false }
            do {
                // Die Textextraktion läuft im Hintergrund, damit die Oberfläche bei großen PDFs nicht blockiert.
                let payload = try await Task.detached(priority: .userInitiated) {
                    try AIImportView.extractPDF(from: url)
                }.value
                pdfText = payload.text
                pdfName = payload.name
                pdfPages = payload.pages
            } catch {
                errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
            }
        }
    }

    nonisolated static func extractPDF(from url: URL) throws -> PDFPayload {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize > 0 else {
            throw LearningAPIError.message("Die PDF-Dateigröße konnte nicht ermittelt werden.")
        }
        guard fileSize <= ImportLimits.pdfBytes else { throw LearningAPIError.message("PDF überschreitet 20 MB.") }
        guard let pdf = PDFDocument(url: url) else { throw LearningAPIError.message("PDF ließ sich nicht öffnen.") }
        guard pdf.pageCount <= ImportLimits.pdfPages else { throw LearningAPIError.message("Das PDF hat zu viele Seiten (maximal 250).") }
        let extractedText = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        guard extractedText.count <= ImportLimits.textCharacters else {
            throw LearningAPIError.message("Der Text im PDF ist zu umfangreich. Verwende ein kürzeres Dokument.")
        }
        guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LearningAPIError.message("Das PDF enthält keinen auswählbaren Text. Verwende für gescannte Seiten den Foto-Import.")
        }
        return PDFPayload(text: extractedText, pages: pdf.pageCount, name: url.lastPathComponent)
    }

    @MainActor private func createCards() async {
        isLoading = true; errorText = nil; statusText = nil
        defer { isLoading = false }
        do {
            let styleInstructions = style == "Quiz"
                ? "Erstelle Multiple-Choice-Karten. Die Vorderseite enthält die Frage und 3 bis 4 klar markierte Antwortoptionen. Die Rückseite nennt die richtige Option und begründet sie kurz."
                : "Erstelle offene Frage-Antwort-Karten ohne Auswahloptionen. Die Vorderseite enthält eine klare Frage, die Rückseite die passende Musterantwort."
            let combinedInstructions = [styleInstructions, instructions]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            var text: String?
            var image: Data?
            switch mode {
            case .photo: image = imageData
            case .pdf: text = pdfText
            case .text: text = trimmedPastedText
            }

            let result = try await LearningAPI.shared.generate(text: text, image: image, mimeType: "image/jpeg", language: cardLanguage, style: style, instructions: combinedInstructions)
            guard !result.cards.isEmpty else {
                errorText = store.t("Die KI hat keine Karten erzeugt. Versuche es mit anderem Material.")
                return
            }
            drafts = result.cards
            showingPreview = true
        } catch { errorText = LearningAPI.shared.userFacingMessage(for: error, language: store.language) }
    }
}

// MARK: - Vorschau

struct GeneratedCardsPreview: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var drafts: [CardDraft]
    let deckID: UUID
    let onSaved: (UUID) -> Void
    @State private var editing: CardDraft?
    @State private var selectedIDs: Set<UUID>

    init(drafts: Binding<[CardDraft]>, deckID: UUID, onSaved: @escaping (UUID) -> Void) {
        _drafts = drafts
        self.deckID = deckID
        self.onSaved = onSaved
        _selectedIDs = State(initialValue: Set(drafts.wrappedValue.map(\.id)))
    }

    private var allSelected: Bool { !drafts.isEmpty && selectedIDs.count == drafts.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.t("Wähle die Karten aus, die du übernehmen möchtest. Tippe auf den Text, um eine Karte zu bearbeiten."))
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                        HStack {
                            Button(allSelected ? store.t("Alle abwählen") : store.t("Alle auswählen")) {
                                withAnimation(.snappy) { selectedIDs = allSelected ? [] : Set(drafts.map(\.id)) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.purple)
                            Spacer()
                            Text("\(selectedIDs.count) / \(drafts.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 4, trailing: 18))
                }

                Section {
                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, card in
                        row(card, number: index + 1)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { remove(card) } label: {
                                    Label(store.t("Löschen"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .overlay {
                if drafts.isEmpty {
                    ContentUnavailableView(store.t("Keine Karten übrig"), systemImage: "rectangle.stack")
                }
            }
            .navigationTitle(store.tf("Vorschau · %d", drafts.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Verwerfen")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: save) {
                    Label(store.tf("Übernehmen · %d", selectedIDs.count), systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedIDs.isEmpty)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(
                    Palette.canvas
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .top) { Divider() }
                )
            }
            .sheet(item: $editing) { card in
                DraftEditorSheet(draft: card) { updated in
                    if let i = drafts.firstIndex(where: { $0.id == updated.id }) { drafts[i] = updated }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ card: CardDraft, number: Int) -> some View {
        let selected = selectedIDs.contains(card.id)
        return HStack(alignment: .top, spacing: 12) {
            Button { toggle(card.id) } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Palette.purple : Palette.muted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t(selected ? "Karte abwählen" : "Karte auswählen"))

            Button { editing = card } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("#\(number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.purple)
                    Text(card.question)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Divider()
                    Text(card.answer)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "pencil")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.top, 4)
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(selected ? Palette.purple : Color.clear, lineWidth: 2)
        )
        .opacity(selected ? 1 : 0.7)
        .animation(.snappy, value: selected)
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func remove(_ card: CardDraft) {
        withAnimation(.snappy) {
            selectedIDs.remove(card.id)
            drafts.removeAll { $0.id == card.id }
        }
    }

    private func save() {
        let chosen = drafts.filter { selectedIDs.contains($0.id) }
        store.addCards(chosen, to: deckID)
        dismiss()
        onSaved(deckID)
    }
}

// MARK: - Karte bearbeiten

private struct DraftEditorSheet: View {
    private enum Field: Hashable { case question, answer }

    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CardDraft
    @FocusState private var focus: Field?
    var onSave: (CardDraft) -> Void

    init(draft: CardDraft, onSave: @escaping (CardDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(store.t("Frage"), systemImage: "questionmark.bubble")
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            FocusedEditor(text: $draft.question, placeholder: store.t("Frage"), minHeight: 100, maxHeight: 240, field: Field.question, focus: $focus)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(store.t("Antwort"), systemImage: "text.bubble")
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            FocusedEditor(text: $draft.answer, placeholder: store.t("Antwort"), minHeight: 160, maxHeight: 360, field: Field.answer, focus: $focus)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas)
            .navigationTitle(store.t("Karte bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Speichern")) { onSave(draft); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.t("Fertig")) { focus = nil }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Kamera

/// Die Systemkamera für eine einzelne Aufnahme. Liefert das Foto und schließt sich selbst.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    /// Grund (als Übersetzungsschlüssel), warum die Kamera gerade nicht geöffnet werden kann; sonst nil.
    static var unavailableReason: String? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return "Auf diesem Gerät ist keine Kamera verfügbar."
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            return "Die App darf nicht auf die Kamera zugreifen. Erlaube den Zugriff in den iOS-Einstellungen unter „Lernkarten“."
        default:
            return nil
        }
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
