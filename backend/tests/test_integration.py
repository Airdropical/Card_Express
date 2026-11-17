"""End-to-end checks against a real PostgreSQL (started by the optional `pgserver` package).

Gemini and Apple are replaced by stand-ins; everything else is the real application: migrations,
models, rate limits, locks and cascades.
"""

import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

pgserver = pytest.importorskip("pgserver")

import ai_client  # noqa: E402
import apns  # noqa: E402
import apple_auth  # noqa: E402
import config  # noqa: E402
import daily_tests  # noqa: E402
import db  # noqa: E402
import server  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
APPLE_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
NONCE = "integration-test-nonce"
TABLES = ["accounts", "user_profiles", "ai_usage", "device_tokens", "generated_tests"]


def alembic(url, *arguments):
    environment = {**os.environ, "DATABASE_URL": url, "PYTHONPATH": str(ROOT / "backend")}
    return subprocess.run([sys.executable, "-m", "alembic", *arguments], cwd=ROOT, env=environment, capture_output=True, text=True)


@pytest.fixture(scope="module")
def database(tmp_path_factory):
    instance = pgserver.get_server(tmp_path_factory.mktemp("pg"))
    url = instance.get_uri()
    result = alembic(url, "upgrade", "head")
    assert result.returncode == 0, result.stderr
    engine = create_engine(url.replace("postgresql://", "postgresql+psycopg://", 1))
    yield url, engine
    engine.dispose()
    instance.cleanup()


@pytest.fixture()
def client(database, monkeypatch):
    from starlette.testclient import TestClient

    url, engine = database
    monkeypatch.setattr(config, "DATABASE_URL", url)
    monkeypatch.setattr(db, "SessionLocal", sessionmaker(bind=engine, expire_on_commit=False))
    public_jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(APPLE_KEY.public_key()))
    monkeypatch.setattr(apple_auth, "apple_public_keys", lambda force=False: {"k": public_jwk})
    with TestClient(server.app) as test_client:
        yield test_client


def apple_token(subject, email=None):
    claims = {"iss": apple_auth.APPLE_ISSUER, "aud": config.APPLE_BUNDLE_ID, "sub": subject, "iat": int(time.time()), "exp": int(time.time()) + 600,
              "nonce": hashlib.sha256(NONCE.encode()).hexdigest()}
    if email:
        claims.update(email=email, email_verified="true")
    return jwt.encode(claims, APPLE_KEY, algorithm="RS256", headers={"kid": "k"})


def sign_in(client, subject, email=None, ip="10.1.0.1"):
    response = client.post("/api/v1/auth/apple", json={"identityToken": apple_token(subject, email), "nonce": NONCE}, headers={"X-Real-IP": ip})
    assert response.status_code == 200, response.text
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def gemini_reply(payload):
    return {"candidates": [{"content": {"parts": [{"text": json.dumps(payload)}]}, "finishReason": "STOP"}], "usageMetadata": {"promptTokenCount": 50, "candidatesTokenCount": 20}}


def count(engine, table, where="true"):
    with engine.connect() as connection:
        return connection.execute(text(f"select count(*) from {table} where {where}")).scalar_one()


def swift_seconds(moment):
    return moment.timestamp() - daily_tests.SWIFT_REFERENCE_EPOCH


def snapshot_with_exam(days_ahead=1, cards=5):
    when = datetime.now(timezone.utc) + timedelta(days=days_ahead)
    deck = {"id": "D1", "name": "Bio", "cards": [{"id": f"C{i}", "question": f"Q{i}", "answer": f"A{i}"} for i in range(cards)]}
    return {"schemaVersion": 1, "decks": [deck], "vocabulary": [], "calendarEntries": [{"id": "E1", "title": "Bio-Klausur", "date": swift_seconds(when), "deckID": "D1"}]}


def test_migrations_match_the_models_and_can_be_reversed(database):
    url, _ = database
    drift = alembic(url, "check")
    assert drift.returncode == 0, drift.stdout + drift.stderr
    scratch = pgserver.get_server(Path(url.split("host=")[1]).parent / "scratch")
    try:
        for step in (("upgrade", "head"), ("downgrade", "base"), ("upgrade", "head")):
            result = alembic(scratch.get_uri(), *step)
            assert result.returncode == 0, f"{step}: {result.stderr}"
    finally:
        scratch.cleanup()


def test_health_reports_the_database(client):
    assert client.get("/api/health").json() == {"ok": True, "service": "word-express-api", "database": "ok"}


def test_apple_sign_in_creates_one_account_and_reuses_it(client, database):
    _, engine = database
    first = sign_in(client, "apple-user-1", "one@example.com")
    again = sign_in(client, "apple-user-1", "one@example.com")
    assert count(engine, "accounts", "apple_sub = 'apple-user-1'") == 1
    overview = client.get("/api/v1/account", headers=again).json()
    assert overview["email"] == "one@example.com" and overview["plan"] == "free" and overview["serverPush"] is False
    assert overview["ai"] == {"usedToday": 0, "dailyLimit": config.AI_DAILY_REQUEST_LIMIT, "unlimited": False}
    assert client.get("/api/v1/account", headers=first).status_code == 200


def test_hidden_email_account_reports_no_address(client):
    headers = sign_in(client, "apple-hidden")
    assert client.get("/api/v1/account", headers=headers).json()["email"] is None


def test_tampered_apple_token_is_refused(client):
    token = apple_token("apple-user-x") + "x"
    response = client.post("/api/v1/auth/apple", json={"identityToken": token, "nonce": NONCE}, headers={"X-Real-IP": "10.1.0.9"})
    assert response.status_code == 401


def test_sync_roundtrip_and_revision_conflict(client):
    headers = sign_in(client, "apple-sync")
    assert client.get("/api/v1/profile", headers=headers).json() == {"profile": None, "revision": 0}
    document = snapshot_with_exam()
    assert client.put("/api/v1/profile", json={"profile": document}, headers=headers).status_code == 428
    saved = client.put("/api/v1/profile", json={"profile": document}, headers={**headers, "If-Match": '"0"'})
    assert saved.status_code == 200 and saved.json() == {"revision": 1}
    stale = client.put("/api/v1/profile", json={"profile": document}, headers={**headers, "If-Match": '"0"'})
    assert stale.status_code == 409 and stale.headers["ETag"] == '"1"'
    fetched = client.get("/api/v1/profile", headers=headers).json()
    assert fetched["revision"] == 1 and fetched["profile"]["decks"][0]["name"] == "Bio"
    assert client.put("/api/v1/profile", json={"profile": {"decks": []}}, headers={**headers, "If-Match": '"1"'}).status_code == 422


def test_accounts_cannot_read_each_others_data(client):
    owner = sign_in(client, "apple-owner")
    other = sign_in(client, "apple-other")
    client.put("/api/v1/profile", json={"profile": snapshot_with_exam()}, headers={**owner, "If-Match": '"0"'})
    assert client.get("/api/v1/profile", headers=other).json()["profile"] is None
    assert client.get("/api/v1/profile").status_code == 401


def test_ai_request_is_counted_and_failures_are_not(client, database, monkeypatch):
    _, engine = database
    headers = sign_in(client, "apple-ai")
    body = {"cards": [{"question": "Q", "answer": "A"}], "language": "Deutsch"}
    monkeypatch.setattr(ai_client, "call_gemini", lambda parts, schema: (gemini_reply({"summary": "kurz"}), "primary-flash-lite"))
    assert client.post("/api/summary", json=body, headers=headers).json() == {"summary": "kurz"}
    assert client.get("/api/v1/account", headers=headers).json()["ai"]["usedToday"] == 1

    def unavailable(parts, schema):
        raise HTTPException(status_code=503, detail="AI service is temporarily unavailable")

    monkeypatch.setattr(ai_client, "call_gemini", unavailable)
    assert client.post("/api/summary", json=body, headers=headers).status_code == 503
    assert client.get("/api/v1/account", headers=headers).json()["ai"]["usedToday"] == 1
    assert count(engine, "ai_usage", "state = 'failed' and actual_cost = 0") == 1


def test_daily_limit_blocks_further_requests_but_not_the_operator(client, monkeypatch):
    monkeypatch.setattr(config, "AI_DAILY_REQUEST_LIMIT", 1)
    monkeypatch.setattr(ai_client, "call_gemini", lambda parts, schema: (gemini_reply({"summary": "ok"}), "primary-flash-lite"))
    body = {"cards": [{"question": "Q", "answer": "A"}]}
    limited = sign_in(client, "apple-limited", "limited@example.com")
    assert client.post("/api/summary", json=body, headers=limited).status_code == 200
    refused = client.post("/api/summary", json=body, headers=limited)
    assert refused.status_code == 429 and "Daily" in refused.json()["detail"]
    monkeypatch.setattr(config, "AI_UNLIMITED_ACCOUNT_EMAIL", "admin@example.com")
    operator = sign_in(client, "apple-admin", "admin@example.com")
    assert [client.post("/api/summary", json=body, headers=operator).status_code for _ in range(3)] == [200, 200, 200]
    assert client.get("/api/v1/account", headers=operator).json()["ai"]["unlimited"] is True


def test_global_daily_ceiling_applies_to_everyone_else(client, monkeypatch):
    monkeypatch.setattr(config, "AI_GLOBAL_DAILY_REQUEST_LIMIT", 1)
    headers = sign_in(client, "apple-late")
    response = client.post("/api/summary", json={"cards": [{"question": "Q", "answer": "A"}]}, headers=headers)
    assert response.status_code == 429 and "capacity" in response.json()["detail"]


def test_daily_test_is_checked_first_written_once_and_then_served_from_storage(client, database, monkeypatch):
    _, engine = database
    headers = sign_in(client, "apple-tests")
    calls = []

    def write_test(parts, schema):
        calls.append(parts[0]["text"])
        return gemini_reply({"cards": [{"question": f"Neu {i}?", "answer": f"Antwort {i}"} for i in range(8)]}), "primary-flash-lite"

    monkeypatch.setattr(ai_client, "call_gemini", write_test)
    today = datetime.now(timezone.utc).date()
    cards = [{"question": f"Q{i}", "answer": f"A{i}"} for i in range(6)]
    request = {"kind": "exam", "reference": "E1", "localDay": today.isoformat(), "examDay": (today + timedelta(days=2)).isoformat(), "title": "Bio-Klausur", "cards": cards}

    too_far = client.post("/api/v1/tests", json={**request, "examDay": (today + timedelta(days=9)).isoformat()}, headers=headers)
    not_hard = client.post("/api/v1/tests", json={**request, "kind": "weak", "reference": ""}, headers=headers)
    wrong_day = client.post("/api/v1/tests", json={**request, "localDay": (today + timedelta(days=5)).isoformat()}, headers=headers)
    assert (too_far.status_code, not_hard.status_code, wrong_day.status_code) == (409, 409, 422)
    assert calls == [] and client.get("/api/v1/account", headers=headers).json()["ai"]["usedToday"] == 0

    first = client.post("/api/v1/tests", json=request, headers=headers).json()
    second = client.post("/api/v1/tests", json=request, headers=headers).json()
    assert first["cached"] is False and len(first["questions"]) == 6 and "Bio-Klausur" in calls[0]
    assert second["cached"] is True and second["questions"] == first["questions"] and len(calls) == 1
    assert client.get("/api/v1/account", headers=headers).json()["ai"]["usedToday"] == 1
    assert count(engine, "generated_tests") == 1


def test_push_job_is_closed_without_secret_and_notifies_each_account_once(client, database, monkeypatch):
    _, engine = database
    headers = sign_in(client, "apple-push")
    client.put("/api/v1/profile", json={"profile": snapshot_with_exam()}, headers={**headers, "If-Match": '"0"'})
    token = "ab" * 32
    assert client.put("/api/v1/devices", json={"token": token.upper(), "environment": "sandbox", "language": "en"}, headers=headers).status_code == 204
    assert client.put("/api/v1/devices", json={"token": token, "environment": "sandbox", "language": "en"}, headers=headers).status_code == 204
    assert count(engine, "device_tokens", f"token = '{token}'") == 1

    assert client.post("/api/internal/daily-tests").status_code == 404
    monkeypatch.setattr(config, "JOB_SECRET", "s" * 40)
    assert client.post("/api/internal/daily-tests", headers={"X-Job-Secret": "wrong"}).status_code == 404
    job = {"X-Job-Secret": "s" * 40}
    assert client.post("/api/internal/daily-tests", headers=job).status_code == 503

    sent = []

    class FakeClient:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    monkeypatch.setattr(apns, "configured", lambda: True)
    monkeypatch.setattr(apns, "open_client", lambda: FakeClient())
    monkeypatch.setattr(apns, "send", lambda http, device, environment, title, body, kind: sent.append((device, environment, body, kind)) or 200)
    assert client.get("/api/v1/account", headers=headers).json()["serverPush"] is True
    first = client.post("/api/internal/daily-tests", headers=job).json()
    second = client.post("/api/internal/daily-tests", headers=job).json()
    assert first["sent"] == 1 and second["sent"] == 0
    assert sent == [(token, "sandbox", "Your test for “Bio-Klausur” is ready.", "exam")]

    assert client.request("DELETE", "/api/v1/devices", json={"token": token}, headers=headers).status_code == 204
    assert count(engine, "device_tokens", f"token = '{token}'") == 0


def test_login_attempts_are_rate_limited_per_address(client):
    attempt = {"email": "nobody@example.com", "password": "wrong-password"}
    statuses = [client.post("/api/v1/auth/login", json=attempt, headers={"X-Real-IP": "10.9.9.9"}).status_code for _ in range(12)]
    assert statuses[:8] == [401] * 8 and statuses[-1] == 429
    assert client.post("/api/v1/auth/login", json=attempt, headers={"X-Real-IP": "10.9.9.10"}).status_code == 401


def test_logout_ends_the_session(client):
    headers = sign_in(client, "apple-logout")
    assert client.post("/api/v1/auth/logout", headers=headers).status_code == 204
    assert client.get("/api/v1/account", headers=headers).status_code == 401


def test_deleting_an_account_removes_every_trace(client, database, monkeypatch):
    _, engine = database
    headers = sign_in(client, "apple-delete", "delete@example.com")
    monkeypatch.setattr(ai_client, "call_gemini", lambda parts, schema: (gemini_reply({"summary": "x"}), "primary-flash-lite"))
    client.put("/api/v1/profile", json={"profile": snapshot_with_exam()}, headers={**headers, "If-Match": '"0"'})
    client.post("/api/summary", json={"cards": [{"question": "Q", "answer": "A"}]}, headers=headers)
    client.put("/api/v1/devices", json={"token": "cd" * 32}, headers=headers)
    with engine.connect() as connection:
        account_id = connection.execute(text("select id from accounts where apple_sub = 'apple-delete'")).scalar_one()
    owned = f"account_id = '{account_id}'"
    assert all(count(engine, table, owned) == 1 for table in ("user_profiles", "ai_usage", "device_tokens"))

    assert client.request("DELETE", "/api/v1/account", headers=headers).status_code == 204
    assert count(engine, "accounts", f"id = '{account_id}'") == 0
    assert all(count(engine, table, owned) == 0 for table in TABLES[1:])
    assert client.get("/api/v1/account", headers=headers).status_code == 401
    # Signing in again starts from nothing.
    fresh = sign_in(client, "apple-delete", "delete@example.com")
    assert client.get("/api/v1/profile", headers=fresh).json() == {"profile": None, "revision": 0}
