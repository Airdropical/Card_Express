# Word Express HTML-Vorschau

Eine statische Vorschau mit den 40 Wörtern aus Testlauf 3. Die Vorschau lädt `frontend/data/testlauf-03-ergebnisse.json` nach Schema-Version 1.1.

## Lokal starten

Vom Projektordner aus:

```sh
python3 -m http.server 8000 --bind 127.0.0.1
```

Dann `http://localhost:8000/frontend/` öffnen. Alternativ den Server im Ordner `frontend` starten und `http://localhost:8000/` aufrufen.

## Diagnose

Auf der Seite **Technische Diagnose** aufklappen. Dort stehen Seiten-URL, Datenpfad, HTTP-Status, Antworttyp und Anzahl geladener Einträge. Wenn `index.html` selbst 404 liefert, zeigt das Server-Terminal den angefragten Pfad.

## Zu prüfen

- Deutsch und Englisch als Lernsprache und Erklärungssprache
- Suche, Niveau-Filter, Wortnavigation und mehrdeutige Wörter
- sense-spezifischer Artikel und Plural (besonders „Band“, „Leiter“ und „See“)
- Übersetzungen, Beispiele, Erklärungen und Qualitätshinweise

Die Vorschau speichert keinen Lernfortschritt und ruft keine API auf.
