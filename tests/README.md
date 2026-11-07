# Testläufe

Testläufe verwenden das Inhaltsschema in `data/` (Version 1.1). Nutzerdaten validieren gegen `data/user-profile.schema.json` (Profilversion 1.0). Zum Prüfen einmal `python3 -m pip install -r requirements-dev.txt` ausführen. Eingabe und Ausgabe sind jeweils Listen mit 40 Lemma-Einträgen.

Prüfung eines Laufs:

```sh
python3 tests/validate_content_file.py data/content-file.schema.json data/schema.json data/testlauf/testlauf-03-ergebnisse.json
python3 tests/check_testlauf_v1_1.py data/schema.json tests/testlauf-03-eingabe.json tests/testlauf-03-ergebnisse.json
python3 tests/check_testlauf_03.py
python3 tests/validate_json_schema.py data/manifest.schema.json data/manifests/testlauf-03-manifest.json
python3 tests/validate_user_profile.py data/user-profile.schema.json data/user-profile.example.json data/testlauf/testlauf-03-ergebnisse.json
```

`validate_user_profile.py` prüft zusätzlich IDs, Ordnerverweise/-zyklen, doppelte Status, Tagesdaten und den abgeleiteten Statistik-Cache. `check_testlauf_v1_1.py` prüft zusätzlich Eingabeabdeckung, 20/20 Sprachverteilung, Sense-Verknüpfungen, Artikel/Plural, Erklärungen, identische Beispielreihenfolge und Qualitätsstatus. Erkannte Artikelabweichungen in Beispielsätzen werden als `REVIEW WARNING` gemeldet, nicht als harter Fehler. `check_testlauf_03.py` prüft die gezielten Review-Korrekturen des dritten Laufs.
