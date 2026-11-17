"""Environment-driven settings for the API. Read once at import."""

from __future__ import annotations

import os
from datetime import timedelta
from pathlib import Path


def _text(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _database_url() -> str:
    value = _text("DATABASE_URL")
    for prefix in ("postgres://", "postgresql://"):
        if value.startswith(prefix):
            return "postgresql+psycopg://" + value[len(prefix):]
    return value


ROOT = Path(__file__).resolve().parent.parent
FRONTEND = ROOT / "frontend"
CONTENT_PATH = FRONTEND / "data" / "testlauf-03-ergebnisse.json"
SNAPSHOT_SCHEMA_PATH = ROOT / "data" / "app-snapshot.schema.json"

APP_ENV = _text("APP_ENV", "development")
DATABASE_URL = _database_url()
CORS_ORIGINS = [item.strip() for item in _text("CORS_ORIGINS").split(",") if item.strip()]

# Header the hosting proxy sets to the real client address. Railway documents X-Real-IP.
# Set to an empty value to use the TCP peer address instead.
CLIENT_IP_HEADER = _text("CLIENT_IP_HEADER", "x-real-ip").lower()

JWT_SECRET = os.environ.get("JWT_SECRET", "")
JWT_ISSUER = _text("JWT_ISSUER", "word-express")
JWT_AUDIENCE = "word-express-app"
TOKEN_TTL = timedelta(days=30)
REGISTRATION_INVITE_CODE = os.environ.get("REGISTRATION_INVITE_CODE", "")

# Sign in with Apple. The bundle id is the audience of the identity tokens the app sends.
APPLE_BUNDLE_ID = _text("APPLE_BUNDLE_ID", "de.codex.lernkarten")
# Optional: needed only to revoke the Apple grant when an account is deleted.
APPLE_TEAM_ID = _text("APPLE_TEAM_ID")
APPLE_KEY_ID = _text("APPLE_KEY_ID")
APPLE_PRIVATE_KEY = os.environ.get("APPLE_PRIVATE_KEY", "").replace("\\n", "\n").strip()
# Optional: push notifications for the daily tests (Apple Developer > Keys > Apple Push Notifications service).
APNS_KEY_ID = _text("APNS_KEY_ID")
APNS_PRIVATE_KEY = os.environ.get("APNS_PRIVATE_KEY", "").replace("\\n", "\n").strip()
# Shared secret for the scheduled job that sends them; the job endpoint is closed while this is empty.
JOB_SECRET = os.environ.get("JOB_SECRET", "")

IMAGE_MAX_BYTES = 6 * 1024 * 1024
IMAGE_BASE64_MAX_CHARS = 4 * ((IMAGE_MAX_BYTES + 2) // 3)
MAX_BODY_BYTES = 10 * 1024 * 1024
MAX_PROFILE_BYTES = 4_000_000

GEMINI_API_KEY = _text("GEMINI_API_KEY") or _text("GOOGLE_API_KEY")
GEMINI_MODEL = _text("GEMINI_MODEL", "gemini-3.5-flash-lite")
GEMINI_FALLBACK_MODEL = _text("GEMINI_FALLBACK_MODEL", "gemini-3.1-flash-lite")
AI_MAX_OUTPUT_TOKENS = int(_text("AI_MAX_OUTPUT_TOKENS", "8192"))
# Per account, rolling 24 hours. This is the limit every regular user runs into.
AI_DAILY_REQUEST_LIMIT = int(_text("AI_DAILY_REQUEST_LIMIT", "40"))
# Prepared for a later subscription: accounts whose plan is "plus" get this daily limit instead.
AI_DAILY_REQUEST_LIMIT_PLUS = int(_text("AI_DAILY_REQUEST_LIMIT_PLUS", "200"))
# All accounts together, rolling 24 hours: a ceiling on what a day can cost. 0 disables it.
AI_GLOBAL_DAILY_REQUEST_LIMIT = int(_text("AI_GLOBAL_DAILY_REQUEST_LIMIT", "1000"))
# Optional per-account caps on top of the daily limit; 0 disables each.
AI_TOTAL_REQUEST_LIMIT = int(_text("AI_TOTAL_REQUEST_LIMIT", "0"))
AI_BUDGET_USD = float(_text("AI_BUDGET_USD", "0"))
# 0 keeps the total request limit and the budget as lifetime caps. A positive value
# turns both into rolling caps over that many days (for example 30).
AI_LIMIT_WINDOW_DAYS = int(_text("AI_LIMIT_WINDOW_DAYS", "0"))
AI_RATE_LIMIT_PER_MINUTE = int(_text("AI_RATE_LIMIT_PER_MINUTE", "8"))
AI_UNLIMITED_ACCOUNT_EMAIL = _text("AI_UNLIMITED_ACCOUNT_EMAIL").casefold()

# Conservative USD estimates per 1M tokens; adjust to the current AI Studio rates.
AI_INPUT_USD_PER_MILLION = float(_text("AI_INPUT_USD_PER_MILLION", "0.50"))
AI_OUTPUT_USD_PER_MILLION = float(_text("AI_OUTPUT_USD_PER_MILLION", "3.00"))
AI_PRIMARY_INPUT_USD_PER_MILLION = float(_text("AI_PRIMARY_INPUT_USD_PER_MILLION", str(AI_INPUT_USD_PER_MILLION)))
AI_PRIMARY_OUTPUT_USD_PER_MILLION = float(_text("AI_PRIMARY_OUTPUT_USD_PER_MILLION", str(AI_OUTPUT_USD_PER_MILLION)))
AI_FALLBACK_INPUT_USD_PER_MILLION = float(_text("AI_FALLBACK_INPUT_USD_PER_MILLION", str(AI_INPUT_USD_PER_MILLION)))
AI_FALLBACK_OUTPUT_USD_PER_MILLION = float(_text("AI_FALLBACK_OUTPUT_USD_PER_MILLION", str(AI_OUTPUT_USD_PER_MILLION)))


def startup_problems() -> list[str]:
    """Settings the service must not run without, whatever APP_ENV says."""
    problems: list[str] = []
    if len(JWT_SECRET) < 32:
        problems.append("JWT_SECRET must contain at least 32 characters")
    if not DATABASE_URL:
        problems.append("DATABASE_URL must be configured")
    if JOB_SECRET and len(JOB_SECRET) < 32:
        problems.append("JOB_SECRET must contain at least 32 characters")
    if REGISTRATION_INVITE_CODE and len(REGISTRATION_INVITE_CODE) < 20:
        problems.append("REGISTRATION_INVITE_CODE must contain at least 20 characters")
    return problems
