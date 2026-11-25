from datetime import date, datetime, timedelta, timezone

import pytest

import agent_plan
import ai_client
import ai_prompts
import apns
import config
import daily_tests

TODAY = date(2026, 11, 14)


def card(index, **stats):
    return {"question": f"Q{index}", "answer": f"A{index}", **stats}


def swift(day):
    return datetime(day.year, day.month, day.day, 12, tzinfo=timezone.utc).timestamp() - daily_tests.SWIFT_REFERENCE_EPOCH


@pytest.mark.parametrize("lapses, hard, last, expected", [
    (0, 0, None, False),
    (0, 0, "good", False),
    (0, 0, "wrong", True),
    (0, 0, "hard", True),
    (1, 0, "good", False),
    (1, 1, "easy", True),
    (2, 0, "good", True),
    (0, 3, "good", True),
])
def test_hard_card_rule(lapses, hard, last, expected):
    assert daily_tests.is_hard(lapses, hard, last) is expected


@pytest.mark.parametrize("offset, offered", [(-1, False), (0, True), (3, True), (4, False)])
def test_exam_test_is_offered_only_within_three_days(offset, offered):
    material, reason = daily_tests.exam_material([card(i) for i in range(6)], TODAY, TODAY + timedelta(days=offset))
    assert bool(material) is offered and bool(reason) is not offered


def test_exam_test_needs_a_date_and_enough_usable_cards():
    assert daily_tests.exam_material([card(i) for i in range(6)], TODAY, None)[0] == []
    few = [card(1), card(2), card(3), {"question": " ", "answer": "A"}]
    material, reason = daily_tests.exam_material(few, TODAY, TODAY)
    assert material == [] and "too few" in reason


def test_exam_material_puts_hard_cards_first_and_is_capped():
    cards = [card(i) for i in range(100)] + [card(999, lastRating="wrong")]
    material, _ = daily_tests.exam_material(cards, TODAY, TODAY)
    assert material[0]["question"] == "Q999" and len(material) == daily_tests.MAX_PROMPT_CARDS


def test_weak_test_needs_five_hard_cards():
    cards = [card(i, lastRating="wrong") for i in range(4)] + [card(i) for i in range(10, 30)]
    assert daily_tests.weak_material(cards)[0] == []
    material, _ = daily_tests.weak_material(cards + [card(99, lapses=2)])
    assert len(material) == 5 and all(daily_tests.is_hard(c.get("lapses", 0), 0, c.get("lastRating")) for c in material)


def test_question_count_is_bounded():
    assert daily_tests.question_count(4) == 4
    assert daily_tests.question_count(7) == 7
    assert daily_tests.question_count(60) == daily_tests.MAX_QUESTIONS


def snapshot(**overrides):
    deck = {"id": "D1", "name": "Bio", "cards": [card(i) for i in range(5)]}
    document = {"schemaVersion": 1, "decks": [deck], "vocabulary": [], "calendarEntries": []}
    document.update(overrides)
    return document


def test_snapshot_offers_exam_test_for_linked_entry_in_window():
    entry = {"id": "E1", "title": "Klausur", "date": swift(TODAY + timedelta(days=2)), "deckID": "D1"}
    assert daily_tests.snapshot_offers(snapshot(calendarEntries=[entry]), TODAY) == [{"kind": "exam", "title": "Klausur"}]


def test_snapshot_ignores_entries_without_deck_far_away_or_with_small_deck():
    far = {"title": "Später", "date": swift(TODAY + timedelta(days=9)), "deckID": "D1"}
    loose = {"title": "Ohne Deck", "date": swift(TODAY)}
    unknown = {"title": "Fremd", "date": swift(TODAY), "deckID": "missing"}
    assert daily_tests.snapshot_offers(snapshot(calendarEntries=[far, loose, unknown]), TODAY) == []
    small = snapshot(decks=[{"id": "D1", "name": "Bio", "cards": [card(1)]}], calendarEntries=[{"title": "K", "date": swift(TODAY), "deckID": "D1"}])
    assert daily_tests.snapshot_offers(small, TODAY) == []


def test_snapshot_counts_subdeck_cards_and_deck_exam_dates_once():
    parent = {"id": "D1", "name": "Bio", "cards": [card(1)], "examDate": swift(TODAY + timedelta(days=1))}
    child = {"id": "D2", "name": "Zellen", "parentID": "D1", "cards": [card(i) for i in range(2, 6)]}
    entry = {"title": "Bio-Klausur", "date": swift(TODAY + timedelta(days=1)), "deckID": "D1"}
    offers = daily_tests.snapshot_offers(snapshot(decks=[parent, child], calendarEntries=[entry]), TODAY)
    assert offers == [{"kind": "exam", "title": "Bio-Klausur"}]


def test_snapshot_offers_weak_test_from_hard_cards():
    deck = {"id": "D1", "name": "Bio", "cards": [card(i, lastRating="wrong") for i in range(5)]}
    assert daily_tests.snapshot_offers(snapshot(decks=[deck]), TODAY) == [{"kind": "weak", "title": ""}]


@pytest.mark.parametrize("document", [None, [], {"decks": "x"}, {"decks": [1, {"id": "D", "cards": "x"}], "calendarEntries": [3, {"date": "soon", "deckID": "D"}]}])
def test_snapshot_offers_tolerates_malformed_data(document):
    assert daily_tests.snapshot_offers(document, TODAY) == []


def test_day_parsing_and_plausibility():
    assert daily_tests.parse_day("2026-11-14") == TODAY
    assert daily_tests.parse_day("14.11.2026") is None
    now = datetime.now(timezone.utc).date()
    assert daily_tests.plausible_today(now) and daily_tests.plausible_today(now + timedelta(days=1))
    assert not daily_tests.plausible_today(now + timedelta(days=3))


def test_push_text_names_the_exam_and_follows_language():
    title, body = daily_tests.push_text([{"kind": "weak", "title": ""}, {"kind": "exam", "title": "Klausur"}], "de")
    assert "Klausur" in body and "Test" in title
    assert "difficult" in daily_tests.push_text([{"kind": "weak", "title": ""}], "en")[1]


def test_test_prompt_states_count_and_purpose():
    exam = ai_prompts.daily_test("exam", "Bio-Klausur", 8, "Q: a\nA: b")
    weak = ai_prompts.daily_test("weak", "", 5, "Q: a\nA: b")
    assert "exactly 8" in exam and "Bio-Klausur" in exam and "exactly 5" in weak and "difficult" in weak


def test_daily_limit_follows_the_plan(monkeypatch):
    monkeypatch.setattr(config, "AI_DAILY_REQUEST_LIMIT", 40)
    monkeypatch.setattr(config, "AI_DAILY_REQUEST_LIMIT_PLUS", 200)
    free, plus = type("A", (), {"plan": "free"})(), type("A", (), {"plan": "plus"})()
    assert ai_client.daily_limit_for(free) == 40 and ai_client.daily_limit_for(plus) == 200


def test_push_is_off_without_credentials_and_payload_shape(monkeypatch):
    monkeypatch.setattr(config, "APNS_KEY_ID", "")
    assert not apns.configured()
    assert apns.payload("T", "B", "exam") == {"aps": {"alert": {"title": "T", "body": "B"}, "sound": "default"}, "kind": "exam"}


def test_new_tutor_actions_need_their_fields():
    plan = {"reply": "ok", "actions": [
        {"type": "update_calendar_entry", "title": "Klausur", "newDateISO": "2026-12-01"},
        {"type": "update_calendar_entry", "title": "Ohne Änderung"},
        {"type": "delete_calendar_entry", "title": "Alt"},
        {"type": "delete_calendar_entry"},
        {"type": "rename_deck", "deckName": "Bio", "newName": "Biologie"},
        {"type": "rename_deck", "deckName": "Bio"},
        {"type": "start_test", "deckName": "Bio"},
        {"type": "start_test"},
    ]}
    kept = [action["type"] + ":" + (action.get("title") or action.get("deckName")) for action in agent_plan.sanitize_agent_plan(plan)["actions"]]
    assert kept == ["update_calendar_entry:Klausur", "delete_calendar_entry:Alt", "rename_deck:Bio", "start_test:Bio"]


def test_planning_prompt_carries_date_and_calendar():
    prompt = ai_prompts.agent_plan("German", "automatic", "German", "English", "Bio", "", "Verschiebe die Klausur", "2026-12-01 · Klausur", "2026-11-14")
    assert "Today is 2026-11-14" in prompt and "2026-12-01 · Klausur" in prompt and "update_calendar_entry" in prompt


def test_vocabulary_per_response_is_capped():
    entries = [{"term": f"t{i}", "translation": f"u{i}", "pronunciation": "/x/"} for i in range(90)]
    plan = {"reply": "ok", "actions": [{"type": "add_vocabulary", "folderName": "ENGS", "vocabularyEntries": entries}]}
    kept = agent_plan.sanitize_agent_plan(plan)["actions"][0]["vocabularyEntries"]
    assert len(kept) == agent_plan.VOCABULARY_PER_RESPONSE and kept[0]["term"] == "t0"


def test_planning_prompt_continues_after_extracted_terms():
    first = ai_prompts.agent_plan("German", "vocabulary", "German", "English", "", "ENGS", "Alle Vokabeln aus der PDF")
    later = ai_prompts.agent_plan("German", "vocabulary", "German", "English", "", "ENGS", "Alle Vokabeln aus der PDF", exclude_terms="husband\nwife")
    assert "copy the entries from the material" in first and "already taken over" not in first
    assert "already taken over" in later and "husband\nwife" in later


def test_term_actions_are_kept_only_when_complete():
    plan = {"reply": "ok", "actions": [
        {"type": "create_term_subject", "subjectName": "Biologie", "termEntries": [{"term": "Zelle", "definition": "Kleinste Einheit"}, {"term": "", "definition": "x"}]},
        {"type": "create_term_subject"},
        {"type": "add_terms", "subjectName": "Jura"},
        {"type": "add_terms", "subjectName": "Jura", "termEntries": [{"term": "Vertrag", "definition": "Zwei übereinstimmende Willenserklärungen"}]},
    ]}
    kept = agent_plan.sanitize_agent_plan(plan)["actions"]
    assert [(a["type"], a["subjectName"]) for a in kept] == [("create_term_subject", "Biologie"), ("add_terms", "Jura")]
    assert kept[0]["termEntries"] == [{"term": "Zelle", "definition": "Kleinste Einheit"}]


def test_tutor_has_glossary_modes_and_planner_knows_subjects():
    quiz = ai_prompts.tutor_conversation("terms_quiz", "German", "German", "English", "Biologie", "Zelle: Einheit", "", "Start")
    explain = ai_prompts.tutor_conversation("terms_explain", "German", "German", "English", "Biologie", "Zelle: Einheit", "", "Was ist eine Zelle?")
    assert "one term per turn" in quiz and "simple language" in explain
    plan = ai_prompts.agent_plan("German", "automatic", "German", "English", "", "", "Lege Fach Biologie an", term_subjects="Jura (3)")
    assert "create_term_subject" in plan and "Jura (3)" in plan


def test_calendar_title_falls_back_to_note():
    from agent_plan import drop_unknown_deck_actions, sanitize_agent_plan

    plan = sanitize_agent_plan({"reply": "", "actions": [
        {"type": "create_calendar_entry", "dateISO": "2026-12-03", "note": "Mathe-Klausur am 3. Dezember 2026 eingetragen."},
        {"type": "create_calendar_entry", "dateISO": "2026-12-04", "note": ""},
    ]})
    assert [action.get("title") for action in plan["actions"]] == ["Mathe-Klausur"]


def test_test_and_rename_need_an_existing_deck():
    from agent_plan import drop_unknown_deck_actions

    plan = {"reply": "", "actions": [
        {"type": "start_test", "deckName": "Biologie"},
        {"type": "start_test", "deckName": "chemie grundlagen"},
        {"type": "create_deck", "deckName": "Neu"},
        {"type": "rename_deck", "deckName": "Neu", "newName": "Neu 2"},
    ]}
    kept = drop_unknown_deck_actions(plan, ["Chemie Grundlagen"])["actions"]
    assert [action["type"] for action in kept] == ["start_test", "create_deck", "rename_deck"]


def test_translation_help_names_the_tutor_line_to_translate():
    from ai_prompts.conversation import last_tutor_line, tutor_conversation

    transcript = "Learner: hi\nTutor: Are you a tourist here?\nLearner: was heißt das?"
    assert last_tutor_line(transcript) == "Are you a tourist here?"
    prompt = tutor_conversation("conversation", "German", "German", "English", "", "", transcript, "was heißt das?", True)
    assert 'The line to translate is: "Are you a tourist here?"' in prompt


def test_folder_names_are_mapped_to_existing_folders():
    from agent_plan import canonical_folder_names

    folders = ["ENGH01", "ENGH01 › Unit 1", "Spanisch › Unit 2"]
    plan = {"actions": [
        {"type": "add_vocabulary", "folderName": "ENGH01 ‰ Unit 1"},
        {"type": "create_vocabulary_folder", "folderName": "engh01 > unit 1"},
        {"type": "add_vocabulary", "folderName": "Unit 2"},
        {"type": "create_vocabulary_folder", "folderName": "pronouns"},
    ]}
    result = canonical_folder_names(plan, folders)["actions"]
    assert [a["folderName"] for a in result] == ["ENGH01 › Unit 1", "ENGH01 › Unit 1", "Spanisch › Unit 2", "pronouns"]
    assert [a["type"] for a in result] == ["add_vocabulary", "add_vocabulary", "add_vocabulary", "create_vocabulary_folder"]
