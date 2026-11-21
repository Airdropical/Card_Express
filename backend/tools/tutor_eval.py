"""Prüft den Tutor-Planer mit echten Gemini-Antworten.

Schickt jeden Prompt aus tests/tutor_prompts.json durch denselben Weg wie /api/agent-plan
(Erkennung fester Kartenwünsche, Planer-Prompt, Bereinigung) und prüft, ob die erwartete Aktion
mit sinnvollen Inhalten herauskommt. Datenbank und Tageslimits werden umgangen; es kostet also
echte Gemini-Anfragen (etwa 50 pro Lauf), zählt aber nicht gegen ein App-Konto.

Aufruf aus dem Ordner backend:
    GEMINI_API_KEY=... ../.venv/bin/python tools/tutor_eval.py
    GEMINI_API_KEY=... ../.venv/bin/python tools/tutor_eval.py --only Termin
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
# Optional: Schlüssel aus backend/.env (steht in .gitignore), damit er nicht im Terminal-Verlauf landet.
_local_env = pathlib.Path(__file__).resolve().parent.parent / ".env"
if _local_env.is_file():
    for _line in _local_env.read_text().splitlines():
        _name, _, _value = _line.partition("=")
        if _name.strip() in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GEMINI_MODEL", "GEMINI_FALLBACK_MODEL") and _value.strip():
            os.environ.setdefault(_name.strip(), _value.strip().strip('"').strip("'"))
os.environ.setdefault("DATABASE_URL", "postgresql+psycopg://eval:eval@localhost/eval")

import ai_client  # noqa: E402
import config  # noqa: E402
import server  # noqa: E402
from schemas import AgentPlanRequest  # noqa: E402

PROMPTS = pathlib.Path(__file__).resolve().parent.parent / "tests" / "tutor_prompts.json"
TODAY = dt.date.today()
# So sieht die App eines typischen Nutzers aus, auf den sich die Prompts beziehen.
CONTEXT = {
    "decks": ["Chemie Grundlagen", "Geschichte"],
    "vocabularyFolders": ["Englisch", "Englisch › Unit 3"],
    "termSubjects": ["Biologie (3)", "Jura (2)"],
    "calendarEntries": [f"{(TODAY + dt.timedelta(days=7)).isoformat()} · Chemie-Klausur"],
    "language": "German",
    "sourceLanguage": "Deutsch",
    "targetLanguage": "Englisch",
    "mode": "automatic",
    "today": TODAY.isoformat(),
}


def patient_call(parts, schema):
    """Wie call_gemini, wartet aber bei Ratenlimit (429/503) und versucht es erneut."""
    for wait in (15, 30, 60, 90, 0):
        try:
            return ai_client.call_gemini(parts, schema)
        except Exception as error:  # noqa: BLE001
            if str(getattr(error, "status_code", "")) not in ("502", "503") or not wait:
                raise
            print(f"  (Ratenlimit, warte {wait}s)", flush=True)
            time.sleep(wait)
    raise RuntimeError("unreachable")


def direct_ai(_request, _db, _account, parts, schema):
    response, _model = patient_call(parts, schema)
    return ai_client.parse_gemini_output(response)


def problems(action: dict, expected: list[str]) -> list[str]:
    """Inhaltliche Mindestanforderungen je Aktionstyp."""
    kind = action.get("type")
    found = []
    if kind in ("create_vocabulary_folder", "add_vocabulary"):
        entries = action.get("vocabularyEntries") or []
        if not entries:
            found.append("keine Vokabeln")
        if not action.get("folderName"):
            found.append("kein Ordnername")
        if "add_vocabulary" in expected and expected == ["add_vocabulary"] and not str(action.get("folderName", "")).startswith("Englisch"):
            found.append(f"falscher Ordner {action.get('folderName')!r}")
    if kind in ("create_deck_tree", "create_subdeck", "create_cards") and not action.get("cards"):
        found.append("keine Karten")
    if kind == "create_cards" and expected == ["create_cards"] and action.get("deckName") != "Chemie Grundlagen":
        found.append(f"falsches Deck {action.get('deckName')!r}")
    if kind == "create_calendar_entry":
        try:
            day = dt.date.fromisoformat(action.get("dateISO", ""))
            if day < TODAY:
                found.append(f"Datum in der Vergangenheit {day}")
        except ValueError:
            found.append(f"ungültiges Datum {action.get('dateISO')!r}")
    if kind in ("update_calendar_entry", "delete_calendar_entry") and action.get("title") != "Chemie-Klausur":
        found.append(f"falscher Termin {action.get('title')!r}")
    if kind == "update_calendar_entry" and not (action.get("newDateISO") or action.get("newTitle")):
        found.append("keine Änderung angegeben")
    if kind == "rename_deck" and (action.get("deckName") != "Chemie Grundlagen" or not action.get("newName")):
        found.append(f"Umbenennung unklar {action.get('deckName')!r} → {action.get('newName')!r}")
    if kind == "start_test" and action.get("deckName") != "Chemie Grundlagen":
        found.append(f"falsches Deck {action.get('deckName')!r}")
    if kind in ("create_term_subject", "add_terms"):
        if not action.get("subjectName"):
            found.append("kein Fach")
        if kind == "add_terms" and not action.get("termEntries"):
            found.append("keine Begriffe")
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="nur Funktionen, deren Name diesen Text enthält")
    args = parser.parse_args()
    if not config.GEMINI_API_KEY:
        print("GEMINI_API_KEY fehlt.")
        return 2
    server.execute_ai = direct_ai
    functions = [f for f in json.loads(PROMPTS.read_text())["functions"] if f["expect"] != ["chat"]]
    if args.only:
        functions = [f for f in functions if args.only.lower() in f["name"].lower()]

    report = [f"# Tutor-Test {dt.datetime.now():%Y-%m-%d %H:%M} · Modell {config.GEMINI_MODEL}\n"]
    passed = total = 0
    for function in functions:
        expected = function["expect"]
        report.append(f"\n## {function['name']} (erwartet: {' / '.join(expected)})\n")
        for prompt in function["prompts"]:
            total += 1
            try:
                plan = server.tutor_agent_plan(AgentPlanRequest(message=prompt, **CONTEXT), None, None, None)
            except Exception as error:  # noqa: BLE001 - jeder Fehler ist ein Befund
                plan, error_text = {"reply": "", "actions": []}, f"Fehler: {error}"
            else:
                error_text = ""
            actions = plan.get("actions") or []
            kinds = [action.get("type") for action in actions]
            issues = [error_text] if error_text else []
            # „Englisch + 8 Vokabeln Schule“ als neuer Unterordner in Englisch ist ebenfalls richtig.
            if expected == ["add_vocabulary"] and any(a.get("type") == "create_vocabulary_folder" and str(a.get("folderName", "")).startswith("Englisch ›") for a in actions):
                kinds = ["add_vocabulary" if k == "create_vocabulary_folder" else k for k in kinds]
            if re.search(r"\bich habe\b.*\b(?:erstellt|verschoben|entfernt|gelöscht|eingetragen|hinzugefügt|umbenannt|angelegt|vorbereitet)\b", str(plan.get("reply", "")), re.IGNORECASE):
                issues.append("Antwort klingt, als wäre schon etwas gespeichert")
            if not any(kind in expected for kind in kinds):
                issues.append(f"keine erwartete Aktion (bekommen: {kinds or 'keine'})")
            unexpected = [kind for kind in kinds if kind not in expected and kind not in ("create_deck", "create_term_subject", "create_vocabulary_folder")]
            if unexpected:
                issues.append(f"zusätzliche Aktionen {unexpected}")
            for action in actions:
                issues += problems(action, expected)
            ok = not issues
            passed += ok
            details = "; ".join(f"{a.get('type')}({', '.join(f'{k}={v!r}' for k, v in a.items() if k in ('deckName', 'folderName', 'subjectName', 'title', 'dateISO', 'newDateISO', 'newName', 'newTitle'))}, {len(a.get('cards') or a.get('vocabularyEntries') or a.get('termEntries') or [])} Einträge)" for a in actions)
            line = f"- {'✅' if ok else '❌'} „{prompt}“\n  - Aktionen: {details or '–'}\n  - Antwort: {str(plan.get('reply', ''))[:160]!r}"
            if issues:
                line += "\n  - Probleme: " + "; ".join(issues)
            report.append(line)
            print(("OK   " if ok else "FAIL ") + prompt + ("" if ok else "  → " + "; ".join(issues)), flush=True)
            time.sleep(0.5)
    report.insert(1, f"\n**Ergebnis: {passed}/{total} bestanden**\n")
    out = pathlib.Path("tutor_eval_report.md")
    out.write_text("\n".join(report), encoding="utf-8")
    print(f"\n{passed}/{total} bestanden · Bericht: {out.resolve()}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
