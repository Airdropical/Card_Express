"""Prompts that generate or improve flashcards."""

_VARIETY = (
    "Treat examples in the user's message as examples of topics and question style, not as a requirement to repeat the same format on every card. "
    "Independently select a useful variety of question types that fits the topic (for example definition, enumeration, distinction, and application cards). "
)


def card_generation(language: str, style: str, instructions: str) -> str:
    return (
        f"Create 5 to 12 accurate flashcards in {language}. Cover key facts without duplicates or invention. "
        f"Style: {style}. {instructions} Reply only with the requested JSON."
    )


def new_tree_cards(count: int, language: str, deck_name: str, subdeck_name: str, user_instruction: str) -> str:
    return (
        f"Create exactly {count} flashcards in {language} for the requested subdeck. Main deck: {deck_name}. Subdeck: {subdeck_name}. "
        "Follow the full user instruction and learning objective. " + _VARIETY
        + "Keep the questions distinct, accurate, and useful for study. No duplicates. Return only the required JSON. User instruction: "
        + user_instruction
    )


def new_subdeck_cards(count: int, language: str, deck_name: str, parent_deck: str, user_instruction: str) -> str:
    return (
        f'Create exactly {count} accurate, non-duplicate flashcards in {language} for a new subdeck named "{deck_name}" under the existing parent deck "{parent_deck}". '
        "Follow the user's full learning objective. Make each card directly useful for practice, with a clear question on the front and a precise answer on the back. "
        "Return only the required JSON. User instruction: "
        + user_instruction
    )


def existing_deck_cards(count: int, language: str, deck_name: str, user_instruction: str) -> str:
    return (
        f'Create exactly {count} accurate, non-duplicate flashcards in {language} for the existing deck or subdeck named "{deck_name}". '
        + _VARIETY
        + "Keep the cards precise, curricular, varied, and non-duplicative. Do not claim the cards are saved. Return only the required JSON. User instruction: "
        + user_instruction
    )
