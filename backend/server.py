#!/usr/bin/env python3
"""Word Express API and static web preview: application setup and routes."""

from __future__ import annotations

import base64
import binascii
import re
import secrets
from contextlib import asynccontextmanager
from datetime import timedelta
from typing import Any, Optional
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

import ai_prompts
import apns
import apple_auth
import config
import daily_tests
from agent_plan import (
    CARD_ACTION_TYPES,
    CLAIMS_DONE,
    detect_deck_tree_request,
    detect_existing_deck_cards_request,
    detect_new_subdeck_request,
    enforce_requested_card_count,
    exact_cards,
    language_name,
    no_action_reply,
    preview_reply,
    requested_flashcard_count,
    requests_translation_help,
    sanitize_agent_plan,
    valid_cards,
)
from ai_client import daily_limit_for, execute_ai, is_unlimited, requests_in_last_day
from auth import DUMMY_PASSWORD_HASH, current_account, hash_password, issue_token, verify_password
from db import Account, Base, DeviceToken, GeneratedTest, UserProfile, get_db, utcnow  # noqa: F401  (Base is re-exported for tooling)
from middleware import BodyLimitAndSecurityHeadersMiddleware
from profiles import validate_snapshot
from rate_limit import fail_rate_limit
from schemas import (
    AGENT_PLAN_SCHEMA,
    AttachmentFields,
    CARD_SCHEMA,
    EVALUATION_SCHEMA,
    REPLY_SCHEMA,
    SUMMARY_SCHEMA,
    AgentPlanRequest,
    AppleSignInRequest,
    Credentials,
    DailyTestRequest,
    DeviceRegistration,
    DeviceRemoval,
    EvaluateRequest,
    GenerateCardsRequest,
    LoginCredentials,
    ProfileWrite,
    SummaryRequest,
    TutorRequest,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    problems = config.startup_problems()
    if problems:
        raise RuntimeError("Invalid configuration: " + "; ".join(problems))
    yield


app = FastAPI(title="Word Express API", version="1.0.0", docs_url=None, redoc_url=None, lifespan=lifespan)
app.add_middleware(BodyLimitAndSecurityHeadersMiddleware, max_bytes=config.MAX_BODY_BYTES)

if config.CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=config.CORS_ORIGINS,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "If-Match"],
        max_age=600,
    )


def session_response(account: Account) -> dict[str, Any]:
    return {"access_token": issue_token(account), "token_type": "bearer", "expires_in": int(config.TOKEN_TTL.total_seconds()), "email": account.email}


@app.get("/api/health")
def health(db: Session = Depends(get_db)):
    db.execute(select(1))
    return {"ok": True, "service": "word-express-api", "database": "ok"}


@app.get("/api/v1/content")
def content():
    if not config.CONTENT_PATH.is_file():
        raise HTTPException(status_code=503, detail="Content is unavailable")
    return FileResponse(config.CONTENT_PATH, media_type="application/json; charset=utf-8", headers={"Cache-Control": "public, max-age=300"})


@app.post("/api/v1/auth/register", status_code=status.HTTP_201_CREATED)
def register(body: Credentials, request: Request, db: Session = Depends(get_db)):
    email = str(body.email).strip().lower()
    fail_rate_limit(db, request, "register-global", limit=30, window_seconds=3600, subject="all", by_ip=False)
    fail_rate_limit(db, request, "register-ip", limit=5, window_seconds=3600)
    fail_rate_limit(db, request, "register-email", limit=3, window_seconds=3600, subject=email, by_ip=False)
    if not config.REGISTRATION_INVITE_CODE:
        raise HTTPException(status_code=503, detail="Account creation is not configured")
    if not body.invite_code or not secrets.compare_digest(body.invite_code.encode(), config.REGISTRATION_INVITE_CODE.encode()):
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
    return session_response(account)


@app.post("/api/v1/auth/login")
def login(body: LoginCredentials, request: Request, db: Session = Depends(get_db)):
    email = str(body.email).strip().lower()
    fail_rate_limit(db, request, "login-ip", limit=10, window_seconds=900)
    # The tight per-email limit is tied to the caller's address, so guesses from elsewhere
    # do not lock the owner out. The address-independent cap is deliberately looser.
    fail_rate_limit(db, request, "login-email-ip", limit=8, window_seconds=900, subject=email)
    fail_rate_limit(db, request, "login-email", limit=40, window_seconds=900, subject=email, by_ip=False)
    account = db.scalar(select(Account).where(Account.email == email))
    # Use a dummy hash for unknown emails (and Apple-only accounts) to reduce timing-based account discovery.
    encoded_hash = account.password_hash if account is not None and account.password_hash else DUMMY_PASSWORD_HASH
    password_ok = verify_password(body.password, encoded_hash)
    if account is None or not account.password_hash or not password_ok:
        raise HTTPException(status_code=401, detail="Email or password is incorrect")
    return session_response(account)


def account_for_apple_identity(db: Session, apple_sub: str, email: Optional[str]) -> Account:
    """Find the account for an Apple identity, link an existing one by verified email, or create it."""
    account = db.scalar(select(Account).where(Account.apple_sub == apple_sub))
    if account is not None:
        return account
    existing = db.scalar(select(Account).where(Account.email == email)) if email else None
    if existing is not None and existing.apple_sub is None:
        existing.apple_sub = apple_sub
        return existing
    # No usable email (hidden, or already taken by another Apple identity): keep the address column unique anyway.
    address = email if email and existing is None else f"{apple_sub[:200]}@apple.invalid"
    account = Account(id=UUID(bytes=secrets.token_bytes(16), version=4), email=address, password_hash=None, apple_sub=apple_sub)
    db.add(account)
    db.add(UserProfile(account_id=account.id, document=None, revision=0, updated_at=utcnow()))
    return account


@app.post("/api/v1/auth/apple")
def sign_in_with_apple(body: AppleSignInRequest, request: Request, db: Session = Depends(get_db)):
    fail_rate_limit(db, request, "apple-ip", limit=20, window_seconds=900)
    claims = apple_auth.verify_identity_token(body.identityToken, body.nonce)
    apple_sub = str(claims["sub"])
    account = account_for_apple_identity(db, apple_sub, apple_auth.verified_email(claims))
    refresh_token = apple_auth.refresh_token_for(body.authorizationCode or "")
    if refresh_token:
        account.apple_refresh_token = refresh_token
    try:
        db.commit()
    except Exception:
        db.rollback()
        # Two first sign-ins at once: the other request created the account.
        account = db.scalar(select(Account).where(Account.apple_sub == apple_sub))
        if account is None:
            raise HTTPException(status_code=503, detail="Account could not be created")
    return session_response(account)


@app.get("/api/v1/account")
def account_overview(response: Response, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    response.headers["Cache-Control"] = "no-store"
    hidden_email = account.email.endswith("@apple.invalid")
    return {
        "email": None if hidden_email else account.email,
        "ai": {
            "usedToday": requests_in_last_day(db, account),
            "dailyLimit": daily_limit_for(account),
            "unlimited": is_unlimited(account),
        },
        "plan": account.plan or "free",
        # True when this account gets its test reminders from the server; the app then plans none itself.
        "serverPush": apns.configured() and db.scalar(select(DeviceToken.token).where(DeviceToken.account_id == account.id).limit(1)) is not None,
    }


@app.put("/api/v1/devices", status_code=status.HTTP_204_NO_CONTENT)
def register_device(body: DeviceRegistration, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    """Remember a device for push notifications. A token belongs to whichever account registered it last."""
    fail_rate_limit(db, request, "device", limit=30, window_seconds=3600, subject=str(account.id), by_ip=False)
    token = body.token.lower()
    row = db.get(DeviceToken, token)
    if row is None:
        db.add(DeviceToken(token=token, account_id=account.id, environment=body.environment, language=body.language, updated_at=utcnow()))
    else:
        row.account_id, row.environment, row.language, row.updated_at = account.id, body.environment, body.language, utcnow()
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.delete("/api/v1/devices", status_code=status.HTTP_204_NO_CONTENT)
def remove_device(body: DeviceRemoval, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    db.execute(delete(DeviceToken).where(DeviceToken.token == body.token.lower(), DeviceToken.account_id == account.id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post("/api/v1/tests")
def daily_test(body: DailyTestRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    """A test the tutor writes from the learner's cards: checked first, written once per day, then served from storage."""
    today = daily_tests.parse_day(body.localDay)
    if today is None or not daily_tests.plausible_today(today):
        raise HTTPException(status_code=422, detail="The device date does not match the current date")
    cards = [card.model_dump() for card in body.cards]
    if body.kind == "exam":
        material, reason = daily_tests.exam_material(cards, today, daily_tests.parse_day(body.examDay or ""))
    else:
        material, reason = daily_tests.weak_material(cards)
    if not material:
        # Checked before any AI request: nothing is generated, and nothing is counted, for a test that is not due.
        raise HTTPException(status_code=409, detail=reason)
    key = {"account_id": account.id, "kind": body.kind, "reference": body.reference, "day": body.localDay}
    stored = db.get(GeneratedTest, key)
    if stored is not None:
        return {"questions": stored.questions, "cached": True}
    count = daily_tests.question_count(len(material))
    lines = "\n".join("Q: " + card["question"][:300] + "\nA: " + card["answer"][:500] for card in material)
    prompt = ai_prompts.daily_test(body.kind, body.title.strip() or "an exam", count, lines)
    result = execute_ai(request, db, account, [{"text": prompt}], CARD_SCHEMA)
    questions = [{"question": str(card["question"]).strip(), "answer": str(card["answer"]).strip()} for card in valid_cards(result.get("cards"))][:count]
    if len(questions) < daily_tests.MIN_EXAM_CARDS:
        raise HTTPException(status_code=502, detail="AI did not create a usable test; please try again")
    db.add(GeneratedTest(**key, questions=questions, created_at=utcnow()))
    # Old tests are of no further use.
    db.execute(delete(GeneratedTest).where(GeneratedTest.created_at < utcnow() - timedelta(days=7)))
    try:
        db.commit()
    except Exception:
        db.rollback()  # A parallel request stored the same test first; this one is still valid to return.
    return {"questions": questions, "cached": False}


@app.post("/api/internal/daily-tests")
def send_daily_test_notifications(x_job_secret: Optional[str] = Header(default=None, alias="X-Job-Secret"), db: Session = Depends(get_db)):
    """Run once a day by a scheduler: notify accounts whose synced data qualifies for a test. Makes no AI request."""
    if not config.JOB_SECRET or not x_job_secret or not secrets.compare_digest(x_job_secret.encode(), config.JOB_SECRET.encode()):
        raise HTTPException(status_code=404, detail="Not Found")
    if not apns.configured():
        raise HTTPException(status_code=503, detail="Push notifications are not configured")
    today = utcnow().date()
    day = today.isoformat()
    sent = skipped = removed = 0
    account_ids = db.scalars(select(DeviceToken.account_id).distinct()).all()
    with apns.open_client() as client:
        for account_id in account_ids:
            account = db.get(Account, account_id)
            profile = db.get(UserProfile, account_id)
            if account is None or account.last_test_push_day == day:
                skipped += 1
                continue
            offers = daily_tests.snapshot_offers(profile.document if profile else None, today)
            if not offers:
                skipped += 1
                continue
            for device in db.scalars(select(DeviceToken).where(DeviceToken.account_id == account_id)).all():
                title, text = daily_tests.push_text(offers, device.language)
                try:
                    result = apns.send(client, device.token, device.environment, title, text, offers[0]["kind"])
                except Exception:
                    print("Push delivery failed.", flush=True)
                    continue
                if result == 200:
                    sent += 1
                elif result in (400, 410):
                    # Apple no longer knows this device (app removed or token replaced).
                    db.delete(device)
                    removed += 1
            account.last_test_push_day = day
            db.commit()
    return {"sent": sent, "skipped": skipped, "removedDevices": removed}


@app.post("/api/v1/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(account: Account = Depends(current_account), db: Session = Depends(get_db)):
    account.token_version += 1
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/api/v1/profile")
def get_profile(response: Response, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    row = db.get(UserProfile, account.id)
    if row is None:
        raise HTTPException(status_code=404, detail="Profile record is missing")
    response.headers["ETag"] = f'"{row.revision}"'
    response.headers["Cache-Control"] = "no-store"
    # `profile` is null until a device has uploaded its data for the first time.
    return {"profile": row.document, "revision": row.revision}


@app.put("/api/v1/profile")
def put_profile(
    body: ProfileWrite,
    response: Response,
    request: Request,
    if_match: Optional[str] = Header(default=None, alias="If-Match"),
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    fail_rate_limit(db, request, "profile-write", limit=30, window_seconds=60, subject=str(account.id), by_ip=False)
    if if_match is None or not re.fullmatch(r'"?\d+"?', if_match.strip()):
        raise HTTPException(status_code=428, detail="If-Match revision is required")
    expected_revision = int(if_match.strip().strip('"'))
    document = validate_snapshot(body.profile)
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
    # The device already has the document; only the new revision goes back.
    return {"revision": row.revision}


@app.delete("/api/v1/account", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    """Delete the account with its synced data and usage records. The app asks for confirmation first."""
    fail_rate_limit(db, request, "account-delete", limit=5, window_seconds=3600, subject=str(account.id), by_ip=False)
    refresh_token = account.apple_refresh_token
    db.delete(account)
    db.commit()
    apple_auth.revoke(refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
ATTACHMENT_NOTE = (
    "The learner attached the material that follows. When the request refers to it (for example 'this', 'the picture', "
    "'the PDF', 'the document'), use it as the primary source. Do not invent content that is not in it, and say so "
    "when the material does not answer the question."
)


def image_part(image_base64: str, mime_type: str) -> dict[str, Any]:
    """Validated inline image part for Gemini."""
    if mime_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported image type")
    try:
        image_bytes = base64.b64decode(image_base64, validate=True)
    except (ValueError, binascii.Error):
        raise HTTPException(status_code=400, detail="Invalid image data")
    if len(image_bytes) > config.IMAGE_MAX_BYTES:
        raise HTTPException(status_code=413, detail="Image exceeds 6 MB")
    return {"inlineData": {"mimeType": mime_type, "data": image_base64}}


def attachment_parts(body: AttachmentFields) -> list[dict[str, Any]]:
    """Prompt parts for material attached to a tutor request; empty when nothing is attached."""
    parts: list[dict[str, Any]] = []
    if body.documentText and body.documentText.strip():
        name = body.documentName.strip() or "document"
        parts.append({"text": f"Attached document ({name}):\n" + body.documentText})
    if body.imageBase64:
        parts.append(image_part(body.imageBase64, body.mimeType))
    return [{"text": ATTACHMENT_NOTE}, *parts] if parts else []


@app.post("/api/generate-cards")
def generate_cards(body: GenerateCardsRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    parts: list[dict[str, Any]] = []
    if body.text and body.text.strip():
        parts.append({"text": "Material:\n" + body.text})
    if body.imageBase64:
        parts.append(image_part(body.imageBase64, body.mimeType))
    if not parts:
        raise HTTPException(status_code=400, detail="Provide source text or an image")
    prompt = ai_prompts.card_generation(language_name(body.language), body.style, body.instructions)
    result = execute_ai(request, db, account, [{"text": prompt}, *parts], CARD_SCHEMA)
    if not isinstance(result.get("cards"), list):
        raise HTTPException(status_code=502, detail="AI returned invalid flashcards")
    return {"cards": valid_cards(result["cards"])[:20]}


@app.post("/api/evaluate")
def evaluate_answer(body: EvaluateRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    if not body.question.strip() or not body.expected.strip():
        raise HTTPException(status_code=400, detail="Question and expected answer are required")
    prompt = ai_prompts.evaluate_answer(language_name(body.language), body.question, body.expected, body.answer)
    return execute_ai(request, db, account, [{"text": prompt}], EVALUATION_SCHEMA)


@app.post("/api/tutor")
def tutor(body: TutorRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    transcript = "\n".join(("Tutor" if message.role == "assistant" else "Learner") + ": " + message.text for message in body.history)
    prompt = ai_prompts.tutor_conversation(
        body.mode,
        language_name(body.language),
        language_name(body.sourceLanguage),
        language_name(body.targetLanguage),
        body.question,
        body.answer,
        transcript,
        body.message,
        requests_translation_help(body.message, body.sourceLanguage),
    )
    return execute_ai(request, db, account, [{"text": prompt}, *attachment_parts(body)], REPLY_SCHEMA)


def explicit_card_request(body: AgentPlanRequest, language: str) -> Optional[tuple[str, str, int, dict[str, Any], list[str]]]:
    """Recognize the three unambiguous "N cards for deck X" requests.

    Returns (route name, prompt, card count, action without cards, deck path for the preview),
    or None when the request needs the general planner.
    """
    tree = detect_deck_tree_request(body.message)
    if tree:
        prompt = ai_prompts.new_tree_cards(tree["cardCount"], language, tree["deckName"], tree["subdeckName"], body.message)
        action = {"type": "create_deck_tree", "deckName": tree["deckName"], "subdeckName": tree["subdeckName"]}
        return "new_deck_tree", prompt, tree["cardCount"], action, [tree["deckName"], tree["subdeckName"]]
    subdeck = detect_new_subdeck_request(body.message, body.decks)
    if subdeck:
        prompt = ai_prompts.new_subdeck_cards(subdeck["cardCount"], language, subdeck["deckName"], subdeck["parentDeck"], body.message)
        action = {"type": "create_subdeck", "parentDeck": subdeck["parentDeck"], "deckName": subdeck["deckName"]}
        return "new_subdeck", prompt, subdeck["cardCount"], action, [subdeck["parentDeck"], subdeck["deckName"]]
    existing = detect_existing_deck_cards_request(body.message, body.decks)
    if existing:
        prompt = ai_prompts.existing_deck_cards(existing["cardCount"], language, existing["deckName"], body.message)
        action = {"type": "create_cards", "deckName": existing["deckName"]}
        if existing["parentDeck"]:
            action["parentDeck"] = existing["parentDeck"]
        return "existing_deck_cards", prompt, existing["cardCount"], action, [existing["deckName"]]
    return None


@app.post("/api/agent-plan")
def tutor_agent_plan(body: AgentPlanRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    language = language_name(body.language)
    attached = attachment_parts(body)
    explicit = explicit_card_request(body, language)
    if explicit:
        route, prompt, count, action, path = explicit
        print(f"[TutorAgent][plan] route={route} cards={count} attachment={bool(attached)}", flush=True)
        result = execute_ai(request, db, account, [{"text": prompt}, *attached], CARD_SCHEMA)
        action["cards"] = exact_cards(result, count)
        return {"reply": preview_reply(language, path, count), "actions": [action]}

    requested_count = requested_flashcard_count(body.message)
    print(f"[TutorAgent][plan] route=general mode={body.mode!r} known_decks={len(body.decks)} requested_cards={requested_count or '-'}", flush=True)
    decks = "\n".join(deck[:120] for deck in body.decks)
    folders = "\n".join(folder[:120] for folder in body.vocabularyFolders)
    calendar_entries = "\n".join(entry[:160] for entry in body.calendarEntries)
    exclude_terms = "\n".join(term[:120] for term in body.excludeTerms) if attached else ""
    prompt = ai_prompts.agent_plan(language, body.mode, body.sourceLanguage, body.targetLanguage, decks, folders, body.message, calendar_entries, body.today or "", exclude_terms)
    plan = sanitize_agent_plan(execute_ai(request, db, account, [{"text": prompt}, *attached], AGENT_PLAN_SCHEMA))
    if requested_count is not None:
        generated_count = sum(len(action.get("cards") or []) for action in plan["actions"] if action.get("type") in CARD_ACTION_TYPES)
        print(f"[TutorAgent][plan] requested_cards={requested_count} generated_cards={generated_count}", flush=True)
        plan = enforce_requested_card_count(plan, requested_count)
    if not plan["actions"] and CLAIMS_DONE.search(str(plan.get("reply", ""))):
        plan["reply"] = no_action_reply(language)
    return plan


@app.post("/api/summary")
def summarize_cards(body: SummaryRequest, request: Request, account: Account = Depends(current_account), db: Session = Depends(get_db)):
    material = "\n".join("Q: " + card.question + "\nA: " + card.answer for card in body.cards)
    if not material.strip():
        raise HTTPException(status_code=400, detail="This deck has no cards")
    prompt = ai_prompts.summarize_cards(language_name(body.language), material)
    return execute_ai(request, db, account, [{"text": prompt}], SUMMARY_SCHEMA)


def legal_page(name: str) -> FileResponse:
    page = config.FRONTEND / f"{name}.html"
    if not page.is_file():
        raise HTTPException(status_code=404, detail="Page is unavailable")
    return FileResponse(page)


@app.get("/privacy")
def privacy_page():
    return legal_page("privacy")


@app.get("/terms")
def terms_page():
    return legal_page("terms")


@app.get("/imprint")
def imprint_page():
    return legal_page("imprint")


app.mount("/", StaticFiles(directory=str(config.FRONTEND), html=True), name="frontend")
