# Testlauf 02 – Protokoll

**Umfang:** 40 Lemmata insgesamt (20 Deutsch, 20 Englisch)  
**Schema:** 1.1  
**Erzeugt:** 2026-11-04  
**Modellkontext:** GPT-6 (Codex); keine API  
**Status:** Strukturprüfung bestanden; abschließende Inhalts- und HTML-Abnahme durch den Projektverantwortlichen steht aus.

## Prüfungen

- 40 Eingabe-Lemmata und 40 Ausgabeeinträge, davon je 20 `de` und `en`.
- JSON-Schema-Prüfung: bestanden mit `jsonschema` Draft 2020-12.
- Projektregeln: IDs, Anzahl und Zuordnung der Erklärungen, Artikel/Plural, Beispiele, Niveaugrenzen sowie wechselseitige Sense-Verknüpfungen: bestanden.
- Sense-spezifische Formen demonstriert mit „Schild“: `das Schild / Schilder` und `der Schild / Schilde`.
- Inhaltliche Sichtprüfung der Definitionen und Beispielsätze durchgeführt; App-Anzeige bitte noch auf Desktop und Mobilgerät durchsehen.

## Ergebnisdateien

- `testlauf-02-eingabe.json`
- `testlauf-02-ergebnisse.json`
- `testlauf-02-protokoll.md`
- `../data/manifests/testlauf-02-manifest.json`

## Freigabe

Noch nicht endgültig freigegeben. Der Lauf wird erst nach Sichtprüfung der HTML-Seite und Bestätigung der Inhalte als bestanden markiert.

## Nach der ersten HTML-Sichtprüfung

- Wortübersetzung wird jetzt unabhängig von der Erklärsprache angezeigt.
- Definitionen wurden präzisiert: Sie nennen unterscheidende Merkmale statt nur eine breite Oberkategorie (z. B. Apfelbaum und Kerngehäuse/Kerne beim Apfel).
- Der Sense-Wechsel bei „Schild“ zeigt weiterhin den passenden Artikel und Plural.
- Maschinenprüfungen nach diesen Überarbeitungen erneut bestanden.
- Die Übersetzungsfelder enthalten jetzt die tatsächlichen Wortentsprechungen (z. B. `Apfel` ↔ `apple`); Bedeutungs-Kurzbeschreibungen bleiben getrennt.

- Englische Plurale korrigiert: volle Wortformen; `water` und `work` stehen als nicht zählbare Nomen mit `plural: null`.
