"""Prompt for the daily tests the tutor writes from existing cards."""


def daily_test(kind: str, title: str, count: int, material: str) -> str:
    purpose = (
        f'The learner has "{title}" coming up within days. Write a practice test that checks whether they are ready.'
        if kind == "exam"
        else "These are cards the learner found difficult in the past. Write a short test that revisits exactly these weak spots."
    )
    return (
        f"{purpose} Create exactly {count} new test questions with model answers from the study cards below. "
        "Write in the language the cards are written in. Do not copy the card questions word for word: rephrase them, ask for the reverse direction, "
        "combine two related cards, or ask for an application or a short explanation. Every question must be answerable from the cards alone; "
        "do not introduce facts that are not in them. Keep answers short and precise. Cover different cards rather than repeating one. "
        "Return only the required JSON.\nStudy cards:\n" + material
    )
