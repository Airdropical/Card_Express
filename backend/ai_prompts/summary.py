"""Prompts for deck summaries."""


def summarize_cards(language: str, material: str) -> str:
    return "Summarize these study cards concisely in " + language + ", group related ideas, and do not invent facts.\n" + material
