"""Gemini access with per-account usage limits and cost tracking."""

from __future__ import annotations

import json
import secrets
import urllib.error
import urllib.parse
import urllib.request
from datetime import timedelta
from typing import Any
from uuid import UUID

from fastapi import HTTPException, Request
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

import config
from db import Account, AIUsage, utcnow
from rate_limit import fail_rate_limit

RETRYABLE_STATUS = {429, 500, 502, 503, 504}
# Upper bound on prompt size assumed when reserving budget before the call.
RESERVED_INPUT_TOKENS = 100_000
ADVISORY_LOCK_NAMESPACE = 74190321


def estimate_ai_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    input_rate, output_rate = config.AI_INPUT_USD_PER_MILLION, config.AI_OUTPUT_USD_PER_MILLION
    if model == config.GEMINI_MODEL and "flash-lite" in model:
        input_rate, output_rate = config.AI_PRIMARY_INPUT_USD_PER_MILLION, config.AI_PRIMARY_OUTPUT_USD_PER_MILLION
    elif model == config.GEMINI_FALLBACK_MODEL and "flash-lite" in model:
        input_rate, output_rate = config.AI_FALLBACK_INPUT_USD_PER_MILLION, config.AI_FALLBACK_OUTPUT_USD_PER_MILLION
    return input_tokens * input_rate / 1_000_000 + output_tokens * output_rate / 1_000_000


def token_usage(response: dict[str, Any]) -> tuple[int, int]:
    """Billable (input, output) tokens. Thinking tokens are billed as output."""
    metadata = response.get("usageMetadata") or {}

    def count(key: str) -> int:
        return max(0, int(metadata.get(key, 0) or 0))

    return count("promptTokenCount"), count("candidatesTokenCount") + count("thoughtsTokenCount")


def reserve_ai_usage(db: Session, account: Account, enforce_limits: bool = True) -> AIUsage:
    # Serialize reservation checks per account so concurrent requests cannot overshoot the budget.
    db.execute(
        text("SELECT pg_advisory_xact_lock(:namespace, hashtext(:account))"),
        {"namespace": ADVISORY_LOCK_NAMESPACE, "account": str(account.id)},
    )
    now = utcnow()
    counted = AIUsage.state != "failed"
    if config.AI_LIMIT_WINDOW_DAYS > 0:
        counted = counted & (AIUsage.created_at >= now - timedelta(days=config.AI_LIMIT_WINDOW_DAYS))
    in_last_day = (AIUsage.state != "failed") & (AIUsage.created_at >= now - timedelta(hours=24))
    rows = db.execute(
        select(
            func.count(AIUsage.id).filter(counted),
            func.count(AIUsage.id).filter(in_last_day),
            func.coalesce(func.sum(func.coalesce(AIUsage.actual_cost, AIUsage.reserved_cost)).filter(counted), 0),
        ).where(AIUsage.account_id == account.id)
    ).one()
    total_count, daily_count, spent = int(rows[0]), int(rows[1]), float(rows[2])
    reservation = max(
        estimate_ai_cost(config.GEMINI_MODEL, RESERVED_INPUT_TOKENS, config.AI_MAX_OUTPUT_TOKENS),
        estimate_ai_cost(config.GEMINI_FALLBACK_MODEL or config.GEMINI_MODEL, RESERVED_INPUT_TOKENS, config.AI_MAX_OUTPUT_TOKENS),
    )
    if enforce_limits:
        if daily_count >= config.AI_DAILY_REQUEST_LIMIT:
            raise HTTPException(status_code=429, detail="Daily AI request limit reached")
        if total_count >= config.AI_TOTAL_REQUEST_LIMIT:
            raise HTTPException(status_code=429, detail="Private pilot AI request limit reached")
        if spent + reservation > config.AI_BUDGET_USD:
            raise HTTPException(status_code=429, detail="Private pilot AI budget reached")
    usage = AIUsage(
        id=UUID(bytes=secrets.token_bytes(16), version=4), account_id=account.id,
        created_at=now, reserved_cost=reservation, actual_cost=None,
        input_tokens=0, output_tokens=0, model=config.GEMINI_MODEL, state="reserved",
    )
    db.add(usage)
    db.commit()
    return usage


def settle_ai_usage(db: Session, usage_id: UUID, model: str, response: dict[str, Any]) -> None:
    input_tokens, output_tokens = token_usage(response)
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


def release_ai_usage(db: Session, usage_id: UUID) -> None:
    """Free the reservation of a request that never produced a billable response."""
    usage = db.get(AIUsage, usage_id)
    if usage is None:
        return
    usage.state = "failed"
    usage.actual_cost = 0
    db.commit()


def call_gemini(parts: list[dict[str, Any]], schema: dict[str, Any]) -> tuple[dict[str, Any], str]:
    """Send the request and return the raw API response with the model that answered."""
    models = [config.GEMINI_MODEL]
    if config.GEMINI_FALLBACK_MODEL and config.GEMINI_FALLBACK_MODEL != config.GEMINI_MODEL:
        models.append(config.GEMINI_FALLBACK_MODEL)
    payload = json.dumps({
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseMimeType": "application/json", "responseSchema": schema, "maxOutputTokens": config.AI_MAX_OUTPUT_TOKENS},
    }, ensure_ascii=False).encode("utf-8")
    for model in models:
        is_last = model == models[-1]
        url = "https://generativelanguage.googleapis.com/v1beta/models/" + urllib.parse.quote(model, safe="") + ":generateContent"
        request = urllib.request.Request(
            url, data=payload,
            headers={"Content-Type": "application/json", "x-goog-api-key": config.GEMINI_API_KEY}, method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.loads(response.read()), model
        except urllib.error.HTTPError as exc:
            if exc.code in RETRYABLE_STATUS and not is_last:
                continue
            print("Gemini request failed with upstream status %s." % exc.code, flush=True)
            if exc.code in RETRYABLE_STATUS:
                raise HTTPException(status_code=503, detail="AI service is temporarily unavailable")
            raise HTTPException(status_code=502, detail="AI service rejected the request")
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            if not is_last:
                continue
            raise HTTPException(status_code=502, detail="AI service could not be reached")
    raise HTTPException(status_code=503, detail="AI service is temporarily unavailable")


def parse_gemini_output(response: dict[str, Any]) -> dict[str, Any]:
    """Extract the structured JSON object from a raw API response."""
    candidates = response.get("candidates") or []
    candidate = candidates[0] if candidates and isinstance(candidates[0], dict) else {}
    parts = (candidate.get("content") or {}).get("parts") or []
    output = "".join(part.get("text", "") for part in parts if isinstance(part, dict) and not part.get("thought"))
    if candidate.get("finishReason") == "MAX_TOKENS":
        raise HTTPException(status_code=502, detail="AI response was cut off because it was too long; please ask for fewer items")
    if not output:
        raise HTTPException(status_code=502, detail="AI returned no usable response")
    try:
        result = json.loads(output)
    except json.JSONDecodeError:
        raise HTTPException(status_code=502, detail="AI returned an invalid structured response")
    if not isinstance(result, dict):
        raise HTTPException(status_code=502, detail="AI returned an invalid structured response")
    return result


def execute_ai(request: Request, db: Session, account: Account, parts: list[dict[str, Any]], schema: dict[str, Any]) -> dict[str, Any]:
    if not config.GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="Set GEMINI_API_KEY (or GOOGLE_API_KEY) in the Railway service variables")
    unlimited_operator = bool(config.AI_UNLIMITED_ACCOUNT_EMAIL) and account.email.strip().casefold() == config.AI_UNLIMITED_ACCOUNT_EMAIL
    if not unlimited_operator:
        fail_rate_limit(db, request, "ai", limit=config.AI_RATE_LIMIT_PER_MINUTE, window_seconds=60, subject=str(account.id), by_ip=False)
    usage = reserve_ai_usage(db, account, enforce_limits=not unlimited_operator)
    try:
        response, model = call_gemini(parts, schema)
    except Exception:
        release_ai_usage(db, usage.id)
        raise
    # A response was received and is billed, even if its content turns out to be unusable.
    settle_ai_usage(db, usage.id, model, response)
    return parse_gemini_output(response)
