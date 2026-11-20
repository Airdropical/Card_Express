"""Database models, engine, and session dependency."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import BigInteger, DateTime, Float, ForeignKey, Index, Integer, Numeric, String, Text, create_engine
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from config import DATABASE_URL


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    # None for accounts that sign in with Apple only.
    password_hash: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    apple_sub: Mapped[Optional[str]] = mapped_column(String(255), unique=True, nullable=True)
    apple_refresh_token: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    # "free" for everyone today; a later subscription sets "plus".
    plan: Mapped[str] = mapped_column(String(16), default="free", server_default="free")
    # The UTC day the daily test notification was last sent, so the job never sends two in a day.
    last_test_push_day: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    token_version: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class UserProfile(Base):
    __tablename__ = "user_profiles"

    account_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    document: Mapped[Optional[dict[str, Any]]] = mapped_column(JSONB, nullable=True)
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
    actual_cost: Mapped[Optional[float]] = mapped_column(Numeric(12, 6), nullable=True)
    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    state: Mapped[str] = mapped_column(String(16), nullable=False, default="reserved")


class DeviceToken(Base):
    """An iPhone or iPad that may receive push notifications for an account."""

    __tablename__ = "device_tokens"
    __table_args__ = (Index("ix_device_tokens_account_id", "account_id"),)

    token: Mapped[str] = mapped_column(String(200), primary_key=True)
    account_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    environment: Mapped[str] = mapped_column(String(16), nullable=False, default="production")
    language: Mapped[str] = mapped_column(String(8), nullable=False, default="de")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)


class GeneratedTest(Base):
    """A test the tutor wrote, kept so that the same test is served for the rest of the day."""

    __tablename__ = "generated_tests"
    __table_args__ = (Index("ix_generated_tests_created_at", "created_at"),)

    account_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), primary_key=True)
    reference: Mapped[str] = mapped_column(String(64), primary_key=True)
    day: Mapped[str] = mapped_column(String(10), primary_key=True)
    questions: Mapped[Any] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)


class MathAttempt(Base):
    """One checked maths exercise: what it was about, how hard, and how well it went."""

    __tablename__ = "math_attempts"
    __table_args__ = (Index("ix_math_attempts_account_topic", "account_id", "topic", "created_at"),)

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    account_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    level: Mapped[str] = mapped_column(String(16), nullable=False)
    topic: Mapped[str] = mapped_column(String(64), nullable=False)
    difficulty: Mapped[int] = mapped_column(Integer, nullable=False)
    score: Mapped[float] = mapped_column(Float, nullable=False)
    mistake_skill: Mapped[str] = mapped_column(String(120), nullable=False, default="", server_default="")


engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=5) if DATABASE_URL else None
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False) if engine else None


def get_db():
    if SessionLocal is None:
        raise HTTPException(status_code=503, detail="Database is not configured")
    with SessionLocal() as db:
        yield db
