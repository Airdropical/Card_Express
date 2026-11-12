"""Test setup: make the backend importable and keep it away from real services."""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

os.environ["APP_ENV"] = "development"
os.environ["JWT_SECRET"] = "test-secret-with-at-least-32-characters"
os.environ["REGISTRATION_INVITE_CODE"] = "test-invite-code-with-20-chars"
os.environ["GEMINI_API_KEY"] = "test-key"
os.environ["GEMINI_MODEL"] = "primary-flash-lite"
os.environ["GEMINI_FALLBACK_MODEL"] = "fallback-flash-lite"
for name in ("DATABASE_URL", "GOOGLE_API_KEY", "AI_UNLIMITED_ACCOUNT_EMAIL", "CLIENT_IP_HEADER", "CORS_ORIGINS"):
    os.environ.pop(name, None)
