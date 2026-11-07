# Testlauf 1 — 40 Lemmata

**Umfang:** 20 deutsche und 20 englische Lemmata. Verarbeitung in kleineren Prompt-Batches; für jedes Lemma wurden beide Erklärsprachen erstellt. Die manuelle Generierung erfolgte in ChatGPT.

## Prüfkriterien

- Jeder Eintrag ist valides JSON und erfüllt `schema.json`.
- Lemma- und Sense-IDs folgen der dokumentierten Konvention; IDs sind eindeutig.
- Wortart, Niveau, Bedeutungen, Übersetzungen, deutsche Artikel und Pluralangaben sind geprüft.
- Pro Sense gibt es genau eine Erklärung auf Deutsch und Englisch, jeweils auf Lemma-Niveau.
- Jedes Beispiel enthält das Lemma oder eine gebeugte Form; jede Erklärung hat 2–3 Beispiele.
- Bei A1/A2/B1 halten Definitionen und Beispiele die Längenvorgabe aus `prompts.md` ein.
- Bei gleicher Lern- und Erklärsprache ist die Beispielübersetzung `null`; bei verschiedenen Sprachen ist sie vorhanden und passend.
- Inhalt, Natürlichkeit und Übersetzungen wurden manuell gegengelesen. Unsicherheiten sind in `qualitaet.hinweise` erfasst.

## Ergebnis

- **Status: bestanden**
- **Geprüfte Lemmata: 40/40** (20 Deutsch, 20 Englisch)
- Schema- und Konsistenzprüfungen: bestanden; keine strukturellen Fehler.
- Manuelle Inhaltsprüfung: bestanden nach Überarbeitung der Mehrdeutigkeit von „Freund“, einer falschen englischen Definition bei „fahren“, einzelner unpassender Beispielsätze und der Längenvorgaben.
- Bei „Bank“ sind beide Pluralformen (`Banken`/`Bänke`) im Pluralfeld bedeutungsbezogen angegeben und zusätzlich in `qualitaet.hinweise` erklärt.
- Ergebnisse: `testlauf-01-ergebnisse.json`; Eingabeliste: `testlauf-01-eingabe.json`.

**API-Entscheidung:** noch offen. Sie wird erst nach fünf bestandenen Läufen getroffen.

**Modell-Metadaten:** Die ursprüngliche Oberfläche wurde als ChatGPT dokumentiert, eine genaue Modell-ID ist rückwirkend nicht mehr feststellbar. Sie wurde nicht nachträglich geraten. Die v1.1-Migration und heutige Draft-2020-12-Prüfung bestehen.
