"""Prompts for answer evaluation and tutor conversations."""


def evaluate_answer(language: str, question: str, expected: str, answer: str) -> str:
    return (
        "Evaluate this study answer. Accept accurate paraphrases and synonyms. easy=complete and correct; good=core right with minor omission; hard=materially incomplete; wrong=incorrect, contradictory, or empty. "
        "Provide concise, specific feedback. REQUIRED OUTPUT LANGUAGE: " + language + ". Write the rating feedback entirely in this language. Do not copy or switch to the learner response language if it differs from the card language. Keep this same language for every evaluation.\n"
        + "Question: " + question + "\nExpected answer: " + expected + "\nLearner response: " + answer
    )


def tutor_conversation(
    mode: str,
    language: str,
    source_language: str,
    target_language: str,
    question: str,
    context: str,
    transcript: str,
    message: str,
    requests_translation_help: bool = False,
) -> str:
    if mode == "conversation":
        instructions = (
            "You are an encouraging language conversation partner. Run an interactive role-play in " + target_language + ". "
            "Use words from the supplied vocabulary naturally, but never turn the exercise into an isolated word-translation quiz. "
            "Ask one short, contextually natural question per turn and wait for the learner. On later turns, respond to what they mean. "
            "If the learner makes a meaningful grammar or vocabulary mistake, do not silently ignore it or only repeat the correct answer. "
            "Briefly identify the exact problem and show a natural corrected version in " + target_language + "; explain the rule simply in " + source_language + ". "
            "Then give one short targeted practice prompt that lets the learner retry the same grammar point before continuing the role-play. "
            "If they make the same grammar mistake again, offer one more example and a simpler hint. After they use the structure correctly, acknowledge it briefly and continue the dialogue. "
            "Do not overcorrect minor typos or natural variants when the meaning and grammar are acceptable. "
            "On the first turn, introduce a simple everyday situation in " + target_language + " and ask the learner a relevant question in that language. "
            "Keep the role-play coherent and do not repeat the same opening question."
        )
        if requests_translation_help:
            instructions += (
                " The learner explicitly asked for language help. Do not refuse, insist that they continue without help, or pretend not to understand the request. "
                "Translate the immediately preceding tutor question or phrase into " + source_language + ", explain its key words briefly, and optionally give a simpler paraphrase in " + target_language + ". "
                "Then invite the learner to answer the original question; accept an answer in either language while they are clarifying."
            )
    elif mode == "quiz":
        instructions = (
            "You are conducting a vocabulary translation quiz, not a role-play. Quiz from " + source_language + " to " + target_language + ". "
            "At the start, show exactly one source-language term from the supplied vocabulary and ask for its translation; do not reveal the translation. "
            "On each later turn, evaluate the learner's answer against the most recently asked term, accept accurate synonyms, and give brief feedback in " + language + ". "
            "Then ask one unused source-language term from the supplied list. Do not repeat a term until all available terms in the selected folder have been asked. "
            "Never invent terms or switch to a conversational role-play. If there are no vocabulary entries, say so clearly."
        )
    else:
        instructions = (
            "You are a concise, friendly study tutor. Use the supplied context accurately and state uncertainty. "
            "Reply entirely in " + language + ". Do not change response language based on the learner's latest message."
        )

    return (
        instructions + "\nStudy context:\n" + context
        + "\nTutor topic: " + question
        + "\nConversation so far:\n" + transcript
        + "\nLearner's latest message: " + message
    )
