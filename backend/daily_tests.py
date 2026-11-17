"""Daily tests: who gets one, and from which material. Pure rules, no database or network.

A test is offered for a calendar entry with a linked deck in the next few days ("exam"), and once a day
from cards that went badly in the past ("weak"). The rules run before any AI request is made.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Any, Optional

EXAM_WINDOW_DAYS = 3
MIN_EXAM_CARDS = 4
MIN_WEAK_CARDS = 5
MAX_PROMPT_CARDS = 60
MAX_QUESTIONS = 10
# The app stores dates as seconds since 2001-01-01 UTC (Swift's reference date).
SWIFT_REFERENCE_EPOCH = 978_307_200


def is_hard(lapses: int, hard_count: int, last_rating: Optional[str]) -> bool:
    """A card counts as hard when the last answer went badly or it has failed repeatedly."""
    return last_rating in ("wrong", "hard") or 2 * max(lapses, 0) + max(hard_count, 0) >= 3


def question_count(card_count: int) -> int:
    return max(MIN_EXAM_CARDS, min(MAX_QUESTIONS, card_count))


def usable(cards: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [card for card in cards if str(card.get("question", "")).strip() and str(card.get("answer", "")).strip()]


def exam_material(cards: list[dict[str, Any]], today: date, exam_day: Optional[date]) -> tuple[list[dict[str, Any]], str]:
    """Cards for an exam test, or an empty list with the reason it is not offered."""
    if exam_day is None or not 0 <= (exam_day - today).days <= EXAM_WINDOW_DAYS:
        return [], "The calendar entry is not within the next three days"
    material = usable(cards)
    if len(material) < MIN_EXAM_CARDS:
        return [], "The linked deck has too few cards for a test"
    # Hard cards first, so a large deck is represented by what needs work.
    material.sort(key=lambda card: not is_hard(int(card.get("lapses") or 0), int(card.get("hardCount") or 0), card.get("lastRating")))
    return material[:MAX_PROMPT_CARDS], ""


def weak_material(cards: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], str]:
    """Hard cards for the daily test, or an empty list with the reason it is not offered."""
    material = [card for card in usable(cards) if is_hard(int(card.get("lapses") or 0), int(card.get("hardCount") or 0), card.get("lastRating"))]
    if len(material) < MIN_WEAK_CARDS:
        return [], "There are not enough difficult cards for a test yet"
    return material[:MAX_PROMPT_CARDS], ""


def _swift_day(value: Any) -> Optional[date]:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return None
    try:
        return datetime.fromtimestamp(SWIFT_REFERENCE_EPOCH + value, tz=timezone.utc).date()
    except (OverflowError, OSError, ValueError):
        return None


def snapshot_offers(snapshot: Any, today: date) -> list[dict[str, str]]:
    """Tests a synced snapshot qualifies for today. Used by the daily push job; makes no AI request.

    Days are compared in UTC, so an entry near midnight can be off by one day from the user's own calendar.
    """
    if not isinstance(snapshot, dict):
        return []
    decks = {str(deck.get("id")): deck for deck in snapshot.get("decks") or [] if isinstance(deck, dict)}

    def deck_cards(deck_id: str) -> list[dict[str, Any]]:
        own = [card for card in decks.get(deck_id, {}).get("cards") or [] if isinstance(card, dict)]
        children = [child for child in decks.values() if str(child.get("parentID")) == deck_id]
        return own + [card for child in children for card in child.get("cards") or [] if isinstance(card, dict)]

    offers: list[dict[str, str]] = []
    seen: set[tuple[str, date]] = set()
    dated = [(str(entry.get("deckID") or ""), _swift_day(entry.get("date")), str(entry.get("title") or "")) for entry in snapshot.get("calendarEntries") or [] if isinstance(entry, dict)]
    dated += [(deck_id, _swift_day(deck.get("examDate")), str(deck.get("name") or "")) for deck_id, deck in decks.items()]
    for deck_id, day, title in dated:
        if not deck_id or deck_id not in decks or day is None or (deck_id, day) in seen:
            continue
        if exam_material(deck_cards(deck_id), today, day)[0]:
            seen.add((deck_id, day))
            offers.append({"kind": "exam", "title": title[:80]})
    all_cards = [card for deck in decks.values() for card in deck.get("cards") or [] if isinstance(card, dict)]
    if weak_material(all_cards)[0]:
        offers.append({"kind": "weak", "title": ""})
    return offers


def parse_day(value: str) -> Optional[date]:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def plausible_today(local_day: date) -> bool:
    """The client's own calendar day may differ from the server's by at most one day (time zones)."""
    return abs((local_day - datetime.now(timezone.utc).date()).days) <= 1


def push_text(offers: list[dict[str, str]], language: str) -> tuple[str, str]:
    """Title and body of the daily notification for the given offers."""
    german = language != "en"
    exam = next((offer for offer in offers if offer["kind"] == "exam"), None)
    if exam:
        title = "Test zur Vorbereitung" if german else "Practice test ready"
        name = exam["title"] or ("deinen Termin" if german else "your upcoming date")
        return title, (f"Dein Test für „{name}“ ist bereit." if german else f"Your test for “{name}” is ready.")
    return ("Dein Tagestest" if german else "Your daily test",
            "Ein kurzer Test mit Karten, die dir schwergefallen sind, wartet." if german else "A short test with cards you found difficult is waiting.")
