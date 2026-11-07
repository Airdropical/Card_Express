# Testlauf 03 – Protokoll

**Umfang:** 40 neue Lemmata (20 DE, 20 EN)  
**Schema:** 1.1  
**Erzeugt:** 2026-11-04  
**Modellkontext:** GPT-6 (Codex), keine API  
**Status:** Schema- und Regelprüfungen einschließlich der eingearbeiteten Review-Korrekturen bestanden; HTML-Vorschau aktualisiert.  
**Prompt-Version (SHA-256):** `d7bec93335c57457a6a0dd492f6e7bb0967c2a471ed4f31224c42496805f0ff3`

## Abdeckung

- 40 unterschiedliche Lemmata; keine Wiederholung aus Testlauf 1 oder 2.
- 54 Senses, davon 13 mehrdeutige Lemmata; 108 Explanations und 216 Beispielobjekte.
- B1/B2, fünf ausgewählte unregelmäßige deutsche Verben und vier englische, Adverbien und Präpositionen in beiden Sprachen.
- 1:n-Verknüpfung `de-erwerben-verb-1` ↔ `en-acquire-verb-1` und `en-obtain-verb-1`, mit Rückverweisen.
- Artikel-/Pluralwechsel bei Band, Leiter, See, Kiefer und Mutter.
- 46 Erklärungseinträge mit Merkhilfen und 16 Verwechslungshinweise, jeweils nur dort, wo sie beim Lernen helfen.

## Prüfungen

- Draft-2020-12: `ContentFile` und jedes `LemmaEntry` gültig; Schritt-4-Ausgabe durch `pipeline/assemble_step4.py` reproduziert.
- Projektregeln: 20/20-Sprachverteilung, eindeutige IDs, keine wiederholten Lemmata, vollständige Plurale, korrekte Artikel, Statussummen, gemeinsame Beispielsatzfolge und Satzlängen: bestanden.
- Verknüpfungen: aufgelöst, gegenseitig und sprachübergreifend; 1:n-Fall bestanden.
- Alle Beispielquellen sind ehrlich als `ki` markiert. Keine Tatoeba-Daten, IPA oder Frequenzränge verwendet, da keine geprüfte Rohquelle samt Lizenznachweis im Projekt lag.

## Arbeitsdateien

- `testlauf-03-eingabe.json`
- `testlauf-03-4a-beispiele.json` – Sätze einmal je Sense
- `testlauf-03-4b-erklaerungen.json` – Erklärungen je Sprache
- `testlauf-03-ergebnisse.json`
- `testlauf-03-protokoll.md`
- `../data/manifests/testlauf-03-manifest.json`

## Freigabe

Die gemeldeten Review-Punkte wurden korrigiert. Eine fachliche Freigabe der verbleibenden Inhalte bleibt beim Projektverantwortlichen.


### Nachprüfung nach fachlichem Review

- Artikel Kiefer korrigiert und Artikel-gegen-Beispielsatz als Review-Warnung ergänzt.
- „die See“ (Meer) hat laut Duden keinen Plural; `null` gesetzt.
- Übersetzungsalternativen stehen in der Zielsprache; `band` (Streifen) ist in Hauptübersetzung und Alternative getrennt.
- Gleiche englische Plurale auf Lemma-Ebene normalisiert.
- Merkhilfen für alle mehrdeutigen Testbegriffe ergänzt und präzisiert.
- „gegen/against“ in Kontakt und Gegnerschaft getrennt; `sleep` überarbeitet.
- Erneute Inhalts-, Coverage- und Profil-Schema-Prüfung bestanden.
