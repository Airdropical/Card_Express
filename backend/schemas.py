"""Request models and the structured-output schemas sent to Gemini."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from config import IMAGE_BASE64_MAX_CHARS


class Credentials(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr
    password: str = Field(min_length=12, max_length=256)
    invite_code: str | None = Field(default=None, max_length=256)

    @field_validator("password")
    @classmethod
    def reject_control_characters(cls, value: str) -> str:
        if any(ord(character) < 32 for character in value):
            raise ValueError("Password contains an unsupported character")
        return value


class LoginCredentials(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr
    password: str = Field(min_length=1, max_length=256)


class ProfileWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")
    profile: dict[str, Any]


class AppleSignInRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    identityToken: str = Field(min_length=20, max_length=8_000)
    nonce: str = Field(min_length=16, max_length=200)
    authorizationCode: str | None = Field(default=None, max_length=2_000)


class GenerateCardsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    # Matches the app's import limit for pasted text and PDFs.
    text: str | None = Field(default=None, max_length=120_000)
    imageBase64: str | None = Field(default=None, max_length=IMAGE_BASE64_MAX_CHARS)
    mimeType: str = Field(default="image/jpeg", max_length=64)
    language: str = Field(default="German", max_length=60)
    style: str = Field(default="automatic", max_length=60)
    instructions: str = Field(default="", max_length=1_000)


class EvaluateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(max_length=1_500)
    expected: str = Field(max_length=3_000)
    answer: str = Field(max_length=3_000)
    language: str = Field(default="German", max_length=60)
    mode: str = Field(default="automatic", max_length=40)


class AttachmentFields(BaseModel):
    """Optional material the learner attached in the tutor chat: one image and/or extracted document text."""

    model_config = ConfigDict(extra="forbid")
    imageBase64: str | None = Field(default=None, max_length=IMAGE_BASE64_MAX_CHARS)
    mimeType: str = Field(default="image/jpeg", max_length=64)
    documentText: str | None = Field(default=None, max_length=120_000)
    documentName: str = Field(default="", max_length=200)


class TestCard(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(max_length=600)
    answer: str = Field(max_length=1_200)
    lapses: int = Field(default=0, ge=0, le=100_000)
    hardCount: int = Field(default=0, ge=0, le=100_000)
    lastRating: str | None = Field(default=None, max_length=16)


class DailyTestRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: str = Field(pattern="^(exam|weak)$")
    # The calendar entry the test belongs to; empty for the daily test from difficult cards.
    reference: str = Field(default="", max_length=64, pattern="^[A-Za-z0-9-]*$")
    localDay: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    examDay: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    title: str = Field(default="", max_length=120)
    cards: list[TestCard] = Field(min_length=1, max_length=400)


class DeviceRegistration(BaseModel):
    model_config = ConfigDict(extra="forbid")
    token: str = Field(min_length=32, max_length=200, pattern="^[0-9a-fA-F]+$")
    environment: str = Field(default="production", pattern="^(production|sandbox)$")
    language: str = Field(default="de", pattern="^(de|en)$")


class DeviceRemoval(BaseModel):
    model_config = ConfigDict(extra="forbid")
    token: str = Field(min_length=32, max_length=200, pattern="^[0-9a-fA-F]+$")


MATH_LEVEL_PATTERN = "^(middle|upper|university)$"
MATH_TOPIC_PATTERN = r"^[a-z0-9_]{1,64}$"


class MathTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    level: str = Field(pattern=MATH_LEVEL_PATTERN)
    topic: str = Field(pattern=MATH_TOPIC_PATTERN)
    topicName: str = Field(min_length=1, max_length=120)
    # None: the server chooses from the learner's results (adaptive).
    difficulty: int | None = Field(default=None, ge=1, le=5)
    language: str = Field(default="German", max_length=60)
    # The last few questions, so the next one differs.
    recentQuestions: list[str] = Field(default_factory=list, max_length=5)


class MathCheckRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    level: str = Field(pattern=MATH_LEVEL_PATTERN)
    topic: str = Field(pattern=MATH_TOPIC_PATTERN)
    topicName: str = Field(min_length=1, max_length=120)
    difficulty: int = Field(ge=1, le=5)
    question: str = Field(min_length=1, max_length=3_000)
    referenceSteps: list[str] = Field(default_factory=list, max_length=30)
    referenceAnswer: str = Field(default="", max_length=1_000)
    steps: list[str] = Field(default_factory=list, max_length=40)
    answer: str = Field(default="", max_length=1_000)
    language: str = Field(default="German", max_length=60)


class TutorHistoryItem(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: str = Field(max_length=24)
    text: str = Field(max_length=1_000)


class TutorRequest(AttachmentFields):
    question: str = Field(default="", max_length=1_500)
    answer: str = Field(default="", max_length=9_000)
    message: str = Field(min_length=1, max_length=1_500)
    history: list[TutorHistoryItem] = Field(default_factory=list, max_length=10)
    language: str = Field(default="German", max_length=60)
    mode: str = Field(default="chat", max_length=24)
    sourceLanguage: str = Field(default="German", max_length=80)
    targetLanguage: str = Field(default="English", max_length=80)


class AgentPlanRequest(AttachmentFields):
    message: str = Field(min_length=1, max_length=1_500)
    decks: list[str] = Field(default_factory=list, max_length=100)
    language: str = Field(default="German", max_length=60)
    mode: str = Field(default="automatic", max_length=40)
    sourceLanguage: str = Field(default="German", max_length=80)
    targetLanguage: str = Field(default="English", max_length=80)
    vocabularyFolders: list[str] = Field(default_factory=list, max_length=100)
    # Subjects in the "Begriffe" area, each with its term count, e.g. "Biologie (24)".
    termSubjects: list[str] = Field(default_factory=list, max_length=100)
    # "YYYY-MM-DD · title" for each entry, so the tutor can change or remove existing ones.
    calendarEntries: list[str] = Field(default_factory=list, max_length=100)
    # The learner's own calendar day, so "next Friday" resolves correctly.
    today: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    # Vocabulary already taken from the attached material in earlier rounds; the next round continues after them.
    excludeTerms: list[str] = Field(default_factory=list, max_length=1_000)


class SummaryCard(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(max_length=300)
    answer: str = Field(max_length=500)


class SummaryRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    cards: list[SummaryCard] = Field(min_length=1, max_length=100)
    language: str = Field(default="German", max_length=60)


CARD_SCHEMA = {"type": "OBJECT", "properties": {"cards": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {"question": {"type": "STRING"}, "answer": {"type": "STRING"}}, "required": ["question", "answer"]}}}, "required": ["cards"]}
EVALUATION_SCHEMA = {"type": "OBJECT", "properties": {"rating": {"type": "STRING", "enum": ["easy", "good", "hard", "wrong"]}, "feedback": {"type": "STRING"}}, "required": ["rating", "feedback"]}
REPLY_SCHEMA = {"type": "OBJECT", "properties": {"reply": {"type": "STRING"}}, "required": ["reply"]}
SUMMARY_SCHEMA = {"type": "OBJECT", "properties": {"summary": {"type": "STRING"}}, "required": ["summary"]}
VOCABULARY_DRAFT_SCHEMA = {"type": "OBJECT", "properties": {"term": {"type": "STRING"}, "translation": {"type": "STRING"}, "pronunciation": {"type": "STRING"}, "example": {"type": "STRING"}, "synonyms": {"type": "ARRAY", "items": {"type": "STRING"}}, "difficulty": {"type": "INTEGER"}}, "required": ["term", "translation", "pronunciation"]}
MATH_TASK_SCHEMA = {"type": "OBJECT", "properties": {"question": {"type": "STRING"}, "hint": {"type": "STRING"}, "solutionSteps": {"type": "ARRAY", "items": {"type": "STRING"}}, "finalAnswer": {"type": "STRING"}}, "required": ["question", "solutionSteps", "finalAnswer"]}
MATH_CHECK_SCHEMA = {"type": "OBJECT", "properties": {"correct": {"type": "BOOLEAN"}, "score": {"type": "NUMBER"}, "feedback": {"type": "STRING"}, "firstErrorStep": {"type": "INTEGER"}, "mistakeSkill": {"type": "STRING"}}, "required": ["correct", "score", "feedback"]}
AGENT_PLAN_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "reply": {"type": "STRING"},
        "actions": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "type": {"type": "STRING", "enum": ["create_deck", "create_deck_tree", "create_subdeck", "create_cards", "create_calendar_entry", "update_calendar_entry", "delete_calendar_entry", "rename_deck", "start_test", "create_vocabulary_folder", "add_vocabulary", "create_term_subject", "add_terms"]},
                    "subjectName": {"type": "STRING"},
                    "termEntries": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {"term": {"type": "STRING"}, "definition": {"type": "STRING"}, "example": {"type": "STRING"}}, "required": ["term", "definition"]}},
                    "newTitle": {"type": "STRING"},
                    "newDateISO": {"type": "STRING"},
                    "newName": {"type": "STRING"},
                    "parentDeck": {"type": "STRING"},
                    "createParentDeck": {"type": "BOOLEAN"},
                    "deckName": {"type": "STRING"},
                    "subdeckName": {"type": "STRING"},
                    "folderName": {"type": "STRING"},
                    "title": {"type": "STRING"},
                    "dateISO": {"type": "STRING"},
                    "kind": {"type": "STRING", "enum": ["exam", "test", "assignment", "other"]},
                    "note": {"type": "STRING"},
                    "cards": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {"question": {"type": "STRING"}, "answer": {"type": "STRING"}}, "required": ["question", "answer"]}},
                    "vocabularyEntries": {"type": "ARRAY", "items": VOCABULARY_DRAFT_SCHEMA},
                },
                "required": ["type"],
            },
        },
    },
    "required": ["reply", "actions"],
}
