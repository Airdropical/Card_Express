import pytest
from fastapi import HTTPException

import agent_plan
import ai_prompts


def cards(count):
    return [{"question": f"Q{index}", "answer": f"A{index}"} for index in range(count)]


@pytest.mark.parametrize("message, expected", [
    ("Erstelle 10 Karten zum Thema Zellen", 10),
    ("bitte fünf neue Lernkarten", 5),
    ("mach mir zwölf karten", 12),
    ("99 Karten bitte", 20),
    ("Erstelle Karten zum Thema Zellen", None),
    ("Wann ist die Prüfung am 10. Mai?", None),
])
def test_requested_flashcard_count(message, expected):
    assert agent_plan.requested_flashcard_count(message) == expected


def test_detects_new_deck_tree():
    message = 'Erstelle ein Deck mit dem Namen "Deutsch" und ein Unterdeck mit dem Namen "Satzglieder" mit 8 Karten'
    assert agent_plan.detect_deck_tree_request(message) == {"deckName": "Deutsch", "subdeckName": "Satzglieder", "cardCount": 8}


def test_deck_tree_needs_both_names():
    assert agent_plan.detect_deck_tree_request("Erstelle 5 Karten im Deck Biologie") is None


def test_detects_new_subdeck_in_existing_parent():
    message = "Erstelle ein Unterdeck im Deck Biologie mit dem Namen Zellen und erstelle 6 Karten"
    result = agent_plan.detect_new_subdeck_request(message, ["Biologie", "Mathe"])
    assert result == {"parentDeck": "Biologie", "deckName": "Zellen", "cardCount": 6}


def test_other_subdeck_phrasings_are_left_to_the_general_planner():
    message = "Erstelle im Deck Biologie ein Unterdeck mit dem Namen Zellen und erstelle 6 Karten"
    assert agent_plan.detect_new_subdeck_request(message, ["Biologie", "Mathe"]) is None
    assert agent_plan.detect_existing_deck_cards_request(message, ["Biologie", "Mathe"]) is None


def test_new_subdeck_requires_known_parent():
    message = "Erstelle im Deck Chemie ein Unterdeck mit dem Namen Säuren und erstelle 6 Karten"
    assert agent_plan.detect_new_subdeck_request(message, ["Biologie"]) is None


def test_detects_cards_for_existing_deck():
    result = agent_plan.detect_existing_deck_cards_request("Erstelle 10 Karten im Deck Biologie", ["Biologie", "Mathe"])
    assert result == {"deckName": "Biologie", "parentDeck": None, "cardCount": 10}


def test_existing_deck_request_defaults_to_ten_cards():
    result = agent_plan.detect_existing_deck_cards_request("Add flashcards for Mathe", ["Biologie", "Mathe"])
    assert result == {"deckName": "Mathe", "parentDeck": None, "cardCount": 10}


def test_existing_deck_request_ignores_unknown_decks_and_questions():
    assert agent_plan.detect_existing_deck_cards_request("Erstelle 10 Karten im Deck Chemie", ["Biologie"]) is None
    assert agent_plan.detect_existing_deck_cards_request("Wie viele Karten hat Biologie?", ["Biologie"]) is None


def test_clarifying_reply_passes_through_when_cards_were_requested():
    plan = {"reply": "In welches Deck sollen die Karten?", "actions": []}
    assert agent_plan.enforce_requested_card_count(plan, 10) == {"reply": "In welches Deck sollen die Karten?", "actions": []}


def test_non_card_plan_passes_through_when_cards_were_requested():
    plan = {"reply": "ok", "actions": [{"type": "create_calendar_entry", "title": "Test", "dateISO": "2026-12-01"}]}
    assert len(agent_plan.enforce_requested_card_count(plan, 5)["actions"]) == 1


def test_surplus_cards_are_trimmed_to_the_requested_count():
    plan = {"reply": "ok", "actions": [
        {"type": "create_cards", "deckName": "A", "cards": cards(4)},
        {"type": "create_cards", "deckName": "B", "cards": cards(4)},
        {"type": "create_cards", "deckName": "C", "cards": cards(4)},
    ]}
    result = agent_plan.enforce_requested_card_count(plan, 6)
    assert [len(action["cards"]) for action in result["actions"]] == [4, 2]


def test_too_few_cards_is_an_upstream_error():
    plan = {"reply": "ok", "actions": [{"type": "create_cards", "deckName": "A", "cards": cards(3)}]}
    with pytest.raises(HTTPException) as error:
        agent_plan.enforce_requested_card_count(plan, 5)
    assert error.value.status_code == 502


def test_sanitize_drops_incomplete_and_duplicate_actions():
    plan = {"reply": "ok", "actions": [
        {"type": "create_deck", "deckName": "Mathe"},
        {"type": "create_deck", "deckName": "mathe"},
        {"type": "create_deck", "deckName": " "},
        {"type": "create_cards", "deckName": "Mathe", "cards": []},
        {"type": "create_calendar_entry", "title": "Klausur"},
        "not an action",
    ]}
    assert agent_plan.sanitize_agent_plan(plan)["actions"] == [{"type": "create_deck", "deckName": "Mathe"}]


def test_sanitize_keeps_at_most_six_actions():
    plan = {"actions": [{"type": "create_deck", "deckName": f"Deck {index}"} for index in range(9)]}
    assert len(agent_plan.sanitize_agent_plan(plan)["actions"]) == 6


def test_sanitize_tolerates_missing_or_invalid_actions():
    assert agent_plan.sanitize_agent_plan({"reply": "x", "actions": "nope"})["actions"] == []
    assert agent_plan.sanitize_agent_plan({})["actions"] == []


def test_valid_cards_filters_blank_and_malformed_entries():
    raw = [{"question": "Q", "answer": "A"}, {"question": " ", "answer": "A"}, {"question": "Q"}, "x"]
    assert agent_plan.valid_cards(raw) == [{"question": "Q", "answer": "A"}]
    assert agent_plan.valid_cards(None) == []


def test_exact_cards_trims_or_fails():
    assert len(agent_plan.exact_cards({"cards": cards(7)}, 5)) == 5
    with pytest.raises(HTTPException):
        agent_plan.exact_cards({"cards": cards(2)}, 5)


def test_replies_follow_the_interface_language():
    assert agent_plan.preview_reply("German", ["Bio", "Zellen"], 3) == "Vorschau für Bio › Zellen mit 3 Karten."
    assert agent_plan.preview_reply("English", ["Bio"], 3) == "Preview for Bio with 3 cards."
    assert agent_plan.no_action_reply("German") != agent_plan.no_action_reply("English")


def test_language_name_maps_app_values():
    assert agent_plan.language_name("Deutsch") == "German"
    assert agent_plan.language_name("Englisch") == "English"
    assert agent_plan.language_name("") == "German"
    assert agent_plan.language_name("Polish") == "Polish"


def test_translation_help_detection():
    assert agent_plan.requests_translation_help("Was bedeutet das?", "German")
    assert agent_plan.requests_translation_help("Kannst du das auf Deutsch sagen?", "German")
    assert not agent_plan.requests_translation_help("I went to the market yesterday.", "German")


@pytest.mark.parametrize("prompt", [
    ai_prompts.new_tree_cards(5, "English", "Biology", "Cells", "5 cards about cells"),
    ai_prompts.new_subdeck_cards(5, "English", "Cells", "Biology", "5 cards about cells"),
    ai_prompts.existing_deck_cards(5, "English", "Biology", "5 cards about cells"),
])
def test_card_prompts_carry_no_fixed_topic(prompt):
    lowered = prompt.lower()
    assert "exactly 5" in lowered and "in english" in lowered
    assert "adverbial" not in lowered and "grammar" not in lowered and "in german" not in lowered
