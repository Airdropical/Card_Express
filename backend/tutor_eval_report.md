# Tutor-Test 2026-11-21 20:26 · Modell gemini-3.5-flash-lite


**Ergebnis: 50/50 bestanden**


## Vokabeln: neuer Ordner (erwartet: create_vocabulary_folder / add_vocabulary)

- ✅ „Bitte erstelle mir einen neuen Vokabelordner zum Thema Reisen mit 10 Vokabeln.“
  - Aktionen: create_vocabulary_folder(folderName='Reisen', 10 Einträge)
  - Antwort: 'Ich schlage vor, einen neuen Vokabelordner zum Thema Reisen mit 10 passenden Vokabeln zu erstellen.'
- ✅ „mach mal vokabeln zum thema essen“
  - Aktionen: add_vocabulary(folderName='Englisch', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 Vokabeln zum Thema Essen in den Ordner Englisch hinzuzufügen.'
- ✅ „ich brauch vokablen für urlaub in spanien pls“
  - Aktionen: create_vocabulary_folder(folderName='Englisch › Urlaub in Spanien', 10 Einträge)
  - Antwort: 'Ich schlage vor, Vokabeln zum Thema Urlaub in Spanien hinzuzufügen.'
- ✅ „10 wörter wetter“
  - Aktionen: add_vocabulary(folderName='Englisch', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 Vokabeln zum Thema Wetter in den Ordner Englisch hinzuzufügen.'
- ✅ „Kannst du mir ein paar Vokabeln rund ums Einkaufen geben?“
  - Aktionen: add_vocabulary(folderName='Englisch', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 nützliche Vokabeln zum Thema Einkaufen für dich zu erstellen.'

## Vokabeln: zu bestehendem Ordner (erwartet: add_vocabulary)

- ✅ „Füge bitte 5 weitere Vokabeln zum Ordner Englisch hinzu.“
  - Aktionen: add_vocabulary(folderName='Englisch', 5 Einträge)
  - Antwort: "Ich schlage vor, 5 weitere Vokabeln zum Ordner 'Englisch' hinzuzufügen."
- ✅ „pack noch paar wörter in englisch rein“
  - Aktionen: add_vocabulary(folderName='Englisch', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 weitere nützliche Vokabeln zum Ordner Englisch hinzuzufügen.'
- ✅ „kanst du in meinen englisch ordner noch vokabeln zu sport tun“
  - Aktionen: add_vocabulary(folderName='Englisch', 10 Einträge)
  - Antwort: 'Ich schlage vor, Vokabeln zum Thema Sport in den Ordner Englisch hinzuzufügen.'
- ✅ „Englisch + 8 Vokabeln Schule“
  - Aktionen: add_vocabulary(folderName='Englisch', 8 Einträge)
  - Antwort: 'Ich schlage vor, 8 Vokabeln zum Thema Schule im Ordner Englisch hinzuzufügen.'
- ✅ „Mein Englisch-Ordner ist noch etwas leer, hast du noch Vokabeln zum Thema Familie dafür?“
  - Aktionen: add_vocabulary(folderName='Englisch', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 Vokabeln zum Thema Familie in deinen Englisch-Ordner hinzuzufügen.'

## Lernkarten: neues Deck (erwartet: create_deck / create_deck_tree / create_cards / create_subdeck)

- ✅ „Erstelle mir bitte ein neues Deck Photosynthese mit 8 Lernkarten.“
  - Aktionen: create_deck(deckName='Photosynthese', 0 Einträge); create_cards(deckName='Photosynthese', 8 Einträge)
  - Antwort: "Ich schlage vor, das neue Deck 'Photosynthese' mit 8 Lernkarten zu erstellen."
- ✅ „mach mir karteikarten zu den bundesländern“
  - Aktionen: create_deck(deckName='Bundesländer', 0 Einträge); create_cards(deckName='Bundesländer', 10 Einträge)
  - Antwort: 'Ich schlage vor, einen neuen Karteikarten-Stapel zum Thema "Bundesländer" mit 10 Karten zu erstellen.'
- ✅ „brauch lernkarten für bio zellatmung bis morgen“
  - Aktionen: create_cards(deckName='Biologie', 10 Einträge)
  - Antwort: 'Ich schlage vor, einen neuen Unterordner oder Lernkarten zum Thema Biologie - Zellatmung zu erstellen.'
- ✅ „Deck Französische Revolution, 10 Karten“
  - Aktionen: create_deck(deckName='Französische Revolution', 0 Einträge); create_cards(deckName='Französische Revolution', 10 Einträge)
  - Antwort: 'Ich schlage vor, einen neuen Karteikarten-Stapel namens "Französische Revolution" mit 10 passenden Karten zu erstellen.'
- ✅ „Könntest du mir Karteikarten zum Satz des Pythagoras machen?“
  - Aktionen: create_deck(deckName='Satz des Pythagoras', 0 Einträge); create_cards(deckName='Satz des Pythagoras', 10 Einträge)
  - Antwort: 'Ich schlage vor, einen neuen Karteikartenstapel zum Thema "Satz des Pythagoras" mit 10 passenden Karten zu erstellen.'

## Lernkarten: zu bestehendem Deck (erwartet: create_cards)

- ✅ „Bitte ergänze das Deck Chemie Grundlagen um 5 Karten zu Säuren und Basen.“
  - Aktionen: create_cards(deckName='Chemie Grundlagen', 5 Einträge)
  - Antwort: 'Ich schlage vor, 5 neue Karteikarten zum Thema Säuren und Basen in das Deck „Chemie Grundlagen“ einzufügen.'
- ✅ „pack noch 3 karten zu ionenbindung in chemie grundlagen“
  - Aktionen: create_cards(deckName='Chemie Grundlagen', 3 Einträge)
  - Antwort: "Ich schlage vor, 3 neue Karten zum Deck 'Chemie Grundlagen' hinzuzufügen."
- ✅ „kanst du bei chemie grundlagen noch karten zu redox hinzufügen“
  - Aktionen: create_cards(deckName='Chemie Grundlagen', 10 Einträge)
  - Antwort: "Ich schlage vor, dem Deck 'Chemie Grundlagen' neue Karten zum Thema Redox hinzuzufügen."
- ✅ „Chemie Grundlagen: +5 Karten Periodensystem“
  - Aktionen: create_cards(deckName='Chemie Grundlagen', 5 Einträge)
  - Antwort: 'Ich schlage vor, 5 weitere Karten zum Deck "Chemie Grundlagen" hinzuzufügen.'
- ✅ „In meinem Chemie-Deck fehlt noch was zu Molen, kannst du das ergänzen?“
  - Aktionen: create_cards(deckName='Chemie Grundlagen', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 Karteikarten zum Thema Molen in deinem Chemie-Grundlagen-Deck zu ergänzen.'

## Termin anlegen (erwartet: create_calendar_entry)

- ✅ „Bitte trage am 3. Dezember eine Mathe-Klausur in meinen Kalender ein.“
  - Aktionen: create_calendar_entry(title='Mathe-Klausur', dateISO='2026-12-03', 0 Einträge)
  - Antwort: 'Ich schlage vor, die Mathe-Klausur für den 3. Dezember 2026 in deinen Kalender einzutragen.'
- ✅ „hab nächsten freitag bio test“
  - Aktionen: create_calendar_entry(title='Bioteest', dateISO='2026-11-28', deckName='Geschichte', 0 Einträge)
  - Antwort: 'Ich schlage vor, einen Kalendereintrag für den Biotest am nächsten Freitag, den 28. November 2026, zu erstellen.'
- ✅ „schreib mir die englisch arbeit am 10.12 rein“
  - Aktionen: create_calendar_entry(title='Englisch-Arbeit', dateISO='2026-12-10', 0 Einträge)
  - Antwort: 'Ich schlage vor, die Englisch-Arbeit am 10. Dezember 2026 neu in den Kalender einzutragen.'
- ✅ „Deutsch Referat 15.12.“
  - Aktionen: create_calendar_entry(title='Deutsch Referat', dateISO='2026-12-15', 0 Einträge)
  - Antwort: 'Ich schlage vor, einen Kalendereintrag für das Referat am 15. Dezember 2026 zu erstellen.'
- ✅ „Kannst du dir merken, dass ich am Montag eine Physik-Prüfung habe?“
  - Aktionen: create_calendar_entry(title='Physik-Prüfung', dateISO='2026-11-23', 0 Einträge)
  - Antwort: 'Ich schlage vor, die Physik-Prüfung für den 23. November 2026 in deinen Kalender einzutragen.'

## Termin verschieben (erwartet: update_calendar_entry)

- ✅ „Bitte verschiebe die Chemie-Klausur auf den 5. Dezember.“
  - Aktionen: update_calendar_entry(title='Chemie-Klausur', newDateISO='2026-12-05', 0 Einträge)
  - Antwort: 'Ich schlage vor, die Chemie-Klausur auf den 5. Dezember 2026 zu verschieben.'
- ✅ „chemie klausur ist jetzt am 8.12“
  - Aktionen: update_calendar_entry(title='Chemie-Klausur', newDateISO='2026-12-08', 0 Einträge)
  - Antwort: 'Ich schlage vor, das Datum für die Chemie-Klausur auf den 8. Dezember 2026 zu aktualisieren.'
- ✅ „die chemi klausur wurde verlegt auf nächsten mittwoch, änder das mal“
  - Aktionen: update_calendar_entry(title='Chemie-Klausur', newDateISO='2026-11-25', 0 Einträge)
  - Antwort: 'Ich schlage vor, das Datum der Chemie-Klausur auf den 25. November 2026 zu aktualisieren.'
- ✅ „Chemie-Klausur → 12.12.“
  - Aktionen: update_calendar_entry(title='Chemie-Klausur', newDateISO='2026-12-12', 0 Einträge)
  - Antwort: 'Ich schlage vor, den Termin für die Chemie-Klausur auf den 12. Dezember 2026 zu verschieben.'
- ✅ „Kannst du die Chemie-Klausur eine Woche nach hinten schieben?“
  - Aktionen: update_calendar_entry(title='Chemie-Klausur', newDateISO='2026-12-05', 0 Einträge)
  - Antwort: 'Ich schlage vor, die Chemie-Klausur vom 28. November 2026 auf den 5. Dezember 2026 zu verschieben.'

## Termin löschen (erwartet: delete_calendar_entry)

- ✅ „Bitte lösche den Termin Chemie-Klausur aus meinem Kalender.“
  - Aktionen: delete_calendar_entry(title='Chemie-Klausur', 0 Einträge)
  - Antwort: 'Ich schlage vor, den Termin "Chemie-Klausur" aus Ihrem Kalender zu löschen.'
- ✅ „chemie klausur fällt aus, mach weg“
  - Aktionen: delete_calendar_entry(title='Chemie-Klausur', 0 Einträge)
  - Antwort: 'Ich schlage vor, den Kalendereintrag für die Chemie-Klausur zu löschen.'
- ✅ „lösch mal die chemie klausur raus is abgesagt“
  - Aktionen: delete_calendar_entry(title='Chemie-Klausur', 0 Einträge)
  - Antwort: 'Ich schlage vor, den Kalendereintrag für die Chemie-Klausur zu löschen.'
- ✅ „Chemie-Klausur entfernen“
  - Aktionen: delete_calendar_entry(title='Chemie-Klausur', 0 Einträge)
  - Antwort: "Ich schlage vor, den Kalendereintrag 'Chemie-Klausur' zu entfernen."
- ✅ „Die Chemie-Klausur findet nicht mehr statt, kannst du den Termin rausnehmen?“
  - Aktionen: delete_calendar_entry(title='Chemie-Klausur', 0 Einträge)
  - Antwort: 'Ich schlage vor, den Termin für die Chemie-Klausur zu löschen.'

## Deck umbenennen (erwartet: rename_deck)

- ✅ „Bitte benenne das Deck Chemie Grundlagen in Chemie Klasse 10 um.“
  - Aktionen: rename_deck(deckName='Chemie Grundlagen', newName='Chemie Klasse 10', 0 Einträge)
  - Antwort: 'Ich schlage vor, das Deck "Chemie Grundlagen" in "Chemie Klasse 10" umzubenennen.'
- ✅ „nenn chemie grundlagen um in chemie 10“
  - Aktionen: rename_deck(deckName='Chemie Grundlagen', newName='Chemie 10', 0 Einträge)
  - Antwort: "Ich schlage vor, das Deck 'Chemie Grundlagen' in 'Chemie 10' umzubenennen."
- ✅ „kanst du chemie grundlagen umbenenen zu anorganische chemie“
  - Aktionen: rename_deck(deckName='Chemie Grundlagen', newName='Anorganische Chemie', 0 Einträge)
  - Antwort: 'Ich schlage vor, das Deck „Chemie Grundlagen“ in „Anorganische Chemie“ umzubenennen.'
- ✅ „Chemie Grundlagen → Chemie Abi“
  - Aktionen: rename_deck(deckName='Chemie Grundlagen', newName='Chemie Abi', 0 Einträge)
  - Antwort: "Ich schlage vor, den Karteikarten-Stapel 'Chemie Grundlagen' in 'Chemie Abi' umzubenennen."
- ✅ „Mir gefällt der Name Chemie Grundlagen nicht mehr, kannst du das Deck Allgemeine Chemie nennen?“
  - Aktionen: rename_deck(deckName='Chemie Grundlagen', newName='Allgemeine Chemie', 0 Einträge)
  - Antwort: 'Ich schlage vor, das Deck "Chemie Grundlagen" in "Allgemeine Chemie" umzubenennen.'

## Abfragen / Test starten (erwartet: start_test)

- ✅ „Bitte frage mich das Deck Chemie Grundlagen ab.“
  - Aktionen: start_test(deckName='Chemie Grundlagen', 0 Einträge)
  - Antwort: 'Ich schlage vor, das Deck "Chemie Grundlagen" jetzt abzufragen.'
- ✅ „teste mich mal in chemie grundlagen“
  - Aktionen: start_test(deckName='Chemie Grundlagen', 0 Einträge)
  - Antwort: "Ich schlage vor, den Test für das Deck 'Chemie Grundlagen' jetzt zu starten."
- ✅ „frag mich chemie ab bitte bin unsicher“
  - Aktionen: start_test(deckName='Chemie Grundlagen', 0 Einträge)
  - Antwort: "Ich schlage vor, das Abfragen für das Deck 'Chemie Grundlagen' jetzt zu starten."
- ✅ „Test Chemie Grundlagen“
  - Aktionen: start_test(deckName='Chemie Grundlagen', 0 Einträge)
  - Antwort: "Ich schlage vor, einen Test für das Deck 'Chemie Grundlagen' zu starten."
- ✅ „Kannst du mich zu Chemie Grundlagen abfragen?“
  - Aktionen: start_test(deckName='Chemie Grundlagen', 0 Einträge)
  - Antwort: 'Ich schlage vor, den Test für das Deck Chemie Grundlagen jetzt zu starten.'

## Begriffe: Fach und Begriffe (erwartet: create_term_subject / add_terms)

- ✅ „Bitte lege das Fach Geschichte an und füge 10 Begriffe zur Weimarer Republik hinzu.“
  - Aktionen: create_term_subject(subjectName='Geschichte', 10 Einträge)
  - Antwort: 'Ich schlage vor, das Fach "Geschichte" mit 10 Begriffen zur Weimarer Republik anzulegen.'
- ✅ „mach mir begriffe für bio zur zelle“
  - Aktionen: add_terms(subjectName='Biologie', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 neue Begriffe zum Thema Biologie und Zelle hinzuzufügen.'
- ✅ „ich brauch fachbegriffe für jura vertragsrecht“
  - Aktionen: add_terms(subjectName='Jura', 10 Einträge)
  - Antwort: 'Ich schlage vor, 10 Fachbegriffe für Jura zum Thema Vertragsrecht hinzuzufügen.'
- ✅ „Begriffe Wirtschaft Marktformen“
  - Aktionen: create_term_subject(subjectName='Wirtschaft', 10 Einträge)
  - Antwort: 'Ich schlage vor, das neue Begriffsgebiet Wirtschaft mit 10 Einträgen zu den Marktformen zu erstellen.'
- ✅ „Kannst du in mein Fach Biologie noch ein paar Begriffe zur Genetik packen?“
  - Aktionen: add_terms(subjectName='Biologie', 10 Einträge)
  - Antwort: 'Ich schlage vor, dem Fach Biologie einige Begriffe zur Genetik hinzuzufügen.'