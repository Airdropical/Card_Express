#!/usr/bin/env python3
"""Word Express API and static web preview: application setup and routes."""

from __future__ import annotations

import base64
import binascii
import re
import secrets
from contextlib import asynccontextmanager
from typing import Any, Optional
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import select
from sqlalchemy.orm import Session

import ai_prompts
import config
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
from ai_client import execute_ai
from auth import DUMMY_PASSWORD_HASH, current_account, hash_password, issue_token, verify_password
from db import Account, Base, UserProfile, get_db, utcnow  # noqa: F401  (Base is re-exported for tooling)
from middleware import BodyLimitAndSecurityHeadersMiddleware
from profiles import validate_profile_document
from rate_limit import fail_rate_limit
from schemas import (
    AGENT_PLAN_SCHEMA,
    AttachmentFields,
    CARD_SCHEMA,
    EVALUATION_SCHEMA,
    REPLY_SCHEMA,
    SUMMARY_SCHEMA,
    AgentPlanRequest,
    Credentials,
    DeleteAccountRequest,
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
    # Use a dummy hash for unknown emails to reduce timing-based account discovery.
    encoded_hash = account.password_hash if account is not None else DUMMY_PASSWORD_HASH
    password_ok = verify_password(body.password, encoded_hash)
    if account is None or not password_ok:
        raise HTTPException(status_code=401, detail="Email or password is incorrect")
    return session_response(account)


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
    if_match: Optional[str] = Header(default=None, alias="If-Match"),
    account: Account = Depends(current_account),
    db: Session = Depends(get_db),
):
    fail_rate_limit(db, request, "profile-write", limit=120, window_seconds=60, subject=str(account.id), by_ip=False)
    if if_match is None or not re.fullmatch(r'"?\d+"?', if_match.strip()):
        raise HTTPException(status_code=428, detail="If-Match revision is required")
    expected_revision = int(if_match.strip().strip('"'))
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
    prompt = ai_prompts.agent_plan(language, body.mode, body.sourceLanguage, body.targetLanguage, decks, folders, body.message)
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


@app.get("/privacy")
def privacy_page():
    page = config.FRONTEND / "privacy.html"
    if not page.exists():
        raise HTTPException(status_code=404, detail="Privacy page is unavailable")
    return FileResponse(page)


app.mount("/", StaticFiles(directory=str(config.FRONTEND), html=True), name="frontend")
