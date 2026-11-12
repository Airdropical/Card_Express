"""Tutor Agent planning helpers: intent detection and plan clean-up.

Everything here is pure (no database, no network) so it can be unit-tested directly.
"""

from __future__ import annotations

import re
from typing import Any

from fastapi import HTTPException


def language_name(value: str) -> str:
    names = {"de": "German", "deutsch": "German", "german": "German", "en": "English", "englisch": "English", "english": "English", "fr": "French", "französisch": "French", "es": "Spanish", "spanisch": "Spanish", "it": "Italian", "italienisch": "Italian", "pt": "Portuguese", "ja": "Japanese", "zh": "Chinese", "nl": "Dutch"}
    return names.get(value.casefold(), value or "German")


def requests_translation_help(message: str, source_language: str) -> bool:
    normalized = message.casefold().strip()
    explicit_requests = (
        "translate", "translation", "übersetz", "uebersetz", "auf deutsch", "in german",
        "what does", "what do you mean", "was heißt", "was bedeutet", "verstehe nicht",
        "versteh ich nicht", "i don't understand", "i dont understand", "don't understand",
    )
    if any(phrase in normalized for phrase in explicit_requests):
        return True
    source_aliases = {
        "german": ("german", "deutsch"), "english": ("english", "englisch"),
        "french": ("french", "französisch", "franzosisch"), "spanish": ("spanish", "español", "spanisch"),
        "italian": ("italian", "italiano", "italienisch"),
    }
    aliases = source_aliases.get(source_language.casefold(), (source_language.casefold(),))
    return any(f"in {name}" in normalized or f"auf {name}" in normalized for name in aliases)


def detect_deck_tree_request(message: str) -> dict[str, Any] | None:
    if not re.search(r"\bdeck\b.*\bunterdeck\b", message, re.IGNORECASE | re.DOTALL):
        return None
    def name_after(pattern: str) -> str | None:
        match = re.search(pattern + r'\s+mit\s+dem\s+namen\s*["“„]?([^"”„\n.]+)', message, re.IGNORECASE)
        return match.group(1).strip().strip('"\'“”„ ').strip() if match else None
    main, child = name_after(r"\bdeck"), name_after(r"\bunterdeck")
    if not main or not child:
        return None
    count = requested_flashcard_count(message) or 10
    return {"deckName": main, "subdeckName": child, "cardCount": count}


def requested_flashcard_count(message: str) -> int | None:
    number_words = {
        "ein": 1, "eine": 1, "einen": 1, "eins": 1, "zwei": 2, "drei": 3, "vier": 4,
        "fünf": 5, "funf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10,
        "elf": 11, "zwölf": 12, "zwolf": 12, "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15,
        "funfzehn": 15, "sechzehn": 16, "siebzehn": 17, "achtzehn": 18, "neunzehn": 19, "zwanzig": 20,
    }
    match = re.search(
        r"\b(\d{1,2}|ein(?:e|en|s)?|zwei|drei|vier|fünf|funf|sechs|sieben|acht|neun|zehn|elf|zwölf|zwolf|dreizehn|vierzehn|fünfzehn|funfzehn|sechzehn|siebzehn|achtzehn|neunzehn|zwanzig)\s+(?:(?:neue?|weitere|zusätzliche|zusaetzliche)\s+)?(?:lern)?karten\b",
        message,
        re.IGNORECASE,
    )
    if not match:
        return None
    token = match.group(1).casefold()
    amount = int(token) if token.isdigit() else number_words[token]
    return min(max(amount, 1), 20)


CARD_ACTION_TYPES = {"create_deck_tree", "create_subdeck", "create_cards"}


def valid_cards(cards: Any) -> list[dict[str, Any]]:
    """Cards that have both a non-empty question and a non-empty answer."""
    if not isinstance(cards, list):
        return []
    return [card for card in cards if isinstance(card, dict) and str(card.get("question", "")).strip() and str(card.get("answer", "")).strip()]


def exact_cards(result: dict[str, Any], count: int) -> list[dict[str, Any]]:
    """Exactly `count` valid cards from a card-generation result, or a 502 if the model fell short."""
    cards = valid_cards(result.get("cards"))
    if len(cards) < count:
        raise HTTPException(status_code=502, detail="AI did not create all requested cards; please try again")
    return cards[:count]


def preview_reply(language: str, path: list[str], count: int) -> str:
    target = " › ".join(path)
    if language == "German":
        return f"Vorschau für {target} mit {count} Karten."
    return f"Preview for {target} with {count} cards."


def no_action_reply(language: str) -> str:
    if language == "German":
        return "Ich konnte noch keinen umsetzbaren Vorschlag erstellen. Bitte nenne das genaue Ziel-Deck oder präzisiere den Auftrag."
    return "I could not prepare an actionable proposal yet. Please name the exact target deck or clarify the request."


CLAIMS_DONE = re.compile(r"\b(?:vorbereit|erstellt|angelegt|hinzugefügt|added|created|prepared|ready)\w*\b", re.IGNORECASE)


def enforce_requested_card_count(plan: dict[str, Any], count: int) -> dict[str, Any]:
    card_action_types = CARD_ACTION_TYPES
    if not any(action.get("type") in card_action_types for action in plan.get("actions", [])):
        # No card action at all: the model asked a clarifying question or planned something else.
        return plan
    remaining = count
    for action in plan.get("actions", []):
        if action.get("type") not in card_action_types:
            continue
        cards = action.get("cards") or []
        if not isinstance(cards, list):
            cards = []
        action["cards"] = cards[:remaining]
        remaining -= len(action["cards"])
    if remaining > 0:
        raise HTTPException(status_code=502, detail="AI did not create the requested number of cards; please try again")
    plan["actions"] = [
        action for action in plan.get("actions", [])
        if action.get("type") not in {"create_cards"} or action.get("cards")
    ]
    return plan


def detect_new_subdeck_request(message: str, decks: list[str]) -> dict[str, Any] | None:
    """Recognize creation of a named subdeck and cards inside an existing parent deck."""
    if not re.search(r"\b(?:erstelle|erstell|lege\s+an|create|add)\b", message, re.IGNORECASE):
        return None
    parent_match = re.search(
        r"\b(?:im|in\s+dem|in)\s+deck\s+[\"“„]?(.+?)[\"”„]?\s+mit\s+dem\s+namen\b",
        message,
        re.IGNORECASE,
    )
    child_match = re.search(
        r"\bmit\s+dem\s+namen\s+[\"“„]?(.+?)[\"”„]?"
        r"(?=\s+und\s+(?:passend|dazu|erstelle|erstell|generiere)|[,;.!?]|$)",
        message,
        re.IGNORECASE,
    )
    if not parent_match or not child_match or not re.search(r"\b(?:unterdeck|subdeck)\b", message, re.IGNORECASE):
        return None
    parent = parent_match.group(1).strip().strip(" '\"“”„")
    child = child_match.group(1).strip().strip(" '\"“”„")
    matching_parents = [str(deck).strip() for deck in decks if str(deck).strip().casefold() == parent.casefold()]
    if len(matching_parents) != 1 or not child:
        return None
    count = requested_flashcard_count(message) or 10
    return {"parentDeck": matching_parents[0], "deckName": child, "cardCount": count}


def detect_existing_deck_cards_request(message: str, decks: list[str]) -> dict[str, Any] | None:
    """Recognize explicit card creation requests aimed at a deck the app already has."""
    if not re.search(r"\b(?:erstelle|erstell|mache|mach|füge|fuege|generiere|create|add|make|generate)\b", message, re.IGNORECASE):
        return None
    if re.search(r"\b(?:erstelle|erstell|create)\s+(?:mir\s+)?(?:ein(?:en)?\s+)?(?:neues?\s+)?unterdeck\b", message, re.IGNORECASE):
        return None
    # A subdeck that is being named is a new one; adding its cards to the parent would be wrong.
    if re.search(r"\b(?:unterdeck|subdeck)\b", message, re.IGNORECASE) and re.search(r"\b(?:mit\s+dem\s+namen|namens|named|called)\b", message, re.IGNORECASE):
        return None
    if not re.search(r"\b(?:karten|lern?karten|flashcards|cards)\b", message, re.IGNORECASE):
        return None

    explicit_subdeck = re.search(
        r"\b(?:in\s+dem|im|in)\s+unterdeck\s+[\"“„]?([^()\[\],;:!?]+?)[\"”„]?"
        r"(?=\s*(?:\(|,?\s+(?:karten|lern?karten|cards)\b|[:;,.!?]|$))",
        message,
        re.IGNORECASE,
    )
    explicit_parent = re.search(r"\(\s*(?:im|in\s+dem)\s+deck\s+[\"“„]?([^()\n]+?)[\"”„]?\s*\)", message, re.IGNORECASE)
    if explicit_subdeck and explicit_parent:
        target = explicit_subdeck.group(1).strip().strip(" '\"“”„")
        parent = explicit_parent.group(1).strip().strip(" '\"“”„")
        matching_parents = [str(name).strip() for name in decks if str(name).strip().casefold() == parent.casefold()]
        if target and len(matching_parents) == 1:
            count = requested_flashcard_count(message) or 10
            return {"deckName": target, "parentDeck": matching_parents[0], "cardCount": count}

    matches: list[tuple[int, int, str, bool]] = []
    for raw_name in decks:
        name = str(raw_name).strip()
        if not name:
            continue
        for match in re.finditer(r"(?<!\w)" + re.escape(name) + r"(?!\w)", message, re.IGNORECASE):
            prefix = re.split(r"[,;:.!?()\n]", message[:match.start()])[-1]
            is_subdeck_reference = bool(
                re.search(r"\b(?:unterdeck|subdeck)\s*$", prefix, re.IGNORECASE)
                or re.search(r"\b(?:in|im|für|fuer|for)\s+(?:dem\s+|den\s+)?$", prefix, re.IGNORECASE)
            )
            matches.append((match.start(), len(name), name, is_subdeck_reference))

    if not matches:
        return None
    # Prefer an exact deck name explicitly introduced as an Unterdeck; otherwise use the
    # last named existing deck in the request (e.g. "Satzglieder im Deck Deutsch").
    subdeck_matches = [item for item in matches if item[3]]
    candidates = subdeck_matches or matches
    target_match = max(candidates, key=lambda item: (item[0], item[1]))
    target = target_match[2]
    parent_matches = [item for item in matches if item[2].casefold() != target.casefold() and re.search(r"\bdeck\s*$", re.split(r"[,;:.!?()\n]", message[:item[0]])[-1], re.IGNORECASE)]
    parent = max(parent_matches, key=lambda item: item[0])[2] if parent_matches else None
    if sum(1 for name in decks if str(name).strip().casefold() == target.casefold()) > 1 and not parent:
        return None

    count = requested_flashcard_count(message) or 10
    return {"deckName": target, "parentDeck": parent, "cardCount": count}


def sanitize_agent_plan(plan: dict[str, Any]) -> dict[str, Any]:
    actions = plan.get("actions", [])
    if not isinstance(actions, list):
        actions = []
    kept: list[dict[str, Any]] = []
    seen: set[tuple[str, ...]] = set()
    for action in actions:
        if not isinstance(action, dict):
            continue
        kind = action.get("type")
        if kind == "create_deck_tree" and (not str(action.get("deckName", "")).strip() or not str(action.get("subdeckName", "")).strip()):
            continue
        if kind == "create_subdeck" and (not str(action.get("deckName", "")).strip() or not str(action.get("parentDeck", "")).strip()):
            continue
        if kind == "create_deck" and not str(action.get("deckName", "")).strip():
            continue
        if kind == "create_cards" and (not str(action.get("deckName", "")).strip() or not action.get("cards")):
            continue
        if kind in ("create_vocabulary_folder", "add_vocabulary") and (not str(action.get("folderName", "")).strip() or not action.get("vocabularyEntries")):
            continue
        if kind == "create_calendar_entry" and (not str(action.get("title", "")).strip() or not str(action.get("dateISO", "")).strip()):
            continue
        signature = (str(kind), str(action.get("deckName", "")).casefold(), str(action.get("subdeckName", "")).casefold(), str(action.get("parentDeck", "")).casefold(), str(action.get("folderName", "")).casefold(), str(action.get("title", "")).casefold())
        if signature in seen:
            continue
        seen.add(signature)
        kept.append(action)
        if len(kept) >= 6:
            break
    plan["actions"] = kept
    return plan
