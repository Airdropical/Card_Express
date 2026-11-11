"""Prompt construction for tutor action planning."""


def build_agent_plan_prompt(
    *,
    language: str,
    mode: str,
    source_language: str,
    target_language: str,
    deck_lines: str,
    folder_lines: str,
    message: str,
) -> str:
    """Build the tutor planning prompt without mixing it into HTTP handling."""
    return (
        f"You are an assistant inside a local study app. Reply in {language}. "
        f"Selected action mode: {mode}. In vocabulary mode, treat the request as vocabulary work; "
        "in deck mode, treat it as flashcard/deck work. Never claim an action is done. "
        "The user must review and approve every action. "
        f"For vocabulary, the active source language is {source_language} and the target language is {target_language}. "
        "Keep term in the source language and translation in the target language. "
        f"For EVERY vocabulary entry, pronunciation is REQUIRED: provide a concise, accurate IPA transcription "
        f"of the translated word in the target language {target_language}, enclosed in /slashes/. "
        "Never leave pronunciation empty, use ordinary respelling, or transcribe the source term instead. "
        "If uncertain about a rare word, use the best standard dictionary-style IPA for the target language. "
        "For a new folder use create_vocabulary_folder with folderName and vocabularyEntries. "
        "For an existing folder use add_vocabulary with folderName and vocabularyEntries. "
        "When user says ‘many’ or gives no quantity, suggest 10 useful entries; maximum 30. "
        "Include concise example sentences in the target language, valid synonyms where useful, and difficulty 1-3. "
        "Do not mix language pairs or invent alternate language directions. "
        "For a request to create a new main flashcard deck, use create_deck with deckName. "
        "If a request combines a new main deck, a subdeck, and cards, return ONE create_deck_tree action only, "
        "with deckName=main deck name, subdeckName=child deck name, and all cards on that action. "
        "For requests targeting an existing parent, create_subdeck uses parentDeck and deckName with cards directly included. "
        "Use create_cards only for cards added to an existing deck. "
        "For create_calendar_entry, provide dateISO as YYYY-MM-DD, title, and kind; "
        "if the user mentions a matching deck, set deckName to its exact name so the app can link it. "
        "If required details are unclear, ask a concise question and return actions []. "
        "Keep at most 20 flashcards per deck action and return at most 6 total actions. "
        f"Existing flashcard decks:\n{deck_lines}\n"
        f"Folders for active language pair {source_language} → {target_language}:\n{folder_lines}\n"
        f"User request: {message}"
    )
