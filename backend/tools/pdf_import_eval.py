"""Prüft die Vokabel-Übernahme aus einer PDF so, wie die App sie ablaufen lässt.

Die App teilt das Dokument an Zeilengrenzen in Stücke (wie AssistantChatView.documentParts)
und fragt jedes Stück einzeln ab. Verglichen wird mit der PDF selbst:
Jede Tabellenzeile beginnt mit dem englischen Wort, danach folgt das deutsche.

Aufruf aus dem Ordner backend, mit dem PDF-Text als Datei (per PDFKit extrahiert, Seiten mit Seitenvorschub getrennt):
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

PART_CHARACTERS, PART_LINES, MAX_PARTS, MAX_PAGE_CHARACTERS = 1_100, 26, 20, 2_400  # wie in der App
SOURCE, TARGET = "Deutsch", "Englisch"
MESSAGE = "Übernimm alle Vokabeln aus der PDF in einen neuen Ordner Englisch Units 1-8."


def document_parts(text: str) -> list[str]:
    """Wie AssistantChatView.documentParts: ganze Seiten (Seitenvorschub), kurze zusammengelegt, lange an Zeilen geteilt."""
    pages = [page.strip("\n") for page in text.split("\f") if page.strip()]
    units: list[str] = []
    for page in pages:
        units += [page] if len(page) <= MAX_PAGE_CHARACTERS else line_chunks(page)
    target = max(PART_CHARACTERS, len(text) // MAX_PARTS + 1)
    parts: list[str] = []
    for unit in units:
        if parts and len(parts[-1]) + len(unit) + 1 <= target:
            parts[-1] += "\n" + unit
        else:
            parts.append(unit)
    return parts


def line_chunks(text: str) -> list[str]:
    parts, current, count = [], "", 0
    for line in text.split("\n"):
        if current and (len(current) + len(line) + 1 > PART_CHARACTERS or count >= PART_LINES):
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


def plan(message: str, document: str, name: str, exclude: list[str] | None = None) -> list[dict]:
    body = AgentPlanRequest(message=message, documentText=document, documentName=name, sourceLanguage=SOURCE, targetLanguage=TARGET,
                            vocabularyFolders=[], decks=[], language="German", mode="automatic", excludeTerms=exclude or [])
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
        note = f"\n(Teil {index + 1} von {len(parts)} des angehängten Dokuments. Übernimm alle Vokabeln aus diesem Teil und wende meine Anweisungen (Filter, Zielordner) auch auf diesen Teil an. term ist immer {SOURCE}, translation immer {TARGET}, auch wenn die Tabelle andersherum aufgebaut ist.)"
        try:
            entries = plan(MESSAGE[:1300] + note, part, f"Vokabeln.pdf ({index + 1}/{len(parts)})")
            # Wie die App: deutlich weniger Einträge als Zeilen → einmal mit Ausschlussliste nachfragen.
            lines = len([line for line in part.split("\n") if len(line.strip()) > 1])
            if len(entries) >= 5 and len(entries) < (lines - 3) * 0.85:
                more = plan(MESSAGE[:1300] + note, part, f"Vokabeln.pdf ({index + 1}/{len(parts)})", [f"{e['term']} → {e['translation']}" for e in entries])
                print(f"  Teil {index + 1}: Nachfrage ({len(entries)} von ~{lines - 3}) brachte {len(more)}")
                entries += more
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
