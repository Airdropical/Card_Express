"""Spielt Übungsgespräche mit dem Tutor durch, wie die App sie führt.

Je Modus (Alltagssituation, Vokabeln abfragen, Begriffe abfragen, Begriffe erklären, freier Chat)
gibt es 5 Lernende mit unterschiedlichem Schreibstil. Ein zweites Gemini spielt den Lernenden,
ein drittes bewertet das Gespräch nach festen Kriterien. Die Gespräche landen in
tutor_conversation_report.md, damit man sie auch selbst lesen kann.

Aufruf aus dem Ordner backend (Schlüssel wie bei tutor_eval.py):
    ../.venv/bin/python tools/tutor_conversation_eval.py [--only quiz] [--turns 3]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import tutor_eval  # noqa: E402,F401 - lädt den Schlüssel und die Umgebung

import ai_client  # noqa: E402
import ai_prompts  # noqa: E402
from agent_plan import requests_translation_help  # noqa: E402
from schemas import REPLY_SCHEMA  # noqa: E402

VOCABULARY = """pleased → erfreut
by the way → übrigens
husband → der Ehemann
wife → die Ehefrau
airport → der Flughafen
to introduce → vorstellen
married → verheiratet
interested → interessiert
manager → der Manager
tourist → der Tourist
excellent → ausgezeichnet
time zone → die Zeitzone"""
# Wie in der App: Deutsch → Englisch, Begriffe kommen als „term: definition“.
VOCAB_CONTEXT = "Aktives Sprachpaar: Deutsch → Englisch. Ausgewählter Ordner: Englisch › Unit 1.\nVokabeln des ausgewählten Bereichs:\n" + "\n".join(
    f"{line.split(' → ')[1]} → {line.split(' → ')[0]}" for line in VOCABULARY.splitlines()
)
TERM_CONTEXT = """Fach: Biologie
Begriffe des Lernenden:
- Mitochondrium: Zellorganell, das durch Zellatmung Energie in Form von ATP bereitstellt.
- Osmose: Diffusion von Wasser durch eine halbdurchlässige Membran zur Seite mit höherer Teilchenkonzentration.
- Enzym: Protein, das als Biokatalysator chemische Reaktionen beschleunigt, ohne verbraucht zu werden.
- Fotosynthese: Aufbau von Glucose aus Kohlenstoffdioxid und Wasser mit Lichtenergie, dabei entsteht Sauerstoff.
- Chromosom: Aufgewickelter DNA-Strang, der die Erbinformation trägt."""
CHAT_CONTEXT = """Heute ist {today}.
Anstehende Termine:
- {exam}: Chemie-Klausur (Deck: Chemie Grundlagen)
Decks (Karten gesamt / heute fällig / schwer):
- Chemie Grundlagen: 24 / 6 / 3
- Geschichte: 12 / 0 / 1
Schwere Karten:
- Chemie Grundlagen: Was ist eine Redoxreaktion?
""" + VOCAB_CONTEXT

MODES = {
    "conversation": {
        "title": "Alltagssituation (Rollenspiel)",
        "start": "Lass uns eine kurze Alltagssituation auf Englisch üben. Nutze Vokabeln aus meinem ausgewählten Ordner. Stelle mir nur eine Frage auf einmal und warte auf meine Antwort.",
        "context": VOCAB_CONTEXT,
        "rubric": "Rollenspiel auf Englisch, eine Frage pro Zug, nutzt Vokabeln aus der Liste, korrigiert echte Fehler kurz mit Erklärung auf Deutsch und lässt üben, übertreibt nicht bei Kleinigkeiten, hilft bei Bitte um Übersetzung, bleibt freundlich und im Szenario.",
        "learners": [
            "antwortet in gutem, vollständigem Englisch",
            "schreibt Englisch klein, ohne Satzzeichen, mit Grammatikfehlern (z. B. 'i am work at airport')",
            "versteht die Frage nicht und fragt auf Deutsch 'was heißt das?' oder 'kannst du das übersetzen'",
            "antwortet nur mit einzelnen Wörtern",
            "antwortet auf Deutsch statt auf Englisch",
        ],
    },
    "quiz": {
        "title": "Vokabeln abfragen",
        "start": "Prüfe mich mit den Vokabeln aus meinem ausgewählten Ordner von Deutsch nach Englisch. Zeige immer nur ein Wort, verrate die Übersetzung nicht vor meiner Antwort und gib danach kurzes Feedback.",
        "context": VOCAB_CONTEXT,
        "rubric": "Fragt genau ein deutsches Wort aus der Liste, verrät die Lösung nicht vorher, bewertet die Antwort richtig (Tippfehler und Synonyme fair, Falsches klar als falsch), nennt die Lösung bei Fehlern, fragt danach ein neues Wort, wiederholt keins, erfindet keine Wörter.",
        "learners": [
            "antwortet immer richtig",
            "antwortet richtig, aber mit kleinen Tippfehlern und klein geschrieben",
            "antwortet meistens falsch",
            "schreibt 'keine ahnung' oder '?'",
            "antwortet mit Synonymen statt dem Listenwort (z. B. glad statt pleased)",
        ],
    },
    "terms_quiz": {
        "title": "Begriffe abfragen",
        "start": "Frag mich die Begriffe aus Biologie ab. Immer nur einen Begriff, verrate die Erklärung nicht vor meiner Antwort und gib danach kurzes Feedback.",
        "context": TERM_CONTEXT,
        "rubric": "Fragt genau einen Begriff aus der Liste, verrät die Erklärung nicht vorher, akzeptiert sinngemäße Antworten in eigenen Worten, korrigiert falsche oder unvollständige Antworten mit der richtigen Erklärung, fragt danach einen neuen Begriff, erfindet keine Begriffe.",
        "learners": [
            "antwortet fachlich richtig und ausführlich",
            "antwortet richtig, aber sehr umgangssprachlich und kurz ('das ding wo energie macht')",
            "antwortet falsch",
            "sagt 'weiß nicht'",
            "antwortet halb richtig, ein wichtiger Teil fehlt",
        ],
    },
    "terms_explain": {
        "title": "Begriffe erklären",
        "start": "Erkläre mir die Begriffe aus Biologie in einfacher Sprache. Fang mit einem wichtigen Begriff an und frag danach, welchen ich als Nächstes verstehen möchte.",
        "context": TERM_CONTEXT,
        "rubric": "Erklärt in einfacher Sprache mit Alltagsbeispiel, kurz, fachlich korrekt, nutzt die gespeicherten Definitionen, sagt bei Begriffen außerhalb der Liste, dass sie nicht im Glossar sind, und erklärt sie trotzdem, geht auf Nachfragen ein.",
        "learners": [
            "fragt nach dem nächsten Begriff ('und osmose?')",
            "sagt 'versteh ich nicht, noch einfacher bitte'",
            "fragt nach einem Begriff, der nicht in der Liste ist (z. B. 'was ist ein ribosom')",
            "fragt nach einem Beispiel aus dem Alltag",
            "schreibt förmlich und stellt eine anspruchsvolle Vertiefungsfrage",
        ],
    },
    "chat": {
        "title": "Freier Chat",
        "start": None,
        "context": CHAT_CONTEXT,
        "rubric": "Antwortet auf Deutsch, korrekt und knapp, nutzt den Lernstand (Termine, schwere Karten) wo passend, erfindet keine Daten, bleibt beim Lernen, behauptet nie, etwas in der App gespeichert oder geändert zu haben.",
        "learners": [
            "fragt, wann die nächste Klausur ist und was er dafür lernen soll",
            "fragt locker 'was soll ich heute lernen'",
            "lässt sich ein Schulthema erklären (z. B. Redoxreaktion) und fragt nach",
            "schreibt auf Englisch",
            "fragt etwas, das nichts mit Lernen zu tun hat",
        ],
    },
}


def gemini(prompt: str) -> str:
    response, _ = tutor_eval.patient_call([{"text": prompt}], REPLY_SCHEMA)
    return str(ai_client.parse_gemini_output(response).get("reply", ""))


def tutor_turn(mode: str, context: str, history: list[tuple[str, str]], message: str) -> str:
    transcript = "\n".join(("Tutor" if role == "assistant" else "Learner") + ": " + text for role, text in history[-10:])
    prompt = ai_prompts.tutor_conversation(
        mode, "German", "Deutsch", "Englisch",
        "Lern-Tutor für Schule und Uni" if mode == "chat" else "Begriffe-Tutor" if mode.startswith("terms") else "Vokabel-Tutor",
        context, transcript, message,
        requests_translation_help(message, "Deutsch"),
    )
    return gemini(prompt)


def learner_turn(persona: str, history: list[tuple[str, str]], first: bool) -> str:
    transcript = "\n".join(("Tutor" if role == "assistant" else "Du") + ": " + text for role, text in history[-8:])
    task = "Schreibe deine erste Nachricht an den Tutor." if first else "Antworte auf die letzte Nachricht des Tutors."
    return gemini(
        "Du spielst einen Schüler, der eine Lern-App benutzt. Dein Verhalten: " + persona + ". "
        "Schreib kurz und natürlich wie ein echter Schüler am Handy, nie wie eine KI. " + task + "\n" + transcript
    )


def judge(title: str, rubric: str, history: list[tuple[str, str]]) -> dict:
    transcript = "\n".join(("Tutor" if role == "assistant" else "Lernender") + ": " + text for role, text in history)
    response, _ = tutor_eval.patient_call([{"text": (
        "Bewerte streng, ob der Tutor in diesem Übungsgespräch (" + title + ") alles richtig macht. Kriterien: " + rubric +
        " Nenne konkrete Fehler mit Zitat. pass ist nur true, wenn kein Kriterium verletzt ist.\n" + transcript
    )}], {"type": "OBJECT", "properties": {"pass": {"type": "BOOLEAN"}, "issues": {"type": "ARRAY", "items": {"type": "STRING"}}}, "required": ["pass", "issues"]})
    return ai_client.parse_gemini_output(response)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--turns", type=int, default=3)
    args = parser.parse_args()
    today = dt.date.today()
    report = [f"# Gesprächstest {dt.datetime.now():%Y-%m-%d %H:%M}\n"]
    learner_messages: list[str] = []
    passed = total = 0
    for mode, spec in MODES.items():
        if args.only and args.only not in mode:
            continue
        context = spec["context"].format(today=today.isoformat(), exam=(today + dt.timedelta(days=7)).isoformat())
        report.append(f"\n## {spec['title']} (`{mode}`)\n")
        for persona in spec["learners"]:
            total += 1
            history: list[tuple[str, str]] = []
            try:
                first = spec["start"] or learner_turn(persona, history, first=True)
                if not spec["start"]:
                    learner_messages.append(first)
                history.append(("user", first))
                history.append(("assistant", tutor_turn(mode, context, history[:-1], first)))
                for _ in range(args.turns):
                    message = learner_turn(persona, history, first=False)
                    learner_messages.append(message)
                    history.append(("user", message))
                    history.append(("assistant", tutor_turn(mode, context, history[:-1], message)))
                verdict = judge(spec["title"], spec["rubric"], history)
            except Exception as error:  # noqa: BLE001 - Netzwerkfehler sollen nicht den ganzen Lauf beenden
                verdict = {"pass": False, "issues": [f"Abgebrochen: {error}"]}
            passed += bool(verdict.get("pass"))
            print(("OK   " if verdict.get("pass") else "FAIL ") + f"{mode}: {persona}" + ("" if verdict.get("pass") else "  → " + " | ".join(verdict.get("issues", []))[:300]), flush=True)
            report.append(f"### {'✅' if verdict.get('pass') else '❌'} Lernender: {persona}\n")
            report += [f"- **{'Tutor' if role == 'assistant' else 'Lernender'}:** {text}" for role, text in history]
            if verdict.get("issues"):
                report.append("\n> Bewertung: " + " · ".join(verdict["issues"]))
            report.append("")
            pathlib.Path("tutor_conversation_report.md").write_text("\n".join(report), encoding="utf-8")
    report.insert(1, f"\n**Ergebnis: {passed}/{total} Gespräche ohne Befund**\n")
    pathlib.Path("tutor_conversation_report.md").write_text("\n".join(report), encoding="utf-8")
    pathlib.Path("tutor_learner_messages.json").write_text(json.dumps(learner_messages, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\n{passed}/{total} ohne Befund · Bericht: tutor_conversation_report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
