import Foundation

/// Entscheidet, ob eine Tutor-Nachricht etwas in der App ändern soll (dann plant das Backend Aktionen)
/// oder ob es eine normale Frage ist (dann antwortet der Tutor im Chat).
///
/// Nutzer schreiben selten wie ein Prompt-Profi: kleingeschrieben, mit Tippfehlern, ohne Verb
/// („10 wörter essen“) oder als Frage („kannst du mir … machen?“). Darum zählt nicht ein einzelnes
/// Schlüsselwort, sondern eine Kombination: Tätigkeit + Gegenstand, Anzahl + Gegenstand,
/// Datum + Prüfung oder eine feste Wendung wie „frag mich ab“.
/// Ohne Abhängigkeiten, damit es sich außerhalb der App testen lässt.
enum TutorIntent {
    /// Was angelegt, geändert oder abgefragt werden kann (ohne Umlaute, kleingeschrieben).
    static let objects = [
        "vokabel", "vokabl", "worter", "woerter", "wort ", "worte ", "words", "vocab",
        "karteikart", "lernkart", "karten", "karte ", "flashcard", "cards", "deck", "stapel",
        "ordner", "folder", "unterordner",
        "termin", "kalender", "calendar", "klausur", "prufung", "pruefung", "klassenarbeit", "schulaufgabe", "exam", "abgabe", "referat",
        "begriff", "fach ", "facher", "glossar", "lexikon", "terms", "subject",
        "test ", "tests", "arbeit ", "quiz",
    ]
    /// Tätigkeiten, die etwas in der App verändern (Wortstämme, damit Beugungen und Tippfehler passen).
    static let verbs = [
        "erstell", "erstel", "anleg", "leg ", "lege ", "hinzufug", "hinzufueg", "fug ", "fuge ", "fueg", "erganz", "ergaenz",
        "trag ", "trage ", "eintrag", "schreib", "pack", "pak ", "speicher", "mach", "generier", "brauch", "will ", "mocht", "hatte gern",
        "gib ", "gibst", "geb", "tu ", "tun ", "hast du", "hattest du", "neue ", "neuen ", "neues ", "neu ", "merk",
        "heiss", "uben ", "ueben ", "verschieb", "schieb", "verleg", "aender", "ander", "umbenen", "benen", "nenn", "losch", "loesch", "entfern", "streich", "weg ", "raus", "nehm",
        "create", "make", "add ", "put ", "rename", "delete", "remove", "move", "reschedule", "schedule", "need ", "want ",
    ]
    /// Eindeutige Wendungen, die allein reichen.
    static let phrases = [
        "lass uns", "frag mich", "frage mich", "fragt mich", "abfragen", "abfrag", "teste mich", "test mich", "testen mich", "pruf mich", "pruef mich",
        "quiz me", "test me", "quiz mich", "trag ein", "trage ein", "tragen ein",
    ]
    static let examWords = ["klausur", "prufung", "pruefung", "test", "klassenarbeit", "schulaufgabe", "exam", "abgabe", "referat", "arbeit"]
    static let dateWords = [
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag", "morgen", "ubermorgen", "naechste woche", "nachste woche",
        "januar", "februar", "marz", "april", "mai ", "juni", "juli", "august", "september", "oktober", "november", "dezember",
        "monday", "tuesday", "wednesday", "thursday", "friday", "tomorrow", "next week",
    ]
    /// Anfänge echter Fragen. Ohne Tätigkeit bleiben sie im Chat („was ist der begriff für …“).
    /// Bitten um Rat statt um Inhalte: „gib mir einen tipp für die prüfung“.
    static let adviceWords = ["tipp", "tips", "rat ", "ratschlag", "hilfe", "motivation", "advice"]
    /// Fragewörter mitten im Satz („sag mal, wann schreiben wir die klausur?“). Ohne „was“: „fehlt noch was“ heißt „etwas“.
    static let questionWords = ["wann", "wie", "warum", "wieso", "weshalb", "welche", "welcher", "welches", "wo", "when", "what", "how", "why", "which"]
    /// Aussagen über das eigene Tun, keine Aufträge („mach ich lieber morgen“).
    static let statements = ["mach ich", "mache ich", "machen wir", "schreib ich", "schreibe ich", "schreiben wir", "pack ich", "lern ich", "lerne ich"]
    static let questionStarts = ["was ", "wie ", "warum", "wieso", "weshalb", "wer ", "welche", "erklar", "erklaer", "what ", "how ", "why ", "explain"]

    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
        // Satzzeichen zu Leerzeichen, damit „Vokabeln!“ und „deck,“ als Wörter erkannt werden; Datumspunkte bleiben.
        let cleaned = folded.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "›" ? $0 : " " }
        return " " + String(cleaned).split(separator: " ").joined(separator: " ") + " "
    }

    /// - Parameter knownNames: Namen der eigenen Decks, Ordner, Fächer und Termine. Sie zählen als Gegenstand,
    ///   denn „nenn chemie grundlagen um“ nennt das Deck nur beim Namen.
    static func isActionRequest(_ text: String, knownNames: [String] = []) -> Bool {
        let value = normalized(text)
        if phrases.contains(where: value.contains) { return true }
        let names = knownNames.map { normalized($0).trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 }
        let hasObject = objects.contains(where: value.contains) || names.contains(where: value.contains)
        guard hasObject else { return false }
        // „Chemie Grundlagen → Chemie Abi“
        if text.contains("→") || text.contains("->") { return true }
        if adviceWords.contains(where: { value.contains(" " + $0) }), value.range(of: #" \d{1,3} "#, options: .regularExpression) == nil { return false }
        // „wie erstelle ich ein deck?“ will eine Erklärung, keine Aktion.
        if questionStarts.contains(where: { value.hasPrefix(" " + $0) }) { return false }
        if text.contains("?"), questionWords.contains(where: { value.contains(" " + $0 + " ") }) { return false }
        if statements.contains(where: { value.contains(" " + $0 + " ") }) { return false }
        if verbs.contains(where: { value.contains(" " + $0) }) { return true }
        // Stichworte wie „Begriffe Wirtschaft Marktformen“ oder „Test Chemie Grundlagen“: kurz, ohne Frage, beginnt mit dem Gegenstand.
        let words = value.split(separator: " ")
        if words.count <= 6, !text.contains("?"), let first = words.first, objects.contains(where: { (" " + first + " ").hasPrefix(" " + $0.trimmingCharacters(in: .whitespaces)) }) { return true }
        // „10 wörter zum thema essen“, „5 karten bio“
        if value.range(of: #" \d{1,3} "#, options: .regularExpression) != nil { return true }
        // „am 3.12. bio klausur“, „montag mathe test“
        let hasDate = dateWords.contains(where: value.contains) || value.range(of: #"\d{1,2}\.\d{1,2}"#, options: .regularExpression) != nil
        return hasDate && examWords.contains(where: value.contains)
    }
}
