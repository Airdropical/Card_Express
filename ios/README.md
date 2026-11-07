# Word Express iOS App

SwiftUI-Prototyp für iOS 17 und neuer. Öffne `WordExpress.xcodeproj` in Xcode und starte das Scheme **Word Express** auf einem iPhone-Simulator oder einem angeschlossenen Gerät.

## Enthalten

- Wortliste und Wortkarten aus Testlauf 3 (`Resources/testlauf-03-ergebnisse.json`)
- Lernsprache und Erklärungssprache getrennt wählbar
- Bedeutungswechsel, Übersetzungen, Merkhilfen, Beispielsätze und System-Sprachausgabe
- Favoriten, Hauptordner/Unterordner, Quiz-Kategorien und Schwierigkeitsgrad
- Quiz-Karteikarten mit lokaler Fortschritts- und Tagesstatistik
- Profil wird lokal als JSON-Datei in Application Support gespeichert; nach Anmeldung synchronisiert die App es über HTTPS mit der Railway-API und hält das Sitzungstoken im iOS-Schlüsselbund
- Light-/Dark-Mode mit Systemmaterialien, hellgrauen Karten und zurückhaltender Akzentfarbe

## Konten und Synchronisierung

Im Tab **Profil** kann die Serveradresse eingetragen und ein Konto erstellt oder verwendet werden. Kontenerstellung ist einladungsgeschützt; der Einladungscode wird als `REGISTRATION_INVITE_CODE` im Backend gesetzt. Änderungen bleiben offline lokal und können später synchronisiert werden. Profilrevisionen verhindern stilles Überschreiben eines neueren Cloud-Standes.

Lokale Entwicklung: Simulator und API müssen denselben Mac verwenden; Standardadresse ist `http://127.0.0.1:8080`. Auf einem iPhone nur die Railway-HTTPS-Adresse verwenden.

## Noch nicht enthalten

E-Mail-Verifikation, Passwort-Wiederherstellung, Push-Mitteilungen, StoreKit und Widgets sind nicht enthalten. Das Backend ist für private Nutzung mit Einladungscode ausgelegt.

## Build-Hinweis für diese Entwicklungsumgebung

Geräte- und Simulator-App wurden mit Xcode 27.2 erfolgreich kompiliert. Ein Simulator konnte hier nicht gestartet werden: CoreSimulator 1174.9.2 ist älter als die von Xcode erwartete Version 1174.21. Die Oberfläche muss nach Aktualisierung der lokalen Simulator-Komponenten visuell geprüft werden. Swift-Syntax, Wortdaten- und Profildekodierung wurden separat geprüft.
