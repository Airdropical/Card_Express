# 04 Schema-Bewertung (Stand: Testlauf 02)


## 1. Entscheidungen des Teams

| ID | Thema | Entscheidung |
|---|---|---|
| S3 | Wortformen (`formen`) | **Zurückgestellt** aus Komplexitätsgründen. Ersatz: Lemmatizer in der Validierung |
| S5 | Beispielsätze mehrfach gespeichert | **Option A beschlossen**, Beispiele je Sense generieren (Abschnitt 10) |
| S6 | Mehrere Zielsprachen (`uebersetzungen`) | **Zurückgestellt**. Zuerst Deutsch und Englisch |
| S7 | `niveau` pro Sense | **Zurückgestellt**. Mit 40 Wörtern nicht beurteilbar |
| S9 | Modell-ID, `prompt_version`, `schritt` | **Bestätigt, für die Zukunft geplant** |

Die übrigen Punkte (S1, S2, S4, S8, S10) sind in Abschnitt 2 eingeordnet.

## 2. Stand der Befunde nach Testlauf 02

| ID | Befund | Stand | Anmerkung |
|---|---|---|---|
| S1 | `artikel` und `plural` am Sense | **Umgesetzt** | „Schild": Lemma `null`, Senses „das / Schilder" und „der / Schilde" |
| S2 | Verknüpfung als Liste (`verknuepfte_sense_ids`) | **Umgesetzt** | 40 von 41 Senses verknüpft, alle symmetrisch. Nur 1:1-Fälle getestet |
| S3 | Wortformen | Zurückgestellt | siehe Abschnitt 1 |
| S4 | `qualitaet` an der Explanation | **Umgesetzt** | Pflichtfeld in jeder Explanation; Testläufe 1–3 geprüft |
| S5 | Beispielsätze mehrfach | **Entschieden: Option A** | Schritt 4a/4b, siehe Abschnitt 10 |
| S6 | `uebersetzungen` (mehrere Zielsprachen) | Zurückgestellt | Doku-Aussage korrigieren (Abschnitt 7) |
| S7 | `niveau` pro Sense | Zurückgestellt | erneut prüfen, wenn mehrdeutige Wörter in größerer Zahl vorliegen |
| S8 | IDs für Homographe | Offen, niedrige Priorität | „Schild" wurde als **ein Lemma mit zwei Senses** gelöst (Muster, siehe unten) |
| S9 | Modell-ID, `prompt_version`, `schritt` | Geplant | bis dahin Konvention: `modellversion` = exakte Modell-ID |
| S10 | Dateiformat nicht im Schema | Umgesetzt | `content_{sprache}.json`-Liste und Manifest-Schema mit `schema_version` |

**Muster aus „Schild" (zu S8):** Gleichlautende Wörter mit anderem Artikel werden als ein Lemma mit mehreren
Senses abgelegt. Artikel und Plural stehen dann am Sense. Das reicht, solange Aussprache und Häufigkeit nicht je
Bedeutung verschieden sein müssen. Das `-h{n}`-Suffix aus der ersten Bewertung ist damit vorerst nicht nötig.

## 3. Datenbasis

| Kennzahl | Testlauf 01 | Testlauf 02 |
|---|---|---|
| Einträge (Lemmata) | 40 (20 `de`, 20 `en`) | 40 (20 `de`, 20 `en`) |
| Senses | 72 (32 Lemmata mit 2 Senses) | 41 (nur „Schild" mit 2 Senses) |
| Explanations | 144 | 82 |
| Beispiele pro Explanation | immer 2 | immer 2 |
| `quelle` der Beispiele | 288 von 288 `ki` | 164 von 164 `ki` |
| `merkhilfe` gesetzt | 0 | 0 |
| `verwechslung` gesetzt | 4 (nur „Bank") | 0 |
| `stufe` = Lemma-`niveau` | 144 von 144 | 82 von 82 |
| Niveaus | A1 (14), A2 (20), B1 (6) | A1 (28), A2 (12) |
| `ipa`, `haeufigkeitsrang` | alle `null` | alle `null` |
| `qualitaet.status` | alle `roh` | alle `roh` |
| `modellversion` | `"ChatGPT"` | `"ChatGPT (manueller Test)"` |
| Verknüpfte Senses | 2 | 40 von 41 |

**Grenzen der Aussage:**

- Testlauf 02 besteht fast nur aus eindeutigen A1/A2-Wörtern (39 von 40 Lemmata mit nur einer Bedeutung). Er prüft
  vor allem den Normalfall. Nicht getestet sind 1:n-Verknüpfungen, unregelmäßige Verbformen, höhere Stufen,
  Adverbien und Präpositionen.
- Beide Läufe entstanden ohne Rohdaten (Pipeline-Schritt 2). Es gibt keine `tatoeba`-Sätze, kein IPA, keine Ränge.
- Die Kennzahlen stammen aus einem eigenen Skript. Ein formaler Schema-Validator wurde nicht eingesetzt.

## 4. S5 im Detail: Beispielsätze sind mehrfach gespeichert

### 4.1 Ist-Zustand (Beleg aus Testlauf 02)

Beispiele liegen **in jeder Explanation** (`explanations[].beispiele[]`). Daraus ergibt sich dreifache Redundanz:

1. **Zwischen Erklärsprachen:** In 41 von 41 Senses sind die Sätze der `de`- und der `en`-Explanation identisch.
   Nur das Feld `uebersetzung` ist anders (`null` bei gleicher Sprache, sonst der Text der anderen Sprache).
2. **Zwischen verknüpften Senses:** In 20 von 20 verknüpften DE/EN-Paaren steht dasselbe Satzpaar spiegelverkehrt
   auf beiden Seiten. Beispiel: `de-apfel-nomen-1` hat „Der Apfel ist rot." mit Übersetzung „The apple is red.",
   `en-apple-nomen-1` hat „The apple is red." mit Übersetzung „Der Apfel ist rot.".
3. **Bei Definitionen:** In 19 von 20 Paaren ist auch die deutsche Definition auf beiden Seiten wortgleich.

**Zahlen:** 164 Beispiel-Objekte enthalten nur **42 verschiedene Satzpaare**. Jedes Paar ist im Mittel knapp
viermal gespeichert (2 Lemmata × 2 Erklärsprachen).

### 4.2 Warum das ein Problem sein kann (und wo nicht)

| Aspekt | Bewertung |
|---|---|
| Dateigröße | **kein Problem.** Testlauf 02 hat ca. 2,7 KB je Eintrag, also ca. 5 MB für 2.000 Lemmata |
| Pflege und Konsistenz | **Risiko.** Eine Korrektur muss an bis zu vier Stellen erfolgen, Abweichungen bleiben unbemerkt |
| Pipeline-Kosten | **Risiko.** Schritt 4 erzeugt Sätze pro Lemma und Erklärsprache, also bis zu viermal pro Paar. Bei getrennten Aufrufen können die Sätze auseinanderlaufen |
| Qualitätsprüfung | **Risiko.** `qualitaet` liegt pro Explanation (S4), derselbe Satz kann dort verschieden bewertet werden |
| Natürlichkeit | **Gegenrisiko bei Spiegelung.** Wird ein Satz einfach übersetzt, klingt er in der zweiten Sprache leicht „übersetzt". Sätze sollten in der Lernsprache natürlich sein |
| App-Code | Kein Problem bei der heutigen Struktur, jede Explanation ist in sich vollständig |

### 4.3 Optionen

**Option A: Beispiele je Explanation (Ist-Zustand), Pipeline-seitig dedupliziert**

Das Schema bleibt unverändert. Die Pipeline erzeugt Sätze **einmal** (neuer Schritt 4a pro Sense) und kopiert
sie beim Export in alle Explanations. Die Redundanz bleibt in der Datei, entsteht aber nur noch mechanisch.

```json
"explanations": [
  { "erklaersprache": "de", "beispiele": [ { "satz": "The apple is red.", "uebersetzung": "Der Apfel ist rot." } ] },
  { "erklaersprache": "en", "beispiele": [ { "satz": "The apple is red.", "uebersetzung": null } ] }
]
```

**Option B: Beispiele am Sense, Übersetzungen als Liste je Erklärsprache**

```json
"senses": [{
  "id": "en-apple-nomen-1",
  "beispiele": [
    { "satz": "The apple is red.",
      "uebersetzungen": [ { "sprache": "de", "text": "Der Apfel ist rot." } ],
      "quelle": "ki", "quelle_id": null }
  ],
  "explanations": [ { "erklaersprache": "de", "definition": "…" }, { "erklaersprache": "en", "definition": "…" } ]
}]
```

Entfernt die Duplikate zwischen Erklärsprachen (164 → 82 Objekte), aber nicht die Spiegelung zwischen verknüpften
Senses. Ändert das Schema und die Swift-Modelle.

**Option C: eigene Sammlung von Satzpaaren, Senses verweisen per ID**

```json
// content_satzpaare.json
{ "id": "sp-0001", "texte": { "de": "Der Apfel ist rot.", "en": "The apple is red." },
  "niveau": "A1", "quelle": "ki", "quelle_id": null,
  "qualitaet": { "status": "roh", "pruef_score": null, "hinweise": [], "modellversion": "…", "datum": "2026-11-04" } }

// Sense (de-apfel-nomen-1 und en-apple-nomen-1 verweisen beide darauf)
"beispiel_ids": ["sp-0001", "sp-0002"]
```

Darstellungsregel in der App: Lernsatz = `texte[lemma.sprache]`, Übersetzung = `texte[erklaersprache]`, wenn
Erklärsprache und Lernsprache verschieden sind, sonst `null`. Ein Satzpaar gehört zu mehreren Senses.
Kleinster Speicher (164 → 42 Objekte), jede Korrektur genau einmal.

### 4.4 Vergleich

| Kriterium | A (Ist, dedupliziert in Pipeline) | B (am Sense) | C (Satzpaare) |
|---|---|---|---|
| Satzobjekte im Testlauf 02 | 164 | 82 | 42 |
| Korrektur eines Satzes an | bis zu 4 Stellen, per Skript | 2 Stellen | 1 Stelle |
| Schemaänderung | keine | ja, Migration | ja, neue Datei, Migration |
| Pipeline | neuer Schritt 4a, Rest bleibt | Schritt 4 geteilt | Schritt 4 geteilt, Verknüpfen **vor** Satz-Erzeugung nötig |
| Qualitätsstatus pro Satz | nur über Explanation | nur über Explanation | eigener Status am Satzpaar |
| Swift-Aufwand | gering | mittel | mittel bis hoch (Zusammenführen beim Laden) |
| Unverknüpfte Senses | unproblematisch | unproblematisch | brauchen eigene Satzpaare |
| Weitere Sprache später | Schemaänderung nötig | Liste wächst | Map `texte` wächst |
| Natürlichkeit der Sätze | frei wählbar je Seite | frei wählbar | ein Paar für beide Seiten (Spiegelungsrisiko) |

### 4.5 Empfehlung

**Option A mit deduplizierter Pipeline** für den Teststart bis 1.000 Wörter pro Sprache. Begründung:

- Das Team hat Komplexität bewusst zurückgestellt (S3, S6, S7). A ändert Schema und App nicht.
- Dateigröße ist unkritisch. Das echte Risiko sind Konsistenz und Kosten, und beides löst die Pipeline-Seite:
  Sätze einmal pro Sense erzeugen, einmal prüfen, mechanisch in alle Explanations kopieren.
- B ist der schwächste Kompromiss: Schemabruch, aber die Spiegelung zwischen den Sprachen bleibt.
- **Option C ist das Zielbild**, falls später eine dritte Sprache (S6), Satz-ID-basiertes „Fehler melden" oder
  Inhalts-Updates pro Satz kommen. Der Umstieg ist dann ein einmaliger Export-Umbau, weil die App-Daten aus
  der Pipeline erzeugt werden.

Diese Empfehlung ersetzt die frühere Empfehlung B aus der ersten Fassung dieser Bewertung. Neu ist die
Überlegung, die Redundanz im Export zu akzeptieren und an der Quelle (Pipeline) zu vermeiden.

### 4.6 Umsetzung für Option A

1. Pipeline: Schritt 4 aufteilen in **4a** (Sätze und Übersetzungen pro Sense, einmal) und **4b** (Definition,
   Merkhilfe, Verwechslung pro Erklärsprache).
2. Export: Sätze aus 4a in jede Explanation des Senses kopieren, `uebersetzung` je nach Erklärsprache setzen
   (`null` bei gleicher Sprache).
3. Validierungsregel: Alle Explanations eines Senses haben dieselben `satz`-Werte in gleicher Reihenfolge.
4. Optionale Regel für verknüpfte Paare: Satzpaare spiegeln sich, sonst Hinweis (kein harter Fehler).
5. Natürlichkeits-Check in Schritt 6: „Klingt der Satz in der Lernsprache natürlich, nicht übersetzt?"

### 4.7 Entscheidungskriterien für einen späteren Wechsel zu C

- Eine dritte Sprache wird konkret geplant.
- Fehlermeldungen oder Updates sollen pro Satz laufen.
- Sätze sollen aus Tatoeba mit stabiler ID übernommen und geteilt werden.
- Die Pflege der doppelten Sätze erzeugt in der Praxis nachweisbar Abweichungen (Prüfskript aus 4.6, Punkt 3
  meldet regelmäßig Verstöße).

## 5. Schema v1.1 (abgeleitet aus Testlauf 02)

| Änderung | Betrifft | Stand |
|---|---|---|
| `artikel`, `plural` optional am Sense, überschreiben das Lemma | `Sense` | umgesetzt |
| `verknuepfter_sense_id` → `verknuepfte_sense_ids` (Liste, auch leer) | `Uebersetzung` | umgesetzt |
| `qualitaet` an jeder Explanation (Pflicht) | `Explanation` | umgesetzt |
| `qualitaet` am Eintrag bleibt als Zusammenfassung | `LemmaEntry` | umgesetzt |
| Regel „Artikel am Lemma oder an allen Senses" | Validierung | nötig |
| `formen`, `niveau` am Sense, `uebersetzungen` | S3, S7, S6 | **nicht** Teil von v1.1 |
| `prompt_version`, `schritt` in `qualitaet` | S9 | später, optional |
| `schema_version` im Manifest | Manifest | umgesetzt (S10) |

Ausschnitt der Abweichungen gegenüber v1.0:

```json
"Sense": {
  "properties": {
    "artikel": { "enum": ["der", "die", "das", null] },
    "plural":  { "type": ["string", "null"] }
  }
},
"Uebersetzung": {
  "properties": {
    "verknuepfte_sense_ids": { "type": "array", "items": { "type": "string" } }
  }
},
"Explanation": {
  "required": ["erklaersprache", "stufe", "definition", "beispiele", "qualitaet"],
  "properties": { "qualitaet": { "$ref": "#/$defs/Qualitaet" } }
}
```

**Regeln zur Qualität:**

- Status in der Reihenfolge von schlecht nach gut: `prueffliste`, `roh`, `geprueft`, `freigegeben`.
- Der Eintrag-Status ist der **schlechteste** Status seiner Explanations.
- Der Export (Schritt 7) filtert pro Explanation. Ein Sense erscheint nur, wenn mindestens eine Explanation
  `freigegeben` ist. Die App zeigt nur freigegebene Erklärsprachen an.

## 6. Validierungsregeln (aktualisiert)

| # | Regel | Stand |
|---|---|---|
| 1 | Echter Schema-Validator (`jsonschema`, Draft 2020-12), Content- und Manifest-Dateien | umgesetzt |
| 2 | Lemmaformen im Satz: kuratierter Formenbestand für Testlauf 3; allgemeiner spaCy-Lemmatizer vor großer Pipeline erforderlich | teilweise umgesetzt |
| 3 | Symmetrie: Verweist A auf B, muss B auf A verweisen. Verweise zeigen auf existierende Senses der **anderen** Sprache | neu präzisiert |
| 4 | Export: Jeder freigegebene Sense hat je Erklärsprache mindestens eine Explanation | wie bisher |
| 5 | Artikel: Deutsche Nomen haben `artikel` am Lemma **oder** an jedem Sense. Plural: Sense-Wert gewinnt | neu (Schild) |
| 6 | **Plural als volle Wortform**, nie nur die Endung. Nicht zählbare Nomen: `null` | neu (siehe 8.1) |
| 7 | Quellen: `tatoeba` verlangt `quelle_id`, `ki` verlangt `quelle_id = null` | wie bisher |
| 8 | Eintrag-Status = schlechtester Status der Explanations | neu |
| 9 | Alle Explanations eines Senses haben dieselben `satz`-Werte (Option A) | umgesetzt und geprüft |
| 10 | Einsprachigkeit: In Explanations mit Lernsprache = Erklärsprache kommt die andere Sprache nicht vor (Hinweis, kein harter Fehler) | wie bisher |

## 7. Aufgabe für den Agenten

1. `data/schema.json`, `docs/02-datenschema.md` und diese Datei lesen.
2. Kennzahlen aus Abschnitt 3 für Testlauf 02 mit eigenem Skript nachrechnen. Abweichungen melden.
3. `data/schema.json` auf **v1.1** bringen (Abschnitt 5) und `schema_version` vermerken. Danach beide Testläufe
   gegen den echten Validator prüfen. Testlauf 01 liegt im Format v1.0 vor, Migration dafür ist **optional**
   (als Regressionstest nutzbar).
4. Validierungsregeln aus Abschnitt 6 als Prüfskript umsetzen (Regeln 2, 3, 5, 6, 8, 9 sind neu oder geändert).
5. S5: **nicht** umbauen. Pipeline-Schritt 4a/4b entwerfen (Abschnitt 4.6) und eine Kostenschätzung liefern:
   Aufrufe mit und ohne Deduplizierung.
6. `docs/02-datenschema.md` nachziehen: Felder, Beispiel-JSON, Validierungsregeln, Swift-Modelle. Dabei die
   Aussage in Abschnitt 10 („neue Sprache ohne Schemaänderung") korrigieren, solange S6 zurückgestellt ist:
   Eine dritte Sprache braucht eine Erweiterung von `uebersetzung`.
7. `pipeline/prompts.md` nachziehen: Ausgabeschema, getrennte Sätze (4a), Plural als volle Form.

**Akzeptanzkriterien:**

- Testlauf 02 validiert gegen `schema.json` v1.1 ohne Fehler.
- Regel 5 akzeptiert „Schild" (Artikel an den Senses) und lehnt ein deutsches Nomen ohne Artikel ab.
- Englische Plurale sind volle Wortformen; nicht zählbare Nomen haben `null`. Testlauf 2 entsprechend korrigiert.
- Symmetrie-Prüfung meldet 0 Verstöße.
- Doku und Swift-Modelle spiegeln v1.1.
- Eine Kostenschätzung für Schritt 4a/4b liegt vor.

## 8. Außerhalb des Schemas (nur Verweis)

### 8.1 Aus Testlauf 02

- **Plural bei Englisch (korrigiert):** Testlauf 2 verwendet nun volle Pluralformen; `water` und `work` haben als nicht zählbare Nomen `null`.
- **`merkhilfe` und `verwechslung`** sind in 82 von 82 Fällen leer. Prompt in Schritt 4 nachschärfen. „der Schild /
  das Schild" ist ein ideales Merkhilfe-Beispiel.
- **`en-go-verb-1`:** „move on foot" beschreibt „walk", nicht „go".
- **Mini-Abweichung:** „Das Auto ist schnell." wurde mit „This car is fast." übersetzt.

### 8.2 Aus Testlauf 01 (weiter relevant)

- Falsche oder unpassende Beispielübersetzungen (`de-frei-adjektiv-2`, `en-break-verb-2`).
- Holprige Definitionen bei A1-Wörtern (`de-freund-nomen`, `de-finden-verb-1`).
- Mehrdeutige Hauptübersetzung (`de-schloss-nomen-1`: castle gegenüber palace, Burg-Verwechslung fehlt).

### 8.3 Empfehlung für Testlauf 03

Gezielt die Lücken aus Abschnitt 3 abdecken: mehrdeutige Wörter (mindestens 10), unregelmäßige Verben
(nehmen, werden, go), eine 1:n-Verknüpfung („schwer" ↔ „hard", „difficult", „heavy"), Stufen B1 und höher,
je ein Adverb und eine Präposition, und erstmals Rohdaten aus Schritt 2 (IPA, Rang, Tatoeba-Sätze).

## 9. Offene Fragen

- **S5: entschieden.** Option A ist umgesetzt; erneute Bewertung nur bei unabhängig verwalteten Satzdaten.
- Ab welcher Wortzahl oder welchem Testlauf wird S7 (`niveau` pro Sense) neu bewertet?
- Gilt das „Schild"-Muster (ein Lemma, mehrere Senses mit eigenem Artikel) auch für Wörter mit
  unterschiedlicher Aussprache? Dann wäre S8 neu zu öffnen.
- Zeitpunkt für die Wiederaufnahme von S6 (dritte Sprache) und S3 (`formen`)?
- Soll der Eintrag-Status (Regel 8) auch in der App sichtbar sein oder nur in der Pipeline gelten?

---

## 10. Nachprüfung, Entscheidungen und Umsetzung

### Entscheidungen

- **S5: Option A beschlossen.** Beispiele bleiben im exportierten Schema je Explanation, werden aber in der Pipeline nur einmal je Sense erstellt (4a) und beim Export in alle Explanations kopiert. Das erhält die aktuelle Datenform und App. Eine spätere Migration zu C bleibt möglich, falls Satzdaten unabhängig aktualisiert oder geteilt werden müssen.
- **S4: `qualitaet` ist jetzt Pflicht an jeder Explanation.** Der Status am Eintrag bleibt eine berechnete Zusammenfassung (schlechtester Kinderstatus).
- **S10: umgesetzt.** `data/content-file.schema.json` beschreibt die Liste, `data/manifest.schema.json` erzwingt `schema_version: "1.1"`.
- **S8:** Homographe mit gleicher Grundform bleiben vorerst ein Lemma mit mehreren Senses und Sense-Artikeln/-Pluralen. IDs mit `-h{n}` bleiben zurückgestellt, solange Aussprache/Häufigkeit nicht je Bedeutung getrennt werden müssen.
- **S3:** spaCy ist in der Laufzeitumgebung nicht installiert. Für Testlauf 3 prüft ein kuratierter Formenbestand die bewusst ausgewählten unregelmäßigen Formen. Das ersetzt keinen allgemeinen Lemmatizer; vor der großen Pipeline ist spaCy samt Deutsch-/Englisch-Modellen erforderlich.
- **Rohdaten (Schritt 2):** Nicht in Testlauf 3 aufgenommen. Im Projekt liegt kein geprüfter Rohdatenbestand samt Lizenz-/Attributionsnachweis. IPA, Rang und Tatoeba-IDs werden deshalb nicht erfunden; Beispiele bleiben ehrlich als `ki` markiert. Eine kleine, lizenzgeprüfte Rohdaten-Stichprobe ist ein eigener nächster Test.

### Korrekturen an Testlauf 2

- Englische Plurale wurden von Endungs-Platzhaltern wie `s` auf volle Formen korrigiert (`apples`, `houses` usw.). Nicht zählbare `water` und `work` haben jetzt `null`.
- `GPT-6 (Codex)` ist in allen Testlauf-2-Qualitätsobjekten als Modellkontext eingetragen.
- Ein formaler Draft-2020-12-Validator (`jsonschema`) ist eingerichtet. Beide vorherigen Läufe bestehen ihn.

### Kostenschätzung für S5 / Schritt 4a–4b

Annahme: 40 Lemmata je Batch; bisher ein Schritt-4-Aufruf pro Erklärsprache.

| | Bisher | Option A |
|---|---:|---:|
| Modellaufrufe pro 40er-Batch | 2 | 3 (ein 4a, zwei 4b) |
| Aufrufe für 2.000 Lemmata / 50 Batches | ca. 100 | ca. 150 |
| Beispielsatz-Textausgabe, anhand Testlauf 2 | 864 Wörter einschließlich Wiederholungen | 432 Wörter einmal je Sense |
| Gesamte Inhaltswörter in Definitionen, Satztexten und Satzübersetzungen | 1.928 | ca. 1.496 (rund 22 % weniger) |

Das ist eine Textmengen-Schätzung aus Testlauf 2, kein Preisangebot. Die zusätzliche Anfrage erhöht den Fixaufwand; eingesparte Ausgabe-Tokens hängen vom Modellpreis ab. Ohne ausgewähltes API-Modell und Tokenizer ist eine belastbare Euro-Schätzung nicht möglich.

### Testlauf 3: Abdeckung

- 40 neue Lemmata, 20 je Sprache; keine Wiederholung aus Testlauf 1 oder 2.
- 13 mehrdeutige Lemmata, darunter fünf deutsche Homographen mit Artikel-/Pluralwechsel.
- Neue unregelmäßige Verben (werfen, schlafen, geben, behalten, ziehen; throw, sleep, give, keep).
- 1:n-Verknüpfung: `erwerben` ↔ `acquire` und `obtain`.
- B1/B2, Adverbien und Präpositionen in beiden Sprachen.
- Die empfohlene Wiederholung `nehmen/werden/go` wird ausgelassen, weil sie bereits in Testlauf 1 oder 2 vorkommt und die 200er-Stichprobe unterschiedliche Lemmata enthalten soll.

- Für Testlauf 1 blieb die konkrete Modell-ID rückwirkend unbekannt; `ChatGPT (manueller Test)` ist keine exakte ID. Der Protokollhinweis kennzeichnet diese Lücke, ohne eine ID zu erfinden.

## 11. Review Testlauf 03 und Ausbau auf App-Nutzerdaten

### Fachkorrekturen aus der Prüfung

- **Artikel-Satz-Widerspruch:** `de-kiefer-nomen-1` wird auf „der Kiefer“ korrigiert. Der Validator gibt erkennbare Artikelwidersprüche in Beispielen künftig als manuelle Prüfwarnung aus, nicht als harten Schemafehler.
- **Merkhilfen:** Die Kiefer-Merkhilfe benennt beide Bedeutungen ausdrücklich. Mehrdeutige deutsche und englische Lemmata sowie „ziehen“ bekommen unterscheidende, geprüfte Merkhilfen; Buchstaben-/Endungsregeln werden nicht als Faustregel verwendet.
- **See:** Duden kennzeichnet „die See“ im Sinn von Meer ohne Plural. Daher bleibt der Plural für `de-see-nomen-2` `null`; „Meere“ gehört zu „das Meer“.
- **Übersetzungen:** `en-obtain` wird mit „erhalten“ übersetzt und Alternativen müssen stets in der Übersetzungssprache stehen. Bei `band` (Streifen) ist `text = "Streifen"`, `alternativen = ["Band"]`.
- **Plural-Normalisierung:** Gleiche Plurale von Homographen stehen einmal am Lemma (`barks`, `cranes`, `matches`, `seals`, `bands`), nicht auf jedem Sense.
- **Definitionen und Senses:** `sleep` wird genauer und kürzer erklärt. `gegen/against` trennt Kontakt mit einer Fläche von Gegnerschaft/Widerstand; Definitionen und Beispiele sind parallel.

Die verifizierte Angabe zu „die See“ stammt aus [Duden: See (Meer)](https://www.duden.de/rechtschreibung/See_Meer); der Eintrag nennt im Meer-Sinn „ohne Plural“. „Das Meer“ hat dagegen den Plural „Meere“ ([Duden: Meer](https://www.duden.de/rechtschreibung/Meer)).

### Nutzerprofil-Schema

Die Inhaltsdaten bleiben read-only und app-/nutzerunabhängig (`schema_version: 1.1`). Neu ist ein getrenntes `data/user-profile.schema.json` (Profilversion 1.0). Es deckt Haupt- und Unterordner, Sense-Referenzen, unabhängige Favoriten, Quiz-Kategorien und Schwierigkeitsgrad, Leitner-Fortschritt sowie tägliche Aktivität ab. Statistik-Snapshots sind ausdrücklich abgeleitete Caches; Aktivitätstage und Wortstatus sind die Quelle der Wahrheit. App-seitige Referenz- und Zyklusprüfungen sind zusätzlich zur JSON-Schema-Validierung erforderlich.

Die HTML-Vorschau bekommt diese Nutzerfunktionen noch nicht; die Änderung legt das Datenformat und die Implementierungsregeln für die App fest.
