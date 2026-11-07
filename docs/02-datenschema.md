# 02 Datenschema

Das verbindliche JSON-Schema für gemeinsame Wortinhalte liegt in `data/schema.json` (Inhaltsversion 1.1). `data/content-file.schema.json` beschreibt eine Inhaltsdatei als Liste von Einträgen; `data/manifest.schema.json` beschreibt das Manifest. Nutzerspezifische Daten stehen getrennt in `data/user-profile.schema.json` (Profilversion 1.0). Dieses Dokument erklärt Modell und Swift-Umsetzung. Bei Abweichungen gilt das jeweilige Schema.

## 1. Überblick

Zwei getrennte Bereiche:

1. **Inhalt** (read-only, von der Pipeline erzeugt): Lemma, Bedeutung (Sense), Erklärung, Qualität.
2. **Nutzerprofil** (Nutzerdaten, auf dem Gerät bzw. später synchronisiert): Ordner, Favoriten, Quiz-Einstellungen, Lernfortschritt und Aktivität.

Der Lernstand verweist nur über IDs auf den Inhalt.

```
Lemma 1 ──── n Sense 1 ──── n Explanation 1 ──── n Beispiel
                │
                └── uebersetzung (optional verknüpft mit Sense der anderen Sprache)

Nutzerprofil: sense_id → Ordner/Favorit/Quiz/Fortschritt
Tagesaktivität → Streak und Statistiken
```

## 2. Inhaltsmodell

### 2.1 Lemma

Das Wort selbst in Grundform.

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `id` | string | ja | `{sprache}-{text}-{wortart}`, z. B. `en-bank-nomen` |
| `sprache` | `de` / `en` | ja | ISO-Code der Lernsprache |
| `text` | string | ja | Grundform |
| `wortart` | enum | ja | `nomen`, `verb`, `adjektiv`, `adverb`, `praeposition`, `konjunktion`, `pronomen`, `interjektion`, `andere` |
| `ipa` | string/null | nein | Lautschrift |
| `haeufigkeitsrang` | int/null | nein | Rang in der Häufigkeitsliste |
| `niveau` | enum | ja | `A1` bis `C2` |
| `artikel` | `der`/`die`/`das`/null | nein | nur Deutsch, nur Nomen |
| `plural` | string/null | nein | Volle Pluralform; null, wenn sie je Sense abweicht, ein englisches Nomen unzählbar ist oder der bestätigte Sense keinen üblichen Plural hat |

### 2.2 Sense (Bedeutung)

Ein Lemma hat 1 bis 4 Hauptbedeutungen. Mehrdeutige Wörter („Bank", „Schloss") bekommen mehrere getrennte Senses. `artikel` und `plural` können optional am Sense stehen und überschreiben dann den Lemma-Standardwert.

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `id` | string | ja | `{lemma_id}-{nr}`, z. B. `en-bank-nomen-1` |
| `artikel` | `der`/`die`/`das`/null | nein | Artikel für diesen Sense; überschreibt `lemma.artikel` |
| `plural` | string/null | nein | Volle Pluralform für diesen Sense; überschreibt `lemma.plural`; null ist für belegte plurallose Bedeutungen zulässig |
| `bedeutung_kurz` | string (max. 60) | ja | Kurze Disambiguierung in der Sprache des Lemmas |
| `uebersetzung` | Objekt | ja | siehe unten |
| `explanations` | Liste | ja | Erklärungen, leer im Rohzustand |

`uebersetzung`:

| Feld | Beschreibung |
|---|---|
| `sprache` | Zielsprache der Übersetzung |
| `text` | Hauptübersetzung |
| `alternativen` | bis zu 3 weitere Übersetzungen |
| `verknuepfte_sense_ids` | Liste aller passenden Senses der anderen Sprache; leer, wenn keine Zuordnung besteht |

Der Text steht direkt am Sense. Verknüpfungen sind optional und können mehrere Bedeutungen abbilden. Wenn eine Verknüpfung gesetzt ist, muss der Ziel-Sense die Rückverknüpfung enthalten.

`text` und `alternativen` stehen ausschließlich in der angegebenen Zielsprache. `text` ist genau eine Hauptübersetzung. Falls bei einem englischen Wort wie `band` sowohl `Streifen` als auch `Band` passen, steht `Streifen` in `text` und `Band` in `alternativen`, nicht als „Streifen oder Band“ in einem Feld.

### 2.3 Explanation (Erklärung)

Eine Erklärung gilt für **einen Sense, eine Erklärsprache und eine Stufe**.

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `erklaersprache` | `de`/`en` | ja | Sprache, in der erklärt wird |
| `stufe` | A1 bis C2 | ja | Niveau, für das die Erklärung geschrieben ist |
| `definition` | string (max. 220) | ja | einfache, klare Erklärung |
| `merkhilfe` | string/null (max. 160) | nein | Eselsbrücke, Wortfamilie, Bildidee |
| `verwechslung` | string/null (max. 200) | nein | nur bei echter, häufiger Verwechslung |
| `beispiele` | 2 bis 3 Objekte | ja | siehe unten |
| `qualitaet` | Objekt | ja | Qualitätsstatus dieser Erklärung; Eintragsebene fasst die Kinder zusammen |

Beispiel-Objekt:

| Feld | Beschreibung |
|---|---|
| `satz` | Satz in der **Lernsprache** |
| `uebersetzung` | in der **Erklärsprache**, `null` wenn Lern- und Erklärsprache gleich sind |
| `quelle` | `tatoeba` oder `ki` |
| `quelle_id` | Tatoeba-Satz-ID (für die Namensnennung), sonst `null` |

**Regel einsprachig/zweisprachig:**

- Lernsprache = Erklärsprache: einsprachige Definition, `uebersetzung` im Beispiel ist `null`.
- Lernsprache ≠ Erklärsprache: Definition in der Erklärsprache, jedes Beispiel mit Übersetzung.

### 2.4 Qualität

| Feld | Beschreibung |
|---|---|
| `status` | `roh` → `geprueft` → `freigegeben`, oder `prueffliste` |
| `pruef_score` | 0 bis 1, von der KI-Gegenprüfung |
| `hinweise` | Unsicherheiten, Probleme, Hinweise aus Pipeline-Schritten |
| `modellversion` | verwendetes Modell (Rückverfolgbarkeit) |
| `datum` | Datum der Erzeugung (`YYYY-MM-DD`) |

Nur freigegebene Erklärungen kommen in den App-Export. `LemmaEntry.qualitaet` ist der schlechteste Status der Erklärungen.

## 3. Beispiel-Eintrag

Englisches Lemma „bank", erste Bedeutung, mit deutscher und englischer Erklärung.

```json
{
  "lemma": {
    "id": "en-bank-nomen",
    "sprache": "en",
    "text": "bank",
    "wortart": "nomen",
    "ipa": "/bæŋk/",
    "haeufigkeitsrang": 800,
    "niveau": "A2",
    "artikel": null,
    "plural": "banks"
  },
  "senses": [
    {
      "id": "en-bank-nomen-1",
      "bedeutung_kurz": "financial institution",
      "uebersetzung": {
        "sprache": "de",
        "text": "Bank",
        "alternativen": ["Geldinstitut"],
        "verknuepfte_sense_ids": ["de-bank-nomen-1"]
      },
      "explanations": [
        {
          "erklaersprache": "de",
          "stufe": "A2",
          "definition": "Eine Bank ist ein Unternehmen, bei dem man Geld aufbewahren, überweisen oder leihen kann.",
          "merkhilfe": "Wie im Deutschen: Bank. Aber nicht zum Sitzen.",
          "verwechslung": "Für die Sitzbank sagt man „bench“, nicht „bank“.",
          "beispiele": [
            { "satz": "I need to go to the bank.", "uebersetzung": "Ich muss zur Bank.", "quelle": "ki", "quelle_id": null },
            { "satz": "The bank opens at nine.", "uebersetzung": "Die Bank öffnet um neun.", "quelle": "ki", "quelle_id": null }
          ],
          "qualitaet": { "status": "roh", "pruef_score": null, "hinweise": [], "modellversion": "GPT-6 (Codex)", "datum": "2026-11-04" }
        },
        {
          "erklaersprache": "en",
          "stufe": "A2",
          "definition": "A bank is a place where you can keep, send or borrow money.",
          "merkhilfe": null,
          "verwechslung": "For a seat in a park, use “bench”.",
          "beispiele": [
            { "satz": "I need to go to the bank.", "uebersetzung": null, "quelle": "ki", "quelle_id": null },
            { "satz": "The bank opens at nine.", "uebersetzung": null, "quelle": "ki", "quelle_id": null }
          ],
          "qualitaet": { "status": "roh", "pruef_score": null, "hinweise": [], "modellversion": "GPT-6 (Codex)", "datum": "2026-11-04" }
        }
      ]
    }
  ],
  "qualitaet": {
    "status": "roh",
    "pruef_score": 0.93,
    "hinweise": [],
    "modellversion": "GPT-6 (Codex)",
    "datum": "2026-11-04"
  }
}
```

(Werte wie `haeufigkeitsrang` und `pruef_score` sind nur Beispiele.)

## 4. ID-Konventionen

- Lemma: `{sprache}-{text}-{wortart}`, klein geschrieben, Leerzeichen als `-`, Umlaute als `ae`, `oe`, `ue`, `ss`.
  Beispiele: `en-bank-nomen`, `de-schloss-nomen`, `de-aeussern-verb`.
- Sense: `{lemma_id}-{nr}` ab 1.
- IDs sind **stabil**. Wird ein Eintrag neu erzeugt, bleiben die IDs gleich, damit der Lernstand gültig bleibt.
  Ändert sich die Bedeutungsaufteilung, wird eine neue Sense-ID vergeben und die alte als veraltet markiert.

## 5. Validierungsregeln

Automatisch in Pipeline-Schritt 5 (Code, kein KI-Aufruf):

1. Jeder Eintrag ist gegen `data/schema.json` gültig; eine Inhaltsdatei ist ein Array dieser Einträge.
2. Das Lemma (oder eine gebeugte Form) kommt in jedem Beispielsatz vor.
3. Satzlänge im Limit der Stufe (siehe `prompts.md`).
4. Pro Sense höchstens eine Erklärung je Kombination aus Erklärsprache und Stufe.
5. Bei Lernsprache = Erklärsprache ist `uebersetzung` im Beispiel `null`, sonst nicht leer.
6. Deutsch: Nomen haben einen Artikel. Einen belegten Plural auf Lemma- oder Sense-Ebene speichern; bei nachweislich plural-losen Bedeutungen `plural = null`.
7. Englisch: zählbare Nomen haben die volle Pluralform, niemals nur eine Endung; nicht zählbare Nomen haben `plural = null`.
8. Sense-Verknüpfungen zeigen auf vorhandene Einträge der Zielsprache und sind gegenseitig.
9. Abweichende Artikel/Pluralwerte am Sense verlangen `null` am Lemma.
10. Alle Explanations eines Senses haben dieselben Beispielsätze in gleicher Reihenfolge.
11. `quelle = tatoeba` verlangt `quelle_id`; `quelle = ki` verlangt `quelle_id = null`.
12. Artikel-Satz-Abgleich ist ein **Plausibilitätscheck**: erkennbare Widersprüche aus Beispielen erzeugen einen Hinweis zur manuellen Prüfung, keinen automatischen Schemafehler.
13. Identische Plurale bei mehreren Senses eines Lemmas werden am Lemma normalisiert. Abweichende Formen bleiben je Sense.
14. Für mehrdeutige Senses prüfen Prompt und Review, dass Merkhilfen korrekt unterscheiden; falsche Regeln aus Buchstaben oder Endungen sind unzulässig.
15. Zusammengefasste Übersetzungen und Beispiele müssen semantisch zusammenpassen. Unterschiedliche Funktionen einer Präposition werden in getrennten Senses beschrieben.

## 6. Nutzerprofil und Lernstand

Ein Sense ist **gespeichert**, wenn `saved_at` gesetzt ist; die Ordnerliste darf zunächst leer sein. Beim Einordnen wird eine oder mehrere Ordner-IDs zugewiesen. Ein bloßer Quiz- oder Favoritenstatus macht ein Wort nicht automatisch gespeichert.

Das Nutzerdatenformat ist unabhängig vom gemeinsamen Wortbestand definiert in `data/user-profile.schema.json`. Dadurch können Wörter aktualisiert werden, ohne Ordner, Favoriten oder Statistiken zu überschreiben. Es enthält:

- **Haupt- und Unterordner:** `folders[].parent_folder_id` ist `null` für einen Hauptordner, sonst die ID des Elternordners. Ein Wort kann mehreren Ordnern zugeordnet werden.
- **Wortstatus:** `word_states[]` referenziert stabile `lemma_id` und `sense_id`. Ein Datensatz darf auch nur einen Favoriten oder Quizstatus enthalten, ohne in einem Ordner gespeichert zu sein.
- **Favoriten:** `favorite` ist unabhängig vom Speichern in Ordnern.
- **Quiz:** dieselbe `sense_id` wird wiederverwendet. `quiz.enabled`, freie Kategorien und ein Schwierigkeitsgrad von 1 bis 5 steuern Auswahl und Sortierung, ohne Wortdaten zu duplizieren.
- **Fortschritt:** korrekte/falsche Antworten, Versuche, letzter Übungszeitpunkt, Fälligkeit und Leitner-Box.
- **Tagesaktivität:** pro Kalendertag ein `activity_days`-Eintrag mit Übungszahl und eindeutigen Sense-IDs. Daraus werden Tages-Streak, längste Streak, Quizaktivität und Antwortraten berechnet.
- **Statistik-Cache:** `stats_snapshot` enthält gespeicherte und favorisierte eindeutige Lemma- und Sense-Zahlen, Quiz-Zahlen, aktuelle/längste Streak, aktive Tage, einzigartige geübte Senses und Antwortzähler. Er darf zur schnellen Anzeige gespeichert werden, ist aber abgeleitet. `activity_days` und `word_states` bleiben die Quelle der Wahrheit und der Cache wird neu berechnet.

Schema-Validierung kann Objektformen prüfen. Die App muss zusätzlich Referenzen und Beziehungen prüfen: vorhandene `sense_id`/`lemma_id`, existierende Ordner-IDs, keine Ordnerzyklen, keine doppelten Profil-Wortstatus und genau ein Aktivitätseintrag je Datum. Streak-Tage zählen nach `settings.time_zone` (IANA-Format, z. B. `Europe/Berlin`) nur dann, wenn das Tagesziel erreicht wurde. Die Regel, ob „heute“ oder „gestern“ eine aktuelle Streak erhält, muss die App konsistent festlegen.

Der Fortschritt pro Bedeutung kann zusätzlich je Erklärsprache geführt werden, da dasselbe Wort mit deutscher oder englischer Erklärung geübt werden kann:

| Feld | Beschreibung |
|---|---|
| `senseID` | Verweis auf den Inhalt |
| `lernsprache` | `de` oder `en` |
| `erklaersprache` | `de` oder `en` |
| `box` | Wiederholungsstufe (0 bis 5) |
| `faelligAm` | nächstes Wiederholungsdatum |
| `richtig`, `falsch` | Zähler |
| `zuletztGeuebt` | Datum |
| Ordner, Favoriten, Quizdaten | liegen im Profil-Wortstatus, unabhängig vom Lernfortschritt |

### Wiederholungslogik (Entwurf, Leitner-System)

| Box | Intervall |
|---|---|
| 0 | neu / falsch, sofort |
| 1 | 1 Tag |
| 2 | 3 Tage |
| 3 | 7 Tage |
| 4 | 14 Tage |
| 5 | 30 Tage |

Richtig → eine Box höher. Falsch → zurück auf Box 1. Die Werte sind ein Startwert und werden nach den ersten
Tests angepasst.

## 7. Einstellungen

Gespeichert lokal (z. B. `UserDefaults` oder ein SwiftData-Modell). Felder siehe `01-produkt-und-app.md`,
Abschnitt Editionen.

```swift
struct AppEinstellungen: Codable {
    var edition: Edition               // .de oder .intl
    var uiSprache: Sprache             // .de oder .en
    var erklaersprache: Sprache        // Standard je Edition
    var lernsprachen: [Sprache]
    var einsprachig: [Sprache: Bool]   // pro Lernsprache
    var zweitspracheAnzeigen: Bool
    var niveau: Niveau
}
```

## 8. Swift-Modelle

### 8.1 Inhalt (Codable, read-only)

Die Modelle spiegeln `schema.json`. Schlüssel mit Unterstrich (`bedeutung_kurz`, `verknuepfte_sense_ids`,
`quelle_id`) werden per `CodingKeys` auf camelCase-Eigenschaften abgebildet. Felder, die im Schema schon
einwortig sind, brauchen keine Zuordnung. Die Qualitätsdaten sind Pflichtfelder für Erzeugung und Freigabe. Die App lädt nur freigegebene Erklärungen; danach kann sie die Qualitätsmetadaten ignorieren.

```swift
enum Sprache: String, Codable, CaseIterable { case de, en }
enum Niveau: String, Codable, CaseIterable { case A1, A2, B1, B2, C1, C2 }

struct Lemma: Codable, Identifiable, Hashable {
    let id: String
    let sprache: Sprache
    let text: String
    let wortart: String
    let ipa: String?
    let haeufigkeitsrang: Int?
    let niveau: Niveau
    let artikel: String?
    let plural: String?
}

struct Uebersetzung: Codable, Hashable {
    let sprache: Sprache
    let text: String
    let alternativen: [String]?
    let verknuepfteSenseIds: [String]

    enum CodingKeys: String, CodingKey {
        case sprache, text, alternativen
        case verknuepfteSenseIds = "verknuepfte_sense_ids"
    }
}

struct Beispiel: Codable, Hashable {
    let satz: String
    let uebersetzung: String?
    let quelle: String            // "tatoeba" oder "ki"
    let quelleId: String?

    enum CodingKeys: String, CodingKey {
        case satz, uebersetzung, quelle
        case quelleId = "quelle_id"
    }
}

struct Qualitaet: Codable, Hashable {
    let status: String
    let pruefScore: Double?
    let hinweise: [String]
    let modellversion: String
    let datum: String

    enum CodingKeys: String, CodingKey {
        case status, hinweise, modellversion, datum
        case pruefScore = "pruef_score"
    }
}

struct Erklaerung: Codable, Hashable {
    let erklaersprache: Sprache
    let stufe: Niveau
    let definition: String
    let merkhilfe: String?
    let verwechslung: String?
    let beispiele: [Beispiel]
    let qualitaet: Qualitaet
}

struct Sense: Codable, Identifiable, Hashable {
    let id: String
    let bedeutungKurz: String
    let artikel: String?
    let plural: String?
    let uebersetzung: Uebersetzung
    let explanations: [Erklaerung]

    enum CodingKeys: String, CodingKey {
        case id, artikel, plural, uebersetzung, explanations
        case bedeutungKurz = "bedeutung_kurz"
    }
}

struct WortEintrag: Codable, Identifiable, Hashable {
    let lemma: Lemma
    let senses: [Sense]
    var id: String { lemma.id }
}
```

Zugriff nur über ein Protokoll, damit der Speicher später austauschbar ist:

```swift
protocol ContentRepository {
    func eintraege(lernsprache: Sprache, niveau: Niveau?) -> [WortEintrag]
    func eintrag(lemmaID: String) -> WortEintrag?
    func sense(id: String) -> (WortEintrag, Sense)?
    func suche(_ text: String, lernsprache: Sprache) -> [WortEintrag]
}
```

### 8.2 Lernstand (SwiftData)

Für spätere CloudKit-Synchronisation gelten Einschränkungen: alle Eigenschaften brauchen Standardwerte oder
sind optional, und es gibt keine `unique`-Einschränkungen. Die Eindeutigkeit (`senseID` + Erklärsprache)
prüft deshalb die App selbst.

```swift
import SwiftData

@Model
final class LernFortschritt {
    var senseID: String = ""
    var lernsprache: String = "en"
    var erklaersprache: String = "de"
    var box: Int = 0
    var faelligAm: Date = Date()
    var richtig: Int = 0
    var falsch: Int = 0
    var zuletztGeuebt: Date? = nil

    init(senseID: String, lernsprache: Sprache, erklaersprache: Sprache) {
        self.senseID = senseID
        self.lernsprache = lernsprache.rawValue
        self.erklaersprache = erklaersprache.rawValue
    }
}
```

```swift
@Model
final class ProfilWortstatus {
    var lemmaID: String = ""
    var senseID: String = ""
    var favorit: Bool = false
    var gespeichertAm: Date? = nil
    var ordnerIDs: [String] = []
    var quizAktiv: Bool = false
    var quizKategorien: [String] = []
    var quizSchwierigkeit: Int? = nil  // 1 bis 5
}

@Model
final class Tagesaktivitaet {
    var datum: String = ""             // lokales Datum, YYYY-MM-DD
    var uebungen: Int = 0
    var richtig: Int = 0
    var falsch: Int = 0
    var senseIDs: [String] = []
}
```

Ordner statt flacher eigener Wortlisten:

```swift
@Model
final class EigeneListe {
    var folderID: String = ""
    var name: String = ""
    var parentFolderID: String? = nil
    var erstellt: Date = Date()
    var senseIDs: [String] = []

    init(name: String) { self.name = name }
}
```

Der frühere Favoriten-Bool in `LernFortschritt` wird nicht als Speicherort für Favoriten verwendet. Favorit, Ordnerablage und Quizauswahl sind voneinander unabhängige Merkmale im `word_states`-Datensatz. So kann ein Wort favorisiert oder quizfähig sein, ohne in einem Ordner zu liegen.

## 9. Inhalts-Auslieferung

- Die Pipeline schreibt freigegebene Einträge nach `data/release/`:
  `content_en.json` und `content_de.json` (je eine Liste von `WortEintrag`) plus `manifest.json`.
- Die Listen validieren gegen `data/content-file.schema.json`; jeder Eintrag gegen `data/schema.json`.
- `manifest.json` enthält `schema_version` (aktuell `1.1`), Inhaltsversion, Datum, Anzahl der Einträge und Dateinamen.
- v1: Dateien liegen im App-Bundle. Updates kommen mit App-Updates.
- Später: Inhalts-Updates nachladen, Versionsvergleich über das Manifest. Da IDs stabil sind, bleibt der
  Lernstand gültig.

## 10. Schema-Versionierung und Dateiformat

`data/schema.json` beschreibt genau einen `LemmaEntry`. Die Content-Datei ist ein JSON-Array daraus; das Manifest trägt `schema_version: "1.1"`. `data/user-profile.schema.json` versioniert Nutzerdaten unabhängig als `schema_version: "1.0"`. Änderungen am Nutzerprofil benötigen so keine unnötige Migration des Inhaltsbestands.

## 11. Erweiterbarkeit

- **Neue Sprache:** erfordert zunächst die Erweiterung der zulässigen Sprachcodes und eine Prüfung der Export- und Übersetzungsregeln. Weitere Sprachen sind nicht ohne Schemaänderung freigeschaltet.
- **Neue Stufe:** weitere `explanations` pro Sense mit anderem `stufe`-Wert.
- **Neue Felder** (z. B. Bild, Audio-Datei): als optionale Felder ergänzen, damit alte Daten gültig bleiben.
  Das Schema wird versioniert (`schema_version` im Manifest).
- **Mehr Wörter:** Pipeline erneut laufen lassen. Bei mehr als einigen tausend Wörtern auf SQLite wechseln,
  ohne das `ContentRepository`-Protokoll zu ändern.
