#!/usr/bin/env python3
"""Word Express API and static web preview."""

from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import threading
import time
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
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from jsonschema import Draft202012Validator
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from sqlalchemy import BigInteger, DateTime, ForeignKey, Index, Integer, String, Text, create_engine, select, text
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID, insert
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


ROOT = Path(__file__).resolve().parent.parent
FRONTEND = ROOT / "frontend"
CONTENT_PATH = FRONTEND / "data" / "testlauf-03-ergebnisse.json"
PROFILE_SCHEMA_PATH = ROOT / "data" / "user-profile.schema.json"
MAX_BODY_BYTES = 1_000_000
TOKEN_TTL = timedelta(days=30)
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
        raw_length = headers.get(b"content-length")
        if raw_length:
            try:
                if int(raw_length) > self.max_bytes:
                    await self._reject(send, 413, "Request body is too large")
                    return
            except ValueError:
                await self._reject(send, 400, "Invalid content length")
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
                await self._reject(send, 413, "Request body is too large")
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

        await self.application(scope, replay_body, send)

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


@app.middleware("http")
async def security_headers_and_body_limit(request: Request, call_next):
    try:
        length = int(request.headers.get("content-length", "0"))
    except ValueError:
        return JSONResponse({"detail": "Invalid content length"}, status_code=400)
    if length > MAX_BODY_BYTES:
        return JSONResponse({"detail": "Request body is too large"}, status_code=413)
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
    if request.headers.get("x-forwarded-proto", request.url.scheme) == "https":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


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


@app.get("/privacy")
def privacy_page():
    page = FRONTEND / "privacy.html"
    if not page.exists():
        raise HTTPException(status_code=404, detail="Privacy page is unavailable")
    return FileResponse(page)


app.mount("/", StaticFiles(directory=str(FRONTEND), html=True), name="frontend")
