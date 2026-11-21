"""Prüft die Vokabel-Übernahme aus einer PDF so, wie die App sie ablaufen lässt.

Die App teilt das Dokument an Zeilengrenzen in Stücke (wie AssistantChatView.documentParts)
und fragt jedes Stück einzeln ab. Verglichen wird mit der PDF selbst:
Jede Tabellenzeile beginnt mit dem englischen Wort, danach folgt das deutsche.

Aufruf aus dem Ordner backend, mit dem PDF-Text als Datei (z. B. per PDFKit extrahiert):
    ../.venv/bin/python tools/pdf_import_eval.py text.txt
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import tutor_eval  # noqa: E402,F401 - lädt den Schlüssel und die Umgebung

import server  # noqa: E402
from schemas import AgentPlanRequest  # noqa: E402

PART_CHARACTERS, PART_LINES, MAX_PARTS = 1_100, 26, 20  # wie in der App
SOURCE, TARGET = "Deutsch", "Englisch"
MESSAGE = "Übernimm alle Vokabeln aus der PDF in einen neuen Ordner Englisch Units 1-8."


def document_parts(text: str) -> list[str]:
    lines = text.split("\n")
    size = max(PART_CHARACTERS, len(text) // MAX_PARTS + 1)
    max_lines = max(PART_LINES, len(lines) // MAX_PARTS + 1)
    parts, current, count = [], "", 0
    for line in lines:
        if current and (len(current) + len(line) + 1 > size or count >= max_lines):
            parts.append(current)
            current, count = "", 0
        current += ("\n" if current else "") + line
        count += 1
    if current.strip():
        parts.append(current)
    return parts


def table_rows(text: str) -> list[str]:
    rows, in_table = [], False
    for line in text.split("\n"):
        if line.startswith("English Deutsch"):
            in_table = True
            continue
        if line.startswith(("Unit ", "Vokabelliste")):
            continue
        if in_table and line.strip():
            rows.append(line.strip())
    return rows


def strip_article(word: str) -> str:
    return re.sub(r"^(der|die|das)\s+", "", word.strip(), flags=re.IGNORECASE).split(",")[0].strip().lower()


def plan(message: str, document: str, name: str) -> list[dict]:
    body = AgentPlanRequest(message=message, documentText=document, documentName=name, sourceLanguage=SOURCE, targetLanguage=TARGET,
                            vocabularyFolders=[], decks=[], language="German", mode="automatic")
    result = server.tutor_agent_plan(body, None, None, None)
    return [entry for action in result["actions"] if action.get("type") in ("create_vocabulary_folder", "add_vocabulary") for entry in action.get("vocabularyEntries") or []]


def main() -> int:
    server.execute_ai = tutor_eval.direct_ai
    text = pathlib.Path(sys.argv[1]).read_text()
    rows = table_rows(text)
    parts = document_parts(text)
    print(f"{len(rows)} Tabellenzeilen, {len(parts)} Teile")
    # Wie die App seit dem Umbau: Die erste Anfrage bekommt schon nur Teil 1, nicht das ganze Dokument.
    collected, seen = [], set()
    for index, part in enumerate(parts):
        note = f"\n(Teil {index + 1} von {len(parts)} des angehängten Dokuments. Übernimm alle Vokabeln aus diesem Teil. term ist immer {SOURCE}, translation immer {TARGET}, auch wenn die Tabelle andersherum aufgebaut ist.)"
        try:
            entries = plan(MESSAGE[:1300] + note, part, f"Vokabeln.pdf ({index + 1}/{len(parts)})")
        except Exception as error:  # noqa: BLE001
            print(f"  Teil {index + 1}: Fehler {error}")
            continue
        fresh = [e for e in entries if (e["term"].lower(), e["translation"].lower()) not in seen]
        seen |= {(e["term"].lower(), e["translation"].lower()) for e in fresh}
        collected += fresh
        print(f"  Teil {index + 1}: {len(entries)} Einträge")

    covered, correct, swapped, unknown = set(), [], [], []
    for entry in collected:
        term, translation = entry["term"].strip(), entry["translation"].strip()
        hit = next((i for i, row in enumerate(rows) if row.lower().startswith(translation.lower() + " ") and strip_article(term) in row.lower()), None)
        if hit is not None:
            covered.add(hit)
            correct.append(entry)
            continue
        hit = next((i for i, row in enumerate(rows) if row.lower().startswith(term.lower() + " ") and strip_article(translation) in row.lower()), None)
        if hit is not None:
            covered.add(hit)
            swapped.append(entry)
        else:
            unknown.append(entry)
    missing = [rows[i] for i in range(len(rows)) if i not in covered]
    missing_ipa = sum(1 for entry in collected if not str(entry.get("pronunciation", "")).strip())
    print(f"\nGesammelt: {len(collected)} · abgedeckte Zeilen: {len(covered)}/{len(rows)} · Richtung richtig: {len(correct)} · vertauscht: {len(swapped)} · nicht zuzuordnen: {len(unknown)} · ohne Lautschrift: {missing_ipa}")
    print("Vertauscht (Beispiele):", json.dumps([(e['term'], e['translation']) for e in swapped[:8]], ensure_ascii=False))
    print("Nicht zuzuordnen (Beispiele):", json.dumps([(e['term'], e['translation']) for e in unknown[:12]], ensure_ascii=False))
    print("Fehlende Zeilen:", json.dumps(missing[:40], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
