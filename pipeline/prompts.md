# KI-Prompts für die Vokabel-Pipeline

Gilt für alle Schritte: Ausgabe als JSON nach Schema-Version 1.1 (`schema.json`); in der aktuellen Testphase Modellname bzw.
Oberfläche ehrlich dokumentieren. Der Testumfang beträgt insgesamt 200 Lemmata in fünf Läufen à 40. Ein Lauf
kann zur Begrenzung der Tokenmenge in kleinere Eingabe-Batches unterteilt werden. Für Batch-Ausgaben gilt:
Antworte mit einem JSON-Array, das genau einen vollständigen `LemmaEntry` pro Eingabelemma enthält;
jedes Array-Element muss einzeln `schema.json` erfüllen. Keine Kommentare oder Markdown-Fences ausgeben.

## Stufenregeln (in Schritt 4 einsetzen als {stufenregeln})

| Stufe | Regeln für Definition und Beispielsätze |
|---|---|
| A1 | max. 8 Wörter pro Satz, nur Grundwortschatz, Gegenwart, keine Nebensätze |
| A2 | max. 12 Wörter pro Satz, einfache Nebensätze, häufige Zeiten |
| B1 | max. 16 Wörter pro Satz, alltägliche Sprache, einzelne Fachwörter erklären |
| B2 | max. 20 Wörter pro Satz, natürliche Sprache, Redewendungen erlaubt |
| C1 | freier Stil, Nuancen und Register (formal/umgangssprachlich) benennen |

---

## Schritt 3: Bedeutungen bereinigen

**System:**
Du bist Lexikograf für Sprachlernmaterial. Du arbeitest ausschließlich mit den gelieferten Rohdaten
und deinem sicheren Sprachwissen. Wenn du dir unsicher bist, schreibe das in `qualitaet.hinweise`,
statt zu raten. Antworte nur mit gültigem JSON nach dem Schema.

**User:**
Bearbeite jedes Lemma aus der Eingabeliste unabhängig. Erzeuge genau einen Eintrag je Eingabelemma.
Eingabeliste (maximal 40 Lemmata in diesem Testlauf; kleinere Teil-Batches sind zulässig):
{lemmata}

Für jedes Lemma gelten: Sprache, Wortart und Häufigkeitsrang aus der Eingabe übernehmen.
Zielsprache der Übersetzung: {uebersetzungssprache je Lemma}

Rohdaten (je Lemma, falls vorhanden):
{rohdaten}

Aufgabe:
1. Fasse die Bedeutungen auf höchstens 4 gängige Hauptbedeutungen zusammen. Führe Dubletten zusammen.
   Lass veraltete, vulgäre, regionale oder sehr seltene Bedeutungen weg, außer sie sind im Alltag üblich.
2. Gib pro Bedeutung eine kurze Disambiguierung (`bedeutung_kurz`, max. 60 Zeichen, in der Sprache des Lemmas).
3. Gib pro Bedeutung die beste Übersetzung des Lemmas und bis zu 3 Alternativen. `uebersetzung.text` ist genau eine passende Wortform oder Wortgruppe in der Zielsprache. `alternativen` enthalten ebenfalls ausschließlich Wörter der Zielsprache; niemals das Lemma oder eine Alternative in der Ausgangssprache eintragen. Mehrere Synonyme nicht als „X oder Y“ in `text` zusammenfassen.
4. Schlage das Niveau (A1 bis C2) für das Lemma vor, orientiert an Alltagshäufigkeit und Komplexität.
5. Nomen: immer die vollständige Pluralform als Wort eintragen, nie nur eine Endung. Nicht zählbare englische Nomen erhalten `plural: null`. Bei deutschen Nomen Artikel und vollen Plural am Lemma eintragen; unterscheiden sie sich je Sense, den Lemma-Wert auf `null` setzen und beide Werte je Sense setzen. Bei Homographen mit gleichem Plural den Plural nur einmal am Lemma speichern. Artikel gegen Bedeutung und Beispielsätze plausibilisieren; ein erkennbarer Widerspruch wird als Warnhinweis ausgegeben und manuell geprüft, nicht automatisch als harter Schemafehler gewertet. Lautschrift (IPA), falls in Rohdaten vorhanden.
6. `explanations` bleibt leer (`[]`). `qualitaet.status` ist `roh`.

---

## Schritt 4a: Beispielsätze einmalig je Sense erzeugen

Einmal pro Sense ausführen, bevor Erklärungen in Deutsch und Englisch ergänzt werden.

**System:**
Du erstellst natürliche Beispielsätze für Sprachlernmaterial. Die Sätze müssen die konkrete Bedeutung des Senses zeigen und im Niveau liegen. Antworte nur mit gültigem JSON.

**User:**
Für folgende Lemma-Senses erstelle je Sense 2 Beispielsätze in der Lernsprache und eine natürliche Übersetzung in die andere Sprache:
{lemma_und_sense_liste}

Verfügbare Tatoeba-Rohsätze und IDs:
{tatoeba_saetze}

Ausgabe: JSON-Array mit einem Objekt je `sense_id`:
`{"sense_id":"...","beispiele":[{"satz":"...","uebersetzung_andere_sprache":"...","quelle":"ki","quelle_id":null}]}`

Regeln:
- Beispiele einmal pro Sense erzeugen, nicht erneut für jede Erklärsprache.
- `quelle=tatoeba` nur mit übergebener, passender Satz-ID; sonst `quelle=ki`, `quelle_id=null`.
- Satz und Übersetzung müssen in beiden Sprachen natürlich klingen. Nicht wörtlich übersetzen, wenn dadurch unnatürliche Sprache entsteht.
- Die konkrete Sense-Bedeutung muss aus dem Satzkontext erkennbar sein.
- Bei mehrdeutigen Lemmata jede Sense klar von den anderen unterscheiden; getrennte Funktionen (z. B. Kontakt mit einer Fläche vs. Gegnerschaft) werden getrennte Senses mit passenden, parallelen Beispielen und Definitionen.
- Lemma oder eine echte gebeugte Form muss im Satz vorkommen.
- Satzlänge und Wortschatz müssen zur Stufe passen.

## Schritt 4b: Erklärungen je Erklärsprache erzeugen

Zweimal pro Sense ausführen: einmal `erklaersprache=de`, einmal `erklaersprache=en`. Die Sätze aus Schritt 4a sind schreibgeschützt und werden beim lokalen Export unverändert übernommen.

**System:**
Du schreibst fachlich korrekte, natürliche Lernerklärungen. Antworte nur mit gültigem JSON.

**User:**
Senses und Wortdaten:
{lemma_json_ohne_explanations}

Erklärsprache: {erklaersprache}
Stufe: {stufe}
Stufenregeln: {stufenregeln}

Gib pro Sense ein Erklärungsobjekt mit `sense_id`, `definition`, `merkhilfe`, `verwechslung` und `qualitaet` zurück.

Regeln:
- Eine Definition muss die konkrete Bedeutung treffen und mit einem unterscheidenden Merkmal von ähnlichen Begriffen abgrenzen. Eine bloße Oberkategorie wie „runde Frucht“ genügt nicht.
- Vermeide Zirkelschlüsse und leere Füllsätze. Erkläre Funktion, typischen Kontext oder entscheidende Eigenschaft in einfacher, natürlicher Sprache.
- Halte Satzlänge und Wortschatz strikt auf dem vorgegebenen Niveau.
- `merkhilfe`: bei mehrdeutigen, leicht verwechselbaren Senses eine kurze, korrekte und tatsächlich unterscheidende Merkhilfe geben. Keine falschen Faustregeln aus einzelnen Buchstaben oder Endungen ableiten; bei eindeutigen Senses darf das Feld `null` sein.
- `verwechslung`: nur bei einer konkreten, häufigen Verwechslung; nenne den Unterschied kurz, sonst `null`.
- `qualitaet` ist Pflicht und bewertet diese Erklärung einzeln. Unsicherheit in `hinweise` festhalten.
- Beispielsätze und Übersetzungen nicht neu formulieren. Der Export kopiert die exakten Schritt-4a-Beispiele in alle Explanations und setzt `uebersetzung=null`, wenn Lern- und Erklärsprache gleich sind.

## Schritt 5: Automatische Prüfung (Code, kein KI-Aufruf)

- Jeden Eintrag gegen `schema.json` (Version 1.1) und die Datei als Liste gegen `content-file.schema.json` validieren.
- Kommt das Lemma (oder eine Beugungsform) in jedem Beispielsatz vor?
- Satzlänge im Limit der Stufe?
- Gibt es je Bedeutung genau eine Erklärung pro Erklärsprache und Stufe?
- Bei gleicher Lern- und Erklärsprache: `uebersetzung` ist `null`.
- Sense-Links müssen auf vorhandene IDs der Zielsprache zeigen und gegenseitig sein.
- `uebersetzung.text` und alle `alternativen` müssen in der Zielsprache stehen; Übersetzungsfeld und Beispielsatzübersetzungen müssen dieselbe Bedeutung wiedergeben.
- Deutsche Nomen brauchen Artikel und volle Plurale auf Lemma- oder Sense-Ebene. Abweichende Sense-Werte verlangen `null` am Lemma. Englische Nomen verwenden die volle Pluralform, niemals nur `s`/`es`; nicht zählbare Nomen haben `null`.
- Bei identischem Plural aller Homographen steht der Plural am Lemma, nicht redundant auf jedem Sense.
- Für mehrdeutige Lemmata prüfen, ob jeder Sense eine hilfreiche Merkhilfe hat und ob sie die Senses korrekt auseinanderhält. Verdächtige Artikel-Satz-Widersprüche nur als Prüfwarnung ausgeben.
- Alle Explanations desselben Senses müssen die gleichen Beispiel-Sätze in gleicher Reihenfolge enthalten.
- Artikel und Plural am Sense überschreiben Lemma-Werte; bei abweichenden Sense-Werten ist der Lemma-Wert `null`.
- `tatoeba` verlangt eine `quelle_id`; bei `ki` ist `quelle_id` `null`.
- Bei Fehlern: Schritt 4 bis zu 2-mal wiederholen, danach betroffene Explanation auf `prueffliste` setzen.

---

## Schritt 6: KI-Gegenprüfung (optional während der manuellen Testphase)

**System:**
Du bist strenger Prüfer für Sprachlernmaterial. Du erfindest keine Fehler, aber du lässt keine durchgehen.
Antworte nur mit gültigem JSON.

**User:**
Prüfe die folgenden Einträge einzeln:
{lemma_json_liste_mit_erklaerungen}

Gib pro Eintrag ein Prüfergebnis zurück und ordne es über die Lemma-ID zu.

Prüfpunkte:
1. Stimmen Bedeutung und Hauptübersetzung?
2. Sind die DE- und EN-Erklärung inhaltlich deckungsgleich?
3. Passen Definition und Sätze zur Stufe?
4. Sind die Beispielsätze natürlich und korrekt?
5. Fehlt eine wichtige Alltagsbedeutung?

Ausgabe: JSON-Array mit genau einem Ergebnis je geprüftem Lemma: `{"lemma_id": "...", "pruef_score": 0.0, "probleme": [], "empfehlung": "freigeben"}`. `empfehlung` ist `freigeben`, `ueberarbeiten` oder `prueffliste`.

Regel: Score unter 0.85 geht in die Prüfliste, alles darüber wird automatisch `freigegeben`.
In dieser Testphase werden alle 200 Wörter von Hand geprüft; kein Eintrag gilt allein aufgrund eines KI-Prüfscores als freigegeben.


---

## Schritt 7: Sprachübergreifende Senses verknüpfen

Erst ausführen, wenn beide Sprachfassungen eines Testlaufs vorliegen. IDs über Bedeutung und Übersetzung abgleichen; nicht allein auf gleiche Schreibweise schließen. Ein Sense darf mehrere passende Gegen-Senses haben. Ausgabe der geprüften Einträge weiterhin als vollständiges JSON-Array.

Regeln:
- `verknuepfte_sense_ids` enthält alle passenden Senses in der anderen Sprache oder `[]`.
- Jede gesetzte Verknüpfung muss im Ziel-Sense auf den Ausgangs-Sense zurückverweisen.
- Keine passende Bedeutung bedeutet keine Verknüpfung. Erfinde keine Ziel-IDs.
- Unklare Zuordnungen in `qualitaet.hinweise` dokumentieren und zur manuellen Prüfung markieren.
