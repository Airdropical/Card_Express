"""Prompts for the maths area: writing tasks and checking the learner's working."""

LEVEL_NAMES = {"middle": "lower secondary school (grades 7-10)", "upper": "upper secondary school / A-levels (Abitur)", "university": "first-year university"}


def math_task(level: str, topic: str, difficulty: int, language: str, weaknesses: str, avoid: str) -> str:
    return (
        f"Write one maths exercise for {LEVEL_NAMES.get(level, level)} on the topic '{topic}'. "
        f"Difficulty {difficulty} on a scale of 1 (routine, one step) to 5 (several steps, transfer, careful reasoning). "
        + (f"The learner recently struggled with: {weaknesses}. Where it fits the topic, practise exactly that. " if weaknesses else "")
        + (f"Do not repeat these recent exercises: {avoid}. " if avoid else "")
        + f"Write the question, a short hint, the model solution as a list of short calculation steps, and the final answer, all in {language}. "
        "Use plain text with Unicode maths symbols (², √, π, ·, ÷, ≤, ∫, Δ); do not use LaTeX. Make sure the numbers work out and the final answer is correct; "
        "check it before answering. Return only the required JSON."
    )


def math_check(level: str, topic: str, question: str, reference_steps: str, reference_answer: str, steps: str, answer: str, language: str) -> str:
    return (
        f"A learner at {LEVEL_NAMES.get(level, level)} solved a maths exercise on '{topic}'. Check their working. "
        "Accept every correct method, not only the model solution, and equivalent forms of the answer (fractions, decimals, rearranged terms, rounding to sensible precision). "
        "score is 1 for a fully correct answer with sound working, about 0.5 for the right method with a calculation slip or missing final step, and 0 for a wrong approach or no answer. "
        "correct is true only when the final answer is right. firstErrorStep is the 1-based number of the first wrong step of the learner, or 0 when there is none or no steps were given. "
        f"Give short, encouraging feedback in {language} that names the exact mistake and how to fix it, and name the underlying skill in mistakeSkill (a few words, empty when correct). "
        "Return only the required JSON.\n"
        f"Exercise: {question}\nModel solution:\n{reference_steps}\nModel answer: {reference_answer}\n"
        f"Learner's steps:\n{steps or '(none)'}\nLearner's final answer: {answer or '(none)'}"
    )
