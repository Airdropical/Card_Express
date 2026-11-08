#!/usr/bin/env python3
"""Word Express API and static web preview."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import re
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from jsonschema import Draft202012Validator
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from sqlalchemy import BigInteger, DateTime, ForeignKey, Index, Integer, Numeric, String, Text, create_engine, func, select, text
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID, insert
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


ROOT = Path(__file__).resolve().parent.parent
FRONTEND = ROOT / "frontend"
CONTENT_PATH = FRONTEND / "data" / "testlauf-03-ergebnisse.json"
PROFILE_SCHEMA_PATH = ROOT / "data" / "user-profile.schema.json"
MAX_BODY_BYTES = 1_000_000
TOKEN_TTL = timedelta(days=30)
GEMINI_API_KEY = (os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or "").strip()
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite").strip()
GEMINI_FALLBACK_MODEL = os.environ.get("GEMINI_FALLBACK_MODEL", "gemini-3.1-flash-lite").strip()
AI_DAILY_REQUEST_LIMIT = int(os.environ.get("AI_DAILY_REQUEST_LIMIT", "40"))
AI_TOTAL_REQUEST_LIMIT = int(os.environ.get("AI_TOTAL_REQUEST_LIMIT", "400"))
AI_BUDGET_USD = float(os.environ.get("AI_BUDGET_USD", "5"))
AI_RATE_LIMIT_PER_MINUTE = int(os.environ.get("AI_RATE_LIMIT_PER_MINUTE", "8"))
AI_MAX_OUTPUT_TOKENS = int(os.environ.get("AI_MAX_OUTPUT_TOKENS", "2048"))
AI_INPUT_USD_PER_MILLION = float(os.environ.get("AI_INPUT_USD_PER_MILLION", "0.50"))
AI_OUTPUT_USD_PER_MILLION = float(os.environ.get("AI_OUTPUT_USD_PER_MILLION", "3.00"))
PASSWORD_HASHER = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)
PASSWORD_HASH_SLOTS = threading.BoundedSemaphore(3)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def database_url() -> str:
    value = os.environ.get("DATABASE_URL", "").strip()
    if value.startswith("postgres://"):
        value = "postgresql+psycopg://" + value[len("postgres://") :]
    elif value.startswith("postgresql://"):
        value = "postgresql+psycopg://" + value[len("postgresql://") :]
    return value


DATABASE_URL = database_url()
JWT_SECRET = os.environ.get("JWT_SECRET", "")
JWT_ISSUER = os.environ.get("JWT_ISSUER", "word-express")
REGISTRATION_INVITE_CODE = os.environ.get("REGISTRATION_INVITE_CODE", "")
CORS_ORIGINS = [item.strip() for item in os.environ.get("CORS_ORIGINS", "").split(",") if item.strip()]


class RequestBodyLimitMiddleware:
    def __init__(self, application, max_bytes: int):
        self.application = application
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.application(scope, receive, send)
            return
        headers = {key.lower(): value for key, value in scope.get("headers", [])}

        async def send_with_security_headers(message):
            if message["type"] == "http.response.start":
                response_headers = list(message.get("headers", []))
                response_headers.extend([
                    (b"x-content-type-options", b"nosniff"),
                    (b"referrer-policy", b"strict-origin-when-cross-origin"),
                    (b"x-frame-options", b"DENY"),
                    (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
                    (b"content-security-policy", b"default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"),
                ])
                forwarded_proto = headers.get(b"x-forwarded-proto", b"").split(b",", 1)[0].strip()
                if forwarded_proto == b"https" or scope.get("scheme") == "https":
                    response_headers.append((b"strict-transport-security", b"max-age=31536000; includeSubDomains"))
                message = {**message, "headers": response_headers}
            await send(message)

        raw_length = headers.get(b"content-length")
        if raw_length:
            try:
                if int(raw_length) > self.max_bytes:
                    await self._reject(send_with_security_headers, 413, "Request body is too large")
                    return
            except ValueError:
                await self._reject(send_with_security_headers, 400, "Invalid content length")
                return
        chunks: list[bytes] = []
        size = 0
        more_body = True
        while more_body:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > self.max_bytes:
                await self._reject(send_with_security_headers, 413, "Request body is too large")
                return
            chunks.append(chunk)
            more_body = message.get("more_body", False)
        body = b"".join(chunks)
        consumed = False

        async def replay_body():
            nonlocal consumed
            if not consumed:
                consumed = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        await self.application(scope, replay_body, send_with_security_headers)

    async def _reject(self, send, response_status: int, message: str):
        body = json.dumps({"detail": message}).encode("utf-8")
        await send({"type": "http.response.start", "status": response_status, "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]})
        await send({"type": "http.response.body", "body": body})


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    password_hash: Mapped[str] = mapped_column(Text)
    token_version: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class UserProfile(Base):
    __tablename__ = "user_profiles"

    account_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    document: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    revision: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class RateLimitBucket(Base):
    __tablename__ = "rate_limit_buckets"
    __table_args__ = (Index("ix_rate_limit_window_start", "window_start"),)

    bucket_key: Mapped[str] = mapped_column(String(128), primary_key=True)
    window_start: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    hits: Mapped[int] = mapped_column(Integer, nullable=False)


class AIUsage(Base):
    __tablename__ = "ai_usage"
    __table_args__ = (Index("ix_ai_usage_created_at", "created_at"), Index("ix_ai_usage_account_id", "account_id"))

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    account_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    reserved_cost: Mapped[float] = mapped_column(Numeric(12, 6), nullable=False)
    actual_cost: Mapped[float | None] = mapped_column(Numeric(12, 6), nullable=True)
    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    state: Mapped[str] = mapped_column(String(16), nullable=False, default="reserved")


engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=5) if DATABASE_URL else None
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False) if engine else None


def get_db():
    if SessionLocal is None:
        raise HTTPException(status_code=503, detail="Database is not configured")
    with SessionLocal() as db:
        yield db


@asynccontextmanager
async def lifespan(_: FastAPI):
    if os.environ.get("APP_ENV", "development") == "production":
        if len(JWT_SECRET) < 32:
            raise RuntimeError("JWT_SECRET must contain at least 32 characters")
        if not DATABASE_URL:
            raise RuntimeError("DATABASE_URL must be configured")
        if len(REGISTRATION_INVITE_CODE) < 20:
            raise RuntimeError("REGISTRATION_INVITE_CODE must contain at least 20 characters")
    yield


app = FastAPI(title="Word Express API", version="1.0.0", docs_url=None, redoc_url=None, lifespan=lifespan)
app.add_middleware(RequestBodyLimitMiddleware, max_bytes=MAX_BODY_BYTES)

if CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "If-Match"],
        max_age=600,
    )


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


class DeleteAccountRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    password: str = Field(min_length=1, max_length=256)


class GenerateCardsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str | None = Field(default=None, max_length=18_000)
    imageBase64: str | None = Field(default=None, max_length=900_000)
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


class TutorHistoryItem(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: str = Field(max_length=24)
    text: str = Field(max_length=1_000)


class TutorRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(default="", max_length=1_500)
    answer: str = Field(default="", max_length=9_000)
    message: str = Field(min_length=1, max_length=1_500)
    history: list[TutorHistoryItem] = Field(default_factory=list, max_length=10)
    language: str = Field(default="German", max_length=60)
    mode: str = Field(default="chat", max_length=24)
    sourceLanguage: str = Field(default="German", max_length=80)
    targetLanguage: str = Field(default="English", max_length=80)


class AgentPlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    message: str = Field(min_length=1, max_length=1_500)
    decks: list[str] = Field(default_factory=list, max_length=100)
    language: str = Field(default="German", max_length=60)
    mode: str = Field(default="automatic", max_length=40)
    sourceLanguage: str = Field(default="German", max_length=80)
    targetLanguage: str = Field(default="English", max_length=80)
    vocabularyFolders: list[str] = Field(default_factory=list, max_length=100)


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
VOCABULARY_DRAFT_SCHEMA = {"type": "OBJECT", "properties": {"term": {"type": "STRING"}, "translation": {"type": "STRING"}, "example": {"type": "STRING"}, "synonyms": {"type": "ARRAY", "items": {"type": "STRING"}}, "difficulty": {"type": "INTEGER"}}, "required": ["term", "translation"]}
AGENT_PLAN_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "reply": {"type": "STRING"},
        "actions": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "type": {"type": "STRING", "enum": ["create_deck", "create_deck_tree", "create_subdeck", "create_cards", "create_calendar_entry", "create_vocabulary_folder", "add_vocabulary"]},
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


def profile_validator() -> Draft202012Validator:
    with PROFILE_SCHEMA_PATH.open(encoding="utf-8") as stream:
        schema = json.load(stream)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)


PROFILE_VALIDATOR = profile_validator()


def fail_rate_limit(
    db: Session,
    request: Request,
    bucket: str,
    limit: int,
    window_seconds: int,
    subject: str = "",
    by_ip: bool = True,
) -> None:
    forwarded = request.headers.get("x-forwarded-for", "").split(",", 1)[0].strip()
    peer = request.client.host if request.client else "unknown"
    ip = forwarded or peer
    identity = hashlib.sha256(f"{bucket}:{ip if by_ip else ''}:{subject.casefold()}".encode()).hexdigest()
    timestamp = int(time.time())
    current_window = timestamp - timestamp % window_seconds
    statement = (
        insert(RateLimitBucket)
        .values(bucket_key=identity, window_start=current_window, hits=1)
        .on_conflict_do_update(
            index_elements=[RateLimitBucket.bucket_key, RateLimitBucket.window_start],
            set_={"hits": RateLimitBucket.hits + 1},
        )
        .returning(RateLimitBucket.hits)
    )
    hits = db.execute(statement).scalar_one()
    db.execute(
        text("DELETE FROM rate_limit_buckets WHERE window_start < :oldest"),
        {"oldest": timestamp - 86_400},
    )
    db.commit()
    if hits > limit:
        retry = window_seconds - (int(time.time()) % window_seconds)
        raise HTTPException(status_code=429, detail="Too many requests", headers={"Retry-After": str(retry)})


def issue_token(account: Account) -> str:
    now = utcnow()
    return jwt.encode(
        {
            "sub": str(account.id),
            "ver": account.token_version,
            "iat": now,
            "exp": now + TOKEN_TTL,
            "iss": JWT_ISSUER,
            "aud": "word-express-app",
        },
        JWT_SECRET,
        algorithm="HS256",
    )


def current_account(
    authorization: str | None = Header(default=None), db: Session = Depends(get_db)
) -> Account:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required", headers={"WWW-Authenticate": "Bearer"})
    token = authorization[7:].strip()
    try:
        claims = jwt.decode(token, JWT_SECRET, algorithms=["HS256"], issuer=JWT_ISSUER, audience="word-express-app")
        account_id = UUID(claims["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Invalid or expired session", headers={"WWW-Authenticate": "Bearer"})
    account = db.get(Account, account_id)
    if account is None or claims.get("ver") != account.token_version:
        raise HTTPException(status_code=401, detail="Invalid or expired session", headers={"WWW-Authenticate": "Bearer"})
    return account


def verify_password(password: str, encoded: str) -> bool:
    with PASSWORD_HASH_SLOTS:
        try:
            return PASSWORD_HASHER.verify(encoded, password)
        except (VerifyMismatchError, InvalidHashError):
            return False


def hash_password(password: str) -> str:
    with PASSWORD_HASH_SLOTS:
        return PASSWORD_HASHER.hash(password)


DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(32))


def validate_profile_document(document: dict[str, Any], account_id: UUID) -> dict[str, Any]:
    if len(json.dumps(document, ensure_ascii=False).encode("utf-8")) > MAX_BODY_BYTES:
        raise HTTPException(status_code=413, detail="Profile is too large")
    errors = list(PROFILE_VALIDATOR.iter_errors(document))
    if errors:
        error = errors[0]
        location = ".".join(str(part) for part in error.absolute_path) or "profile"
        raise HTTPException(status_code=422, detail=f"Invalid profile at {location}: {error.message[:180]}")
    now = utcnow().replace(microsecond=0).isoformat().replace("+00:00", "Z")
    clean = dict(document)
    clean["profile_id"] = str(account_id)
    clean["updated_at"] = now
    return clean


def estimate_ai_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    # Conservative default rates. Set these to current rates for the selected AI Studio tier.
    input_rate = AI_INPUT_USD_PER_MILLION
    output_rate = AI_OUTPUT_USD_PER_MILLION
    if model == GEMINI_MODEL and "flash-lite" in model:
        input_rate = float(os.environ.get("AI_PRIMARY_INPUT_USD_PER_MILLION", str(input_rate)))
        output_rate = float(os.environ.get("AI_PRIMARY_OUTPUT_USD_PER_MILLION", str(output_rate)))
    elif model == GEMINI_FALLBACK_MODEL and "flash-lite" in model:
        input_rate = float(os.environ.get("AI_FALLBACK_INPUT_USD_PER_MILLION", str(input_rate)))
        output_rate = float(os.environ.get("AI_FALLBACK_OUTPUT_USD_PER_MILLION", str(output_rate)))
    return input_tokens * input_rate / 1_000_000 + output_tokens * output_rate / 1_000_000


def reserve_ai_usage(db: Session, account: Account) -> AIUsage:
    # Serialize reservation checks so concurrent requests cannot overshoot the pilot budget.
    db.execute(text("SELECT pg_advisory_xact_lock(74190321)"))
    now = utcnow()
    day_start = now - timedelta(hours=24)
    rows = db.execute(
        select(
            func.count(AIUsage.id),
            func.count(AIUsage.id).filter(AIUsage.created_at >= day_start),
            func.coalesce(func.sum(func.coalesce(AIUsage.actual_cost, AIUsage.reserved_cost)), 0),
        ).where(AIUsage.account_id == account.id)
    ).one()
    total_count, daily_count, spent = int(rows[0]), int(rows[1]), float(rows[2])
    reservation = max(
        estimate_ai_cost(GEMINI_MODEL, 100_000, AI_MAX_OUTPUT_TOKENS),
        estimate_ai_cost(GEMINI_FALLBACK_MODEL or GEMINI_MODEL, 100_000, AI_MAX_OUTPUT_TOKENS),
    )
    if daily_count >= AI_DAILY_REQUEST_LIMIT:
        raise HTTPException(status_code=429, detail="Daily AI request limit reached")
    if total_count >= AI_TOTAL_REQUEST_LIMIT:
        raise HTTPException(status_code=429, detail="Private pilot AI request limit reached")
    if spent + reservation > AI_BUDGET_USD:
        raise HTTPException(status_code=429, detail="Private pilot AI budget reached")
    usage = AIUsage(
        id=UUID(bytes=secrets.token_bytes(16), version=4), account_id=account.id,
        created_at=now, reserved_cost=reservation, actual_cost=None,
        input_tokens=0, output_tokens=0, model=GEMINI_MODEL, state="reserved",
    )
    db.add(usage)
    db.commit()
    return usage


def settle_ai_usage(db: Session, usage_id: UUID, model: str, result: dict[str, Any]) -> None:
    metadata = result.get("usageMetadata") or {}
    input_tokens = max(0, int(metadata.get("promptTokenCount", 0) or 0))
    output_tokens = max(0, int(metadata.get("candidatesTokenCount", 0) or 0))
    usage = db.get(AIUsage, usage_id)
    if usage is None:
        return
    usage.model = model[:100]
    usage.input_tokens = input_tokens
    usage.output_tokens = output_tokens
    usage.state = "complete"
    # Keep the reservation when upstream usage metadata is absent.
    if input_tokens or output_tokens:
        usage.actual_cost = estimate_ai_cost(model, input_tokens, output_tokens)
    db.commit()


def gemini_generate(parts: list[dict[str, Any]], schema: dict[str, Any]) -> tuple[dict[str, Any], str]:
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="Set GEMINI_API_KEY (or GOOGLE_API_KEY) in the Railway service variables")
    models = [GEMINI_MODEL]
    if GEMINI_FALLBACK_MODEL and GEMINI_FALLBACK_MODEL != GEMINI_MODEL:
        models.append(GEMINI_FALLBACK_MODEL)
    payload = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseMimeType": "application/json", "responseSchema": schema, "maxOutputTokens": AI_MAX_OUTPUT_TOKENS},
    }
    retryable = {429, 500, 502, 503, 504}
    for model in models:
        url = "https://generativelanguage.googleapis.com/v1beta/models/" + urllib.parse.quote(model, safe="") + ":generateContent"
        request = urllib.request.Request(
            url, data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY}, method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                decoded = json.loads(response.read())
            candidates = decoded.get("candidates") or []
            output = "".join(part.get("text", "") for part in candidates[0].get("content", {}).get("parts", []) if isinstance(part, dict)) if candidates else ""
            if not output:
                raise HTTPException(status_code=502, detail="AI returned no usable response")
            try:
                return json.loads(output), model
            except json.JSONDecodeError:
                raise HTTPException(status_code=502, detail="AI returned an invalid structured response")
        except urllib.error.HTTPError as exc:
            if exc.code in retryable and model != models[-1]:
                continue
            print("Gemini request failed with upstream status %s." % exc.code, flush=True)
            if exc.code in retryable:
                raise HTTPException(status_code=503, detail="AI service is temporarily unavailable")
            raise HTTPException(status_code=502, detail="AI service rejected the request")
        except urllib.error.URLError:
            if model != models[-1]:
                continue
            raise HTTPException(status_code=502, detail="AI service could not be reached")
    raise HTTPException(status_code=503, detail="AI service is temporarily unavailable")


def execute_ai(request: Request, db: Session, account: Account, route: str, parts: list[dict[str, Any]], schema: dict[str, Any]) -> dict[str, Any]:
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="Set GEMINI_API_KEY (or GOOGLE_API_KEY) in the Railway service variables")
    fail_rate_limit(db, request, "ai", limit=AI_RATE_LIMIT_PER_MINUTE, window_seconds=60, subject=str(account.id), by_ip=False)
    usage = reserve_ai_usage(db, account)
    result, model = gemini_generate(parts, schema)
    settle_ai_usage(db, usage.id, model, result)
    return result


def language_name(value: str) -> str:
    names = {"de": "German", "deutsch": "German", "german": "German", "en": "English", "englisch": "English", "english": "English", "fr": "French", "französisch": "French", "es": "Spanish", "spanisch": "Spanish", "it": "Italian", "italienisch": "Italian", "pt": "Portuguese", "ja": "Japanese", "zh": "Chinese", "nl": "Dutch"}
    return names.get(value.casefold(), value or "German")


def requests_translation_help(message: str, source_language: str) -> bool:
    normalized = message.casefold().strip()
    explicit_requests = (
        "translate", "translation", "übersetz", "uebersetz", "auf deutsch", "in german",
        "what does", "what do you mean", "was heißt", "was bedeutet", "verstehe nicht",
        "versteh ich nicht", "i don't understand", "i dont understand", "don't understand",
    )
    if any(phrase in normalized for phrase in explicit_requests):
        return True
    source_aliases = {
        "german": ("german", "deutsch"), "english": ("english", "englisch"),
        "french": ("french", "französisch", "franzosisch"), "spanish": ("spanish", "español", "spanisch"),
        "italian": ("italian", "italiano", "italienisch"),
    }
    aliases = source_aliases.get(source_language.casefold(), (source_language.casefold(),))
    return any(f"in {name}" in normalized or f"auf {name}" in normalized for name in aliases)


def detect_deck_tree_request(message: str) -> dict[str, Any] | None:
    if not re.search(r"\bdeck\b.*\bunterdeck\b", message, re.IGNORECASE | re.DOTALL):
        return None
    def name_after(pattern: str) -> str | None:
        match = re.search(pattern + r'\s+mit\s+dem\s+namen\s*["“„]?([^"”„\n.]+)', message, re.IGNORECASE)
        return match.group(1).strip().strip('"\'“”„ ').strip() if match else None
    main, child = name_after(r"\bdeck"), name_after(r"\bunterdeck")
    if not main or not child:
        return None
    count_match = re.search(r"\b(\d{1,2})\s+(?:lern)?karten\b", message, re.IGNORECASE)
    count = min(max(int(count_match.group(1)), 1), 20) if count_match else 10
    return {"deckName": main, "subdeckName": child, "cardCount": count}


def sanitize_agent_plan(plan: dict[str, Any]) -> dict[str, Any]:
    actions = plan.get("actions", [])
    if not isinstance(actions, list):
        actions = []
    kept: list[dict[str, Any]] = []
    seen: set[tuple[str, ...]] = set()
    for action in actions:
        if not isinstance(action, dict):
            continue
        kind = action.get("type")
        if kind == "create_deck_tree" and (not str(action.get("deckName", "")).strip() or not str(action.get("subdeckName", "")).strip()):
            continue
        if kind == "create_subdeck" and (not str(action.get("deckName", "")).strip() or not str(action.get("parentDeck", "")).strip()):
            continue
        if kind == "create_deck" and not str(action.get("deckName", "")).strip():
            continue
        if kind == "create_cards" and (not str(action.get("deckName", "")).strip() or not action.get("cards")):
            continue
        if kind in ("create_vocabulary_folder", "add_vocabulary") and (not str(action.get("folderName", "")).strip() or not action.get("vocabularyEntries")):
            continue
        if kind == "create_calendar_entry" and (not str(action.get("title", "")).strip() or not str(action.get("dateISO", "")).strip()):
            continue
        signature = (str(kind), str(action.get("deckName", "")).casefold(), str(action.get("subdeckName", "")).casefold(), str(action.get("parentDeck", "")).casefold(), str(action.get("folderName", "")).casefold(), str(action.get("title", "")).casefold())
        if signature in seen:
            continue
        seen.add(signature)
        kept.append(action)
        if len(kept) >= 6:
            break
    plan["actions"] = kept
    return plan


@app.get("/api/health")
def health(db: Session = Depends(get_db)):
    db.execute(select(1))
    return {"ok": True, "service": "word-express-api", "database": "ok"}


@app.get("/api/v1/content")
def content():
    try:
        payload = CONTENT_PATH.read_bytes()
    except OSError:
        raise HTTPException(status_code=503, detail="Content is unavailable")
    return Response(payload, media_type="application/json; charset=utf-8", headers={"Cache-Control": "public, max-age=300"})


@app.post("/api/v1/auth/register", status_code=status.HTTP_201_CREATED)
def register(body: Credentials, request: Request, db: Session = Depends(get_db)):
    email = str(body.email).strip().lower()
    fail_rate_limit(db, request, "register-global", limit=30, window_seconds=3600, subject="all", by_ip=False)
    fail_rate_limit(db, request, "register-ip", limit=5, window_seconds=3600)
    fail_rate_limit(db, request, "register-email", limit=3, window_seconds=3600, subject=email, by_ip=False)
    if not REGISTRATION_INVITE_CODE:
        raise HTTPException(status_code=503, detail="Account creation is not configured")
    if not body.invite_code or not secrets.compare_digest(body.invite_code, REGISTRATION_INVITE_CODE):
        raise HTTPException(status_code=403, detail="Invalid invitation code")
    if db.scalar(select(Account.id).where(Account.email == email)):
        raise HTTPException(status_code=409, detail="An account with this email already exists")
    account = Account(id=UUID(bytes=secrets.token_bytes(16), version=4), email=email, password_hash=hash_password(body.password))
    db.add(account)
    db.add(UserProfile(account_id=account.id, document=None, revision=0, updated_at=utcnow()))
    try:
        db.commit()
    except Exception:
        db.rollback()
        # Avoid surfacing database details; a concurrent duplicate registration is common.
        if db.scalar(select(Account.id).where(Account.email == email)):
            raise HTTPException(status_code=409, detail="An account with this email already exists")
        raise HTTPException(status_code=503, detail="Account could not be created")
    return {"access_token": issue_token(account), "token_type": "bearer", "expires_in": int(TOKEN_TTL.total_seconds()), "email": account.email}


@app.post("/api/v1/auth/login")
def login(body: LoginCredentials, request: Request, db: Session = Depends(get_db)):
    email = str(body.email).strip().lower()
    fail_rate_limit(db, request, "login-ip", limit=10, window_seconds=900)
    fail_rate_limit(db, request, "login-email", limit=8, window_seconds=900, subject=email, by_ip=False)
    account = db.scalar(select(Account).where(Account.email == email))
    # Use a dummy hash for unknown emails to reduce timing-based account discovery.
    encoded_hash = account.password_hash if account is not None else DUMMY_PASSWORD_HASH
    password_ok = verify_password(body.password, encoded_hash)
    if account is None or not password_ok:
        raise HTTPException(status_code=401, detail="Email or password is incorrect")
    return {"access_token": issue_token(account), "token_type": "bearer", "expires_in": int(TOKEN_TTL.total_seconds()), "email": account.email}


@app.post("/api/v1/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(account: Account = Depends(current_account), db: Session = Depends(get_db)):
    account.token_version += 1
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/api/v1/profile")
def get_profile(response: Response, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    row = db.get(UserProfile, account.id)
    if row is None or row.document is None:
        raise HTTPException(status_code=404, detail="Profile has not been uploaded")
    response.headers["ETag"] = f'"{row.revision}"'
    response.headers["Cache-Control"] = "no-store"
    return {"profile": row.document, "revision": row.revision}


@app.put("/api/v1/profile")
def put_profile(
    body: ProfileWrite,
    response: Response,
    request: Request,
    if_match: str | None = Header(default=None, alias="If-Match"),
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    fail_rate_limit(db, request, "profile-write", limit=120, window_seconds=60, subject=str(account.id), by_ip=False)
    if if_match is None or not re.fullmatch(r'"?\d+"?', if_match.strip()):
        raise HTTPException(status_code=428, detail="If-Match revision is required")
    expected_revision = int(if_match.strip('"'))
    document = validate_profile_document(body.profile, account.id)
    row = db.scalar(select(UserProfile).where(UserProfile.account_id == account.id).with_for_update())
    if row is None:
        raise HTTPException(status_code=404, detail="Profile record is missing")
    if row.revision != expected_revision:
        raise HTTPException(status_code=409, detail="Profile changed on another device", headers={"ETag": f'"{row.revision}"'})
    row.document = document
    row.revision += 1
    row.updated_at = utcnow()
    db.commit()
    response.headers["ETag"] = f'"{row.revision}"'
    response.headers["Cache-Control"] = "no-store"
    return {"profile": document, "revision": row.revision}


@app.delete("/api/v1/account", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(body: DeleteAccountRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    fail_rate_limit(db, request, "account-delete", limit=5, window_seconds=3600, subject=str(account.id), by_ip=False)
    if not verify_password(body.password, account.password_hash):
        raise HTTPException(status_code=401, detail="Password is incorrect")
    db.delete(account)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post("/api/generate-cards")
def generate_cards(body: GenerateCardsRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    parts: list[dict[str, Any]] = []
    if body.text and body.text.strip():
        parts.append({"text": "Material:\n" + body.text})
    if body.imageBase64:
        if body.mimeType not in {"image/jpeg", "image/png", "image/webp"}:
            raise HTTPException(status_code=400, detail="Unsupported image type")
        try:
            base64.b64decode(body.imageBase64, validate=True)
        except (ValueError, binascii.Error):
            raise HTTPException(status_code=400, detail="Invalid image data")
        parts.append({"inlineData": {"mimeType": body.mimeType, "data": body.imageBase64}})
    if not parts:
        raise HTTPException(status_code=400, detail="Provide source text or an image")
    language = language_name(body.language)
    prompt = f"Create 5 to 12 accurate flashcards in {language}. Cover key facts without duplicates or invention. Style: {body.style}. {body.instructions} Reply only with the requested JSON."
    result = execute_ai(request, db, account, "generate-cards", [{"text": prompt}, *parts], CARD_SCHEMA)
    cards = result.get("cards")
    if not isinstance(cards, list):
        raise HTTPException(status_code=502, detail="AI returned invalid flashcards")
    valid = [card for card in cards if isinstance(card, dict) and str(card.get("question", "")).strip() and str(card.get("answer", "")).strip()]
    return {"cards": valid[:20]}


@app.post("/api/evaluate")
def evaluate_answer(body: EvaluateRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    if not body.question.strip() or not body.expected.strip():
        raise HTTPException(status_code=400, detail="Question and expected answer are required")
    language = language_name(body.language)
    prompt = (
        "Evaluate this study answer. Accept accurate paraphrases and synonyms. easy=complete and correct; good=core right with minor omission; hard=materially incomplete; wrong=incorrect, contradictory, or empty. "
        "Provide concise, specific feedback. REQUIRED OUTPUT LANGUAGE: " + language + ". Write the rating feedback entirely in this language. Do not copy or switch to the learner response language if it differs from the card language. Keep this same language for every evaluation.\n"
        + "Question: " + body.question + "\nExpected answer: " + body.expected + "\nLearner response: " + body.answer
    )
    return execute_ai(request, db, account, "evaluate", [{"text": prompt}], EVALUATION_SCHEMA)


@app.post("/api/tutor")
def tutor(body: TutorRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    transcript = "\n".join(("Tutor" if message.role == "assistant" else "Learner") + ": " + message.text for message in body.history)
    language = language_name(body.language)
    source_language = language_name(body.sourceLanguage)
    target_language = language_name(body.targetLanguage)
    context = "\nStudy context:\n" + body.answer
    conversation = "\nConversation so far:\n" + transcript + "\nLearner's latest message: " + body.message

    if body.mode == "conversation":
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
            "Keep the role-play coherent and do not repeat the same opening question.")
        if requests_translation_help(body.message, body.sourceLanguage):
            instructions += (
                " The learner explicitly asked for language help. Do not refuse, insist that they continue without help, or pretend not to understand the request. "
                "Translate the immediately preceding tutor question or phrase into " + source_language + ", explain its key words briefly, and optionally give a simpler paraphrase in " + target_language + ". "
                "Then invite the learner to answer the original question; accept an answer in either language while they are clarifying.")
    elif body.mode == "quiz":
        instructions = (
            "You are conducting a vocabulary translation quiz, not a role-play. Quiz from " + source_language + " to " + target_language + ". "
            "At the start, show exactly one source-language term from the supplied vocabulary and ask for its translation; do not reveal the translation. "
            "On each later turn, evaluate the learner's answer against the most recently asked term, accept accurate synonyms, and give brief feedback in " + language + ". "
            "Then ask one unused source-language term from the supplied list. Do not repeat a term until all available terms in the selected folder have been asked. "
            "Never invent terms or switch to a conversational role-play. If there are no vocabulary entries, say so clearly.")
    else:
        instructions = (
            "You are a concise, friendly study tutor. Use the supplied context accurately and state uncertainty. "
            "Reply entirely in " + language + ". Do not change response language based on the learner's latest message.")

    prompt = (
        instructions + context + "\nTutor topic: " + body.question + conversation
    )
    return execute_ai(request, db, account, "tutor", [{"text": prompt}], REPLY_SCHEMA)


@app.post("/api/agent-plan")
def tutor_agent_plan(body: AgentPlanRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    language = language_name(body.language)
    decks = "\n".join(deck[:120] for deck in body.decks)
    folders = "\n".join(folder[:120] for folder in body.vocabularyFolders)
    tree = detect_deck_tree_request(body.message)
    if tree:
        prompt = (
            "Create exactly " + str(tree["cardCount"]) + " flashcards in German for the requested subdeck. Main deck: " + tree["deckName"] + ". Subdeck: " + tree["subdeckName"] + ". "
            "Follow the full user instruction and its learning objective. The FRONT of every card must be a distinct complex sentence and a task to identify its sentence constituents. "
            "The BACK must give the same sentence segmented and clearly label each constituent (subject, predicate, objects, adverbials as applicable). "
            "Never make cards that merely translate the subdeck title or explain what sentence constituents are. No duplicates. Return only the required JSON. User instruction: " + body.message
        )
        result = execute_ai(request, db, account, "agent-plan", [{"text": prompt}], CARD_SCHEMA)
        cards = result.get("cards", []) if isinstance(result, dict) else []
        valid = [card for card in cards if isinstance(card, dict) and str(card.get("question", "")).strip() and str(card.get("answer", "")).strip()]
        if len(valid) < tree["cardCount"]:
            raise HTTPException(status_code=502, detail="AI did not create all requested cards; please try again")
        return {"reply": "Preview for " + tree["deckName"] + " › " + tree["subdeckName"] + " with " + str(tree["cardCount"]) + " cards.", "actions": [{"type": "create_deck_tree", "deckName": tree["deckName"], "subdeckName": tree["subdeckName"], "cards": valid[:tree["cardCount"]]}]}
    prompt = (
        "You are an assistant inside a local study app. Reply in " + language + ". Selected action mode: " + body.mode + ". "
        "In vocabulary mode, treat the request as vocabulary work; in deck mode, treat it as flashcard/deck work. Never claim an action is done. The user must review and approve every action. "
        "For vocabulary, the active source language is " + body.sourceLanguage + " and the target language is " + body.targetLanguage + ". Keep term in the source language and translation in the target language. "
        "Write every vocabulary example sentence entirely in the target language (" + body.targetLanguage + "), never in the app interface language or source language. "
        "For a new folder use create_vocabulary_folder with folderName and vocabularyEntries. For an existing folder use add_vocabulary with folderName and vocabularyEntries. "
        "When the user says many or gives no quantity, suggest 10 useful entries; maximum 30. Provide concise target-language example sentences for review, valid synonyms where useful, and difficulty 1-3. Do not mix language pairs or invent alternate language directions. "
        "For a new main flashcard deck use create_deck with deckName. When a request combines a new main deck, a subdeck, and cards, return ONE create_deck_tree action only, with deckName, subdeckName, and all cards on that action. "
        "For a request targeting an existing parent, create_subdeck uses parentDeck and deckName with cards directly included. Use create_cards only for cards added to an existing deck. "
        "For create_calendar_entry, provide dateISO as YYYY-MM-DD, title, and kind; if the user mentions a matching deck, set deckName to its exact name. If required details are unclear, ask a concise question and return actions []. "
        "Keep at most 20 flashcards per deck action and return at most 6 total actions. Existing flashcard decks:\n" + decks + "\nFolders for active language pair " + body.sourceLanguage + " → " + body.targetLanguage + ":\n" + folders + "\nUser request: " + body.message
    )
    result = execute_ai(request, db, account, "agent-plan", [{"text": prompt}], AGENT_PLAN_SCHEMA)
    return sanitize_agent_plan(result if isinstance(result, dict) else {})


@app.post("/api/summary")
def summarize_cards(body: SummaryRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    material = "\n".join("Q: " + card.question + "\nA: " + card.answer for card in body.cards)
    if not material.strip():
        raise HTTPException(status_code=400, detail="This deck has no cards")
    prompt = "Summarize these study cards concisely in " + language_name(body.language) + ", group related ideas, and do not invent facts.\n" + material
    return execute_ai(request, db, account, "summary", [{"text": prompt}], SUMMARY_SCHEMA)


@app.get("/privacy")
def privacy_page():
    page = FRONTEND / "privacy.html"
    if not page.exists():
        raise HTTPException(status_code=404, detail="Privacy page is unavailable")
    return FileResponse(page)


app.mount("/", StaticFiles(directory=str(FRONTEND), html=True), name="frontend")
