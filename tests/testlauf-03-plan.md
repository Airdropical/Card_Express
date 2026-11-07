# Testlauf 03 – Plan und Abdeckung

## Ziel

Schema 1.1 mit echten Grenzfällen erproben: mehrdeutige Lemmata, wechselnde Artikel/Pluralformen, unregelmäßige Formen, bidirektionale 1:n-Verknüpfungen, Niveau B1/B2 sowie Adverbien und Präpositionen.

## Umfang

40 neue Lemmata (20 DE, 20 EN), keine Dopplung in Sprache + Lemma + Wortart gegenüber Testlauf 01/02.

| Deutsch | Englisch |
|---|---|
| Band, Leiter, See, Kiefer, Mutter | bark, crane, match, seal, band |
| werfen, schlafen, geben, behalten, ziehen, erwerben | throw, sleep, give, keep, acquire, obtain |
| öffentlich, seltsam, dünn, sauer | public, strange, thin, sour |
| oft, kaum | often, barely |
| während, gegen, ohne | during, against, without |

Erwartet: 54 Senses, 13 mehrdeutige Lemmata, mindestens ein B2-Eintrag, Adverbien und Präpositionen in beiden Sprachen. `erwerben` wird mit zwei englischen Senses verknüpft (`acquire`, `obtain`), Rückverweise werden geprüft.

## Regeln

- Sätze werden einmal je Sense in Schritt 4a erstellt, dann unverändert in alle Erklärungen kopiert.
- Erklärung und Wortübersetzung sind getrennte Felder. Übersetzung ist das tatsächliche Wort in der anderen Sprache.
- Plurale müssen vollständig ausgeschrieben und bei identischen Homographen am Lemma normalisiert sein; sprachlich belegte plural-lose Nomen und nicht zählbare englische Nomen verwenden `null`.
- Übersetzungsalternativen stehen in der Zielsprache; Synonyme werden aus `text` in `alternativen` aufgeteilt. Artikelwidersprüche zwischen Eintrag und Beispielen werden als Review-Hinweis behandelt.
- Merkhilfen zu mehrdeutigen Bedeutungen müssen korrekt und unterscheidend sein; unterschiedliche Präpositionsfunktionen bekommen getrennte Senses.
- Definitionen benennen ein unterscheidendes Merkmal. Merkhilfen/Verwechslungen nur bei echtem Lernwert.
- Irrreguläre Beispiel-Formen werden gegen einen kuratierten Testformenbestand geprüft. Ein allgemeiner spaCy-Lemmatizer bleibt Voraussetzung für die große Pipeline.
- Keine Tatoeba-, IPA- oder Frequenzdaten ohne verifizierte Rohquelle und Lizenzmetadaten; daher bleiben diese Felder leer und Beispiele `ki`.

## Prüfung

1. JSON-Datei gegen Draft 2020-12 `ContentFile`- und `LemmaEntry`-Schemas.
2. Eingabeabdeckung, 20/20-Verteilung und keine Wiederholungen über die ersten drei Läufe.
3. IDs, Artikel/Plural, vollständige Pluralformen, Qualitätssummen, Beispielsatz-Gleichheit, Stufenlängen.
4. Sense-Links vorhanden, gegenseitig und sprachübergreifend; speziell `erwerben` → zwei Zielsenses.
5. HTML-Vorschau auf mehreren Bedeutungen, Übersetzungen und Sense-Artikeln prüfen.
